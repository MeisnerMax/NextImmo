# P0.5 Testbaseline

Stand: 2026-07-18

## 1. Inventar

| ID | Bereich | Bestand | Status | Evidenz |
|---|---|---:|---|---|
| TST-001 | Testdateien gesamt | 101 | verified | `test/**/*.dart`, einschliesslich MFA-Testhilfe |
| TST-002 | Testfaelle (`test`/`testWidgets`) | 220 Deklarationen; 240 Laufzeitfaelle | verified | `test/**/*.dart`; 234 bestanden, 6 Skips |
| TST-003 | Domain/Core | 29 Dateien | verified | `test/core/` |
| TST-004 | Daten/SQLite-Repositories | 27 Dateien | verified | `test/data/` |
| TST-005 | Widget/UI | 28 Dateien | verified | `test/ui/`, einschliesslich Navigation und responsivem Overflow-Gate |
| TST-006 | Integration | 4 Dateien | verified | `test/integration/`, einschliesslich echten Supabase-Client-, RLS-, RPC- und Mehrclient-Realtime-Gates |
| TST-007 | Root/Smoke/Layout | 2 Dateien | verified | `test/widget_test.dart`, `test/debug_layout_test.dart` |
| TST-008 | Golden-/Screenshot-Tests | 3 Baselines | verified | P1-010 Phone, Tablet und Desktop unter `test/features/reference_slice/goldens/` |
| TST-009 | CI-Testgate | Flutter-, Web-, SQL-, RLS-, Rollback-, Concurrency-, Client-, Mehrclient-Realtime-, Advisor- und lokaler Backup-/Restore-Drill | verified | `.github/workflows/flutter.yml` |
| TST-010 | Feature-Slices | 9 Dateien | verified | `test/features/`, einschliesslich P1-010-UI, P1-011-Lifecycle und P1-012-Migrations-Dry-Run |

Vorhandene Schwerpunkte: deterministische Core-Engines, SQLite- und Supabase-Repository-Vertraege, PostgreSQL/RLS, ausgewaehlte Widgets und vier lokale Integrationsfluesse. Nicht vorhanden sind Import-Reconciliation, echte plattformuebergreifende E2E- und umfassende responsive Screenshot-Gates.

## 2. Kritische Rechen- und Datenpfade

| ID | Pfad | Bestehende Abdeckung | Luecke | Status |
|---|---|---|---|---|
| PATH-001 | `AnalysisEngine.run` -> `normalizeInputs` -> `buildProforma` -> Finanzierung/Amortisation -> `computeMetrics` -> IRR | `analysis_engine_test.dart`, `proforma_test.dart`, `amortization_test.dart`, `irr_test.dart` | nur wenige feste Endwerte; IRR-Toleranz teils grob | verified |
| PATH-002 | Bewertung ueber Appreciation oder Exit-Cap/NOI | einzelne Faelle in `analysis_engine_test.dart` | keine freigegebene Referenzmatrix fuer Rundung, Grenzwerte und Fallbacks | verified |
| PATH-003 | `PortfolioIrrEngine.computeXirr` und Periodenaggregation | 2 Tests | unregelmaessige Mehrfach-Cashflows, gleiche Daten, Mehrfachnullstellen und Konvergenzgrenzen fehlen | verified |
| PATH-004 | `SensitivityEngine.run` -> vollstaendige Analyse je Zelle | GM-SEN-001 prueft 5x5 fuer alle vier Metriken | weitere Presets und persistierte Referenzwerte ausserhalb der Baseline fehlen | verified |
| PATH-005 | `CovenantEngine`: DSCR, LTV, Operator | GM-COV-001 prueft Kennzahlen, exakte Schwellen, Nullfaelle und ungueltige Operatoren | keine weitere P0-Luecke | verified |
| PATH-006 | `RentRollEngine.compute`: Einheit -> aktiver Vertrag -> Mietplan -> KPI | 1 Domain-Test plus Repository/UI-Tests | Periodengrenzen, konkurrierende Vertraege, Offline-Einheiten und fehlende Marktmiete nicht einzeln abgesichert | verified |
| PATH-007 | `BudgetVsActual.computeVariance`: Vorzeichen, Konto/Periode, Aggregation | GM-BVA-001 plus Mehrfachzeilenaggregation, Repository/UI-Tests | Einnahmen, Nullbudget/Prozent und Waehrungsregel fehlen | verified |
| PATH-008 | SQLite `AppDatabase` -> `DbMigrations` v46 -> Repositories/Audit | Schema- und 27 Datentests | Fresh-create dominiert; Upgrade jeder Version, Rollback und Datenverlustpruefung fehlen | verified |
| PATH-009 | `BackupRestoreService`/`BackupService`: Manifest -> ZIP -> DB/Dokumente -> Index | Format-2-Manifest, 13 Archivtests und 2 Integrationsfaelle | Crash-Recovery-Journal und kryptografische Authentizitaet fehlen | verified |
| PATH-010 | Ankauf, Sanierung, Verkauf | je 2 direkte Referenz-/Grenztests fuer `AcquisitionCalculationService`, `RenovationCalculationService`, `DispositionCalculationService` | gemeinsame IRR-Implementierung bleibt langfristiges Konsolidierungsziel | verified |
| PATH-011 | Noch ungetestete Repositories | 14 ohne gleichnamigen Repository-Test | u. a. `property_repo`, `workspace_repo`, `permission_guard`, `valuation_data_repo`, Dokumenttyp/Pflichtdokumente | verified |

