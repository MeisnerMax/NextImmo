# Welle 5 — Detaildokument: valuation_transactions (UI)

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

## Reihenfolge und Begründung

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

## AP3 — SCR-014 CompsScreen (Speisung des Vergleichswertverfahrens)

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

## AP4 — SCR-017 Bewertungsdaten-Tab + SCR-055/SCR-057 Konsolidierung (`DUP-012`)

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
  Annahmen-Ledgers (`report_builder.dart`) folgt in Inkrement 6c/8; Entfernen der
  Legacy-Engine und der Modul-Services (Inkrement 7).

## Definition of done

**Je Arbeitspaket:** Sechs-Punkte-Plan → Umsetzung gegen die Feature-Contracts (keine
Legacy-Repos in neuen Pfaden) → `flutter analyze --no-pub` sauber → gezielte
Widget-Tests grün inkl. `forbidden`/`versionConflict`/`read-only bis migriert`/
**„nicht ermittelbar"**/`stale report` → Responsive-Check an 390×844 / 1024×768 /
1440×900 → manueller Golden-Path im Supabase-Modus → `00_phase_2_status.md`
evidenzbasiert fortgeschrieben. Volle Suite mindestens am Paketende.

**Wellenabschluss:** AP1–AP4 `done`; kein Welle-5-Screen liest die Legacy-Engine für
Bewertungsergebnisse; `DUP-012` UI-seitig aufgelöst; die Fehlbehandlung ist an einem
realen Objekt manuell nachgewiesen (Objekt ohne Liegenschaftszins/Bodenrichtwert →
Ertrags-/Sachwert „nicht ermittelbar" + Grund; nach Bestätigung eines Vorschlags
erscheint der Wert mit Konfidenz- und Annahme-Kennzeichnung); volle Suite + analyze
grün; Check-in beim Nutzer an der Wellengrenze.
