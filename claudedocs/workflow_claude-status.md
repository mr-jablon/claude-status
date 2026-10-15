# Implementační workflow – claude-status

Zdroje: [`docs/requirements.md`](../docs/requirements.md) (F1–F5, oznámení #1–#9, akceptační kritéria AC1–AC10) a [`docs/design.md`](../docs/design.md) (§ = kapitola návrhu).

**Strategie:**
1. Nejdřív krátce vyzkoušet rizikové věci kolem macOS (spike), aby se na ně nestavělo naslepo.
2. Pak `ClaudeStatusCore` přes testy psané podle akceptačních kritérií.
3. Nakonec napojení na systém, UI a zkušební provoz.

Každá fáze končí zelenými testy a commitem.

## Přehled

| Fáze | Obsah | Závisí na | Velikost | Kontrolní bod |
|---|---|---|---|---|
| 0 | Repo a kostra balíčku | – | S | `scripts/test.sh` zelený |
| 1 | Spike: `.app`, oznámení, spuštění po přihlášení | 0 | S | Ruční checklist v §1 |
| 2 | Načtení odpovědi API | 0 | M | AC8 |
| 3 | Denní rozpočet | 0 | M | AC3, AC4, AC5 + DST |
| 4 | Odhad tempa | 0 | S | PaceTests, výpočet z AC9 |
| 5 | Pravidla oznámení a texty | 3, 4 | M | AC6, AC9, AC10 |
| 6 | Engine a uložený stav | 2, 5 | M | AC1, AC2, AC7 (engine) |
| 7 | Smyčka UsageMonitor | 6 | M | AC7 (monitor), backoff |
| 8 | Napojení na systém + `--dump` | 1, 7 | M | `--dump` = `/usage` v Claude Code |
| 9 | UI v liště | 8 | M | F1, F2, F5 v běžící appce |
| 10 | Instalace a zkušební provoz | 9 | S | 2–3 pracovní dny bez chyb |

```
0 ─┬─▶ 1 spike ──────────────────────────────────────┐
   ├─▶ 2 API ───────────────────────┐                │
   ├─▶ 3 rozpočet ──┐               │                │
   └─▶ 4 tempo ─────┴─▶ 5 pravidla ─┴─▶ 6 engine ─▶ 7 monitor ─▶ 8 adaptéry ─▶ 9 UI ─▶ 10 provoz
```

Fáze 1–4 na sobě nezávisí a jdou dělat souběžně. Fáze 3 a 4 pracují jen s čísly a daty a model z fáze 2 nepotřebují.

## Kontroly po každé fázi

- `swift build` projde bez varování (Swift 6, strict concurrency).
- `scripts/test.sh` je zelený.
- Core neimportuje platformní frameworky. Tento příkaz nesmí nic vypsat:
  `grep -rE '^import (AppKit|SwiftUI|UserNotifications|ServiceManagement)' Sources/ClaudeStatusCore`
- Commit ve formátu conventional commits. Push se nedělá, repo nemá remote.

---

## Fáze 0 – Repo a kostra

- `git init` a `.gitignore` (`.build/`, `.swiftpm/`, `build/`, `*.app`, `.DS_Store`).
- `Package.swift`:
  - targety `ClaudeStatusCore`, `ClaudeStatus` a `ClaudeStatusCoreTests`;
  - `platforms: [.macOS(.v14)]`, swift-tools 6.2.
- `scripts/test.sh` obalí `swift test` přepínači pro `Testing.framework` (viz CLAUDE.md) a další argumenty předá dál (`--filter`).
- Jeden smoke test v Core.
- `CLAUDE.md`: přidat sekci Commands a smazat řádek „Status: no code yet“.

**Kontrolní bod:** build bez varování a `scripts/test.sh` zelený.
**Commit:** `chore: scaffold swift package and test script`

## Fáze 1 – Spike platformy

Ověří rizika z design §13 (body 1, 2 a 5) a celý postup sestavení `.app`. Kód ze spiku zůstane jako kostra pro fázi 9.

- `Resources/Info.plist` (`local.ClaudeStatus`, `LSUIElement`).
- `scripts/bundle.sh`:
  - release build → `build/ClaudeStatus.app` → `codesign --force --sign -`;
  - s přepínačem `--install` zkopíruje appku do `~/Applications`;
  - cesty v uvozovkách (`Šifrovaný disk`).
- Minimální `ClaudeStatusApp`:
  - `MenuBarExtra` se statickým textem `◐ 5h –`;
  - v panelu tlačítko „Test oznámení“ a přepínač „Spouštět po přihlášení“ (`SMAppService.mainApp`);
  - „Nastavení…“ přes `SettingsLink`, před ním `NSApp.activate()`.

**Kontrolní bod (ručně):**
- [ ] Položka je v liště a appka nemá ikonu v Docku.
- [ ] Systém se zeptá na povolení oznámení. Testovací oznámení přijde se zvukem i bez něj.
- [ ] Po přebuildění se systém na povolení neptá znovu.
- [ ] `SMAppService` vrátí `.enabled` a po odhlášení a přihlášení se appka sama spustí. **Pokud ne:** záloha je LaunchAgent zapsaný z `bundle.sh` a výsledek se zapíše do design §13.
- [ ] Okno nastavení se otevře v popředí.

**Commit:** `feat(app): menu bar shell and bundle script`

## Fáze 2 – Načtení odpovědi API (design §5)

- **Fixtura.** Jednorázově stáhnout živou odpověď do `Tests/ClaudeStatusCoreTests/Fixtures/usage-full.json`. Token jde jen rourou, na disk se nezapíše. Před commitem zkontrolovat, že fixtura neobsahuje žádné identifikátory.
- **Odvozené fixtury:**
  - `usage-flat-only.json` – bez `limits` a `spend`;
  - `usage-limits-only.json` – ploché objekty jsou `null`;
  - `usage-type-mismatch.json` – jedno vnořené pole má jiný typ.
- **Postupně přes testy:**
  - `ResetDateParser`: formát s mikrosekundami i bez, zaokrouhlení na minutu;
  - `UsageResponseDTO` s tolerantním `init(from:)`;
  - `UsageMapper` → `UsageSample`: session, týden, limit pro model, `Money` v minor units.

**Kontrolní bod:**
- [ ] AC8: `usage-flat-only.json` dá stejný `UsageSample` jako `usage-full.json`.
- [ ] Jiný typ v jednom poli vynuluje jen tu jednu hodnotu.
- [ ] `amount_minor: 235`, `exponent: 2` → 2,35 €.

**Commit:** `feat(core): lenient usage API decoding and mapping`

## Fáze 3 – Denní rozpočet (design §6)

- `WorkdayWeights` (kalendář se předává zvenku, dělí se skutečnou délkou dne), `BaselineReducer`, `BudgetCalculator` (rozpočet, čerpání, plán %, víkend).
- Testy s `Calendar` v `Europe/Prague`:
  - okno út 13. 10. 22:00 → út 20. 10. 22:00: váhy 2/24, 1, 1, 1, 0, 0, 1, 22/24, Σ = 5;
  - příklad z F3: ve čtvrtek při `B = 20` vyjde ≈ 20,4 p. b.;
  - AC3 (páteční přečerpání), AC4 (sobota 3 p. b.), AC5 (reset v úterý ve 22:00 → nový základ);
  - **DST:** okno 20. 10. → 27. 10. 2026 (konec letního času 25. 10.). Absolutních 168 h, reset 27. 10. ve 21:00 místního času, Σ = 4 + 23/24.

**Kontrolní bod:** AC3–AC5 a test DST.
**Commit:** `feat(core): workday-weighted daily budget`

## Fáze 4 – Odhad tempa (design §7)

- `PaceEstimator`: vstup jsou body `(Date, Double)`, `now` a limit, výstup `ETA?`.
- Testy:
  - méně než 12 min dat → `nil`;
  - `rate ≤ 0` → `nil`;
  - body z jiného okna nebo jiného dne se ignorují;
  - čísla z AC9: 13 p. b. v 10:00 při 8 p. b./h → ETA 10:52:30.

**Commit:** `feat(core): pace estimator`

## Fáze 5 – Pravidla oznámení a texty (design §8)

- `NotificationKind`, `AppNotification`, `NotificationRules` jako čistá funkce a `Format` (text lišty včetně víkendu, chybějících a starých dat; devět textů oznámení; `cs_CZ`, 24h čas).
- Testy tabulkou, jeden řádek na pravidlo:
  - AC6: #3 má `fireAt == resets_at`;
  - AC9: #9 s textem „v 10:53“;
  - AC10: o víkendu nepřijde #5, #6 ani #9;
  - vypnutý druh se nevyhodnocuje;
  - zvuk mají jen #2 a #6.

**Commit:** `feat(core): notification rules and czech texts`

## Fáze 6 – Engine a uložený stav (design §4, §9, §10)

- `PersistedState` a `AppSettings` (Codable s výchozími hodnotami).
- `Engine.step` skládá fáze 2–5:
  - dedupe přes `sent`, mazání klíčů starších než 8 dní;
  - vzorky ořezané na 1 h;
  - `sessionPeak`;
  - stavy: `stale`, když poslední úspěch je starší než 5 min.
- Testy:
  - AC1: sekvence hodnot + zakódování a dekódování stavu jako restart;
  - AC2;
  - AC7 v enginu: `.tokenExpired` → status, žádná oznámení;
  - po chybě zůstanou poslední známé hodnoty;
  - #8 hlásí dnešní přírůstek;
  - když útrata spadne na začátku měsíce, vezme se nový základ.

**Kontrolní bod:** všechna akceptační kritéria kromě těch, která jdou ověřit jen v UI.
**Commit:** `feat(core): engine step with persisted state`

## Fáze 7 – Smyčka UsageMonitor (design §4, §10)

- Porty a `UsageMonitor`. Čekání (`sleep`) se předává zvenku (viz změny návrhu níže). Pro porty testovací náhrady.
- Testy:
  - pořadí kroků: token → stažení → `step` → doručení → uložení;
  - 401 → znovu přečíst token a jednou zopakovat;
  - `tokenExpired` → API se nevolá;
  - backoff 120 / 240 / 480 / 900 s a po úspěchu zpět na 60 s;
  - 429 s `Retry-After` čeká aspoň 60 s;
  - `refreshNow` nejvýš jednou za 60 s;
  - `handleWake` spustí stažení hned.

**Commit:** `feat(core): usage monitor loop`

## Fáze 8 – Napojení na systém a `--dump`

- `SecurityCLITokenProvider`: asynchronní `Process`, čte jen `claudeAiOauth`. **Ověřit jednotky `expiresAt`**: ms, nebo s od epochy.
- `URLSessionUsageClient`: hlavičky, převod HTTP stavů na chyby, `Retry-After`.
- `UserDefaultsStateStore` (explicitní suite).
- `UserNotificationsNotifier`: okamžitá oznámení i `UNTimeIntervalNotificationTrigger` pro `fireAt`; identifikátor = dedupe klíč.
- `LoginItem` a `WakeObserver`.
- Logování přes `os.Logger` se subsystémem `local.ClaudeStatus`.
- `Main.swift --dump`: jedno stažení, vypíše snapshot a oznámení, která by odešla. **Stav neukládá**, jinak by označil oznámení za odeslaná a posunul základ dne.

**Kontrolní bod (ručně):**
- [ ] `swift run ClaudeStatus --dump`: procenta a časy resetu odpovídají `/usage` v Claude Code.
- [ ] Položka v Klíčence je nezměněná: atribut `mdat` z `security find-generic-password -s "Claude Code-credentials"` je před i po stejný.
- [ ] `log stream --predicate 'subsystem == "local.ClaudeStatus"'` ukazuje jednotlivá stažení.

**Commit:** `feat(app): platform adapters and dump mode`

## Fáze 9 – UI v liště (F1, F2, F5)

- `MenuBarLabel` zobrazuje `snapshot.menuBarText`.
- `PanelView` + `LimitRow`: pruhy, značka plánu, odpočet do resetu, útrata, čas poslední aktualizace, Obnovit / Nastavení / Ukončit.
- `SettingsView`: prahy, horizont předpovědi, přepínače oznámení, spouštění po přihlášení.
- Stavy chyby a `tokenExpired` a upozornění, když systém oznámení zakázal.
- Propojení: `UsageMonitor` se vytvoří v `App`, `start()` při spuštění, `WakeObserver` → `handleWake()`.

**Kontrolní bod (ručně, ze sestavené `.app`):**
- [ ] Lišta se obnoví do 60 s.
- [ ] Hodnoty v panelu odpovídají `--dump`.
- [ ] Nastavení přežije restart appky.

**Commit:** `feat(app): menu bar panel and settings`

## Fáze 10 – Instalace a zkušební provoz

- `scripts/bundle.sh --install`, zapnout spouštění po přihlášení a vyzkoušet odhlášení a přihlášení.
- 2–3 pracovní dny provozu, pak z logů vyhodnotit:
  - šum u předpovědi #9 (celá procenta);
  - prahy 80 % a 10 p. b.;
  - horizont 60 min.

  Upravené výchozí hodnoty zapsat do `requirements.md` (sekce „Výchozí hodnoty k ověření“).
- **Termíny v kalendáři, na kterých se dá ověřit chování:**
  - **út 20. 10. ve 22:00** týdenní reset: nový základ a rozpočet od 100 % (AC5);
  - **so–ne 24.–25. 10.:** víkendový text v liště a žádná denní oznámení (AC4, AC10);
  - **po 26. 10.:** rozpočet zahrnuje víkendové čerpání a poprvé počítá s koncem letního času.
- Nakonec aktualizovat `CLAUDE.md`: příkazy a ověřená rizika.

**Kontrolní bod:**
- [ ] Žádné zdvojené oznámení po restartu ani po probuzení.
- [ ] Rozpočty odpovídají ručnímu přepočtu.

**Commit:** `chore: tune defaults after dogfooding`

---

## Změny návrhu nalezené při plánování

Zapracují se do `docs/design.md` při implementaci.

1. **`UsageMonitor.init`** dostane parametr `sleep: @Sendable (Duration) async throws -> Void`, aby šly backoff a interval testovat bez čekání.
2. **`--dump` je jen pro čtení.** Stav načte, ale neuloží.
3. **Časy v textech se zaokrouhlují na nejbližší minutu, půlminuta nahoru** (10:52:30 → 10:53, AC9). Stejné pravidlo jako u `resets_at`.
4. **Jednotky `claudeAiOauth.expiresAt`** se ověří ve fázi 8.
