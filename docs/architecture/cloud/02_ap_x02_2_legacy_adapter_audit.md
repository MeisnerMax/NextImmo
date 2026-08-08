# `AP-X02-2` — Bestandsaufnahme Legacy-Adapter vor jeder Löschung

Audit: 2026-08-07 · Commit `ada10fb` · Ausführung `AP-X02-2a`: 2026-08-08 auf `main` (`2236a96`)
Status: **`AP-X02-2a` DONE · `AP-X02-2b` OPEN**
Entscheidungsgrundlage: `DEC-024` · Plan: `phase_2/04y_p2_x02_sqlite_decommission.md`

> **SQLite ist damit ausdrücklich noch nicht aus der Laufzeit entfernt.** Entfernt wurde
> ausschließlich Gruppe B — zwei Adapter, die schon vor dieser Änderung an keinem
> Laufzeitpfad hingen. Die sieben Adapter der Gruppe A und der `DataBackend.sqlite`-Zweig in
> `app_backend_wiring.dart` stehen unverändert im Baum.

`DEC-024` erlaubt die Entfernung. Es beweist sie nicht. Dieses Dokument liefert je Artefakt
die Evidenz, die vor einer Löschung vorliegen muss, und **weicht in einem Punkt bewusst von
`04y` ab** — siehe §5.

---

## 1. Methodik

Für jedes Artefakt erhoben, jeweils gegen `ada10fb`:

- Importeure in `lib/`, `test/`, `tool/` (`git grep -l -- "/<dateiname>"`)
- Klassenreferenzen (`git grep -l <Klassenname>`), um Re-Exporte nicht zu übersehen
- Bindung in der Composition Root `lib/app_backend_wiring.dart` (vollständig gelesen)
- Backend-Zweig, in dem die Bindung steht (`DataBackend.sqlite` vs. `.supabase`)

