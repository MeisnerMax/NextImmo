# Welle 1 — Detaildokument: portfolio_property + identity_access (UI)

Status: `active` (Ausführungsgrundlage der Welle 1)
Stand: 2026-07-20
Bezug: `04_screen_redesign_wave_plan.md` (Wellenzuordnung + zwei Worked Examples als Qualitätsmaßstab), `03_design_system.md` (Sechs-Punkte-Template, Pflicht-Komponenten, Pflicht-Zustände), `00_phase_2_status.md` (Ist-Stand).

## Backend-Voraussetzungen

- `portfolio_property` ist der abgeschlossene Referenzschnitt (P1-001..P1-021) — Welle 1 ist für diese Domäne **UI-only**, kein neues Backend.
- `identity_access`: Der P1-Stand (Auth, MFA/AAL2, RLS-Baseline) ist die Grundlage. `P2-D01` (Membership-Invitation-Flow, Supabase-Rollen-UI) ist `proposed` und **keine Voraussetzung dieser Welle** (Welle 1 hängt laut Wellenplan nur an Welle 0). Konsequenz für SCR-061 siehe dort.
- Alle Screens konsumieren ausschließlich Riverpod-Provider/Repositories (Audit 2026-07-20: kein direkter SQLite/Supabase-Zugriff in einem Welle-1-Screen) — die Redesigns ändern keine Datenverträge.

## Scope

| SCR | Screen | Datei (Ist) | LOC (Ist) | Status in W1 |
|---|---|---|---|---|
| SCR-005/007/009 | Dashboard-Wrapper, Properties V1, PropertyShellV2 | — | — | **bereits in W0 erledigt** (MOD-CLEAN-002..004) |
| SCR-006 | PropertiesScreen | `lib/ui/screens/properties_screen.dart` | 975 | Arbeitspaket 1 (Pattern-Beweis) |
| SCR-010 | PropertyShell | `lib/ui/screens/property_detail/property_shell.dart` | 1052 | Arbeitspaket 2 |
| SCR-011 | OverviewScreen | `lib/ui/screens/property_detail/overview_screen.dart` | 2064 | Arbeitspaket 3 |
| SCR-004 | DashboardScreen | `lib/ui/screens/dashboard_screen.dart` | 2258 | Arbeitspaket 4 |
| SCR-008 | PropertyCreationWorkflowScreen | `lib/ui/screens/properties/property_creation_workflow_screen.dart` | 1791 | Arbeitspaket 5 |
| SCR-043/044 | PortfoliosScreen + PortfolioDetailScreen | `lib/ui/screens/portfolios_screen.dart` | 2958 | Arbeitspaket 6 (Datei-Split) |
| SCR-045 | PortfolioAnalyticsScreen | `lib/ui/screens/portfolio/portfolio_analytics_screen.dart` | 498 | Arbeitspaket 7 (parallelisierbar) |
| SCR-046 | DataQualityDashboardScreen | `lib/ui/screens/portfolio/data_quality_dashboard_screen.dart` | 303 | Arbeitspaket 7 (parallelisierbar) |
| SCR-061 | UsersScreen | `lib/ui/screens/admin/users_screen.dart` | 547 | Arbeitspaket 7 (parallelisierbar) |
| SCR-062 | SettingsScreen | `lib/ui/screens/settings_screen.dart` | 2211 | Arbeitspaket 8 (zuletzt) |
| — | DEBT-012 (deletePermanently → Archiv/Tombstone) | `lib/data/repositories/property_repo.dart` | — | Arbeitspaket 9 (eigener Plan, Hard-Stop vor Umsetzung) |

## Reihenfolge und Begründung