## 3. Golden-Master-Faelle

Golden Master bedeutet hier: versionierte Eingabe plus erwartete numerische/strukturierte Ausgabe; Geld auf 2 Dezimalstellen, Quoten auf `1e-8`, IRR/XIRR auf `1e-6`, sofern eine fachlich freigegebene Rundungsregel nichts anderes bestimmt.

| ID | Fall und feste Eingabe | Erwartete Kernausgabe | Prioritaet | Status |
|---|---|---|---|---|
| GM-VAL-001 | Kauf 300000, Cash, manueller stabilisierter NOI 25000, Exit-Cap 5 % | Verkaufspreis 500000; Modus `exit_cap` | P0 | verified (Teilfall vorhanden) |
| GM-VAL-002 | Kauf 200000, Wertsteigerung 3 %, Haltedauer 10 Jahre | Verkaufspreis `200000 * 1.03^10`; Modus `appreciation` | P0 | verified (Teilfall vorhanden) |
| GM-FIN-001 | Kauf 200000, Sanierung 20000, Kaufkosten 5 % + 5000, Darlehen 150000 | Gesamtkosten 235000; Eigenkapital 85000; Darlehen 150000 | P0 | verified (Teilfall vorhanden) |
| GM-FIN-002 | Darlehen 100000, 6 % p. a., 30 Jahre | Monatsrate ca. 599.55; 360 Perioden; Schlussrest 0 | P0 | verified (`amortization_test.dart`) |
| GM-IRR-001 | periodisch `[-1000, 300, 420, 680]` | IRR ca. 0.1634056 | P0 | verified (Test vorhanden, Toleranz schaerfen) |
| GM-XIRR-001 | -100000 am 2024-01-01; +120000 am 2024-12-31 | XIRR ca. 0.2 | P0 | verified (Test vorhanden) |
| GM-SEN-001 | Standardraster -20/-10/0/+10/+20 % fuer Kaufpreis und Miete | 5x5-Matrix je Metrik; Mitte exakt Baseline; steigende Miete senkt keine Cashflow-Zelle | P0 | verified (`sensitivity_test.dart`) |
| GM-COV-001 | NOI 120, Schuldendienst 100; Saldo 600, Wert 1000 | DSCR 1.2; LTV 0.6; Grenzoperatoren inklusiv | P0 | verified (`covenant_engine_test.dart`) |
| GM-REN-001 | 2 vermietbare Einheiten, 1 belegt; Sollmieten 1200/900; Istmiete 1100; 1 Offline-Einheit | Belegung 0.5; GPR 2100; Ist/EGI 1100; Leerstandsverlust 1000 | P0 | verified (Teilfall vorhanden) |
| GM-BVA-001 | Budget Ausgabe 100, Ist Ausgabe 120, gleiches Konto/Periode | Budget -100; Ist -120; Abweichung -20; Quote 0.2 | P0 | verified (`budget_vs_actual_test.dart`) |
| GM-ACQ-001 | Fester Ankauf mit Kaufnebenkosten, Sanierung, Finanzierung und Miete | Investition, NOI, Schuldendienst, Cashflow, LTV und Preisgrenze stimmen | P0 | verified (`acquisition_calculation_service_test.dart`) |
| GM-RNV-001 | Feste Sanierung mit Kostenfortschreibung, NOI-Uplift, Zeit- und Risikofaktoren | Forecast, NPV, IRR, Wertsteigerung und Worst Case stimmen | P0 | verified (`renovation_calculation_service_test.dart`) |
| GM-DSP-001 | Fester Verkauf mit Kosten, Darlehen, Steuern und laufenden Cashflows | Nettoerloes, Gewinn, Multiple, Marge und IRR stimmen | P0 | verified (`disposition_calculation_service_test.dart`) |
| GM-BKP-001 | deterministische SQLite-Fixture plus Dokumente | Manifest, Payload-Hashes und Dateizahl stimmen; Restore liefert zeilen- und bytegleichen Stand | P0 | verified (`backup_service_test.dart`, `backup_restore_integration_test.dart`) |
| GM-BKP-002 | manipulierte oder inkompatible Payload, unsichere Pfade und Fehler nach Mutation | Restore wird vor Mutation abgelehnt oder rollt DB und Dokumente auf den Vorzustand zurueck | P0 | verified (`backup_service_test.dart`, `backup_restore_integration_test.dart`) |
| GM-IMP-001 | SQLite-Referenzbestand mit Stammdaten, Vertraegen, Ledger und Dokumentmetadaten | Quell-/Zielanzahl, IDs, Summen und Fremdschluessel stimmen; zweiter Lauf idempotent | P1 | proposed |

