# Požadavky – claude-status

Stav: požadavky uzavřené (brainstorm 15. 10. 2026). Další krok je návrh architektury.

## Cíl

Vystačit s týdenním limitem Claude na celý pracovní týden a nenarazit nečekaně na 5h limit. Appka v horní liště ukazuje stav a upozorní včas, dokud se dá ještě něco udělat.

Uživatel je jeden člověk (vlastník účtu) s jedním Macem. Jeho předplatné má 5h a týdenní limit a placené čerpání (extra usage) má zapnuté.

## Pojmy

| Pojem | Význam |
|---|---|
| 5h limit | Limit relace (`limits[kind=session]`). Resetuje se 5 h od začátku okna. |
| Týdenní limit | `limits[kind=weekly_all]`. Pevné 7denní okno, teď vždy od úterý 22:00 do úterý 22:00. |
| Denní rozpočet | Kolik procentních bodů týdenního limitu smí padnout dnes, aby zbytek vystačil do resetu. API ho nevrací, appka ho počítá. |
| Pracovní den | Po–Pá. Sobota a neděle mají rozpočet 0. |
| p. b. | Procentní body týdenního limitu. |

## Funkční požadavky

### F1 Položka v liště

- Vedle hodin je text `◐ 5h 82%  den 64%`:
  - `5h` je využití 5h limitu;
  - `den` je dnešní čerpání ÷ dnešní rozpočet a může přesáhnout 100 %.
- O víkendu je místo `den …` text `víkend +X p. b.`. Nic víc, žádné oznámení navíc.
- Když data chybějí, lišta to ukáže (`5h –`). U starých dat ukáže, jak jsou stará.
- Appka nemá ikonu v Docku.

### F2 Rozbalovací panel (po kliknutí na položku)

- **5h limit:** pruh, %, čas resetu a odpočet („reset 12:20, za 14 min“).
- **Dnešní rozpočet:** pruh, čerpání a rozpočet v p. b. a v %.
- **Týdenní limit:** pruh, %, značka „kde bys měl být podle plánu“ a den s časem resetu.
- **Týdenní limit pro model** (teď Fable): pruh, % a reset.
- **Placené čerpání:** utraceno a měsíční strop v €.
- Čas poslední aktualizace a tlačítka Obnovit, Nastavení a Ukončit.

### F3 Denní rozpočet

- **Jen pracovní dny.** Zbytek týdenního limitu se dělí jen mezi pracovní dny, které zbývají do resetu. Den resetu se počítá poměrně: do 22:00 je to 22/24 dne.
- **Průběžný přepočet.** Rozpočet se počítá znovu na začátku každého dne a po resetu týdne, vždy z toho, co z týdne zbývá. Nevyčerpaný rozpočet přejde do dalších dnů a přečerpaný je úměrně zmenší.
- **Víkend.** Co spotřebuješ o víkendu, ubere z rozpočtu následujících pracovních dnů.
- **Svátky a dovolená** se neřeší a počítají se jako běžné pracovní dny. Nevyčerpaný rozpočet z nich přejde do dalších dnů.
- **Den začíná o půlnoci** místního času.
- **Příklad** (čísla jsou smyšlená): ve čtvrtek v 00:00 je týden vyčerpaný na 20 % a reset je v úterý ve 22:00. Zbývá čt + pá + po + 22/24 út = 3,92 dne, takže čtvrteční rozpočet je 80 ÷ 3,92 ≈ 20,4 p. b.

### F4 Oznámení

| # | Oznámení | Kdy | Kolikrát |
|---|---|---|---|
| 1 | 5h blízko | ≥ 80 % | 1× za okno |
| 2 | 5h dosažen | 100 % | 1× za okno |
| 3 | 5h je zpět | Okno se resetovalo a v předchozím okně bylo dosaženo ≥ 80 % | 1× za okno |
| 4 | Předpověď 5h | Při tempu posledních ~15 min narazíš na limit ještě před resetem, např. „Tímto tempem narazíš na 5h limit ve 14:35“. Přijde obvykle dřív než #1. | 1× za okno |
| 5 | Den blízko | Čerpání ≥ 80 % dnešního rozpočtu | 1× za den |
| 6 | Den dosažen | Čerpání ≥ 100 % dnešního rozpočtu | 1× za den |
| 7 | Týdenní tempo | Týdenní % je o víc než 10 p. b. nad plánem (plán = rovnoměrné rozložení na pracovní dny) | nejvýš 1× za den |
| 8 | Placené čerpání | Utracená částka extra usage vzrostla | 1× za den, i s částkou |
| 9 | Předpověď den | Při tempu posledních ~15 min vyčerpáš dnešní rozpočet do 60 min, např. „Tímto tempem vyčerpáš dnešní rozpočet v 15:10“. Při velkém tempu přijde dřív než #5. | 1× za den |

