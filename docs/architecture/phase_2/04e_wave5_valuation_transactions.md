# Welle 5 — Detaildokument: valuation_transactions (UI)

Status: `done` (AP1–AP8, 2026-08-02)

Detailplan für die Welle-5-Screens nach dem Sechs-Punkte-Template aus
`03_design_system.md`. Er setzt die neue Bewertungs-Engine (`lib/features/valuation/`)
voraus und beschreibt, wie sie sichtbar wird — nicht, wie sie rechnet.

## Backend-/Engine-Voraussetzungen (erfüllt)

- **Engine** (Inkremente 1–4): `ValuationFactor`/Provenienz, fünf Verfahren
  (Ertrags-, Sach-, Vergleichswert, DCF, Direktkapitalisierung), `ValuationReconciler`
  (gewichteter Verkehrswert + Konfidenz), `ValuationCase`/`ValuationEngine` mit
  Annahmen-Ledger und Investmentkennzahlen. Deterministisch, backend-agnostisch,
  120 Tests.
- **Persistenz** (Inkrement 5): P2-D07-Kontrakt (`valuation_cases`, `valuation_factors`,
  `valuation_method_results`, `market_value_opinions`, `valuation_reference_data`)
  mit default-deny RLS, `expectedVersion`, `mutationId`, Audit und Rollback-Tests;
  Supabase- und read-only Legacy-SQLite-Adapter; Provider-Wiring in
  `app_backend_wiring.dart` (entspricht Arbeitspaket 0 der Welle — bereits `done`).

## Die eine Regel, die diese Welle sichtbar macht

Die Engine gibt statt falscher Zahlen ein begründetes **„nicht ermittelbar"** aus.
Die UI muss diese Aussage **tragen**, nicht kaschieren: kein Platzhalter-Strich, der
wie ein Ladezustand aussieht, keine graue 0, kein leeres Feld. Ein nicht verfügbares
Verfahren zeigt seinen Namen, den Status und die **konkret fehlenden Faktoren mit
Absprung zur Eingabe**. Das ist der Kern des Zielbilds jedes Screens hier.

Zweite, gleichrangige Regel: **Systemvorschläge sind sichtbar unbestätigt.** Ein
`suggestedDefault` erscheint als Vorschlag mit Quelle und Bestätigen-Aktion, nie als
bereits gültiger Wert. Erst die Bestätigung (`accepted`) macht ihn rechnend — und
verschiebt die Konfidenz des Ergebnisses sichtbar von „hoch" auf „mittel".

## Nachtrag 2026-07-30 — Bewertungen werden ein Arbeitsbereich (Nutzerentscheidung)

Nach AP1 (Wertermittlungs-Tab, `done`) hat der Nutzer den Bereich als **nicht
benutzerfreundlich** beurteilt: die eigentliche Bewertung liegt drei Klicks tief
(Objekt → Szenario → Underwriting → Tab), im Hauptmenü stehen stattdessen fünf
unverbundene Werkzeuge, und der Lebenszyklus, den der Contract kann, ist unsichtbar.
Drei Entscheidungen (2026-07-30, bestätigt):

1. **Bewertungen werden ein eigener Arbeitsbereich im Hauptmenü** — eine Liste aller
   Bewertungsfälle über alle Objekte als Arbeitsvorrat und Freigabe-Warteschlange. Das
   Objekt behält einen Absprung auf seine Fälle; der Wertermittlungs-Tab aus AP1 bleibt,
   nutzt aber dieselben Bausteine.