1. **PropertiesScreen zuerst** — er ist die zweite Hälfte von Worked Example 2 und der Pattern-Beweis für `NxPageHeader` + `NxDataTableShell` (beide heute mit 0 bzw. 2 Nutzungen in der Codebasis). Erst wenn das Muster hier steht, lohnt Delegation der übrigen Screens.
2. **PropertyShell vor OverviewScreen** — alle Property-Detail-Screens rendern in dieser Shell; ihr Rahmen (Header, Szenario-Wahl, Navigation) bestimmt, wie viel Kopf-Fläche OverviewScreen selbst noch braucht.
3. **OverviewScreen, dann DashboardScreen** — die beiden größten Hex-Hotspots (~48 bzw. ~28 Literale), beide durch Worked Examples abgedeckt.
4. **CreationWorkflow und Portfolios-Split** — große, in sich geschlossene Umbauten ohne Abhängigkeit zueinander.
5. **Analytics / DataQuality / Users parallel** — klein, unabhängig, klar spezifizierbar → je ein Subagent mit eigenständigem Brief, sobald das Muster aus Paket 1–3 bewiesen ist.
6. **SettingsScreen zuletzt** — größter Einzelscreen mit Querbezügen in fast alle Domänen; profitiert von allen vorher etablierten Bausteinen. Domänen-Sektionen werden nur visuell gehoben, Inhalte werden pro späterer Welle aufgefrischt (Wellenplan, Hinweis zu SCR-062).
7. **DEBT-012 als Abschluss** — Verhaltensänderung am Löschpfad, nicht reines Redesign; eigener Plan + Nutzerfreigabe (Hard-Stop, destruktiver Pfad).

Präzisierung gegenüber Worked Example 2: das dort erwähnte Desktop-„Liste + Detail nebeneinander" ist im Reference Slice (`lib/features/reference_slice/`) bereits implementiert und getestet. Der Legacy-`PropertiesScreen` behält in Welle 1 seine bestehende Navigation (Liste → `PropertyShell`) — eine Zusammenführung mit dem adaptiven Reference-Slice-Pattern wäre eine Navigationsänderung und setzt die (nicht in W1 geplante) Migration des Screens auf die Feature-Architektur voraus. Falls das anders gewollt ist: Nutzerentscheidung, nicht stillschweigend umbauen.

---

## SCR-006 — PropertiesScreen (Arbeitspaket 1, Pattern-Beweis)

