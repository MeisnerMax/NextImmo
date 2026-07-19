# Phase 2 Status

Stand: 2026-07-19
Owner: execution session
Zweck: Einzige Wahrheit über den tatsächlichen Fortschritt von Phase 2 (nicht das Zielbild — das steht in `00_phase_2_charter.md`..`05_claude_execution_prompt.md`). Jede abgeschlossene Einheit wird hier evidenzbasiert eingetragen, damit jede Folge- oder frische Sitzung den Stand kennt, ohne den Chatverlauf zu rekonstruieren.

## Aktueller Fokus

Welle 0 — Foundation. **Token-Foundation (Light + Dark) und Shell-Cleanup (MOD-CLEAN-001..005 inkl. V2→kanonisch-Rename) abgeschlossen und verifiziert.** Welle 0 ist damit fertig; nächster Schritt: Welle-1-Vorbereitung per `04_screen_redesign_wave_plan.md` (Wellen-Detaildokument zuerst).

## Fortschritt je Einheit

| Einheit | Typ | Status | Evidenz / Notiz |
|---|---|---|---|
| Plan Phase 2 (00–05) | Doku | `done` | `docs/architecture/phase_2/00_phase_2_charter.md`..`05_claude_execution_prompt.md` |
| W0 — Design-Token-Verfeinerung (Light) | UI-Foundation | `done` | Warm-neutrale Light-Tokens in `AppColors` + `_lightTokens` (`lib/ui/theme/app_theme.dart`) + 3 Canvas-Drift-Stellen (`overview_screen.dart:1303`, `property_shell.dart:43`, `units_screen.dart:625`); analyze sauber, 253 Tests grün/8 Skips, 3 Reference-Slice-Goldens bewusst neu generiert |
| W0 — Design-Token-Verfeinerung (Dark) | UI-Foundation | `done` | Warm-neutrale Dark-Tokens in `_darkTokens` (`app_theme.dart`); Reference-Slice-Test um Dark-Golden-Variante erweitert (schließt Teil von `RISK-QA-007`); 3 neue Dark-Goldens generiert und visuell geprüft; analyze sauber, 256 Tests grün/8 Skips |
| W0 — SearchScreen/RentalOverview-Entscheidung (MOD-CLEAN-005 / OPEN-003) | Entscheidung | `done` | **Entschieden (2026-07-19):** SearchScreen (SCR-064) → entfernen (redundant zur `CommandPalette`, nicht produktiv verdrahtet); RentalOverviewScreen (SCR-065) → behalten, fest Welle 3 (leasing_operations); ungenutzten Import in `AppScaffold` dabei bereinigen. Ausführung im W0-Shell-Cleanup. |
| W0 — Token-Quellen-Zusammenführung (DEBT-TOKEN-001, W0-Anteil) | UI-Foundation | `done` | **2026-07-19.** Einzige `_Palette`-Quelle in `app_theme.dart`; `AppColors` + `_lightTokens`/`_darkTokens` referenzieren sie nur noch; Drift-Guard-Test `test/ui/theme/token_source_sync_test.dart`; Goldens pixel-identisch, analyze sauber, 258 Tests grün / 8 Skips. Rest (per-Screen-Hex, `AppColors.background`-Semantik) in Wellen 1/3/6. |
| W0 — V1/V2-Shell/Wrapper-Bereinigung + SearchScreen-Entfernung (MOD-CLEAN-001..005) | Refactor | `done` | **2026-07-19, mit Nutzerfreigabe vor jeder Löschung.** Paritäts-/Charakterisierungstests zuerst geschrieben und grün (V1-vs-V2 Properties-Liste, Legacy-vs-V2-Shell, Dashboard-Wrapper-Delegation), dann gelöscht: `search_screen.dart`+Test, `dashboard_screen.dart`-Wrapper, `properties_screen.dart` (V1), `property_shell_v2.dart`-Wrapper, `shell/sidebar.dart`+`topbar.dart` (V1), `ui_feature_flags.dart`+Test (alle 4 `UiScreenFlag`s referenzlos). V2→kanonisch umbenannt (`DashboardScreenV2`→`DashboardScreen`, `PropertiesScreenV2`→`PropertiesScreen`, `SidebarV2`→`Sidebar`, `TopBarV2`→`TopBar`), `v2/`-Ordner aufgelöst, `AppScaffold` auf eine Shell reduziert. Dauerhafte neue Coverage: `test/ui/screens/properties_screen_parity_test.dart`, `test/ui/shell/shell_consolidation_parity_test.dart` (Liste/Shell hatten vorher keinen dedizierten Widget-Test). Verifiziert: `flutter analyze` sauber, volle Suite 256 Tests grün / 8 Skips. Hinweis: der in MOD-CLEAN-005 genannte RentalOverview-Import in `AppScaffold` existierte nicht mehr (bereits früher entfernt) — Doc-Pointer in `02_architecture_modernization_backlog.md` korrigiert; `RentalOverviewScreen` bleibt (verwaist, geplant Welle 3). |

### Neuer Debt-Fund (2026-07-19)

Zwei parallele Token-Quellen: `AppColors` (statisch, ~61 Dateien / 293 Refs) **und** `_lightTokens`/`_darkTokens` (bauen `ThemeData`). Als `DEBT-TOKEN-001` in `02_architecture_modernization_backlog.md` erfasst. **W0-Anteil aufgelöst (2026-07-19):** beide Quellen lesen jetzt aus einer einzigen privaten `_Palette`-Const-Tabelle in `app_theme.dart` (inkl. der 3 Streu-Literale in `_buildTheme`); Drift ist strukturell unmöglich, zusätzlich abgesichert durch `test/ui/theme/token_source_sync_test.dart`. Null visuelle Änderung (Reference-Slice-Goldens pixel-identisch; volle Suite 258 Tests grün / 8 Skips). Bewusst offen gelassen: `AppColors.background` bleibt Weiß (= Surface) statt des warmen Canvas — Legacy-Screens nutzen es als weiße Fläche; Auflösung sowie die hardkodierten Hex-Werte einzelner Screens weiterhin pro Screen in dessen Welle (1/3/6).

Status-Werte: `todo`, `in_progress`, `blocked`, `done`.

## Offene Punkte, die eine Nutzerentscheidung brauchen

- OPEN-003 (SearchScreen/RentalOverviewScreen: integrieren oder entfernen) — vor W0-Wrapper-Bereinigung.
- Alle `DEC-014`..`017`, `OPN-DOM-*` unverändert offen (siehe `phase_0/11_decision_register.md`).

## Nächster Schritt

Welle 0 ist vollständig abgeschlossen (inkl. DEBT-TOKEN-001-W0-Anteil; Wellen-Grenze = Check-in-Punkt laut `05_claude_execution_prompt.md`). Nächstes Arbeitspaket: Welle 1 (portfolio_property-Screens) per `04_screen_redesign_wave_plan.md` — zuerst das Wellen-Detaildokument (`04a_wave1_....md`) schreiben, dann implementieren.
