# Návrh architektury – claude-status

Vychází z [`requirements.md`](requirements.md), na který odkazují čísla F1–F5, #1–#9 a AC1–AC10 (akceptační kritéria). Stav: návrh (15. 10. 2026), kód zatím neexistuje.

## 1. Hlavní rozhodnutí

| Rozhodnutí | Volba | Proč |
|---|---|---|
| Sestavení | Jen SwiftPM; `.app` skládá skript | Na stroji není Xcode, jen Command Line Tools. |
| Vrstvy | `ClaudeStatusCore` (logika) + `ClaudeStatus` (UI a systémové adaptéry) | Core jde testovat bez `.app` balíčku a bez sítě. |
| Logika | Jedna čistá funkce `Engine.step` | Rozpočet, předpovědi i rozhodnutí o oznámeních se testují přímo na AC1–AC10. |
| Deduplikace oznámení | Uvnitř `Engine`, ne v adaptéru | AC1 („ani po restartu“) se testuje jako serializace stavu tam a zpět. |
| Stav | Jeden Codable blob v `UserDefaults(suiteName: "local.ClaudeStatus.state")` | Explicitní suite, aby `--dump` ze `swift run` četl stejná data jako `.app`. |
| Token | `/usr/bin/security` přes `Process`, jen pro čtení | ACL položky v Klíčence důvěřuje `security`, takže nevyskočí dotaz po každém přebuildění. |
| Instalace | `~/Applications/ClaudeStatus.app` | Repo leží na šifrovaném svazku, který při přihlášení nemusí být připojený. |

Bundle ID je `local.ClaudeStatus`. Suite pro `UserDefaults` se od něj musí lišit (`local.ClaudeStatus.state`), protože suite pojmenovaná stejně jako vlastní bundle ID nefunguje.

## 2. Komponenty

