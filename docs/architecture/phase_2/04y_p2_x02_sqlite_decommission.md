# P2-X02 — Cloud-Only Zielbild und SQLite-Rückbau

Status: `in_progress` — `AP-X02-1` done (`101325c`, 2026-08-07), `AP-X02-2a` done (`11e2890`, 2026-08-08), `AP-X02-2b` done (`cd7356f`/PR #12, 2026-08-08); `AP-X02-2c`/`2d` und `AP-X02-3`..`10` offen
Erstellt: 2026-08-06 · Entscheidungsgrundlage aktualisiert 2026-08-06 · Status aktualisiert 2026-08-23
Vorgänger: `04x_p2_x01_supabase_main_host.md` (`AP0`–`AP3` done, `AP4` partial)
Entscheidung: `DEC-024` in `phase_0/11_decision_register.md`

Weg von „Supabase-Host mit SQLite-Rest" zu „ausschließlich Cloud, kein SQLite".
`P2-X01` macht den Cloud-Host erreichbar; `P2-X02` entfernt die zweite
Datenschicht darunter.

`04_screen_redesign_wave_plan.md` bleibt Quelle für Screen-Zuordnung,
`01_domain_expansion_backlog.md` für Domänenumfang. Dieses Dokument verknüpft
beide mit dem Rückbau, ohne sie zu duplizieren.

---

## 1. Entscheidungsstand

Alle blockierenden Fragen sind entschieden (Nutzerentscheidung 2026-08-06).

| Frage | Entscheidung | Fixiert in |
|---|---|---|
| Darf SQLite hart entfernt werden? | **Ja.** `DEC-005` ist abgelöst | `DEC-024` |
| Offline-Startfähigkeit? | **Entfällt ersatzlos.** Kein lokaler Speicher, kein Lesecache, kein Offline-Schreibpfad | `DEC-024`; Charter Z. 21 ist aufzuheben |
| Gehostetes Supabase? | **Erst zum Shipping.** Bis dahin lokaler Stack — *Stand 2026-08-23: Staging ja (`DEC-017` accepted 2026-08-09, ein isoliertes Staging mit synthetischen Daten, Auto-Deploy); Produktion nein* | `DEC-015`..`DEC-017` accepted (nur Staging); Produktion weiterhin nicht autorisiert |
| Legacy-Datenmigration? | **Gegenstandslos.** Objektdaten waren Testdaten und wurden am 2026-08-04 bewusst entfernt | `04x` Z. 337 |
| Wann fällt der SQLite-Modus? | **Früher Schnitt (V1).** `DataBackend.sqlite` wird vor allen Domänenarbeiten gestrichen | §3, `AP-X02-2` |

Aus der letzten Zeile folgt die größte Vereinfachung gegenüber dem ersten
Entwurf: **es gibt keinen Datencutover mehr.** Damit entfällt nicht nur der
offene `AP4`-Rest (`documents` inkl. Storage-Upload), sondern auch die gesamte
Cutover-Maschinerie als künftige Verpflichtung — sie hat nichts mehr zu
migrieren und wird mit dem Rückbau entsorgt statt weitergepflegt.

Zwei Folgeänderungen an bestehenden Dokumenten gehören zum ersten Arbeitspaket:
`00_phase_2_charter.md` Z. 21 (Offline-Zusage) und die `offline-first`-Beschreibung
in `CLAUDE.md`. — **erledigt in `AP-X02-1` (`101325c`, 2026-08-07).**

---

## 2. Ausgangslage (gemessen 2026-08-06)

| Kennzahl | Wert | Quelle |
|---|---|---|
| `GlobalPage`-Ziele gesamt | 23 | `cloudReadPermissionForPage`, erschöpfender Switch |
| davon cloudfähig | 7 | `cloudReadinessForPage`, `app_navigation.dart:219` |
| davon `migrationRequired` | 16 | ebenda |
| Legacy-Repositories | 39 Dateien | `lib/data/repositories/` |
| Provider-Konstruktionen gegen `databaseProvider` | 41 | `lib/ui/state/app_state.dart` |
| Dateien, die `databaseProvider` kennen | 2 | `main.dart`, `app_state.dart` |
| Legacy-Adapter (Feature-Schicht) | 9 | `lib/features/*/data/legacy_*` |
| Cutover-Mapper | 6 | `lib/features/legacy_cutover/` |
| Testdateien mit SQLite-Bezug | 57 von 202 | `sqflite`/`AppDatabase`/`databaseFactoryFfi` |
| Legacy-Nutzdaten | 0 | `app_data.db`: 0 Properties, 0 Scenarios, 0 Users |

**Günstig:** nur zwei Dateien kennen `databaseProvider`; die 39 Repositories
werden zentral in `app_state.dart` konstruiert. Der Rückbau hat eine einzige
Naht. Und ohne Nutzdaten gibt es keine Migrations-, Parität- oder
Rollback-Verpflichtung — nur Code-Entfernung.

**Ungünstig:** die 16 nicht-cloudfähigen Screens lesen diese Provider direkt.
Solange ein Screen nicht migriert ist, hält er sein Repository am Leben.

---

## 3. Weichenstellung: Wann fällt der SQLite-Modus?

**Entschieden 2026-08-06: V1, früher Schnitt.** `DataBackend.sqlite` wird als
unterstützter Modus gestrichen, bevor an Domänen gearbeitet wird.

Das löscht in einem Zug: 9 Legacy-Adapter, 6 Cutover-Mapper, den SQLite-Zweig
in `app_backend_wiring.dart`, die `verify_p2_x01_*`-Skripte und den `AP4`-Rest —
zusammen 5785 LOC und 14 Testdateien (gemessen 2026-08-06).

> **Präzisiert am 2026-08-07 durch `cloud/02_ap_x02_2_legacy_adapter_audit.md`.**
> Der Audit widerspricht diesem Bündel in einem Punkt: die **Dry-Run-Migrationsmapper**
> (`sqlite_to_postgres_*`, 6492 LOC) hängen nicht am Laufzeitmodus — sie lesen eine
> SQLite-Datei als Datei, werden nicht über `app_backend_wiring.dart` gebunden und kennen
> `DataBackend` nicht. Sie bleiben (`KEEP`). Das **Cutover-Paket** (Gruppe C, 1860 LOC)
> ist `DEFER`, bis die Nullmessung von `app_data.db` auf der Zielmaschine reproduziert
> ist — Nachweis 7 lässt sich nicht durch Zitieren einer Messung vom 2026-08-04 aus einer
> anderen Sitzung erbringen. Der Schnitt umfasst damit zunächst Gruppe A + B = 4111 LOC.
> Die Reihenfolge steht als `AP-X02-2a`..`2d` im Audit §8.

**Der Zeitpunkt ist der eigentliche Hebel.** Charter Z. 21 schreibt pro Domäne
zwei Adapter vor (`legacy_sqlite_*` + `supabase_*`); die bisherigen Domänen
haben entsprechend 399–931 LOC Legacy-Adapter je Domäne erzeugt. Laufen `D06`,
`D08` und `D09` vor dem Schnitt, entstehen grob 2000 weitere Zeilen samt Tests,
die anschließend wieder entfernt werden. Der Schnitt gehört daher **vor**
Welle 4/6/7, nicht ans Ende — und wegen der geteilten Dateien
(`app_backend_wiring.dart`, `main.dart`, `app_state.dart`) nicht parallel zu
einer offenen Welle, sondern exklusiv an einer Wellengrenze.

**Bewusst in Kauf genommen:** die 16 noch nicht migrierten Ziele sind bis zu
ihrer jeweiligen Welle **in keinem Modus** erreichbar. Tragfähig, weil sie im
Cloud-Modus ohnehin nur einen Migrationszustand zeigen, laut
`.claude/launch.json` ausschließlich der Cloud-Host gestartet wird und keine
Nutzdaten existieren, deren Erreichbarkeit zu verteidigen wäre.

Verworfen wurde V2 (SQLite-Modus bis zur letzten Domäne halten): hält
Windows-Local funktionsfähig, kostet dafür dauerhafte Pflege aller
Legacy-Adapter, Mapper, des Backend-Switches und ihrer Tests — für Code, der am
Ende gelöscht wird.

---

## 4. Drei Arbeitsströme

Der verbreitete Denkfehler wäre, „cloudfähig" mit „Domäne migriert"
gleichzusetzen. Die `AP0`-Matrix in `04x` zeigt das Gegenteil: mehrere Domänen
sind migriert, während ihr **produktiver** Screen weiter SQLite liest.

### Strom A — Fehlende Domänen-Backends

| Backlog | Domain | Schaltet frei |
|---|---|---|
| `P2-D06` | `maintenance_capex` | `maintenance`, `contractors` |
| `P2-D08` | `finance_debt` | `ledger`, `budgets`, Covenants, Asset Workbook |
| `P2-D09` | `reporting_analytics` | `dashboard`, `reportTemplates`, `portfolios`, `esg` |
| `P2-D07`-Rest | Comparables, Kriterien, Vergleich | `criteriaSets`, `compare` |

Reihenfolge durch `01_domain_expansion_backlog.md:40` erzwungen:
**D06 → D08 → D09**. Das Dashboard ist damit strukturell das *letzte*
cloudfähige Ziel — nicht abkürzbar, weil `D09` ein Read-Model über allen
anderen Domänen ist.

### Strom B — Screen-Cutover bei bereits migrierten Domänen

| `GlobalPage` | Backend-Stand | Was noch SQLite ist |
|---|---|---|
| `properties` | migriert | Produktiver `PropertiesScreen` liest `PropertyRepository`; Cloud zeigt stattdessen `ReferenceSliceScreen`. Auflösung = `DUP-003` |
| `adminUsers` | migriert | Produktiver `UsersScreen` nutzt lokalen `securityControllerProvider` |
| `documents` | migriert | `DocumentsScreen` mischt lokale Tabs; nur das Workspace-Panel ist cloudfähig |
| `valuations` | Kern migriert | Comparables in beiden Modi Legacy; Cloud bewusst als `_UnavailableCloudValuationComparableSource` |
| `tasks`, `notifications`, `imports`, `audit` | **Schema und Adapter vorhanden** (`P2-D04`) | Kein Screen umgebaut; nur `TaskRepository` konsumiert |
| `contractors` | Party migriert | Screen hängt an `maintenanceRepositoryProvider` → wartet auf `D06` |
| `settings` | — | Mischt Plattform-, Security- und Domänen-Defaults (`BIG-009`, `DEBT-015`); vor Migration aufzuteilen |

`tasks`/`notifications`/`imports`/`audit` sind der günstigste Zugewinn im
gesamten Plan: vier Ziele, kein neues Backend, reine UI-Arbeit gegen einen
fertigen Adapter.

### Strom C — Rückbau

1. `DataBackend.sqlite` streichen; SQLite-Zweig in `app_backend_wiring.dart`,
   9 Legacy-Adapter, 6 Cutover-Mapper, `tool/verify_p2_x01_*`, `AP4`-Rest
2. Je migriertem Ziel: `cloudReadinessForPage`-Eintrag entfernen, zugehörige
   Repositories und Provider löschen
3. `SecurityGate`, `LockScreen`, `local_users`/`users`, `password_hasher` —
   die lokale Authentifizierung hat ohne SQLite keinen Speicher mehr
4. `lib/data/sqlite` inkl. `migrations.dart` (4390 LOC, `BIG`-kritisch),
   `lib/data/repositories` (39 Dateien), die 41 Provider in `app_state.dart`
5. `CloudDestinationReadiness` und `_CloudDestinationState` entfallen
6. ~~`NEXIMMO_DATA_BACKEND` aus `phase_1/01_environment_contract.md` und
   `app_environment.dart`; `DataBackend` kollabiert~~ — **geändert in `AP-X02-2b`:**
   `NEXIMMO_DATA_BACKEND` bleibt als fail-closed Deployment-Guard (`DataBackend { supabase }`);
   nur der Wert `sqlite` ist gestrichen, der Environment-Contract ist nachgezogen
7. `sqflite_common_ffi`, ggf. `path_provider` aus `pubspec.yaml`
8. 57 Testdateien: teils löschen, teils gegen Supabase-Fixtures neu schreiben

Schritt 1 läuft unter V1 **vorne**, nicht am Ende — er ist die eigentliche
Aufwandsersparnis dieses Plans.

---

## 5. Arbeitspakete

| AP | Inhalt | Gate |
|---|---|---|
| `AP-X02-1` | Dokumentenpflege an `DEC-024` angleichen: Charter Z. 21 (Offline-Zusage **und** das dort vorgeschriebene Zwei-Adapter-Muster `legacy_sqlite_*` + `supabase_*`), `CLAUDE.md` (`offline-first`, Adapter-Pattern-Abschnitt) | Charter, `CLAUDE.md` und Register widerspruchsfrei; kommende Wellen bauen nachweislich nur noch einen Adapter je Domäne — **`done`** (`101325c`, 2026-08-07) |
| `AP-X02-2` | **Früher Schnitt (V1).** `DataBackend.sqlite` streichen; Legacy-Adapter, Cutover-Mapper, Cutover-Skripte und `AP4`-Rest entfernen; `P2-X01-AP4` als *nicht anwendbar* schließen. Per `cloud/02_ap_x02_2_legacy_adapter_audit.md` §8 in `2a`..`2d` geteilt | `flutter analyze`/`test` grün; CI-Job `database` unverändert; Gate umformuliert zu „kein Legacy-Adapter mehr app-runtime-erreichbar" (zwei Dateien bleiben als Non-Runtime-Support, Comparables `DEFER` bis `AP-X02-5`) — **`2a`/`2b` `done`** (2026-08-08), **`2c`** (Nullmessung) und **`2d`** (Gruppe C + `tool/verify_p2_x01_*` + CI-Schritt) offen |
| `AP-X02-3` | Strom B Schnellgewinne: `tasks`, `notifications`, `imports`, `audit` auf `SupabasePlatformRepositoryAdapter` | 4 Ziele `ready`; Provider-Read-Test weist keinen Legacy-Provider im Widget-Baum nach |
| `AP-X02-4` | Strom B Host-Konvergenz: `properties` (`DUP-003`), `adminUsers`, `documents` — produktiver Screen ersetzt die Reference-Slice-Fläche | Reference Slice ist nicht mehr produktiver Einstieg; Deep-Links unverändert |
| `AP-X02-5` | `P2-D07`-Rest: Comparables, `criteriaSets`, `compare` | `_UnavailableCloudValuationComparableSource` entfällt |
| `AP-X02-6` | `P2-D06` `maintenance_capex` + `maintenance`, `contractors` | Status-Transition-Audit (`STM-006`/`STM-007`), Non-Negative-Cost-Constraint |
| `AP-X02-7` | `P2-D08` `finance_debt` + `ledger`, `budgets`; `settings`-Aufteilung | Ledger-Append-Only, Budget-Immutability, Covenant-Reproduzierbarkeit |
| `AP-X02-8` | `P2-D09` `reporting_analytics` + `dashboard`, `reportTemplates`, `portfolios`, `esg` | Report-Reproduzierbarkeit, No-Write-Back; **alle 23 Ziele `ready`** |
| `AP-X02-9` | Restrückbau Strom C Schritte 2–8 | Kein `sqflite` in `pubspec.yaml`; `lib/data/sqlite` und `lib/data/repositories` entfernt |
| `AP-X02-10` | Finales Gate: 65-Screen-Abdeckung, Responsive, Auth, Golden Path Web + Windows | Deckt `P2-X01-AP6` mit ab |

`AP-X02-3` bis `AP-X02-6` sind untereinander unabhängig und parallelisierbar.
`AP-X02-7` erst nach `-6`, `AP-X02-8` erst nach `-7`.

---

## 6. Abhängigkeitsgraph

```
AP-X02-1 (Doku)
    │
AP-X02-2 (Früher Schnitt) ──┬──> AP-X02-3 (Platform-UI)      ──┐
                            ├──> AP-X02-4 (Host-Konvergenz)   ──┤
                            ├──> AP-X02-5 (D07-Rest)          ──┤
                            └──> AP-X02-6 (D06) ──> AP-X02-7 (D08) ──> AP-X02-8 (D09)
                                                                            │
                                                            AP-X02-9 (Rückbau)
                                                                            │
                                                            AP-X02-10 (Gate)
```

---

## 7. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Früher Schnitt macht 16 Ziele unerreichbar, bevor ihre Welle steht | Bewusst akzeptiert (V1, entschieden 2026-08-06). Nach `AP-X02-2` nicht mehr günstig umkehrbar — ein Zurück zu V2 hieße, gelöschte Adapter und Mapper zu rekonstruieren |
| `AP-X02-2` kollidiert mit laufender Wellenarbeit an denselben Dateien | `app_backend_wiring.dart`, `main.dart` und `app_state.dart` sind die Kollisionspunkte. Vor Ausführung mit der laufenden Wellensession abstimmen; nicht parallel zu einer offenen Welle schneiden |
| `migrations.dart` (4390 LOC) wird in einem Zug entfernt und reißt Tests mit | `02_architecture_modernization_backlog.md:55` gilt: inkrementell je Domäne stilllegen, kein Einzel-Rewrite |
| Screen gilt als migriert, liest aber weiter einen Legacy-Provider | Provider-Read-Widgettests pro Ziel, analog `AP0`-Evidenz |
| Lokale Auth fällt mit SQLite, bevor die Cloud-Auth alle Rollen abdeckt | `AP-X02-4` (`adminUsers`) liegt vor Strom C Schritt 3; `DEC-016` (accepted 2026-08-08) und `DEC-025` (AAL2 für die gesamte Workspace-Geschäftsfläche) sind entschieden — die Cloud-Auth deckt die Rollenmatrix serverseitig ab |
| Gehosteter Betrieb wird vorweggenommen | `DEC-015`..`017` sind seit 2026-08-08/09 accepted und decken nur Staging ab; dieser Plan endet vor der Produktionsfreigabe |
| 57 SQLite-Tests werden gelöscht statt ersetzt, Abdeckung sinkt unbemerkt | Pro Rückbauschritt Abdeckungsvergleich; `09_test_baseline.md` fortschreiben |

---

## 8. Definition of Done

- Alle 23 `GlobalPage`-Ziele sind `ready`; `CloudDestinationReadiness` existiert nicht mehr
- `pubspec.yaml` ohne `sqflite_common_ffi`; `lib/data/sqlite` und `lib/data/repositories` entfernt
- `NEXIMMO_DATA_BACKEND` bleibt als fail-closed Deployment-Guard (`DataBackend { supabase }`, `AP-X02-2b`); nur der Wert `sqlite` ist entfernt
- `flutter analyze --no-pub` und `flutter test --no-pub` grün, `flutter build web --no-pub` unverändert
- CI-Job `database` unverändert grün; kein `tool/verify_*` referenziert eine SQLite-Quelle
- `DEC-005` als abgelöst markiert, `DEC-024` umgesetzt
- Charter und `CLAUDE.md` beschreiben das Produkt nicht mehr als offline-first (erledigt, `AP-X02-1`)
- Vor Produktions-Shipping: Produktionsfreigabe entscheiden (`DEC-015`..`DEC-017` sind accepted und decken nur Staging ab)