**Zentraler Strukturbefund:** `lib/app_backend_wiring.dart` ist die **einzige** Naht.
Alle produktiv gebundenen Legacy-Adapter hängen ausschließlich am Zweig
`case DataBackend.sqlite:` (Z. 345–442). **Kein einziger Legacy-Adapter wird im
Supabase-Zweig gebunden.** Damit ist Nachweis 1 („kein produktiver Cloud-Runtime-Pfad
nutzt ihn mehr") für die gesamte Gruppe A strukturell erbracht, nicht adapterweise
zu erraten.

---

## 2. Gruppe A — im SQLite-Zweig gebundene Laufzeit-Adapter

Alle: Runtime SQLite **ja**, Runtime Supabase **nein**, Composition-Root-Nutzung
ausschließlich `app_backend_wiring.dart`, Datenmigrations-Abhängigkeit **keine**
(die Migration läuft über die Dry-Run-Mapper der Gruppe D, nicht über diese Adapter).

| Datei | Domäne | LOC | Klassen | Tests | Aktion |
|---|---|---|---|---|---|
| `contacts_parties/data/legacy_sqlite_party_repository_adapter.dart` | `contacts_parties` | 429 | `LegacySqlitePartyRepositoryAdapter` + Read-Source | 1 direkt, 1 indirekt | **REMOVE** |
| `documents_compliance/data/legacy_sqlite_document_repository_adapter.dart` | `documents_compliance` | 840 | `LegacySqliteDocumentRepositoryAdapter` + Read-Source | 1 direkt, 1 indirekt | **REMOVE** |
| `leasing_operations/data/legacy_sqlite_leasing_repository_adapter.dart` | `leasing_operations` | 746 | 4 Adapter (`Unit`, `Lease`, `LeasingCase`, `RentRoll`) + Read-Source | 1 direkt, 1 indirekt | **REMOVE** |
| `leasing_operations/data/legacy_operations_signals_adapter.dart` | `leasing_operations` | 154 | `LegacySqliteOperationsSignalsAdapter` | 1 direkt, 2 indirekt | **REMOVE** |
| `maintenance_capex/data/legacy_sqlite_maintenance_capex_repository_adapter.dart` | `maintenance_capex` | 497 | 2 Adapter (`MaintenanceTicket`, `CapexProject`) + Read-Source | 1 direkt, 1 indirekt | **REMOVE** |
| `platform_audit_jobs/data/legacy_sqlite_platform_repository_adapter.dart` | `platform_audit_jobs` | 717 | `LegacySqlitePlatformRepositoryAdapter` + Read-Source | 1 direkt, 1 indirekt | **REMOVE** |
| `valuation/data/legacy_sqlite_valuation_repository_adapter.dart` | `valuation` | 360 | `LegacySqliteValuationRepositoryAdapter` + Read-Source | 1 direkt, 1 indirekt | **REMOVE** |
| **Summe Gruppe A** | | **3743** | | | |

### Warum `REMOVE` hier tragfähig ist

| Nachweis | Evidenz |
|---|---|
| 1 Kein Cloud-Runtime-Pfad | Bindung nur im `DataBackend.sqlite`-Zweig, `app_backend_wiring.dart:345–442` |
| 2 Kein Screen/Provider hängt daran | Screens lesen die **Port-Provider** (`partyRepositoryProvider` usw.), nie den Adapter. Der Adapter wird per `overrideWith` eingesetzt; fällt der Zweig, fällt die Bindung |
| 3 Keine Migration/Reconciliation | Diese Adapter sind **Lesepfade für die laufende App**, nicht für die Migration. Migration läuft über Gruppe D |
| 4 Charakterisierungstests | Je Adapter existiert eine eigene Testdatei; sie testet den Legacy-Pfad und entfällt mit ihm |
| 5 Supabase-Adapter deckt ab | Je Domäne existiert der `Supabase*`-Adapter und ist im Cloud-Zweig gebunden |
| 6 Keine Cloud-Reduktion | Cloud-Verhalten ist von diesen Dateien nicht erreichbar |
| 7 Legacy lesbar | Bleibt über Gruppe C/D erhalten — deshalb dürfen die nicht mitgelöscht werden |

**Verhaltensänderung, die bewusst hinzunehmen ist:** diese Adapter liefern heute den
Zustand „read-only bis migriert" (jede Mutation antwortet `dependencyConflict`,
`mutationsSupported: false`). Mit dem Wegfall des Modus entfällt dieser Zustand
ersatzlos — die 16 noch nicht migrierten Ziele sind dann in keinem Modus erreichbar.
Das ist in `04y` §3 als V1 entschieden und akzeptiert, gehört aber in die
Release-Notiz, nicht in eine Fußnote.

---

## 3. Gruppe B — bereits toter Code

Nicht gebunden, nicht importiert, nur von der eigenen Testdatei referenziert.
Verifiziert per `git grep -l <Klassenname>`: je zwei Treffer, die eigene Datei und ihr Test.

| Datei | Domäne | LOC | `lib/`-Importeure | Aktion |
|---|---|---|---|---|
| `identity_access/data/legacy_sqlite_membership_admin_repository_adapter.dart` | `identity_access` | 211 | **0** | **REMOVE** |
| `portfolio_property/data/legacy_sqlite_property_repository_adapter.dart` | `portfolio_property` | 157 | **0** | **REMOVE** |
| **Summe Gruppe B** | | **368** | | |

Diese beiden sind unabhängig von `DataBackend.sqlite` löschbar — sie sind schon heute
an keinem Laufzeitpfad. Sie eignen sich als **erster, risikoärmster Schritt**, mit dem
sich das Vorgehen validieren lässt, bevor die Composition Root angefasst wird.

### `AP-X02-2a` ausgeführt am 2026-08-08

Re-Audit gegen den integrierten `main` (`2236a96`), nicht gegen den Auditstand vom 07.08.:

| Adapter | Runtime-Refs | Migrations-Refs | Test-Refs | Entscheidung |
|---|---|---|---|---|
| `LegacySqliteMembershipAdminRepositoryAdapter` | **0** | **0** | 1 (nur eigener Test) | **REMOVE** |
| `LegacySqlitePropertyRepositoryAdapter` | **0** | **0** | 1 (nur eigener Test) | **REMOVE** |