```
┌─────────────────────── ClaudeStatus (executable → .app) ───────────────────────┐
│  UI (SwiftUI)                         Platform/ (adaptéry portů)               │
│  ┌──────────────┐ ┌───────────┐       SecurityCLITokenProvider ─▶ /usr/bin/security
│  │ MenuBarLabel │ │ PanelView │       URLSessionUsageClient    ─▶ api.anthropic.com
│  └──────┬───────┘ └─────┬─────┘       UserNotificationsNotifier ─▶ Centrum oznámení
│         │  SettingsView │             UserDefaultsStateStore, LoginItem (SMAppService),
│         └───────┬───────┘             WakeObserver (NSWorkspace.didWakeNotification)
│                 │ pozoruje (Observation)          │ implementují porty
└─────────────────┼─────────────────────────────────┼────────────────────────────┘
┌─────────────────┼───── ClaudeStatusCore (library, jen Foundation) ─────────────┐
│        ┌────────┴─────────┐   volá porty   ┌──────────────────────────────┐     │
│        │   UsageMonitor   │───────────────▶│ Ports: TokenProviding,       │     │
│        │ smyčka, backoff  │                │ UsageFetching, Notifying,    │     │
│        └────────┬─────────┘                │ StateStoring                 │     │
│                 │ step(input) → output     └──────────────────────────────┘     │
│        ┌────────┴───────────────────────────────────────────────────┐           │
│        │ Engine (čistá funkce)                                      │           │
│        │  UsageMapper → BaselineReducer → BudgetCalculator          │           │
│        │             → PaceEstimator → NotificationRules → Snapshot │           │
│        └────────────────────────────────────────────────────────────┘           │
│  Model: UsageResponseDTO, UsageSample, PersistedState, AppSettings, Snapshot     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**Pravidlo závislostí.** Core neimportuje AppKit, SwiftUI, UserNotifications ani ServiceManagement. Všechno se systémovými efekty prochází porty.

## 3. Jedno obnovení dat (každých 60 s, po probuzení a po kliknutí na Obnovit)

```
UsageMonitor     TokenProvider     UsageClient        Engine          Notifier      StateStore
    │ tick            │                 │                │               │              │
    │─ readToken() ──▶│ security -w     │                │               │              │
    │◀─ token ────────│ (nebo expired)  │                │               │              │
    │─ fetchUsage(token) ──────────────▶│ GET /usage     │               │              │
    │◀─ DTO / UsageFetchError ──────────│                │               │              │
    │   (401 → jednou znovu přečíst token a zopakovat)   │               │              │
    │─ step(state, result, now, settings, calendar) ────▶│               │              │
    │◀─ StepOutput(state', snapshot, notifications) ─────│               │              │
    │─ deliver(notifications) ──────────────────────────────────────────▶│              │
    │─ save(state') ───────────────────────────────────────────────────────────────────▶│
    │  snapshot = output.snapshot  → UI se překreslí přes Observation                    │
```

- **Při chybě** se `step` volá také: výsledek je `.failure`. Engine nechá poslední známé hodnoty a oznámení nevyhodnocuje. Do 5 min od posledního úspěchu zůstane status `ok` a chyba se jen ukáže v `lastError`, potom přejde na `stale`.
- **Bez platného tokenu** se API vůbec nevolá. Snapshot má status `tokenExpired`.

## 4. Rozhraní (Core)

Jen signatury; implementace přijde v `/sc:implement`.

```swift
// Ports
struct OAuthToken: Sendable { let accessToken: String; let expiresAt: Date }
protocol TokenProviding: Sendable { func readToken() async throws -> OAuthToken }
protocol UsageFetching: Sendable { func fetchUsage(token: String) async throws -> UsageResponseDTO }  // hází UsageFetchError
enum UsageFetchError: Error { case unauthorized, rateLimited(retryAfter: TimeInterval?), http(Int), decoding, network(String) }
protocol Notifying: Sendable { func deliver(_ notifications: [AppNotification]) async }
protocol StateStoring: Sendable { func loadState() -> PersistedState; func saveState(_:)
                                  func loadSettings() -> AppSettings; func saveSettings(_:) }

// Engine – mapování DTO → UsageSample dělá UsageMonitor, Engine dostává už UsageSample
enum FetchResult: Sendable { case pending /* start appky */, success(UsageSample), tokenExpired, failure(String) }
struct StepInput { var state: PersistedState; var result: FetchResult; var now: Date; var settings: AppSettings; var calendar: Calendar }
struct StepOutput { var state: PersistedState; var snapshot: Snapshot; var notifications: [AppNotification] }
enum Engine { static func step(_ input: StepInput) -> StepOutput }

struct AppNotification: Sendable, Equatable {
    let kind: NotificationKind; let key: String          // key = dedupe key, zároveň UN identifier
    let title: String; let body: String; let sound: Bool
    let fireAt: Date?                                      // nil = hned; #3 se plánuje na resets_at
}
enum NotificationKind: Int, Codable, CaseIterable { case sessionNear = 1, sessionReached, sessionBack, sessionForecast,
                                                    dayNear, dayReached, weeklyPace, paidUsage, dayForecast }

// Monitor
@MainActor @Observable final class UsageMonitor {
    private(set) var snapshot: Snapshot
    var settings: AppSettings                                // ukládá se zvlášť
    init(tokens: TokenProviding, client: UsageFetching, notifier: Notifying, store: StateStoring,
         now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current)
    func start()                                             // okamžitý tick + smyčka
    func refreshNow()                                        // tlačítko; jen když od posledního dotazu uplynulo ≥ 60 s
    func handleWake()                                        // po probuzení okamžitý tick
    func dryRun() async -> StepOutput                        // pro --dump: nic neuloží ani neodešle
    func tick() async; var nextDelay: TimeInterval           // internal; testy je volají přímo, bez čekání
}
```

### Snapshot (to, co zobrazuje UI)

```swift
struct Snapshot: Equatable {
    enum Status: Equatable { case loading, ok, stale(since: Date?), tokenExpired }
    var status: Status
    var fetchedAt: Date?
    var lastError: String?              // poslední chyba, i když status zůstává ok
    var session: LimitState?            // percent, resetsAt
    var weekly: LimitState?
    var weeklyPlanPercent: Double?      // značka „podle plánu“ v panelu (F2)
    var scoped: [ScopedLimitState]      // např. Fable
    var day: DayState                   // .workday(budget:used:) | .weekend(used:) | .unknown
    var spend: Money?                   // utraceno + strop, v minor units
    var sessionETA: Date?; var dayETA: Date?
    var menuBarText: String             // „◐ 5h 82%  den 64%“ – generuje Core, UI ho jen vypíše
}
```

Text do lišty a texty oznámení tvoří Core (`Format`), takže je pokrývají testy. Formátuje se v locale `cs_CZ`, ve 24h čase a v místním pásmu.

## 5. Mapování odpovědi API

`UsageResponseDTO` je tolerantní: každé pole je volitelné a každé vnořené pole se dekóduje přes `try?` ve vlastním `init(from:)`. Samotné `decodeIfPresent` při jiném typu hodí chybu a shodilo by celou odpověď.

| Údaj | 1. volba | Záloha |
|---|---|---|
| 5h limit | `limits[kind=session]`: `percent`, `resets_at` | `five_hour`: `utilization`, `resets_at` |
| Týden | `limits[kind=weekly_all]` | `seven_day` |
| Týden pro model | `limits[kind=weekly_scoped]` + `scope.model.display_name` | – |
| Placené čerpání | `spend.used` / `spend.limit` (`amount_minor`, `exponent`, `currency`) | `extra_usage.used_credits` / `monthly_limit` (`decimal_places`) |

- **Částky jsou v minor units.** `235` s `exponent: 2` znamená 2,35 €.
- **`resets_at` přichází s mikrosekundami i bez nich.** `ResetDateParser` zkusí oba formáty.
- **Okno týdne** je `[resets_at − 7 × 86 400 s, resets_at]`, tedy absolutní čas. Přes změnu času (DST) se místní čas resetu posune (22:00 → 21:00).
- **Testy mapování** stojí na fixturách: `usage-2026-10-15.json` (skutečná odpověď bez tokenu) a `usage-flat-only.json` (AC8).

## 6. Denní rozpočet

```
týdenní okno: út 13. 10. 22:00 ───────────────────────────── út 20. 10. 22:00
den:            út    st   čt   pá   so   ne   po    út
w(den):        2/24   1    1    1    0    0    1   22/24     Σ ≈ 5
```

- **Váha dne.** `w(den)` = délka průniku dne s oknem ÷ **skutečná délka toho dne**. V den změny času má den 23 nebo 25 h, takže dělit pevnými 24 h nestačí. So a Ne mají váhu 0.
- **Dnešní rozpočet a čerpání:** `budget = (100 − B) × w(dnes) / Σ w(dnes … den resetu)`, `used = týden% − B`.
- **Plán pro #7:** `plán% = 100 × Σ w(začátek okna … konec dneška) / Σ w(celé okno)`. Plán je, kolik mělo být přiděleno do konce dneška. Dělí se spočtenou sumou, ne konstantou 5 (DST).
- **`BaselineReducer`** nastaví nové `B`:
  - při prvním vzorku nového dne;
  - když se `resets_at` týdne posune o víc než 1 min dopředu (reset okna);
  - když týden% klesne pod `B`.

  Spolu s `B` uloží i `spendMinor` (základ pro #8).

## 7. Předpověď tempa (#4, #9)

`PaceEstimator` počítá z bodů za posledních 15 min, a to jen ze stejného 5h okna (#4), resp. ze stejného dne (#9):

- **Tempo:** `rate = (poslední − nejstarší) / Δt`.
- **Kdy se nepočítá:** když je `Δt` menší než 12 min nebo `rate ≤ 0`. Výsledek je pak `nil`.
- **Odhad vyčerpání:** `ETA = now + (limit − aktuální) / rate`.
- **Kdy oznámit:**
  - #4, když `ETA < resets_at`;
  - #9, když `ETA − now ≤ horizont` (60 min) a je pracovní den.

**Riziko:** procenta chodí v celých číslech. Týden se za 15 min pohne o 0–2 p. b., takže odhad #9 je hrubý. Ověří se provozem; když bude moc šumět, prodlouží se okno měření, ne práh.

## 8. Pravidla oznámení

| # | Podmínka (vyhodnocuje se při každém `step`) | Dedupe klíč | Zvuk |
|---|---|---|---|
| 1 | `session ≥ sessionWarn` | `1\|<session resets_at po minutách>` | – |
| 2 | `session ≥ 100` | `2\|<okno>` | ✓ |
| 3 | Okno dosáhlo `≥ sessionWarn` → **naplánovat** na `resets_at` (`fireAt`) | `3\|<okno>` | – |
| 4 | `sessionETA < resets_at` | `4\|<okno>` | – |
| 5 | pracovní den ∧ `used ≥ dayWarn % × budget` | `5\|<datum>` | – |
| 6 | pracovní den ∧ `used ≥ budget` | `6\|<datum>` | ✓ |
| 7 | `týden% − plán% > weeklyPaceMargin` | `7\|<datum>` | – |
| 8 | `spendMinor > B.spendMinor` (dnešní přírůstek) | `8\|<datum>` | – |
| 9 | pracovní den ∧ `dayETA − now ≤ horizont` | `9\|<datum>` | – |

- **Vypnutý druh** (`AppSettings.enabled`) se vůbec nevyhodnocuje.
- **Odeslaný klíč** jde do `state.sent[key] = now`, a to už v `Engine`. Klíče starší než 8 dní se mažou.
- **#3 přes plánování.** Plánuje se jako `UNTimeIntervalNotificationTrigger` s identifikátorem = klíč, takže přijde přesně v čas resetu, i když appka zrovna nepolluje. Když Mac spí, macOS oznámení doručí po probuzení.

Ukázky textů:

| # | Titulek | Text |
|---|---|---|
| 1 | 5h limit: 82 % | Reset ve 12:20 (za 14 min). |
| 2 | 5h limit vyčerpán | Znovu k dispozici ve 12:20. |
| 3 | 5h limit je zpět | Můžeš pokračovat. |
| 4 | 5h limit: tempo | Tímto tempem narazíš na limit ve 14:35, reset je v 15:20. |
| 5 | Denní rozpočet: 83 % | Zbývá 3,4 p. b. z 20,0. |
| 6 | Denní rozpočet vyčerpán | Další čerpání ubírá ze zbývajících pracovních dnů. |
| 7 | Týden: napřed oproti plánu | Využito 45 %, plán 33 %. Reset út 22:00. |
| 8 | Placené čerpání | Dnes utraceno 1,20 € z extra usage. |
| 9 | Denní rozpočet: tempo | Tímto tempem vyčerpáš dnešní rozpočet v 15:10. |

## 9. Persistovaný stav a nastavení

```swift
// UserDefaults(suiteName: "local.ClaudeStatus"), klíč "state.v1", JSON
struct PersistedState: Codable {
    var day: DayBaseline?          // date "2026-10-15", weeklyPercent (B), weeklyResetsAt, spendMinor
    var samples: [SamplePoint]     // poslední 1 h: at, sessionPercent, sessionResetsAt, weeklyPercent
    var sessionPeak: SessionPeak?  // resetsAt + nejvyšší % v okně (podklad pro #3)
    var sent: [String: Date]       // dedupe klíč → čas odeslání
    var lastSample: UsageSample?   // zobrazí se po restartu, než dorazí první data
}

// tamtéž, klíč "settings.v1"
struct AppSettings: Codable {
    var sessionWarn = 80.0, dayWarn = 80.0, weeklyPaceMargin = 10.0
    var dayForecastHorizon: Duration = .seconds(3600)
    var enabled = Set(NotificationKind.allCases)
    var launchAtLogin = true
}
```

Změna tvaru stavu znamená nový klíč (`state.v2`). Starý se zahodí, protože jde jen o cache a odvozená data.

## 10. Smyčka a stavy

```
           start / wake / Obnovit
                    │
  ┌──────────┐   úspěch   ┌────┐  poslední úspěch > 5 min  ┌───────┐
  │ loading  │───────────▶│ ok │─────────────────────────▶│ stale │
  └──────────┘            └────┘◀─────────────────────────└───────┘
        │ token expiroval        ▲        úspěch
        ▼                        │ úspěch
  ┌──────────────┐  (UI: „otevři Claude Code“)
  │ tokenExpired │ ─ každý tick znovu čte token, API nevolá
  └──────────────┘
```

- **Interval** je 60 s.
- **Backoff při chybě:** 120 → 240 → 480 → 900 s (strop).
- **429** respektuje `Retry-After`, ale vždy čeká aspoň 60 s.
- **Úspěch** vrací interval na 60 s.
- **Po probuzení** přijde okamžitý tick. Monitor neplánuje vlastní timery přes spánek, stačí `Task.sleep` ve smyčce.

## 11. Struktura balíčku

```
Package.swift                 platforms: [.macOS(.v14)], swift-tools 6.2
Sources/ClaudeStatusCore/
  API/        UsageResponseDTO, UsageMapper, ResetDateParser
  Model/      UsageSample, PersistedState, AppSettings, Snapshot, Money
  Budget/     WorkdayWeights, BaselineReducer, BudgetCalculator
  Pace/       PaceEstimator
  Notify/     NotificationKind, NotificationRules, AppNotification
  Engine/     Engine (step)
  Format/     Format (lišta, texty oznámení, cs_CZ)
  Monitor/    UsageMonitor, Ports
Sources/ClaudeStatus/
  App/        Entry (@main: „--dump“ → Dump, jinak ClaudeStatusApp.main()), ClaudeStatusApp
              (MenuBarExtra .window), AppDelegate, AppModel (monitor, oprávnění, login item)
  UI/         MenuBarLabel, PanelView, LimitRow, SettingsView (uvnitř panelu, ne Settings scene)
  Platform/   SecurityCLITokenProvider, URLSessionUsageClient, UserNotificationsNotifier,
              UserDefaultsStateStore, System (LoginItem, WakeObserver)
Resources/Info.plist          CFBundleIdentifier local.ClaudeStatus, LSUIElement true
Tests/ClaudeStatusCoreTests/  Fixtures/*.json; Mapper-, Budget-, Pace-, Rules-, EngineTests
scripts/test.sh               swift test s cestou ke Testing.framework z CLT
scripts/bundle.sh             release build → .app → codesign -s - → ~/Applications
```

`--dump` nesahá na `UNUserNotificationCenter`, takže funguje i ze `swift run` bez `.app`.

## 12. Akceptační kritéria → testy

| AC | Test | Jak |
|---|---|---|
| 1 | EngineTests | Sekvence 79 → 81 → 85 → 90 % dá právě jedno #1. Po zakódování a dekódování stavu (restart) žádné další. |
| 2 | EngineTests | `budget 20`, `used 16,5` → `menuBarText` obsahuje „den 83%“ a přijde #5. |
| 3, 4, 5 | BudgetTests | Pevný `Calendar` s `Europe/Prague` a data kolem aktuálního týdne. Navíc týden přes konec DST 25. 10. 2026. |
| 6 | RulesTests | Okno dosáhne 100 % → #3 s `fireAt == resets_at`. |
| 7 | EngineTests + MonitorTests | `.tokenExpired` → status, API se nevolá. `TokenProviding` nemá zapisovací metodu, takže zápis do Klíčenky je vyloučený už typem. |
| 8 | MapperTests | `usage-flat-only.json` dá stejný `UsageSample` jako plná fixtura. |
| 9 | PaceTests + RulesTests | 13 p. b. v 10:00, tempo 8 p. b./h → #9 s časem 10:53. |
| 10 | RulesTests | Sobota → žádné #5, #6, #9; #1 ano. |

## 13. Rizika k ověření při implementaci

1. **`SMAppService.mainApp` s ad-hoc podpisem.** Že spuštění po přihlášení takhle funguje, není ověřené. Záloha: LaunchAgent plist v `~/Library/LaunchAgents`, který zapíše `bundle.sh`.
2. ~~**Okno nastavení v appce bez Docku** se může otevřít za ostatními okny.~~ Vyřešeno: nastavení je přímo v panelu a žádné samostatné okno nemá.
3. **Hrubost procent u #9** (viz §7).
4. **Změny nezdokumentovaného API.** Mapper je tolerantní a fixtury se při změně tvaru doplňují.
5. **Oprávnění k oznámením** se váže na bundle ID. Při prvním spuštění `.app` se systém zeptá. Když uživatel odmítne, panel to ukáže.