Die erwarteten Werte von `GM-REN-001` und `GM-BVA-001` bilden das aktuelle Verhalten ab. Fachliche Definitionen, insbesondere GPR/EGI, Vorzeichen und Rundung, muessen vor ihrer Freigabe bestaetigt werden.

## 4. Testebenen und Abnahmekriterien

| ID | Ebene | Pflichtumfang | Gate |
|---|---|---|---|
| LVL-001 | Domain Unit | Rechenkerne, Grenzwerte, Nullfaelle, Determinismus, Golden Master | alle P0-Golden-Master-Faelle bestanden |
| LVL-002 | Repository Contract | gleicher Vertrag fuer SQLite und spaeter PostgreSQL; CRUD, Filter, Audit, Fehler | jeder produktive Repository-Vertrag gegen beide Adapter |
| LVL-003 | PostgreSQL Migration | leere DB, Upgrade aus jeder freigegebenen Version, Reconciliation, Wiederholung, Rollback | keine verlorenen Zeilen/Beziehungen; zweite Ausfuehrung ohne Delta |
| LVL-004 | RLS Security | Default-Deny, fremder Workspace, Rolle, Entity-Scope, Service-Role-Trennung | alle Negativtests verweigert; kein Cross-Tenant Read/Write |
| LVL-005 | Widget | Laden, leer, Fehler, Rechte, Eingabevalidierung, Tastatur | keine unbehandelten Exceptions/Overflows |
| LVL-006 | Responsive Screenshot | Desktop 1440x900, Tablet 1024x768, Phone 390x844 | freigegebene Goldens ohne unerwartetes Pixel-Diff |
| LVL-007 | End-to-End | Anmeldung -> Workspace -> Objekt -> Mutation -> Audit -> Realtime | Referenzschnitt auf Staging vollstaendig bestanden |
| LVL-008 | Import Reconciliation | Dry Run, Mappingfehler, Counts/Summen/Hashes, Idempotenz, Abbruch | 100 % erklaerte Differenzen; Wiederholung ohne Duplikate |
| LVL-009 | Backup/Restore | Integritaet, Version, Abbruch, Restore, Index, Dokumente | Restore nur nach Hash-/Schema-Pruefung; byte-/zeilengleicher Stand |