Runtime-Nachweis: keiner der beiden erscheint in `app_backend_wiring.dart`, `main.dart`,
`app_state.dart` oder `app.dart`. Die Composition Root bindet dort **elf andere**
`LegacySqlite*`-Klassen — die zwei sind nicht darunter. Migrations-Nachweis: null Treffer in
`lib/features/legacy_cutover/`, `tool/` und den `sqlite_*`-Dateien.

**Entfernt (767 LOC):**

| Datei | LOC |
|---|---|
| `lib/features/identity_access/data/legacy_sqlite_membership_admin_repository_adapter.dart` | 211 |
| `lib/features/portfolio_property/data/legacy_sqlite_property_repository_adapter.dart` | 157 |
| `test/features/identity_access/legacy_sqlite_membership_admin_repository_adapter_test.dart` | 191 |
| `test/features/portfolio_property/legacy_sqlite_property_repository_adapter_test.dart` | 208 |

**Warum die Tests mitgehen, ohne dass Abdeckung verloren geht.** Beide charakterisieren
ausschließlich das Verhalten *des toten Adapters* (Mapping der lokalen Nutzer, leere
Invitation-Fläche, `dependencyConflict` bei jeder Mutation) — es gibt danach nichts mehr,
was sie beschreiben könnten. Die eine Invariante mit eigenständigem Wert, das
fail-closed-Verhalten bei fremdem Workspace, ist im produktiven Pfad unabhängig abgedeckt:
`supabase_membership_admin_repository_adapter_test.dart` (608 LOC) prüft
„rejects a member row from a foreign workspace" und „rejects a directory entry from a
foreign workspace", `supabase_property_repository_adapter_test.dart` (329 LOC) das
`forbidden`-Mapping. Und `property_repository_contract_test.dart` (195 LOC) testet den
Contract implementierungsunabhängig — **null** `LegacySqlite`-Referenzen, es war also nie
an den gelöschten Adapter gebunden.

**Evidenz:** `flutter analyze --no-pub` sauber · volle Suite **1464 grün / 24 Skips**
(vorher 1476; die Differenz von 12 sind exakt die Fälle der zwei gelöschten Testdateien) ·
beide Web-Builds des `verify`-Jobs grün, auch der mit gesetzten Cloud-Dart-Defines ·
`git grep` findet die Klassennamen nirgends mehr, die Dateinamen nur noch in drei
Dokumentationszeilen.

**Nicht angefasst:** die sieben Gruppe-A-Adapter, `DataBackend.sqlite`, die Composition
Root, das Cutover-Paket, die Dry-Run-Mapper und `legacy_comps_comparable_source.dart`.

---

## 4. Gruppe C — Cutover-Paket (`P2-X01` `AP4`)

| Datei | LOC | Erreichbar über | Aktion |
|---|---|---|---|
| `legacy_cutover/application/legacy_cutover.dart` | 171 | 7 `lib/`-Dateien, `tool/p2_x01_domain_cutover.dart` | **DEFER** |
| `legacy_cutover/data/legacy_cutover_fields.dart` | 221 | 5 Paket-Dateien (`LegacyCutoverEntityResult`) | **DEFER** |
| `legacy_cutover/data/legacy_cutover_planner.dart` | 91 | `tool/p2_x01_domain_cutover.dart`, 4 Tests | **DEFER** |
| `legacy_cutover/data/legacy_lease_cutover_mapper.dart` | 414 | über den Planner | **DEFER** |
| `legacy_cutover/data/legacy_party_cutover_mapper.dart` | 261 | über den Planner | **DEFER** |
| `legacy_cutover/data/legacy_unit_cutover_mapper.dart` | 379 | über den Planner | **DEFER** |
| `legacy_cutover/data/legacy_valuation_case_cutover_mapper.dart` | 298 | über den Planner | **DEFER** |
| `legacy_cutover/data/sqlite_legacy_cutover_source_adapter.dart` | 25 | `tool/p2_x01_domain_cutover.dart` | **DEFER** |
| **Summe Gruppe C** | **1860** | | |

**Warum `DEFER` und nicht `REMOVE`:** dieses Paket ist der einzige Pfad, der Legacy-Daten
nach Postgres überführt, und es ist über `tool/verify_p2_x01_domain_cutover.ps1` **in CI
getestet** (gegen eine generierte Fixture, damit keine Binärdatenbank im Repo liegt).