1. **Zielbild**: Der tägliche Haupteinstieg — schnelle Suche/Filterung über potenziell hunderte Objekte, Status auf einen Blick, ein Klick ins Detail. Ruhige, tabellarisch dichte Darstellung statt der heutigen KPI-Kachel+Karten-Mischfläche; Karten bleiben als sekundäre Ansicht (Titelbilder) erhalten.
2. **Layout**: `NxPageHeader` (Titel, Suche, Primäraktion „Neues Objekt" → CreationWorkflow, Ansicht-Umschalter Tabelle/Karten). KPI-Zeile als `NxCard`-Tiles (heute ad hoc `_buildKpisHeader`). Hauptbereich: `NxDataTableShell` mit den `PropertySummaryDto`-Spalten des Referenzschnitts (Name, Adresse, Status via `NxStatusBadge`, eine KPI-Spalte); weitere Spalten hinter einem Column-Picker. Kartenansicht nutzt die bestehenden `NxCard`-basierten Property-Cards. Phone: KPI-Zeile wrappt auf 1 Spalte, Tabelle horizontal scrollbar mit gepinnter Namensspalte; Tablet: 2-spaltige KPI-Zeile.
3. **States**: loading = Skeleton in Tabellen-/Kachelform (kein Vollflächen-Spinner); empty = `NxEmptyState` „Lege dein erstes Objekt an" → CreationWorkflow; error = Retry-Aktion ohne Roh-Exception. forbidden/conflict: n. a. (Navigation ist capability-gated, Liste mutiert nicht) — Statuswechsel siehe Interactions.
4. **Data density**: Datenquelle bleibt `propertiesControllerProvider` (+ `propertyTitleImageProvider`, `portfolioAnalyticsRepositoryProvider` für KPI-Zeile). Sortierung + gespeicherte Filter als reine UI-Schicht; keine neuen Backend-Anforderungen.
5. **Interactions**: Zeilen-/Kartenklick → Detail (bestehende Navigation über `selectedPropertyIdProvider`); Primäraktion Anlegen; Statuswechsel (Archivieren) nur mit Bestätigungsdialog — echter Workflow-Übergang (`STM-002`), kein Soft-Toggle und kein Hard-Delete aus der Liste (Vorgriff auf DEBT-012).
6. **Debt resolved**: BIG-026-Rest (KPI-Header, Grid/Tabelle, Card in eigene Widget-Dateien unter `lib/ui/screens/properties/widgets/`); ~32 Farb-Literale + 3 per-Screen-TextStyles → Tokens/`textTheme`; DUP-003 ist bereits erledigt (W0). Neuer dedizierter Widget-Test für die Pflicht-Zustände (heute nur Paritätstest).

## SCR-010 — PropertyShell (Arbeitspaket 2)

1. **Zielbild**: Ruhiger Detail-Rahmen: oben Objektname, Status-Badge, Szenario-Auswahl; darunter die Modul-Navigation gruppiert nach Domänen (Analyse, Bewirtschaftung, Dokumente/Compliance, Finanzen, Module) statt einer flachen 32-Ziele-Leiste. Die Navigation selbst (Ziele, `PropertyDetailPage`-Enum, Routing-Verhalten) bleibt unverändert — nur Darstellung und Struktur werden gehoben.
2. **Layout**: `NxPageHeader` als Objekt-Kopf (Name, `NxStatusBadge`, Szenario-Picker als Header-Aktion). Modul-Navigation als gruppierte, horizontale Sektionen (Desktop/Tablet) bzw. kompaktes Dropdown/Sheet (Phone, ersetzt `_buildNarrowNavigation`-Ad-hoc-Bau). Content-Router (`_buildDetailPage`) bleibt funktional identisch.
3. **States**: loading (Szenarien/Objekt) als Skeleton im Kopf; error mit Retry; empty = „kein Szenario" führt sichtbar in die bestehende Auto-Szenario-Anlage (`autoScenarioCreationInFlightProvider`) statt leerer Fläche; forbidden = Module, deren Capability fehlt, erscheinen nicht (bestehende RBAC-Logik, kein neues Verhalten).
4. **Data density**: unverändert — `scenariosByPropertyProvider`, `propertiesControllerProvider`, `propertyHasHotelModulesProvider` etc.; keine neuen Reads.
5. **Interactions**: Modulwechsel, Szenario-Wechsel (mit sichtbarem Kontext, welches Szenario aktiv ist), Zurück zur Liste. Keine destruktiven Aktionen in der Shell.
6. **Debt resolved**: BIG-024 — Split in `property_shell.dart` (Gerüst), `property_nav.dart` (Gruppen/Einträge/Capability-Mapping), `property_page_router.dart` (Enum→Screen); ~25 Farb-Literale + 6 TextStyles → Tokens (DEBT-TOKEN-001-W1-Anteil); bestehender `property_shell_navigation_test.dart` bleibt grün, ergänzt um Zustands-Widget-Test.

## SCR-011 — OverviewScreen (Arbeitspaket 3)

1. **Zielbild**: Das Detail führt mit den Zahlen, die ein Portfolio-Manager zuerst prüft (Belegung, NOI-Trend, nächste Mietvertragsfälligkeit, offene Aufgaben) — vor jeder Rohfeld-Liste. Workflow-Pipeline und Onboarding bleiben, aber als ruhige, klar getrennte Sektionen statt 2064-LOC-Monolith.
2. **Layout**: Sektionen mit `NxSectionHeader` (ersetzt `_buildSectionHeader`): (1) Metric-Grid als `NxCard`-Tiles, (2) Workflow-Pipeline als eigenes Widget, (3) Snapshot-Sektionen, (4) Charts (Cashflow, Mietprojektion) in `NxChartContainer` (ersetzt die Ad-hoc-Chart-Cards). Desktop 2-spaltig (Metrics+Snapshots links, Charts rechts), Tablet/Phone gestapelt.
3. **States**: loading pro Sektion (Tiles/Charts unabhängig, kein Vollflächen-Spinner); empty = bestehende Onboarding-Card als `NxEmptyState`-konforme „nächster Schritt"-Führung; error pro Sektion mit Retry. forbidden/conflict n. a. (lesende Sicht; Mutationen liegen in den Modul-Screens).
4. **Data density**: unverändert `propertiesControllerProvider`, `scenarioAnalysisControllerProvider`, `propertyTitleImageProvider`; keine neuen Aggregationen — nur Präsentation.
5. **Interactions**: Jede Kennzahl/Pipeline-Stufe navigiert direkt zum Quell-Modul (`propertyDetailPageProvider`), nie zu einer generischen Liste; Tooltips (`InfoTooltip`) für abgeleitete Kennzahlen (Formel ein Hover entfernt).
6. **Debt resolved**: BIG-010 — Split in Sektions-Widgets unter `property_detail/overview/`; ~48 Farb-Literale (größter Hotspot der Codebasis) + 2 TextStyles → Tokens; Screen löst sich von `AppColors.background`-als-Weiß (W1-Anteil DEBT-TOKEN-001). Neuer Widget-Test (heute keiner).

## SCR-004 — DashboardScreen (Arbeitspaket 4)

Worked Example 1 aus `04_screen_redesign_wave_plan.md` gilt unverändert als Design; Präzisierungen aus dem Ist-Audit:

1. **Zielbild**: wie Worked Example 1 — echte Executive Summary (Portfolio-Gesundheit, Fälligkeiten, Auffälligkeiten) ohne Navigation.
2. **Layout**: `NxPageHeader` (Workspace + Zeitraum-Wahl), KPI-Zeile als `NxCard`-Tiles (wrappt 2-spaltig Tablet / 1-spaltig Phone), Desktop-Body 2-spaltig: Attention-Liste links, Wertentwicklungs-/Trend-Charts in `NxChartContainer` rechts; darunter Aktivitätstabelle als `NxDataTableShell` (ersetzt die Ad-hoc-Tabelle OBJEKT/BEREICH/DATUM/AKTION).
3. **States**: Skeleton pro KPI-Tile (Tiles lösen unabhängig auf); empty = `NxEmptyState` „Lege dein erstes Objekt an"; error pro Sektion mit Retry; forbidden n. a. (Inhalt ist rollenbasiert gefiltert via `activeUserRoleProvider`, kein Zugriffsverbot auf den Screen selbst).
4. **Data density**: weiterhin `dashboardOverviewProvider` + lokale Aggregation — kein Dashboard-Inhalt darf auf nicht-migrierte Domänen (`P2-D09`) warten.
5. **Interactions**: Zeitraum-Wahl als einziger dashboard-weiter State; jede Attention-Zeile navigiert direkt zur Quelle (bestehende `selectedPropertyIdProvider`/`globalPageProvider`-Navigation).
6. **Debt resolved**: BIG-007 (Ist: 2258 LOC) — Split in KPI-Tile-, Attention-List- und Chart-Sektions-Widgets unter `dashboard/`; ~28 Farb-Literale → Tokens; DUP-002 bereits in W0 erledigt. Bestehender `dashboard_screen_test.dart` wird um Pflicht-Zustände erweitert.

## SCR-008 — PropertyCreationWorkflowScreen (Arbeitspaket 5)

1. **Zielbild**: Der 12-Schritte-Wizard (Entry → … → Save) fühlt sich wie ein geführter, professioneller Erfassungsprozess an: klarer Fortschritt, Pflicht-/Optionalfelder erkennbar, Zusammenfassung vor dem Speichern. Schrittumfang und Validierungslogik bleiben unverändert.
2. **Layout**: Material-`AppBar` entfällt → `NxPageHeader` (Titel + Abbrechen). Desktop/Tablet: Schritt-Navigation als linke Rail (bestehende `_StepNavTile`-Logik, visuell auf Tokens); Phone: kompakter Fortschritts-Kopf. Jeder Schritt in `NxFormSectionCard`(s); Fußzeile als `NxActionToolbar` (Zurück/Weiter/Speichern). `ResponsiveConstraints` bleibt.
3. **States**: Validierungsfehler inline am Feld (kein Sammel-Snackbar); Save-Step: loading (vorhanden), error mit Retry ohne Datenverlust; empty n. a.; forbidden: Anlage nur mit `property.create`-Capability (Navigation dorthin ist bereits gated — im Screen kein Zusatz-UI nötig); conflict n. a. (Neuanlage).
4. **Data density**: Formularlogik bleibt lokaler State (kein Provider-Read im Screen — bestätigt im Audit); Persistenz weiterhin ausschließlich im Save-Step.
5. **Interactions**: explizites Speichern am Ende (kein Autosave nachrüsten — wäre neues Verhalten); Abbrechen mit Bestätigung bei ungespeicherten Eingaben; Units-/Tenants-Editoren behalten ihre Funktion, visuell auf `NxCard`/Token-Basis.
6. **Debt resolved**: BIG-012 — Split: ein Datei-Modul pro Schrittgruppe (`properties/creation/steps/…`) + schlanker Wizard-Container; ~28 Farb-Literale → Tokens. Erster dedizierter Widget-Test (Schritt-Navigation + Validierungs-/Save-Zustände; heute testlos).

## SCR-043/044 — PortfoliosScreen + PortfolioDetailScreen (Arbeitspaket 6)

1. **Zielbild**: Portfolios bekommen dasselbe Listen→Detail-Muster wie Objekte: Liste mit Status und Kern-KPIs, Detail mit Tabs (Dashboard, Analyse, Objekte, Notizen), die ruhig und konsistent aussehen. Der 2958-LOC-Monolith wird in Liste/Detail/geteilte Widgets zerlegt.
2. **Layout**: Split in `portfolio/portfolios_screen.dart` (Liste), `portfolio/portfolio_detail_screen.dart`, `portfolio/widgets/…`. Liste: `NxPageHeader` (+ „Neues Portfolio"), `NxDataTableShell` (Name, Objektanzahl, Kern-KPI, Status-Badge); Eigenkapital-Dashboard-Tab bleibt, als `NxCard`/`NxChartContainer`-Sektionen. Detail: `NxPageHeader` (Portfolioname + Aktionen), Material-`TabBar` bleibt (bestehendes Navigationsmuster), Tab-Inhalte auf `NxCard`/`NxSectionHeader`/`NxChartContainer`-Basis; Objekte-Tab nutzt dieselbe Tabellen-Komponente wie SCR-006.
3. **States**: loading/empty/error pro Tab-Inhalt (kein Vollflächen-Spinner); empty-Liste = `NxEmptyState` „Lege dein erstes Portfolio an"; error mit Retry statt der heute 11 verstreuten Error-Zweige; forbidden/conflict n. a. (Mutationen: Anlegen/Notizen — Konfliktverhalten bleibt wie im Repository definiert).
4. **Data density**: die breite Provider-Palette (12 Repos, u. a. `portfolioRepositoryProvider`, `portfolioAnalyticsRepositoryProvider`, `notesRepositoryProvider`) bleibt unverändert — der Split ist Präsentations-Refactoring, keine Datenvertragsänderung.
5. **Interactions**: Listenzeile → Detail; Anlegen/Umbenennen als Dialoge; Notizen mit explizitem Speichern; destruktive Aktionen (Portfolio löschen) nur mit Bestätigung.
6. **Debt resolved**: BIG-004 (3003→Ist 2958 LOC, Liste+Detail+Nav in einer Datei) — der im Wellenplan vorgesehene Split; ~14 Farb-Literale + 5 TextStyles → Tokens. Erste dedizierte Widget-Tests für Liste und Detail (heute keine).

## SCR-045 — PortfolioAnalyticsScreen (Arbeitspaket 7a, delegierbar)

1. **Zielbild**: Analytics-Sicht liest sich als ruhige Kennzahlen-/Chart-Seite im selben Register wie Dashboard/Overview.
2. **Layout**: Material-`AppBar` entfällt → `NxPageHeader`; Metriken als `NxCard`-Tiles; Charts in `NxChartContainer`; Desktop 2-spaltig, darunter gestapelt.
3. **States**: loading pro Sektion, empty (`NxEmptyState` mit Hinweis auf fehlende Datengrundlage + nächster Aktion), error mit Retry; forbidden/conflict n. a. (rein lesend).
4. **Data density**: unverändert `portfolioAnalyticsRepositoryProvider`, `workspaceRepositoryProvider`, `inputsRepositoryProvider`.
5. **Interactions**: Kennzahl → Quell-Screen-Navigation, wo heute schon vorhanden; sonst keine neuen Aktionen.
6. **Debt resolved**: ~12 Farb-Literale + 4 TextStyles → Tokens; kein BIG/DUP-Eintrag. Bestehender `portfolio_analytics_screen_test.dart` um Pflicht-Zustände erweitert.

## SCR-046 — DataQualityDashboardScreen (Arbeitspaket 7b, delegierbar)

1. **Zielbild**: Datenqualität pro Portfolio auf einen Blick: Score, Regelverletzungen, direkter Absprung zur betroffenen Stelle.
2. **Layout**: `AppBar` → `NxPageHeader` („Datenqualität — {Portfolio}"); Score/Schwellen als `NxCard`-Tiles mit `NxStatusBadge` je Befund-Schwere; Befundliste als `NxDataTableShell`.
3. **States**: loading, empty (= keine Befunde: positiver Leerzustand „Alles im grünen Bereich" mit letzter Prüfzeit), error mit Retry; forbidden/conflict n. a.
4. **Data density**: unverändert `dataQualityServiceProvider`/`dataQualityRepositoryProvider`; Schwellenwerte (rentRollStaleMonths etc.) bleiben Konfiguration in Settings.
5. **Interactions**: Befund-Zeile navigiert zum Quell-Screen (bestehende Navigation via `globalPageProvider`/`propertyDetailPageProvider`).
6. **Debt resolved**: nur 2 Farb-Literale (bereits sauber) — Aufwand ist fast rein kompositorisch; `DUP-014` (Regel-Registry-Konsolidierung) bleibt bewusst außerhalb W1. Bestehender Test wird erweitert.

## SCR-061 — UsersScreen (Arbeitspaket 7c, delegierbar)

**Scope-Abgrenzung:** `P2-D01` ersetzt später UsersScreen-Datenlage (Supabase-Membership, Invitation-Lifecycle `STM-001`) — das ist Backend + UI der P2-D01-Einheit, nicht dieser Welle. W1 hebt den Screen visuell auf den Systemstandard **gegen den bestehenden `securityControllerProvider`**, damit die spätere P2-D01-UI in ein fertiges Gerüst einzieht.

1. **Zielbild**: Nutzer-/Rollenverwaltung als klare Admin-Tabelle: wer, welche Rolle, seit wann; Rolle ändern und Nutzer anlegen ohne Umwege.
2. **Layout**: `NxPageHeader` (Titel + „Nutzer anlegen"), Rollen-Filter als Header-Aktion; Nutzerliste als `NxDataTableShell` (heute Card-Liste) mit `NxStatusBadge` je Rolle; Anlege-/Rollen-Dialoge bleiben.
3. **States**: loading, empty (`NxEmptyState`), error mit Retry; **forbidden explizit** (Admin-Screen: dedizierte „kein Zugriff"-Darstellung statt leerer Fläche, gespeist aus der bestehenden RBAC-Prüfung); conflict n. a. (Rollenwechsel ist Last-Write über Controller — Verhalten unverändert).
4. **Data density**: unverändert `securityControllerProvider` (Lesen + `updateUserRole`).
5. **Interactions**: Rollenwechsel mit Bestätigung (privilegierte Aktion), Nutzeranlage per Dialog; keine Löschung in W1.
6. **Debt resolved**: keiner offen (Screen ist bereits token-sauber: 0 Farb-Literale) — Lücke ist Komposition (`NxPageHeader`/Tabelle) + fehlender Widget-Test; beides wird geschlossen.

## SCR-062 — SettingsScreen (Arbeitspaket 8)

1. **Zielbild**: Einstellungen wirken wie ein ruhiges Kontrollzentrum: linke Sektionsnavigation (General, Analysis Defaults, Operations Defaults, Alerts, Appearance, Security, Backup & Restore, Admin), rechts pro Sektion saubere Formularkarten mit sichtbarem Speicherstatus. Inhaltlich ändert sich nichts — Sektionen anderer Domänen werden in deren Wellen aufgefrischt.
2. **Layout**: `NxPageHeader`; Sektionsnavigation als Rail (Desktop/Tablet) bzw. Dropdown (Phone); jede Sektion aus `NxFormSectionCard`s (heute nur 1 Nutzung); `SaveStatusIndicator` bleibt das Muster (bereits vorbildlich) und wird in allen Sektionen konsistent platziert; `ResponsiveConstraints` bleibt.
3. **States**: loading, error (heute 22 verstreute Zweige → einheitliches Fehler-Pattern mit Retry); **conflict**: bestehendes Revisions-/`SaveStatusTone`-Verhalten (`settingsRevisionProvider`) bleibt der Standard und wird sichtbar dokumentiert (warning bei fehlender Berechtigung = forbidden-Variante auf Feldebene); empty n. a.
4. **Data density**: unverändert (`settingsRevisionProvider`, `inputsRepositoryProvider`, `backupRestoreServiceProvider`, `rbacProvider`, …); **kein** Datenmodell-Split — `DEBT-015` (app_settings-Zerlegung) gehört zu P2-D01, nicht zu W1.
5. **Interactions**: Autosave mit `SaveStatusIndicator` wo heute schon Autosave ist; explizite Aktionen (Backup/Restore) mit Bestätigung; Security-/Admin-Sektion nur mit Capability sichtbar (bestehende `canSettingsEdit`-Logik).
6. **Debt resolved**: BIG-009 — Split: eine Datei pro Sektion unter `settings/sections/…` + schlanker Container; ~8 Farb-Literale → Tokens. Erster dedizierter Widget-Test (Sektionswechsel + Save-Status-Zustände).

## Arbeitspaket 9 — DEBT-012: `deletePermanently` → Archiv/Tombstone

Kein Screen-Redesign, sondern die im Modernisierungs-Backlog **der Welle 1 zugeordnete** Verhaltensänderung: die manuelle Cascade-Löschung in `property_repo.dart` wird durch Archivierung/Tombstone (Workflow-Übergang `STM-002`) ersetzt; UI-seitig bieten Welle-1-Screens bereits nur noch „Archivieren" mit Bestätigung an (siehe SCR-006). **Vorgehen:** eigener Funktions-Plan vor Umsetzung, Charakterisierungstest des heutigen Löschverhaltens zuerst, und ausdrückliche Nutzerfreigabe vor jeder Verhaltensänderung am Löschpfad (Hard-Stop-Regel). Falls die Umsetzung serverseitige/Schema-Anteile braucht, wird das als Abweichung gemeldet statt still erweitert.

---

## Querschnittsthemen der Welle

- **`NxPageHeader` überall**: Es gibt keine Direkt-Nutzungen, aber `ListFilterTemplate` kapselt ihn bereits für 21 Screens (u. a. Properties, Users). Die Welle-1-Lücke sind die Screens ohne Template: Dashboard, Overview, PropertyShell, Portfolios, Settings sowie die drei Material-`AppBar`-Nutzer SCR-008/045/046 — die bekommen ihn (direkt oder via Template). Das ist der größte einzelne Konsistenzhebel der Welle.
- **`NxChartContainer` überall**: Ist-Stand 0 Nutzungen — Dashboard, Overview, Portfolios, Analytics stellen alle Charts darauf um. Falls der Komponente Fähigkeiten fehlen, wird die Komponente (+ Tests) einmal erweitert, nie inline geforkt (Regel aus `03_design_system.md`).
- **DEBT-TOKEN-001, W1-Anteil**: alle per-Screen-Farb-Literale der Welle-1-Screens verschwinden (Hotspots: overview ~48, properties ~32, dashboard ~28, creation ~28, shell ~25, portfolios ~14, analytics ~12, sidebar ~7); per-Screen-`TextStyle`s weichen `textTheme`. Die `AppColors.background`-Weiß-Semantik wird für Welle-1-Screens aufgelöst (Screens nutzen die Theme-Flächen, nicht `AppColors.background` als Weiß); die verbleibenden Nutzer (Wellen 3/6-Screens) bleiben unangetastet.
- **Shell-Nacharbeit (klein)**: `lib/ui/shell/sidebar.dart` trägt noch ~7 Farb-Literale — wird im Zuge von Arbeitspaket 1 mit bereinigt (reine Token-Substitution, keine Strukturänderung).
- **Testpflicht (DEBT-016 pro Screen)**: jeder Screen verlässt die Welle mit einem Widget-Test, der alle für ihn geltenden Pflicht-Zustände abdeckt. Neu zu schaffen für: Overview, Portfolios (Liste+Detail), Settings, Users, CreationWorkflow (heute testlos); zu erweitern: Dashboard, Properties, Analytics, DataQuality, PropertyShell.
- **Responsive-Gate**: 390×844 / 1024×768 / 1440×900 pro Screen, zusätzlich alle drei Dichte-Modi (comfort/compact/adaptive); Reference-Slice-Goldens bleiben pixel-identisch (Welle 1 fasst den Reference Slice nicht an).
- **Nicht in W1** (bewusst): Migration der Legacy-Screens auf die Feature-Architektur (`lib/features/…`), `DUP-014` (DataQuality-Regel-Konsolidierung), `DEBT-015` (app_settings-Split, → P2-D01), P2-D01-Membership-UI, Liste+Detail-Side-by-Side im Legacy-PropertiesScreen.

## Definition of done

**Je Screen:** Sechs-Punkte-Plan im Chat gezeigt (ein Plan pro Arbeitspaket) → Umsetzung → `flutter analyze --no-pub` sauber → gezielte Widget-Tests grün (inkl. neuer Zustands-Tests) → Responsive-Check an den drei Breiten → manueller Golden-Path im laufenden App-Build → `00_phase_2_status.md` evidenzbasiert fortgeschrieben. Volle Suite (`flutter test --no-pub`, Referenz 258 Tests / 8 Skips) mindestens am Ende jedes Arbeitspakets.

**Wellenabschluss:** alle Arbeitspakete `done` im Status-Doc; kein Welle-1-Screen nutzt mehr Material-`AppBar`, Farb-Literale oder per-Screen-`TextStyle`s; volle Suite + analyze grün; Zusammenfassung + Check-in beim Nutzer an der Wellengrenze (Hard-Stop) — Welle 2 startet erst nach Freigabe und nach ihrem eigenen Detaildokument.