## 5. Konkrete Gate-Kommandos

Aus dem Projektroot, in dieser Reihenfolge:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/core
flutter test --no-pub test/data
flutter test --no-pub test/integration
flutter test --no-pub test/ui
flutter test --no-pub
```

Nach Einfuehrung der Artefakte:

```powershell
flutter test --no-pub test/golden_master
flutter test --no-pub test/repository_contracts
flutter test --no-pub test/goldens
supabase db reset --local
supabase test db
flutter test --no-pub integration_test
```

Gate-Regeln:

- Exitcode muss 0 sein; Warnungen der statischen Analyse sind nicht zulaessig.
- CI-Limit: Analyse 5 Minuten, Teil-Suite je 10 Minuten, Gesamtsuite 20 Minuten; Timeout ist Fehler.
- Golden-Updates nie implizit im Gate; erwartete Werte brauchen Finance-/Domain-Review.
- PostgreSQL/RLS-Gates sind erst ausfuehrbar, wenn lokales Supabase und die Phase-1-Fixtures vorhanden sind.

## 6. Lokaler Befund

| ID | Kommando | Ergebnis | Status |
|---|---|---|---|
| RUN-001 | `flutter analyze --no-pub` | 2 bekannte Web-Interop-Infos, keine Warnungen oder Fehler | partial |
| RUN-002 | `flutter test --no-pub` | 174 bestanden, 4 Skips | verified |
| RUN-003 | responsives Overflow-Gate | 9/9 auf Mobile, Tablet und Desktop bestanden | verified |
| RUN-004 | GM-FIN-002 | Monatsrate, 360 Perioden und Schlussrest bestanden | verified |
| RUN-005 | `supabase test db --local` | 160 pgTAP-Pruefungen bestanden | verified |
| RUN-006 | P1-004 Rollback/Concurrency | 9 Rollback-Pruefungen und Zwei-Sitzungs-Test bestanden | verified |
| RUN-007 | P1-007 Clientintegration | Login, RLS, RPC, Retry, Konflikt und Readback bestanden | verified |
| RUN-008 | `flutter analyze --no-pub` / Web-Build | 0 Findings; Web-Build erfolgreich | verified |
| RUN-009 | P1-009 Auth-/Workspace-/Property-State | 15 gezielte Tests bestanden; echter Clienttest ohne Harness erwartungsgemaess uebersprungen und separat im lokalen Harness bestanden | verified |
| RUN-010 | P1-009 Abschlussgate | lokale Supabase-Integration 1/1, Gesamtsuite 202 bestanden/5 Skips, Analyzer 0 Findings und Web-Build erfolgreich | verified |
| RUN-011 | P1-010 Adaptive UI | 14 Widgettests, 7 Breakpoint-Breiten und 3 Golden-Baselines bestanden; Gesamtsuite 216 bestanden/5 Skips, Analyzer 0 Findings, Web-Build erfolgreich | verified |
| RUN-012 | P1-011 Realtime-Invalidierung | lokaler Mehrclient-E2E fuer aktiven und fremden Workspace, kanonischer Readback, 160 pgTAP- und 12 Rollback-Pruefungen; Gesamtsuite 221 bestanden/6 Skips, Analyzer 0 Findings, Web-Build erfolgreich | verified |
| RUN-013 | P1-012 Migrations-Dry-Run | 7 gezielte Mapper-/SQLite-Adaptertests fuer deterministische IDs, Counts, Checksums, Fail-closed-Zuordnung, PII-freien Report und Abbruch; Gesamtsuite 228 bestanden/6 Skips, Analyzer 0 Findings, Web-Build erfolgreich | verified |
| RUN-014 | P1-014 lokaler Backup-/Restore-Vertrag | Zielguard 7/7, manipuliertes Archiv vor Zielerstellung abgelehnt, nichtleerer PostgreSQL-Restore mit 18 reconciliierten Zeilen und Cleanup bestanden; 160 pgTAP, Gesamtsuite 228 bestanden/6 Skips, Analyzer 0 Findings, Web-Build erfolgreich | partial: Remote-/Storage-Drill offen |
| RUN-015 | P1-015 lokales Gate-Review | Unknown-AAL fail-closed, Realtime-Burst-Coalescing/Pagination, suspendierte Membership und Audit-Korrelation; 164 pgTAP, Security-/Performance-Advisors ohne Error-Befund, Gesamtsuite 232 bestanden/6 Skips, Analyzer 0 Findings, Web-Build erfolgreich | partial: Gate abgelehnt; weitere Gates offen |
| RUN-016 | Runtime-, AAL2- und Performance-Hardening | Explizite Runtimeauswahl, Kaltstart-Deep-Link, serverseitiges Property-AAL2 mit echtem TOTP-Clientnachweis, FK-/Keyset-Indizes und RLS-InitPlans; 196 pgTAP, beide Clientgates, 43 gezielte Tests, Gesamtsuite 234 bestanden/6 Skips, Analyzer 0 Findings, Web-Build und DB-Lint erfolgreich | verified_local; allgemeine Auth-Aktionen/Entitlements/Remote offen |

## 7. Risiken

| ID | Risiko | Auswirkung | Massnahme/Gate | Status |
|---|---|---|---|---|
| RISK-QA-001 | Keine versionierten Golden-Master-Fixtures | unbemerkte Aenderung finanzieller Ergebnisse | GM-VAL bis GM-BKP vor Migration einfrieren | open |
| RISK-QA-002 | Mehrere IRR-Implementierungen koennen langfristig divergieren | abweichende Renditewerte bei kuenftigen Aenderungen | direkte Referenzfaelle fuer alle drei Rechner bestehen; gemeinsame Implementierung spaeter konsolidieren | mitigated |
| RISK-QA-003 | Migrationstest startet nur am aktuellen Schema | Upgrade kann Daten verlieren oder Beziehungen brechen | Versions-Fixtures, Upgrade, Reconciliation und Rollback | open |
| RISK-QA-004 | Prozessabsturz kann Cleanup unterbrechen; SHA-256 beweist keine Urheberschaft | verwaistes Restore-Ziel oder absichtlich neu gehashtes Fremdarchiv | lokaler atomarer Drill besteht; Restore-Journal/Start-Recovery, AEAD und HMAC/Signatur mit Schluesselverwaltung bleiben fuer P1-014 offen | partial |
| RISK-QA-005 | Neue Policies koennen Mandantentrennung regressieren | Cross-Tenant-Datenzugriff | pgTAP/RLS- und reale Clientintegration sind CI-Gates | mitigated |
| RISK-QA-006 | Web-Interop kann bei SDK-Wechsel regressieren | Web-Build oder Analyzer bricht | `package:web`, Analyzer und Web-Build sind CI-Gates | mitigated |
| RISK-QA-007 | Responsive-Golden-Abdeckung ist noch auf den Referenzschnitt begrenzt | pixelbezogene Regressionen anderer Screens bleiben moeglich | P1-010 besitzt Phone-/Tablet-/Desktop-Baselines; weitere Kern-Screens schrittweise aufnehmen | partial |
| RISK-QA-008 | Keine verbindlichen Performance-Budgets; breite Property-Projektion und serielle Identity-Reads sind ungemessen | Last- und Skalierungsregressionen bleiben unentdeckt | Budgets festlegen und reproduzierbare Queryplan-, RPC- und Flutter-Profile messen | open |