`04y` §1 erklärt es für gegenstandslos, weil keine Nutzdaten mehr existieren
(`app_data.db`: 0 Properties / 0 Scenarios / 0 Users, gemessen 2026-08-04). Diese Messung
ist **zwei Tage älter als `DEC-024` und stammt aus einer anderen Sitzung**. Nachweis 7
(„Legacy-Daten bleiben lesbar, solange erforderlich") lässt sich nicht durch Zitieren
einer fremden Messung erbringen.

**Vor `REMOVE` erforderlich:** die Nullmessung auf dieser Maschine reproduzieren und das
Ergebnis mit Datum und Pfad in diesem Dokument festhalten. Danach ist `REMOVE` korrekt und
löscht 1860 LOC plus zwei `tool/verify_p2_x01_*`-Skripte, den CI-Schritt und vier Testdateien.

---

## 5. Gruppe D — Dry-Run-Migrationsmapper

| Datei | LOC | Consumer | Aktion |
|---|---|---|---|
| `portfolio_property/data/sqlite_to_postgres_reference_dry_run_mapper.dart` | 1189 | 3 Tests, `tool/p2_x01_property_cutover.dart` | **KEEP** |
| `portfolio_property/data/sqlite_reference_migration_source_adapter.dart` | 20 | 1 Test, `tool/p2_x01_property_cutover.dart` | **KEEP** |
| `contacts_parties/data/sqlite_to_postgres_contacts_parties_dry_run_mapper.dart` | 947 | 2 Tests | **KEEP** |
| `documents_compliance/data/sqlite_to_postgres_documents_compliance_dry_run_mapper.dart` | 1504 | 1 Test | **KEEP** |
| `leasing_operations/data/sqlite_to_postgres_leasing_operations_dry_run_mapper.dart` | 1388 | 1 Test | **KEEP** |
| `platform_audit_jobs/data/sqlite_to_postgres_platform_audit_jobs_dry_run_mapper.dart` | 1444 | 1 Test | **KEEP** |
| **Summe Gruppe D** | **6492** | | |

### Abweichung von `04y`

`04y` §3 bündelt „9 Legacy-Adapter, 6 Cutover-Mapper, den SQLite-Zweig, die
`verify_p2_x01_*`-Skripte und den `AP4`-Rest" in **einen** Schnitt.

Der Audit widerspricht dem in einem Punkt, und der Grund ist technisch, nicht
vorsichtshalber: **Gruppe D hängt nicht am Laufzeitmodus.** Diese Mapper lesen eine
SQLite-Datei als Datei; sie werden nicht über `app_backend_wiring.dart` gebunden, nicht
über `databaseProvider` konstruiert und kennen `DataBackend` nicht. Der Wegfall von
`DataBackend.sqlite` macht sie weder kaputt noch tot.

Sie in denselben Schnitt zu legen, verwechselt zwei getrennte Dinge — den **Laufzeitmodus**
und das **Offline-Migrationswerkzeug**. `CLAUDE.md` nennt diesen Dry-Run ausdrücklich die
Vorlage für die Migration weiterer Legacy-Tabellen. Ihn zusammen mit dem Modus zu entsorgen,
löscht eine Fähigkeit, deren Entbehrlichkeit nur über eine ungeprüfte Fremdmessung
begründet ist.

**Empfehlung:** `AP-X02-2` schneidet den **Modus**. Gruppe C und D werden in einem eigenen
Arbeitspaket nach reproduzierter Nullmessung behandelt. `04y` §3 und §5 sind entsprechend
zu präzisieren.

---

## 6. Gruppe E — Sonderfall Comparables

| Datei | LOC | Bindung | Aktion |
|---|---|---|---|
| `valuation/data/legacy_comps_comparable_source.dart` | 48 | nur SQLite-Zweig (`app_backend_wiring.dart:402`) | **DEFER** |

Der einzige Adapter, bei dem die Löschung eine **fachliche Lücke zementiert** statt nur
Code zu entfernen. Im Cloud-Zweig ist stattdessen
`_UnavailableCloudValuationComparableSource` gebunden (Z. 322, 446–458), die bei jedem
Aufruf einen `UnsupportedError` wirft — das P2-D07-Comps-Aggregat ist nicht migriert.

Fällt der SQLite-Zweig, ist die werfende Attrappe die **einzige** verbleibende
Implementierung, und der Vergleichswert-Ansatz hat nirgends mehr eine funktionierende
Quelle. Cloud-Verhalten verschlechtert sich dadurch nicht (dort wirft es heute schon),
aber die 48 Zeilen sind die einzige lauffähige Referenz für `AP-X02-5`, das genau diese
Lücke schließen soll. Sie zu behalten kostet nichts und erhält die Vorlage.

### Nebenbefund: falscher Kommentar in der Composition Root

`app_backend_wiring.dart:114–116` behauptet:

> „Both backend modes read comparables from the legacy comps store … Stated here rather
> than hidden behind a mode switch that pretends otherwise."

Der Code sagt das Gegenteil: Z. 322 bindet im Cloud-Zweig
`cloudValuationComparableSourceOverride`, also die werfende Attrappe. `04y` §4 (Strom B)
wiederholt dieselbe Formulierung. Ein Kommentar, der ausdrücklich beansprucht, nichts
vorzutäuschen, täuscht hier etwas vor. **Zu korrigieren, bevor jemand darauf plant** —
eigenständig von jeder Löschung.

---

## 7. Gesamtbild

| Gruppe | Dateien | LOC | Aktion |
|---|---|---|---|
| A — gebundene Laufzeit-Adapter | 7 | 3743 | REMOVE mit dem Modus |
| B — toter Code | 2 | 368 | REMOVE sofort möglich |
| C — Cutover-Paket | 8 | 1860 | DEFER bis Nullmessung reproduziert |
| D — Dry-Run-Mapper | 6 | 6492 | KEEP |
| E — Comparables | 1 | 48 | DEFER bis `AP-X02-5` |
| **gesamt** | **24** | **12 511** | |

`04y` §3 beziffert den Schnitt mit 5785 LOC und 14 Testdateien. Der Audit kommt für
Gruppe A + B auf 4111 LOC — die Differenz ist im Wesentlichen Gruppe C, die hier nicht
im selben Schritt fällt.

---

## 8. Vorgeschlagene Reihenfolge

| Schritt | Inhalt | Gate |
|---|---|---|
| `AP-X02-2a` | Gruppe B (2 Dateien, 368 LOC) plus ihre 2 Testdateien | `flutter analyze`/`test` grün; `git grep` findet keine Referenz mehr |
| `AP-X02-2b` | `DataBackend.sqlite` streichen: SQLite-Zweig in `app_backend_wiring.dart`, Gruppe A, ihre Testdateien, `DataBackend`-Kollaps in `app_environment.dart`, `NEXIMMO_DATA_BACKEND` aus Environment-Contract und CI-Aufrufen | volle Suite grün; CI-Job `database` unverändert; kein `legacy_sqlite_*`-Adapter mehr gebunden; Provider-Read-Widgettest je migriertem Ziel |
| `AP-X02-2c` | Nullmessung von `app_data.db` auf dieser Maschine reproduzieren und protokollieren | Ergebnis mit Datum und Pfad in §4 eingetragen |
| `AP-X02-2d` | Nach `2c`: Gruppe C plus `tool/verify_p2_x01_*`, CI-Schritt und 4 Testdateien | CI grün ohne den Cutover-Schritt; `04y` §3/§5 präzisiert |
| — | Gruppe D bleibt. Gruppe E bis `AP-X02-5` | — |

`AP-X02-2a` ist bewusst zuerst: es validiert das Vorgehen an zwei Dateien, die schon
heute an keinem Laufzeitpfad hängen, bevor die Composition Root angefasst wird.

**Kollisionsrisiko:** `AP-X02-2b` fasst `app_backend_wiring.dart`, `main.dart` und
`app_state.dart` an — dieselben Dateien, die der Worktree
`.claude/worktrees/codex-ai-ph00-baseline` uncommittet verändert
(`lib/app.dart`, `supabase/config.toml`, `.github/workflows/flutter.yml`). `04y` §7 nennt
genau dieses Risiko. Vor `2b` ist der Worktree zu klären.