- **Předpovědi** (#4, #9) se počítají až z aspoň 15 minut dat v okně nebo v daném dni, aby začátek nedával planý poplach.
- **O víkendu** denní oznámení (#5, #6, #9) nechodí. 5h a týdenní oznámení chodí dál.
- **Měsíční strop placeného čerpání** se nehlídá, jen se ukazuje v panelu.
- **Styl a zvuk.** Oznámení jsou bannery, které zmizí samy. Zvuk mají jen #2 a #6, ostatní jsou tichá.
- **Čas resetu.** Text oznámení o 5h a týdenním limitu obsahuje čas resetu v místním čase.
- **Výchozí hodnoty** (prahy 80 %, 10 p. b. a horizont předpovědi 60 min) jdou změnit v nastavení.
- **Stejné oznámení nepřijde podruhé**, ani po restartu appky.

### F5 Nastavení

- Prahy upozornění (5h limit, denní rozpočet, týdenní tempo) a horizont denní předpovědi.
- Zapnutí a vypnutí jednotlivých oznámení z F4.
- Spouštění po přihlášení, ve výchozím stavu zapnuté.

## Nefunkční požadavky

- **Jen pro tento Mac.** macOS 14+ (teď 26). Xcode tu není, takže se sestavuje přes SwiftPM.
- **Přihlášení appka jen čte.** Bere ho z Klíčenky Claude Code a nikdy ho neobnovuje ani nemění. Když vyprší, appka ukáže „otevři Claude Code“.
- **Data neopouštějí Mac** kromě volání `api.anthropic.com`.
- **Šetrnost.** Dotaz na API nejvýš 1× za 60 s. Po probuzení Macu se data obnoví hned.
- **Odolnost.** API není zdokumentované. Když se změní tvar odpovědi, smí to rozbít nanejvýš jeden ukazatel, ne celou appku. Při chybě appka ukáže poslední známé hodnoty a jak jsou staré.
- **Lokalizace.** Texty česky, čas ve 24h formátu, místní časové pásmo.

## Akceptační kritéria

1. **5h limit stoupne ze 79 % na 81 %:** přijde právě jedno oznámení „blízko“ s časem resetu. Další hodnoty v tomtéž okně (85 %, 90 %) ani restart appky žádné další nepošlou.
2. **Dnešní rozpočet je 20 p. b. a dnes padlo 16,5 p. b.:** lišta ukazuje `den 83%` a přijde oznámení „Den blízko“.
3. **V pátek přečerpáš rozpočet o 5 p. b.:** rozpočty zbývajících pracovních dnů do resetu se úměrně zmenší, víkendové dny zůstanou na 0.
4. **V sobotu spotřebuješ 3 p. b.:** lišta ukazuje `víkend +3 p. b.` a pondělní a další rozpočty jsou o tyto 3 p. b. (rozložené) menší.
5. **V úterý ve 22:00 se týdenní limit resetuje:** rozpočet se ještě týž večer přepočítá od 100 %.
6. **5h okno skončí po dosažení 100 %:** přijde oznámení „5h je zpět“.
7. **Token vyprší:** lišta ukáže chybový stav, panel poradí otevřít Claude Code a Klíčenka zůstane nedotčená.
8. **API vrátí odpověď bez `limits[]`, jen s `five_hour` a `seven_day`:** appka funguje dál bez výpadku.
9. **Dnešní rozpočet je 20 p. b., v 10:00 padlo 13 p. b. a tempo posledních 15 min je 8 p. b./h:** přijde #9 „Tímto tempem vyčerpáš dnešní rozpočet v 10:53“, i když práh 80 % (#5) ještě dosažený není.
10. **V sobotu čerpáš:** #5, #6 ani #9 nepřijdou, oznámení o 5h limitu ano.

## Otevřené otázky

Žádné. Tyto výchozí hodnoty se ověří až provozem:
- prahy 80 % a 10 p. b.;
- horizont denní předpovědi 60 min;
- tempo měřené za ~15 min.