2. **„Echte Bewertungsszenarien" = Fallarten mit Vorlagen + Varianten je Fall.** Vier
   Fallarten (Ankauf/Bestand/Sanierung/Verkauf) mit vorausgewählten Verfahren,
   Gewichtungsvorschlag und Referenz-Vorschlägen; dazu mehrere Varianten pro Fall
   (Base/Optimistisch/Konservativ, „vor/nach Sanierung") mit Nebeneinander-Vergleich.
3. **Schnellbewertung, Renovierung und Verkauf/Exit werden ersetzt**, nicht ergänzt:
   sie werden Fallarten des neuen Workflows, ihre Menüeinträge verschwinden und die
   Screens fallen im Cutover — womit auch die dreifache IRR-Solver-Duplizierung endet.

Damit ist die Navigations-Guardrail aus `CLAUDE.md` **ausdrücklich aufgehoben** für
diesen Bereich: neue Route + geänderte Menüstruktur sind vom Nutzer beauftragt. Der
frühere Satz „keine neue Route" unten gilt nur noch für AP1.

### Zielbild der Informationsarchitektur

Hauptmenü-Gruppe „Bewertung & Szenarien" nach dem Umbau:

| Eintrag | Inhalt | Status |
|---|---|---|
| **Bewertungen** (neu) | Arbeitsvorrat aller Fälle: Objekt, Fallart, Status, Verkehrswert, Konfidenz, „Bericht veraltet"; Filter nach Status/Art/Objekt; Primäraktion „Neue Bewertung" | neu (AP3) |
| Kriterien | unverändert (Ankaufsprofile), speist die Fallart-Vorlagen | bleibt |
| Szenariovergleich | bleibt bis der Varianten-Vergleich (AP6) ihn fachlich ersetzt; danach Entscheidung über Rückbau | offen |
| ~~Schnellbewertung~~ | wird Fallart „Ankauf – Schnellprüfung" | entfällt (AP8) |
| ~~Renovierung~~ | wird Fallart „Sanierung" mit Varianten vor/nach | entfällt (AP8) |
| ~~Verkauf / Exit~~ | wird Fallart „Verkauf" | entfällt (AP8) |

Im Objekt bleibt die Sektion „Bewertung & Szenarien", verliert aber ihre Doppelrolle:
„Bewertungen" listet die Fälle *dieses* Objekts (dieselbe Liste, vorgefiltert),
„Underwriting" behält den Wertermittlungs-Tab, „Ankauf Intensivbewertung" wird zur
Faktor-Eingabe des Falls (AP2).

### Der Workflow, den es heute nicht gibt

Ein Fall wird als **fünfstufiger Stepper** geführt, der den Lifecycle des Contracts
sichtbar macht statt ihn zu verstecken:

| Schritt | Inhalt | Fertig, wenn | Status im Contract |
|---|---|---|---|
| 1 Objekt & Art | Objekt, Fallart, Variante, Verfahrensauswahl aus der Vorlage | Fall existiert | `draft` |
| 2 Faktoren | Faktor-Gruppen je Verfahren mit Provenienz, Menüs, „4 von 6" aus `ValuationFactorCatalog.progress` | jede Gruppe vollständig **oder** bewusst unvollständig quittiert | `draft` |
| 3 Ergebnis | Verfahren, Verkehrswert-Abgleich, Annahmen-Ledger, Investmentkennzahlen | Bericht veröffentlicht | `draft` |
| 4 Prüfung | Vier-Augen-Blick: Ledger + Streuung + offene Vorschläge; „Zur Prüfung geben" | Prüfer bestätigt | `in_review` |
| 5 Freigabe & Bericht | Freigabe (unwiderruflich), PDF/Export, Historie | freigegeben | `approved` |

Der Stepper erzwingt keine Reihenfolge — man darf jederzeit zurück —, aber er zeigt
**pro Schritt**, was fehlt. Ein Schritt ist nie „grün", weil man ihn besucht hat,
sondern nur, wenn seine Bedingung erfüllt ist. Schritt 3 bleibt ausdrücklich benutzbar,
wenn Verfahren „nicht ermittelbar" melden: der Verkehrswert wird dann aus den
verfügbaren Verfahren abgeleitet, und die fehlenden stehen mit Grund daneben.

### Fallart-Vorlagen (die „echten Szenarien")

Eine Vorlage setzt nichts fest, sie **schlägt vor** — alle Referenzwerte kommen als
`suggestedDefault` und müssen bestätigt werden:

| Fallart | Verfahren (aktiv) | Gewichtungsvorschlag | Fokus-Faktoren |
|---|---|---|---|
| Ankauf | alle fünf | Vergleich 35 / Ertrag 30 / DCF 20 / Sachwert 10 / Direktkap. 5 | Kaufpreis, Exit-Cap, Kalkulationszins |
| Bestand | Ertrag, Sachwert, Direktkap. | Ertrag 55 / Sachwert 25 / Direktkap. 20 | Liegenschaftszins, Restnutzungsdauer, BWK |
| Sanierung | Ertrag, Sachwert, DCF | Ertrag 40 / Sachwert 35 / DCF 25 | NHK, Alterswertminderung, Mietwachstum |
| Verkauf | Vergleich, DCF, Direktkap. | Vergleich 45 / DCF 35 / Direktkap. 20 | Vergleichspreise, Verkaufskostenquote, Exit-Cap |

Die Gewichtungen landen als `weightOverrides` auf dem Fall — der `ValuationReconciler`
renormiert sie ohnehin über die *verfügbaren* Verfahren, eine Vorlage kann also nichts
kaputt gewichten.

### Varianten — mit einer offenen Schemafrage

Eine Variante ist ein eigener `ValuationCase` zum selben Objekt, gruppiert und
benannt. Das Schema kennt diese Gruppierung heute **nicht**; drei Wege:

1. **Neue Spalten** `variant_group_id uuid` + `variant_label text` auf
   `valuation_cases` (eigene Migration in der P2-D07-Reihe, RLS unverändert,
   Rollback-Test). Klar, explizit, kostet eine Migration. **Empfehlung.**
2. `scenario_id` als Gruppierung missbrauchen — spart die Migration, verkoppelt aber
   Varianten mit dem Legacy-Szenariobegriff, den diese Welle gerade entkoppelt.
3. Varianten rein clientseitig über Titel-Konventionen — würde genau die Art von
   impliziter Semantik einführen, die dieser Rewrite abschafft. Abgelehnt.

Weg 1 braucht einen Eintrag im Decision-Register, bevor AP6 startet.

## Scope

| Screen | Rolle in dieser Welle |
|---|---|
| SCR-012 InputsScreen (2858 LOC) | Faktor-Eingabe mit Provenienz-Status, Menüs, Pflicht/fehlt-Indikatoren |
| SCR-013 AnalysisScreen (540 LOC) | **Neuer Wertermittlungs-Abschnitt**: Ergebnisse je Verfahren, Verkehrswert-Abgleich, Konfidenz, Annahmen-Ledger |
| SCR-014 CompsScreen (457 LOC) | speist das Vergleichswertverfahren (`ComparableSale`) |
| SCR-017 ScenariosScreen | Tab „Bewertungsdaten" auf `ValuationCase` |
| SCR-055 QuickScreeningScreen / SCR-057 DispositionExitScreen | Konsolidierung auf `ValuationCase` (`DUP-012`) |

**Keine neue Route.** Der Verkehrswert-Abgleich ist ein Abschnitt in SCR-013, keine
eigene Seite — das respektiert die Navigations-Guardrail aus `CLAUDE.md`. Ein
separater Wertermittlungs-Screen bleibt optional und würde gesondert bestätigt.

## Arbeitspakete nach dem Nachtrag (2026-07-30)

AP1–AP8 sind geliefert. Die Reihenfolge folgte einer Regel: **jedes Paket ist für
sich benutzbar**, und keines ließ einen halb umgebauten Menüpunkt zurück.

| # | Paket | Inhalt | Abhängt von |
|---|---|---|---|
| AP1 | Wertermittlungs-Tab | geteilte Bausteine, Verkehrswert-Karte, Ledger, alle Pflichtzustände | — (`done`) |
| AP2 | Faktor-Eingabe | `ValuationFactorCatalog` (`done`), Faktor-Zeile mit Provenienz + „Übernehmen", Gruppenkarten mit Fortschritt, Menüs die Vorschläge füllen | AP1 |
| AP3 | Arbeitsbereich „Bewertungen" | neue Route + Menüeintrag, Keyset-Liste mit Filtern, Statusspalte, „Bericht veraltet", Primäraktion „Neue Bewertung"; im Objekt dieselbe Liste vorgefiltert | AP1 |
| AP4 | Workflow-Stepper + Freigabe | fünf Schritte mit echten Fertig-Bedingungen, „Zur Prüfung geben", Freigabe mit Bestätigung, Prüfansicht | AP2, AP3 |
| AP5 | Fallart-Vorlagen | vier Vorlagen (Verfahren, Gewichtung, Referenz-Vorschläge), Anlege-Dialog aus dem Arbeitsbereich | AP4 |
| AP6 | Varianten & Vergleich | Migration (`variant_group_id`, `variant_label`) + Decision-Register-Eintrag, Varianten-Umschalter im Fall, Nebeneinander-Vergleich der Verkehrswerte | AP5 |
| AP7 | Comps-Speisung | CompsScreen → `ComparableSale`, Eignungs-Status („3 von mindestens 3") | AP2 |
| AP8 | Cutover | Menüeinträge Schnellbewertung/Renovierung/Verkauf-Exit entfernen, Legacy-Screens + die drei IRR/NPV-Solver löschen, Doks/Status fortschreiben | AP5, AP6, AP7 |

**Abschlussstand 2026-08-02:** AP1–AP8 sind `done`. AP8 hat die drei alten
Menüziele und Screens sowie `AcquisitionCalculationService`,
`RenovationCalculationService` und `DispositionCalculationService` einschließlich
ihrer direkten Tests entfernt. Historische SQLite-Tabellen, DTOs und Daten bleiben
für Migration und Nachvollziehbarkeit erhalten. Der Bewertungsbereich hat damit nur
noch einen produktiven Einstieg: den Arbeitsbereich **Bewertungen** mit Fallarten und
Varianten. Verifiziert: geänderte Dateien analyzer-sauber, 243 gezielte Bewertungs-,
Workflow-, Varianten- und Navigationstests grün.

**Reihenfolge-Begründung.** AP3 vor AP4, weil ein Stepper ohne Einstiegsliste nur den
bestehenden tiefen Klickweg reproduziert. AP5 vor AP6, weil Varianten ohne Vorlagen
lediglich leere Kopien wären. AP8 zuletzt und in einem Zug, damit nie ein halb
entfernter Menüpunkt existiert — und erst, wenn die neuen Wege alles abdecken, was die
drei Werkzeuge heute leisten (Parität wird vor dem Löschen am realen Objekt geprüft,
nicht behauptet).

**Was diese Überarbeitung ausdrücklich nicht anfasst:** die Engine (fertig und
getestet), den P2-D07-Contract (bis auf die Varianten-Spalten), die Legacy-Daten der
drei Modul-Tabellen (deren Übernahme ist Sache des Dry-Run-Mappers, nicht der UI) und
`Kriterien` (bleibt, speist die Vorlagen).

## Reihenfolge und Begründung (AP1-Stand, historisch)

1. **AP1 — Geteilte Bewertungs-Bausteine + AnalysisScreen-Abschnitt.** Die Darstellung
   von „nicht ermittelbar", Provenienz-Badges und Verfahrenskarten wird einmal gebaut
   und von allen folgenden Paketen genutzt. Der AnalysisScreen ist der Ort, an dem der
   Nutzen sofort sichtbar wird (Ergebnis vor Eingabe).
2. **AP2 — InputsScreen.** Erst wenn feststeht, wie ein fehlender Faktor *dargestellt*
   wird, lohnt sich der Umbau der Eingabe — der Absprung „fehlt → Feld" ist die
   Verbindung zwischen AP1 und AP2.
3. **AP3 — CompsScreen.** Liefert die Vergleichspreise; ohne AP1/AP2 hätte das
   Vergleichswertverfahren keine sichtbare Wirkung.
4. **AP4 — Szenarien-Tab + Quick-Screening/Disposition-Konsolidierung.** Die
   `DUP-012`-Auflösung ist der invasivste Schritt und kommt zuletzt, wenn das Muster
   dreifach bewiesen ist.

---

## AP1 — Wertermittlungs-Abschnitt in SCR-013 AnalysisScreen (Pattern-Beweis)

1. **Zielbild**: Ein Gutachten-Abschnitt statt einer Kennzahlenliste: pro Verfahren
   ein Ergebnis mit Rechenweg, darunter der **abgeglichene Verkehrswert** mit
   Gewichtung, Konfidenzband und Begründung, daneben das vollständige Annahmen-Ledger.
   Nicht verfügbare Verfahren stehen gleichberechtigt daneben — mit Grund, nicht
   ausgeblendet. Ein professioneller Nutzer sieht auf einen Blick, worauf der Wert
   beruht und was ihn noch limitiert.
2. **Layout**: `NxSectionHeader` „Wertermittlung" innerhalb des bestehenden Screens.
   Verkehrswert-Karte (`NxCard`) als Kopf: Betrag oder „nicht ermittelbar",
   `NxStatusBadge` für das Konfidenzband, Gewichtungszeile, Rationale-Text.
   Darunter Verfahrenskarten in `Wrap`/Grid (Desktop 2–3 Spalten, Tablet 2, Phone 1),
   jede mit Verfahrensname, Betrag oder Fehlbegründung, aufklappbarem Rechenweg
   (`MethodBreakdownLine` als Label/Formel/Betrag-Zeilen). Annahmen-Ledger als
   `NxDataTableShell` (Faktor, Wert, Einheit, Provenienz-Badge, Quelle), auf Phone
   horizontal scrollbar mit gepinnter Faktorspalte. Investmentkennzahlen (IRR, NPV,
   Equity-Multiple) als KPI-Tiles mit `InfoTooltip` auf die Formel; `null` bleibt
   „nicht ermittelbar", nie 0.
3. **States**: loading = Karten-Skeletons in der späteren Rasterform; empty = es gibt
   noch keinen Bewertungsfall → `NxEmptyState` „Bewertung anlegen"; error = Retry ohne
   Roh-Exception; **forbidden** = `valuation.read` fehlt, explizit getrennt von leer;
   **versionConflict** = `ValuationVersionConflict` beim Veröffentlichen mit beiden
   Ständen und Auflösen-Aktion; **read-only bis migriert** = im SQLite-Modus
   (`unsupportedByBackend`) sind Veröffentlichen/Freigeben deaktiviert mit Hinweis;
   **stale report** = `ValuationCaseDetail.hasStaleReport` zeigt „Bericht basiert auf
   einem älteren Faktorstand" mit Neuberechnen-Aktion — der Fall, den die
   Versionierungsentscheidung bewusst sichtbar lässt.
4. **Data density**: Ein Read (`valuationCaseRepositoryProvider.getValuationCaseById`)
   liefert Fall + Faktoren + letzten Bericht. Die **Anzeige rechnet live** über
   `ValuationEngine` (deterministisch, kein Backend-Roundtrip); der gespeicherte
   Bericht ist der veröffentlichte Stand und wird als solcher gekennzeichnet, wenn er
   abweicht. Verfahrenskarten standardmäßig zugeklappt außer dem führenden Verfahren;
   Annahmen-Ledger sortiert nach Faktor-ID (deterministisch wie im Engine-Ledger).
5. **Interactions**: primär „Bericht veröffentlichen" (`publishReport`, mit
   `expectedVersion`); sekundär „Vorschlag bestätigen" direkt aus einer Fehlbegründung
   heraus (`upsertFactors` mit Provenienz `accepted`); „Zur Eingabe springen" von jedem
   fehlenden Faktor zum passenden Feld in SCR-012. Freigabe (`approved`) ist eine
   **bestätigungspflichtige, folgenreiche** Aktion (danach ist der Fall unveränderlich,
   `AGG-014`) und nur mit `valuation.approve` sichtbar.
6. **Debt resolved**: löst die stillen Fehlwerte aus `proforma.dart:221-244`,
   `normalize.dart:77-85` und `metrics.dart` **UI-seitig** ein — erstmals sieht der
   Nutzer, dass ein Wert nicht ermittelbar ist, statt einer plausiblen Erfindung.
   Etabliert die geteilten Bewertungs-Widgets (`property_detail/widgets/valuation/`)
   für AP2–AP4. Neue Widget-Tests über alle Pflicht-Zustände inkl. „nicht ermittelbar"
   und „stale report".

## AP2 — SCR-012 InputsScreen (Faktor-Eingabe mit Provenienz)

1. **Zielbild**: Die Eingabemaske sagt jederzeit, **woher jeder Wert kommt** und was
   noch fehlt: eigene Eingabe, systemberechnet, Vorschlag (unbestätigt) oder bestätigt.
   Pflichtfaktoren eines Verfahrens sind als Gruppe sichtbar, inklusive Fortschritt
   („Ertragswertverfahren: 4 von 6 Faktoren"). Der Nutzer versteht ohne Handbuch,
   warum ein Verfahren noch nichts liefert.
2. **Layout**: bestehende Eingabestruktur bleibt; die Bewertungsfaktoren kommen als
   `NxFormSectionCard`-Gruppen je Verfahren dazu, mit `NxSectionHeader` und einer
   Fortschritts-/Statuszeile. Jedes Feld: Label, `CurrencyField`/`PercentField`
   (bestehende Komponenten), Provenienz-Badge, bei Vorschlägen eine Quelle-Zeile plus
   „Übernehmen"-Aktion. Menüs (Gebäudetyp → NHK/GND, Assetklasse → Liegenschaftszins-/
   Sachwertfaktor-Spanne) als `DropdownButtonFormField`, deren Auswahl einen Vorschlag
   **füllt**, nicht setzt. Phone: eine Spalte, Gruppen einklappbar.
3. **States**: loading = Feld-Skeletons; empty n. a. (Formular); error = Retry;
   **forbidden** = `valuation.manage` fehlt → Felder read-only mit Hinweis;
   **versionConflict** = paralleler Faktor-Write → Konfliktdialog mit beiden Ständen;
   **read-only bis migriert** = SQLite-Modus zeigt alle Faktorfelder lesend mit dem
   vorgeschriebenen Hinweis (Legacy-Adapter antwortet `unsupportedByBackend`);
   **unbestätigter Vorschlag** ist ein eigener, gestalteter Zustand — nicht „gültig",
   nicht „fehlt".
4. **Data density**: `valuationFactorProvider` für Lesen/Schreiben, Autosave über den
   bestehenden `SaveStatusIndicator`-/Debounce-Pfad aus `analysis_state.dart`, aber
   **eine** Mutation je Speichervorgang (`upsertFactors` nimmt mehrere Faktoren) statt
   pro Feld. Referenzwerte aus `ReferenceDataProvider` (Seed) bzw. später
   `valuation_reference_data`.
5. **Interactions**: Eingeben (→ `userProvided`), Menü wählen (→ `suggestedDefault`),
   Übernehmen (→ `accepted`), Zurücksetzen (→ Faktor entfernen, `removeFactorIds`;
   dokumentiert, dass das abhängige Verfahren dadurch wieder „nicht ermittelbar" wird —
   das ist gewollt, kein Fehler). Keine Löschung des Falls hier.
6. **Debt resolved**: `BIG-*`-Anteil von 2858 LOC wird durch Auslagern der
   Bewertungsgruppen in geteilte Widgets reduziert; die stille Default-Übernahme aus
   `normalize.dart:77-85` verschwindet aus der Bedienung — ein Vorschlag ist ab jetzt
   ein sichtbarer, bestätigungspflichtiger Schritt.

## SCR-014 CompsScreen (Speisung des Vergleichswertverfahrens) — jetzt AP7

1. **Zielbild**: Vergleichsobjekte sind nicht mehr nur eine Liste, sondern der
   **Input eines Verfahrens**: pro Comp der angepasste €/m²-Preis, sichtbar welche
   Zu-/Abschläge wirken, und wie viele geeignete Comps noch bis zur Verfügbarkeit des
   Verfahrens fehlen.
2. **Layout**: bestehende Liste auf `NxDataTableShell` (Objekt, Kaufpreis, Fläche,
   Anpassungsfaktor, angepasster €/m²); Kopfzeile mit Eignungs-Status
   („3 von mindestens 3 geeigneten Vergleichspreisen") als `NxStatusBadge`.
3. **States**: loading/empty (`NxEmptyState` „Erstes Vergleichsobjekt erfassen")/error/
   forbidden wie AP1; **zu wenige Comps** ist ein eigener, positiv formulierter
   Zustand mit der konkreten Restzahl — er entspricht exakt der
   `MethodUnavailable`-Begründung der Engine.
4. **Data density**: Comps stammen weiterhin aus dem Legacy-`comps`-Bestand
   (`comps_repo`), bis das `comps`-Aggregat des P2-D07-Scope migriert ist — **benannte
   Lücke**, keine erfundene Zwischenlösung. Die Umrechnung auf `ComparableSale` liegt
   in einer geteilten Mapper-Funktion, nicht im Screen.
5. **Interactions**: Comp anlegen/bearbeiten/entfernen; Anpassungsfaktor je Comp
   pflegen; „Im Vergleichswertverfahren verwenden" als Auswahl, damit ungeeignete
   Comps in der Liste bleiben, ohne das Verfahren zu verfälschen.
6. **Debt resolved**: Der Screen bekommt erstmals eine Wirkung über die reine Ablage
   hinaus; Farbliterale/`Card`-Eigenbau → `nx_*`.

## SCR-017 Bewertungsdaten-Tab + SCR-055/SCR-057 Konsolidierung (`DUP-012`) — AP5/AP8 (`done`)

1. **Zielbild**: Ein Szenario zeigt seine Bewertungsdaten im selben Muster wie der
   AnalysisScreen; Quick-Screening und Disposition-Exit arbeiten nicht mehr auf drei
   getrennten Modul-Services mit je eigenem IRR-Solver, sondern auf **einem**
   `ValuationCase` mit passender `ValuationCaseKind`.
2. **Layout**: Szenarien-Tab „Bewertungsdaten" = Verfahrenskarten + Verkehrswert-Karte
   aus AP1, ohne Ledger (Platz); Quick-Screening behält seine schlanke Eingabe, zeigt
   aber die Direktkapitalisierungs-/DCF-Ergebnisse der neuen Engine; Disposition-Exit
   nutzt Verkehrswert + Exit-Szenario derselben Engine.
3. **States**: identischer Pflichtzustandssatz; zusätzlich in SCR-055/057 der Zustand
   **„Fall noch nicht angelegt"** mit einer Aktion, die einen `ValuationCase` der
   jeweiligen Art erzeugt.
4. **Data density**: ein Read je Fall; keine parallelen Modul-Reads mehr.
5. **Interactions**: Anlegen/Bearbeiten wie AP1/AP2; Freigabe nur im Szenario-Kontext.
6. **Debt resolved**: **`DUP-012`** — Acquisition/Renovation/Disposition kollabieren
   auf `ValuationCase`; die drei duplizierten IRR/NPV-Solver in `lib/core/services/`
   werden in **Inkrement 7 (Cutover)** entfernt, nicht hier — dieses Paket macht sie
   nur konsumentenlos.

---

## Querschnittsthemen der Welle

- **Geteilte Bewertungs-Bausteine**: Verfahrenskarte, „nicht ermittelbar"-Darstellung,
  Provenienz-Badge, Verkehrswert-Karte und Annahmen-Ledger liegen einmal unter
  `lib/ui/screens/property_detail/widgets/valuation/` und werden von AP1–AP4 genutzt.
- **`NxStatusBadge` als einzige Statusquelle**: `ValuationCaseStatus`,
  `FactorProvenance` und `ConfidenceBand` bekommen je eine konsistente Abbildung —
  kein per-Screen-Chip. Kein Farb-only-Signal: jede Badge trägt Text.
- **Live-Rechnung vs. veröffentlichter Bericht**: die UI trennt beides sichtbar. Die
  Engine rechnet lokal für die Anzeige; `market_value_opinions` hält den
  veröffentlichten Stand. Abweichung = sichtbarer „veraltet"-Hinweis, kein stilles
  Überschreiben.
- **Freigabe ist endgültig**: eine `approved` Bewertung ist serverseitig unveränderlich
  (`AGG-014`, Fehlercode `approved_immutable`). Die UI kündigt das vor der Bestätigung
  an und bietet danach nur noch „neue Version anlegen".
- **Backend-Modus**: Supabase-Modus voll mutierend; SQLite-Modus lesend mit dem
  Pflicht-Hinweis. Die Legacy-Projektion liefert bewusst nur zwei Faktoren
  (Exit-Cap, manueller Reinertrag) — die UI zeigt daher dort im Normalfall
  „nicht ermittelbar", und das ist die korrekte Aussage, kein Defekt.
- **Nicht in W5** (bewusst): `comps`-Aggregat-Migration; Report-PDF-Integration des
  Annahmen-Ledgers (`report_builder.dart`) folgt in Inkrement 6c/8. Die drei
  parallelen Modul-Services wurden mit AP8 entfernt; die übrige Legacy-Datenhaltung
  bleibt bis zum Migration-Cutover bestehen.

## Definition of done

**Je Arbeitspaket:** Sechs-Punkte-Plan → Umsetzung gegen die Feature-Contracts (keine
Legacy-Repos in neuen Pfaden) → `flutter analyze --no-pub` sauber → gezielte
Widget-Tests grün inkl. `forbidden`/`versionConflict`/`read-only bis migriert`/
**„nicht ermittelbar"**/`stale report` → Responsive-Check an 390×844 / 1024×768 /
1440×900 → manueller Golden-Path im Supabase-Modus → `00_phase_2_status.md`
evidenzbasiert fortgeschrieben. Volle Suite mindestens am Paketende.

**Wellenabschluss:** AP1–AP8 `done`; kein Welle-5-Screen liest die Legacy-Engine für
Bewertungsergebnisse; `DUP-012` UI-seitig aufgelöst; die Fehlbehandlung ist an einem
realen Objekt manuell nachgewiesen (Objekt ohne Liegenschaftszins/Bodenrichtwert →
Ertrags-/Sachwert „nicht ermittelbar" + Grund; nach Bestätigung eines Vorschlags
erscheint der Wert mit Konfidenz- und Annahme-Kennzeichnung); volle Suite + analyze
grün; Check-in beim Nutzer an der Wellengrenze.
