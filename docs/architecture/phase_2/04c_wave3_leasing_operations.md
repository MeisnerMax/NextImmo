# Welle 3 — Detaildokument: leasing_operations (UI)

Status: `active` — alle Punkte unter „Plan gegen Realität" sind am 2026-08-04 vom Nutzer entschieden, einschließlich der Folgefrage aus Befund 1 (Alert-Ableitung vollständig serverseitig). Kein Arbeitspaket dieser Welle ist mehr durch eine offene Entscheidung blockiert. **AP8 (`P2-D05a operations_signals`) ist `done` (2026-08-06, siehe W3-AP8-Zeile in `00_phase_2_status.md`)** — damit sind AP9 (OperationsOverviewScreen) und AP10 (OperationsAlertsScreen) entblockt.
Stand: 2026-08-04
Bezug: `04_screen_redesign_wave_plan.md` (Wellenzuordnung + zwei Worked Examples als Qualitätsmaßstab), `03_design_system.md` (Sechs-Punkte-Template, Pflicht-Komponenten, Pflicht-Zustände), `04b_wave2_contacts_documents.md` (Muster der Backend-gewählten Contract-Konsumtion), `00_phase_2_status.md` (Ist-Stand), P2-D05-Contract unter `lib/features/leasing_operations/`.

## Backend-Voraussetzungen

- **P2-D05 `leasing_operations` ist `done`** (Schema + 10 RPCs + Contract + Supabase-/Legacy-Adapter + Realtime + Dry-Run-Mapper + Zwei-Sitzungs-Concurrency-Gate). **7 Ports**: `UnitRepository`/`UnitSearchPort`, `LeaseRepository`/`LeaseSearchPort`, `LeasingCaseRepository`/`LeasingCaseSearchPort`, `RentRollPort`. DTOs `UnitDto`/`UnitSummaryDto`, `LeaseDto`/`LeaseSummaryDto`, `LeasingCaseDto`/`LeasingCaseSummaryDto`, `RentRollSnapshotDto`/`RentRollSnapshotLineDto`. Enums `UnitStatus` (STM-003), `LeaseStatus` (STM-005), `LeasingCaseStatus` (STM-004), `LeasingCaseSource`, `LeaseBillingFrequency`. Keyset-Suche (`LeasingPageRequest`/`LeasingPageResult`); sealed `LeasingRepositoryResult<T>` + `LeasingVersionConflict` + `RentRollCurrencyMismatch`.
- **P2-D02 `contacts_parties` ist `done`** — und ist für diese Welle **die** Mieter-Quelle: es gibt bewusst **keine Cloud-`tenants`-Tabelle** (AGG-005). Ein Mieter ist eine Partei mit offener `tenant`-Rolle; `LeaseSummaryDto.tenantPartyId` ist der Join.
- **Provider-Naht steht bereits** (`lib/app_backend_wiring.dart`, `featureBackendOverrides`): alle 7 Ports sind Backend-gewählt verdrahtet, Realtime nur im Cloud-Modus, Nicht-verdrahtet = fail closed. **Anders als Welle 2 braucht Welle 3 also kein Arbeitspaket 0** — die Naht ist Teil von P2-D05 Increment 3 und durch `test/app_backend_wiring_test.dart` abgesichert.

## Entschiedene Domänenfragen, die diese Screens sichtbar machen müssen (nicht neu verhandeln)

- **`OPN-DOM-001`: eine Einheit darf mehrere gleichzeitig wirksame Verträge haben** (Nutzerentscheidung 2026-07-29, dokumentierter Default ausdrücklich überstimmt). Konsequenz für die UI: **kein Screen darf „der Vertrag der Einheit" sagen.** Einheiten-Detail zeigt eine Vertrags*liste*, der Rent Roll summiert je Einheit, und die Vertragsliste gefiltert nach Einheit liefert alle Treffer. Ein Einzahl-Wording wäre hier ein Rückschritt hinter eine getroffene Entscheidung.
- **`AGG-004`: Belegung ist abgeleitet, nicht gesetzt.** `vacant`/`occupied` folgen aus den wirksamen Verträgen; nur `offline` ist eine Nutzeraktion und braucht einen Grund. Die UI bietet deshalb **keinen** Status-Umschalter auf `occupied`/`vacant` — der Server weist das mit `validationFailed` ab. Der Grund im Offline-Dialog **ist** der Offline-Grund (ein Feld, ein Sachverhalt).
- **`AGG-007`: ein Rent Roll ist unveränderlich, aber ausdrücklich nicht eindeutig je Periode.** Mehrere Snapshots je Stichtag sind zulässig und werden nach `generatedAt` sortiert; „der aktuelle" ist eine Leserentscheidung. Die UI zeigt deshalb eine Snapshot-*Historie*, keinen überschreibbaren Einzelstand.
- **Ein Einheit kann `occupied` sein und 0,00 zum Rent Roll beitragen** (Statusfenster vs. Laufzeitfenster). `RentRollSnapshotLineDto.isOccupiedButOutsideTerm` benennt genau das — die UI muss es **erklären**, sonst sieht es wie ein Rechenfehler aus.
- **`OPN-DOM-005` ist offen → es gibt nirgends einen Löschpfad.** Kein Screen dieser Welle bekommt eine Löschaktion.

---

## Plan gegen Realität — vier Befunde, die vor der Umsetzung entschieden werden müssen

Beim Aufmaß der zehn Screens gegen den fertigen Contract sind vier Stellen aufgefallen, an denen der Wellenplan mehr voraussetzt, als P2-D05 liefert. Sie wurden benannt statt umgangen (Hard-Stop-Regel des Ausführungsprompts: einen Plan-vs-Realität-Fehler flaggen, nicht still improvisieren) und am **2026-08-04 vom Nutzer entschieden**. Die Entscheidung steht jeweils am Ende des Befunds.

### Befund 1 — SCR-032 OperationsAlertsScreen hat gar kein Cloud-Backend

`operations_alerts_screen.dart` liest `operationsRepositoryProvider.loadAlerts(...)` und schreibt `updateAlertStatus(...)`. Es gibt **keine** `alerts`-Tabelle in irgendeiner Migration, und der P2-D05-Contract hat keinen Alerts-Port. `platform_audit_jobs` (P2-D04) hat einen `NotificationPort` — das sind Benachrichtigungen, nicht operative Alerts mit eigenem Lebenszyklus und Objekt-/Einheiten-/Vertragsbezug.

**ENTSCHIEDEN (2026-08-04): eigener Backend-Increment zuerst**, danach der Screen darauf. Der Increment heißt hier **`P2-D05a operations_signals`** und ist Voraussetzung für AP7 und AP8.

**Was beim Aufmaß dieses Increments herauskam und seine Form komplett ändert — bitte vor der ersten Migrationszeile lesen:**

**Alerts existieren im Legacy gar nicht als Datensätze. Sie werden *berechnet*.** Es gibt keine `operations_alerts`-Tabelle. `operations_repo.dart` leitet Alerts bei jedem Aufruf aus den Fachdaten ab (Vertragsablauf in 30/60/90/180 Tagen, Einheiten ohne aktiven Vertrag, fehlende Mieterstammdaten, Datenkonflikte) und faltet die Datenqualitätsbefunde über `_buildQualityAlerts` in dieselbe Liste. Persistiert wird ausschließlich die **menschliche Reaktion** darauf, in `operations_alert_states` (`alert_id` PK, `property_id`, `status`, `resolution_note`, `updated_at`).

Daraus folgen drei Dinge, die dieser Increment entscheiden muss statt sie zu erben:

1. **Wo lebt die Ableitung? — ENTSCHIEDEN (2026-08-04): vollständig serverseitig in Postgres.** Die Regeln (Ablauffenster 30/60/90/180 Tage, Einheiten ohne wirksamen Vertrag, fehlende Mieterstammdaten, Datenkonflikte) werden nach PL/pgSQL portiert; der Client rechnet nichts mehr aus, er liest Signale. **Damit ist die `RISK-QA-001`-Gefahr bewusst eingegangen und muss aktiv beherrscht werden**, denn die Dart-Engine in `operations_repo.dart` bleibt für den SQLite-Modus bestehen und ist ab dann die zweite Implementierung. **Bindende Auflage für diesen Increment:** ein **Paritätstest**, der denselben Fixture-Bestand durch beide Wege schickt und identische Signale (Typ, Schwere, Bezugsentität) erwartet — bricht er, ist eine der beiden Seiten gedriftet und das fällt im Build auf statt beim Nutzer. Ohne diesen Test gilt der Increment nicht als fertig. Die verworfene Alternative (nur der quittierte Zustand serverseitig, Ableitung im Client) hätte die Drift vermieden, aber jeden Client gezwungen, die Regeln selbst zu kennen — und der Cloud-Betrieb soll die Wahrheit halten, nicht die Oberfläche.
2. **Die Alert-Identität ist inhaltsabgeleitet und dadurch zerbrechlich.** `_buildAlertId` verkettet `type | propertyId | unitId | leaseId | tenantId | **message**`. Der Meldungstext ist Teil des Schlüssels — eine Umformulierung oder Übersetzung ändert die ID und **verwaist stillschweigend jede Quittierung**. Das ist ein latenter Fehler schon im Legacy; die Cloud-Fassung darf ihn nicht übernehmen (Vorschlag: stabiler Schlüssel aus Typ + Bezugsentität + fachlichem Diskriminator, Meldung als Anzeigetext ohne Schlüsselwirkung).
3. **Der Zustand hat heute weder Historie noch Version.** `updateAlertStatus` schreibt mit `ConflictAlgorithm.replace` — Überschreiben ohne Audit. Das widerspricht der Guardrail, dass jede kritische Mutation append-only auditiert ist, und muss in der Cloud-Fassung als versionierter, auditierter Übergang neu gebaut werden, nicht 1:1 portiert.

### Befund 2 — SCR-030 RentRollScreen verliert im SQLite-Modus die Anzeige *und* eine Funktion

Zwei Dinge auf einmal:

1. Der Legacy-Adapter **verweigert** den Rent Roll bewusst (`dependencyConflict` mit Begründung, siehe P2-D05-Increment-3-Zeile im Status-Doc): die lokalen Snapshots sind nach Periode statt nach Datum verschlüsselt und tragen weder Währung noch Status-Partition noch die Aufteilung Grund-/Neben-/Stellplatzmiete. Heute zeigt der Screen genau diese lokalen Snapshots über `rentRollRepositoryProvider`. Zieht Welle 3 ihn auf den Contract, sieht der SQLite-Modus **keinen Rent Roll mehr** — nicht „read-only", sondern gar nichts. Das ist materiell etwas anderes als die Welle-2-Entscheidung („lesen geht, mutieren nicht").
2. `rent_roll_screen.dart` ruft heute `deleteSnapshot(...)`. Die Cloud hat **keinen** Löschpfad (AGG-007 unveränderlich, `OPN-DOM-005` offen). Der Umbau **entfernt** also eine heute vorhandene Funktion.

**ENTSCHIEDEN (2026-08-04): der vorgeschlagene Default.** (a) Der Screen konsumiert den Contract wie alle anderen; im SQLite-Modus zeigt er den Pflicht-Zustand „read-only bis migriert" **mit der Begründung des Adapters** (die ist genau dafür gebaut) statt einer leeren Liste. (b) Die Löschaktion entfällt ersatzlos; der Screen erklärt stattdessen, dass ein Snapshot eingefroren ist und eine Korrektur ein neuer Snapshot ist. Punkt (b) ist ausdrücklich als Entfernen eines V1-Pfads bestätigt worden.

### Befund 3 — SCR-022 OperationsOverviewScreen aggregiert mehr, als der Contract kennt

`operationsRepositoryProvider.loadOverview(propertyId)` liefert ein Bündel aus Einheiten-, Vertrags-, Mieter-, **Alert**- und **Datenqualitäts**-Kennzahlen. Einheiten-, Vertrags- und Belegungsteile sind aus `UnitSearchPort`/`LeaseSearchPort` rekonstruierbar; der Alert-Teil hängt an Befund 1, der Datenqualitätsteil (`OperationsDataQualityIssue`) hat ebenfalls kein Cloud-Gegenstück.

**ENTSCHIEDEN (2026-08-04): voll auf das Cloud-Gegenstück** — kein gemischter Betrieb und keine „noch nicht verfügbar"-Kacheln. Das bindet SCR-022 an denselben `P2-D05a`-Increment wie Befund 1: dieser muss also **beides** abdecken, Alerts *und* Datenqualitätsbefunde, denn beide sind heute berechnete Größen aus derselben Quelle (`_buildQualityAlerts` faltet die Datenqualität in die Alertliste). Konsequenz für die Reihenfolge: **AP7 und AP8 starten erst nach `P2-D05a`**; AP1–AP6 sind davon unabhängig und können vorher laufen.

### Befund 4 — SCR-065 RentalOverviewScreen ist inzwischen vollständig toter Code

Der Wellenplan verortet ihn unter `portfolio/` und beschreibt `DEAD-002` als „importiert, aber keinem `GlobalPage`-Zweig zugeordnet". Beides stimmt nicht mehr: die Datei liegt unter `lib/ui/screens/rental_overview_screen.dart`, und sie wird **von nichts mehr importiert** — der von `DEAD-002` beschriebene `app_scaffold.dart`-Import ist durch die Welle-0/1-Bereinigung bereits weg. Der Screen ist also nicht mehr „unerreichbar verdrahtet", sondern schlicht unbenutzt.

**ENTSCHIEDEN (2026-08-04): als Portfolio-Unterseite wiederbeleben**, nicht löschen. Der Screen bleibt in Welle 3 (der Wellenplan weist ihm SCR-065 dort zu), liest aber portfolioweit statt objektbezogen: Belegungs- und Mietkennzahlen über **alle** Objekte aus `unitSearchProvider`/`leaseSearchProvider` ohne `propertyId`-Filter. Er braucht damit eine Anbindung an die Portfolio-Navigation — die einzige additive Navigationsänderung dieser Welle, vor Umsetzung als solche zu bestätigen. `DEAD-002` wird damit als „angebunden" statt als „entfernt" geschlossen.

---

## Scope

| SCR | Screen | Datei (Ist) | LOC (Ist) | `Nx*`-Ist | Backend in W3 | Schuld |
|---|---|---|---|---|---|---|
| SCR-024 | UnitsScreen | `lib/ui/screens/property_detail/units_screen.dart` | 1253 | 21 | Contract | `BIG-018` |
| SCR-025 | UnitDetailScreen | `lib/ui/screens/property_detail/unit_detail_screen.dart` | 1382 | 8 | Contract | `BIG-016` |
| SCR-028 | LeasesScreen | `lib/ui/screens/property_detail/leases_screen.dart` | 1211 | 14 | Contract | `BIG-020` |
| SCR-029 | LeaseDetailScreen | `lib/ui/screens/property_detail/lease_detail_screen.dart` | 920 | 0 | Contract | — |
| SCR-026 | TenantsScreen | `lib/ui/screens/property_detail/tenants_screen.dart` | 687 | 18 | **P2-D02** (Rollen-Sicht) | `DUP-010` |
| SCR-027 | TenantDetailScreen | `lib/ui/screens/property_detail/tenant_detail_screen.dart` | 414 | 2 | **P2-D02** + Contract | `DUP-010` |
| SCR-030 | RentRollScreen | `lib/ui/screens/property_detail/rent_roll_screen.dart` | 567 | 0 | Contract (Befund 2) | V9.1 Punkte 3+4 |
| SCR-065 | RentalOverviewScreen | `lib/ui/screens/rental_overview_screen.dart` | 486 | 0 | Contract, portfolioweit (Befund 4) | `DEAD-002` |
| SCR-022 | OperationsOverviewScreen | `lib/ui/screens/property_detail/operations_overview_screen.dart` | 397 | 0 | Contract + `P2-D05a` (Befund 3) | — |
| SCR-032 | OperationsAlertsScreen | `lib/ui/screens/property_detail/operations_alerts_screen.dart` | 612 | 0 | `P2-D05a` (Befund 1) | V9.1 Punkt 6 |
| — | **`P2-D05a operations_signals`** (Backend, kein Screen) | `lib/features/leasing_operations/{application,data,domain}` | 0 | — | `done` — Voraussetzung für SCR-022 + SCR-032 erfüllt | — |

**Neu in dieser Welle, ohne Legacy-Vorlage:** die `LeasingCase`-Pipeline (STM-004) hat heute **keinen** Screen — sie war der UI-only-Statusstring-Teil von `FTR-024`, den P2-D05 zum echten Aggregat gemacht hat. Sie bekommt eine Fläche im Vertragsbereich (siehe Arbeitspaket 4), nicht einen eigenen SCR-Eintrag, weil der Wellenplan die Screenzahl auf 65 pinnt.

## Reihenfolge und Begründung

1. **UnitsScreen (AP1) als Pattern-Beweis.** Er ist der Screen, an dem `AGG-004` und `OPN-DOM-001` beide sichtbar werden, und mit 21 `Nx*`-Nutzungen bereits am weitesten. Was hier steht — Contract-Konsumtion, abgeleiteter Status ohne Umschalter, Offline-Transition mit Pflichtgrund, alle Pflicht-Zustände inkl. `versionConflict` — übernehmen die folgenden drei.
2. **UnitDetailScreen (AP2)** direkt danach, weil es dieselben Ports plus die Vertragsliste je Einheit ist: der Ort, an dem „mehrere Verträge je Einheit" zuerst wirklich weh tut, wenn das Wording falsch ist.
3. **LeasesScreen + LeaseDetailScreen (AP3)** als Paar — Liste und Detail teilen STM-005-Übergangslogik, Statusabbildung und Formularbausteine; getrennt gebaut würde die Übergangslogik zweimal entstehen.
4. **LeasingCase-Pipeline (AP4)** nach den Verträgen, weil ihr Endzustand `signed` einen Vertrag **braucht** (`LeasingCaseBlockedReason.leaseRequired`) — die Fläche ist ohne funktionierenden Vertragsteil nicht durchspielbar.
5. **TenantsScreen + TenantDetailScreen (AP5)** als Paar, gebaut als **Rollen-Sicht auf das Parteien-Verzeichnis aus Welle 2** plus Vertragsliste über `LeaseListQuery.tenantPartyId`. Sie lösen `DUP-010` UI-seitig dort ein, wo Welle 2 es bewusst offen ließ.
6. **RentRollScreen (AP6)** nach Einheiten und Verträgen, weil er beide summiert und die Erklärung „belegt, trägt aber 0,00 bei" nur mit korrektem Einheiten- und Vertragsbild überhaupt formulierbar ist.
7. **RentalOverviewScreen (AP7)** — portfolioweite Sicht auf dieselben Ports, ohne `propertyId`-Filter; sinnvoll erst, wenn die objektbezogenen Flächen stehen (Befund 4).
8. **`P2-D05a operations_signals` (AP8, Backend) — `done`.** Eigener Increment nach der Domänen-Arbeitsordnung (Schema → pgTAP → Rollback → Contract → Adapter → Integrationstest → Realtime → CI), siehe W3-AP8-Zeile in `00_phase_2_status.md` für Details und Verifikation.
9. **OperationsOverviewScreen (AP9)** — aggregiert alles Vorherige, jetzt vollständig aus Cloud-Gegenstücken (Befund 3).
10. **OperationsAlertsScreen (AP10)** zuletzt, auf dem in AP8 gebauten Contract (Befund 1).

`BIG-016`/`BIG-018`/`BIG-020` werden nicht durch Aufteilen „in Dateien" gelöst, sondern durch geteilte Bausteine unter `lib/ui/screens/property_detail/leasing/widgets/` (Statusabbildung, Vertragsformular, Einheitenformular, Transitions-Bestätigung) plus schlanke Orchestrierung je Screen — dieselbe Linie wie `docs/widgets/` in Welle 2.

---

## AP1 — SCR-024 UnitsScreen (Pattern-Beweis)

1. **Zielbild**: Die Einheiten eines Objekts als ruhige, statusgeführte Fläche — Belegung auf einen Blick, Leerstand mit Dauer, offline genommene Einheiten mit ihrem Grund. Der Status ist sichtbar **abgeleitet**: die UI erklärt, dass Belegung aus den wirksamen Verträgen folgt, statt einen Schalter anzubieten, den der Server ablehnt.
2. **Layout**: `NxPageHeader` (Titel „Einheiten", Suche, Primäraktion „Einheit anlegen", Statusfilter als Header-Aktion). Hauptfläche `NxDataTableShell` mit `UnitSummaryDto`-Spalten (Code, Status als `NxStatusBadge` STM-003, Typ, Etage, Fläche, Zimmer, Leerstand-seit); weitere Spalten hinter Column-Picker. Desktop optional Liste+Detailpanel, Tablet/Phone Liste→Detail-Route. Tabelle horizontal scrollbar mit gepinnter Code-Spalte auf Phone.
3. **States**: loading = Tabellen-Skeleton; empty = `NxEmptyState` „Noch keine Einheit — erste anlegen"; leerer Filtertreffer als **eigener** Leerzustand; error = Retry ohne Roh-Exception; **forbidden** = explizit (`lease.read` fehlt, RLS); **versionConflict** = Konfliktdialog mit der aktuellen Einheit aus `LeasingVersionConflict.currentUnit` und Auflösen-Aktion; **read-only bis migriert** = im SQLite-Modus tragen alle Mutationsaffordanzen den Hinweis (Legacy-Adapter → `dependencyConflict`) statt still zu no-oppen.
4. **Data density**: `unitSearchProvider` (Keyset über `UnitListQuery`, serverseitig nach `propertyId` und `status` gefiltert), `unitRepositoryProvider` für Detail/Mutation. Textsuche und Sortierung client-seitig über die geladenen Seiten — `UnitListQuery` hat kein Textprädikat, und diese Welle führt keine neuen Backend-Reads ein (Welle-2-Präzedenz). Realtime-Invalidierung über `leasingQueryInvalidationSourceProvider`, coalescing je Workspace; **eine Vertragsaktivierung erzeugt bewusst zwei Ereignisse** (Vertrag + abgeleitete Einheit) — der Screen darf daraus nicht zwei Refetches machen.
5. **Interactions**: Anlegen (`UnitDraft`), Bearbeiten (`UnitUpdateDto`, Whole-Record mit `expectedVersion`); **Offline nehmen / zurückholen** als eigener, bestätigungspflichtiger Übergang mit **Pflichtgrund** — der Dialogtext sagt ausdrücklich, dass dieser Grund als Offline-Grund gespeichert und auditiert wird; **kein** Umschalter auf `occupied`/`vacant`; keine Löschung.
6. **Debt resolved**: `BIG-018` (1253 LOC) → schlanke Orchestrierung + geteilte `leasing/widgets/`-Bausteine. Erster Screen der Welle mit vollständigem Pflicht-Zustandssatz als Widget-Test. Etabliert die STM-003-Badge-Abbildung, die AP2/AP6/AP7 wiederverwenden.

## AP2 — SCR-025 UnitDetailScreen

1. **Zielbild**: Eine Einheit in ganzer Tiefe — Stammdaten, abgeleiteter Status mit Begründung, **alle** auf ihr wirksamen Verträge (nicht „der" Vertrag), Miet-Zielwerte, Vermarktungs-/Renovierungsstand, und die Historie ihrer Statuswechsel als auditierte Tatsachen.
2. **Layout**: `NxPageHeader` mit `NxBreadcrumbs` (Objekt → Einheiten → Code); Sektionen über `NxSectionHeader`/`NxFormSectionCard`: (1) Identität und Fläche, (2) Status + Belegungsbegründung, (3) **Verträge dieser Einheit** als `NxDataTableShell`, (4) Miete/Vermarktung. Rendert in `PropertyShell` — Kopffläche knapp halten (W1-AP2-Regel).
3. **States**: wie AP1, plus **notFound** als eigener Zustand (direkt aufgerufene, nicht existente Einheit) statt leerer Fläche; **`currencyCode == null` bei gesetztem Mietbetrag** wird als „Währung nicht hinterlegt" ausgewiesen, nicht als 0 oder als stille Auslassung — im SQLite-Modus ist das der Normalfall, weil die Legacy-Tabelle keine Währung führt.
4. **Data density**: `unitRepositoryProvider.getById`, dazu `leaseSearchProvider` mit `LeaseListQuery(unitId: …)` — **ohne** `effectiveOnly`, damit Historie sichtbar bleibt, mit `isEffective` als Spaltenmarkierung. Keine Aggregation im Screen: was der Contract nicht liefert, wird nicht gerechnet.
5. **Interactions**: Bearbeiten und Offline-Übergang wie AP1; Absprung in einen Vertrag (AP3); Absprung in den Rent Roll des Objekts (AP6). Keine Löschung.
6. **Debt resolved**: `BIG-016` (1382 LOC) → geteilte Bausteine + Orchestrierung. **Der Screen ist der Ort, an dem `OPN-DOM-001` im Produkt ankommt**: die heutige `UnitDetailBundle.activeLease`-Einzahl (`operations_repo.dart`) verschwindet zugunsten einer Liste. Widget-Test deckt ausdrücklich den Fall „zwei gleichzeitig wirksame Verträge" ab.

## AP3 — SCR-028 LeasesScreen + SCR-029 LeaseDetailScreen

1. **Zielbild**: Verträge als geführter Lebenszyklus statt als Formularliste. STM-005 (`draft → reviewed → sent → tenantSigned → landlordSigned → active → ended`, Abbruch aus jedem nichtterminalen Zustand) ist im Screen sichtbar: der nächste zulässige Schritt ist die Primäraktion, alles andere ist gar nicht erst angeboten.
2. **Layout**: Liste = `NxPageHeader` + Filterzeile (Status, nur wirksame, Mieter) + `NxDataTableShell` (Name, Einheit, Mieter, Status als `NxStatusBadge` STM-005, Beginn/Ende, Grundmiete + Währung). Detail = `NxBreadcrumbs` + Sektionen: Vertragsdaten, Laufzeit/Fristen, Miete und Nebenkosten, Statusverlauf. Phone: gepinnte Namensspalte, Detail als eigene Route.
3. **States**: voller Pflichtsatz; **versionConflict** ist hier der wahrscheinlichste Echtfall (zwei Sitzungen am selben Vertrag — genau das, was der P2-D05-Concurrency-Test beweist) und bekommt einen expliziten Dialog mit `LeasingVersionConflict.currentLease` und Auflösen-Aktion; **validationFailed bei unzulässigem Übergang** wird als erklärter Zustand gerendert („STM-005 erlaubt von *x* nur *y*"), nicht als Fehler-Snackbar.
4. **Data density**: `leaseSearchProvider` (Keyset, `LeaseListQuery` mit `propertyId`/`unitId`/`tenantPartyId`/`status`/`effectiveOnly` — alles serverseitig), `leaseRepositoryProvider` für Detail und Übergänge. `LeaseDto.totalRentMonthly` kommt aus dem DTO, wird nicht im Screen nachgerechnet.
5. **Interactions**: Anlegen (`LeaseDraft`, startet immer in `draft`); Bearbeiten (`LeaseUpdateDto`) **nur solange der Vertrag nicht bindend ist** — der Server weist es danach ab, die UI bietet es dann gar nicht erst an und erklärt warum („Änderung der Konditionen = neuer Vertrag"); Übergänge als bestätigungspflichtige Einzelschritte, **Abbruch mit Pflichtgrund**, **Beenden mit optionalem Auszugsdatum** (nur dort zulässig). Keine Löschung.
6. **Debt resolved**: `BIG-020` (1211 LOC, Schwere „hoch") → Liste und Detail teilen Statusabbildung, Formular und Transitions-Bestätigung aus `leasing/widgets/`. `lease_detail_screen.dart` geht von **0** `Nx*`-Nutzungen auf Systemstandard. Widget-Tests decken die Übergangsmatrix ab, inklusive „kein Rückwärtsschritt".

## AP4 — LeasingCase-Pipeline (neu, ohne Legacy-Vorlage)

1. **Zielbild**: Die Vermietungspipeline als echtes Aggregat statt als UI-Statusstring (`FTR-024`): eine Anfrage wandert in zehn Stufen von `inquiry` bis `completed`, jeder Schritt auditiert, Abbruch mit Grund, kein Wiederöffnen — ein neuer Versuch ist ein neuer Fall.
2. **Layout**: Pipeline-Board (Spalten je Stufe) auf Desktop, gestapelte Liste mit Stufenfilter auf Tablet/Phone. `NxCard` je Fall, `NxStatusBadge` für die Stufe. Fall-Detail als Panel/Route mit Interessent, Einheit, erzeugtem Vertrag.
3. **States**: voller Pflichtsatz; **der blockierte nächste Schritt ist ein eigener, erklärter Zustand**: `LeasingCaseDto.blockedReason` sagt vorab, ob Interessent, Einheit oder Vertrag fehlt — die Affordanz wird deaktiviert **mit** diesem Grund, statt den Nutzer in ein `validationFailed` laufen zu lassen. Der Server bleibt die Autorität; das Client-Mirror entscheidet nichts.
4. **Data density**: `leasingCaseSearchProvider` (`openOnly` für das Board), `leasingCaseRepositoryProvider` für Detail und Übergänge. `LeasingCaseStatus.nextStage`/`canTransitionTo` steuern nur Affordanzen.
5. **Interactions**: Anlegen (`LeasingCaseDraft`, startet in `inquiry`); Attribute ändern solange offen; **genau ein Schritt vorwärts** oder **Abbruch mit Pflichtgrund**; ab `signed` ist ein Vertrag zu benennen — die UI verlinkt an dieser Stelle direkt in den Vertragsanlage-Flow aus AP3. Keine Rückwärtskante, keine Löschung.
6. **Debt resolved**: `FTR-024` UI-seitig eingelöst. **Kein Legacy-Screen wird migriert** — es gibt keinen; die heutige Pipeline existierte nur als Statusstring ohne Persistenz.

## AP5 — SCR-026 TenantsScreen + SCR-027 TenantDetailScreen

1. **Zielbild**: Mieter als **Rollen-Sicht auf das Parteien-Verzeichnis**, nicht als zweite Personenstammdatei. Liste = Parteien mit offener `tenant`-Rolle; Detail = Identität (aus P2-D02) plus alle Verträge dieser Partei (aus P2-D05). Damit ist `DUP-010` auch an der Stelle eingelöst, an der Welle 2 es bewusst offenließ.
2. **Layout**: Liste `NxPageHeader` + `NxDataTableShell` über `PartySummaryDto` (Name, Typ-Badge, Kontakt) — **rollengefiltert serverseitig** über `PartyListQuery.roleType = tenant`. Detail: Sektion Identität/Rollen (P2-D02-Ports) + Sektion „Verträge" als `NxDataTableShell` über `LeaseListQuery(tenantPartyId: …)`.
3. **States**: voller Pflichtsatz beider Domänen; **read-only bis migriert** gilt hier für den Parteien-Teil genauso wie für den Vertragsteil, weil **beide** Legacy-Adapter mutationsfrei sind.
4. **Data density**: `partySearchProvider` + `partyRoleProvider` (Welle 2) und `leaseSearchProvider` (Welle 3) — zwei Contracts in einem Screen, sauber getrennt gelesen, **keine** neue gemeinsame Abfrage. Im SQLite-Modus stimmen die IDs überein, weil der Legacy-Leasing-Adapter die Mieter-ID bewusst als Partei-ID durchreicht (kommentiert im Adapter) — ohne diese Übereinstimmung zeigte das Detail einen Vertrag ohne Mieter.
5. **Interactions**: Mieter anlegen = **Partei anlegen + `tenant`-Rolle zuweisen** über die P2-D02-Ports (kein eigener Mieter-Schreibpfad); Rolle beenden statt löschen; Absprung in Vertrag und Einheit.
6. **Debt resolved**: `DUP-010` UI-seitig abgeschlossen; der heutige `leaseRepositoryProvider.upsertTenant`-Pfad in `tenants_screen.dart:630` (Legacy-Mieterstammsatz) entfällt. **Zu beachten:** `tenants_screen.dart` liest heute zusätzlich `propertiesControllerProvider` — der Cloud-Host-Befund aus Welle 2 (`04b`, Nachtrag 2026-07-28) gilt hier sinngemäß und ist beim Umbau zu prüfen.

## AP6 — SCR-030 RentRollScreen

1. **Zielbild**: Der Rent Roll als **eingefrorenes Dokument mit Historie**, nicht als Live-Tabelle: eine Liste erzeugter Snapshots (mehrere je Stichtag zulässig, nach `generatedAt` sortiert) und ein Snapshot in ganzer Tiefe mit Kopfsummen und Zeilen je Einheit. V9.1-Punkte 3 (Überlauf nach rechts) und 4 (Mieter/Vertrag nicht automatisch eingetragen) lösen sich hier auf: die Zeilen kommen **serverseitig gefüllt** aus dem Snapshot, und die Tabelle bekommt den `NxDataTableShell`-Scrollcontainer.
2. **Layout**: `NxPageHeader` (Primäraktion „Rent Roll erzeugen"); zweigeteilt: Snapshot-Historie als Liste, gewählter Snapshot als Kopf-KPIs (`NxCard`: Einheiten, belegt/leer/offline, Belegungsquote, Summen) + `NxDataTableShell` der Zeilen. Phone: gepinnte Einheiten-Spalte, horizontaler Scroll.
3. **States**: voller Pflichtsatz; **currencyMismatch als eigener, erklärter Zustand** — `RentRollCurrencyMismatch.currencies` trägt die tatsächlich gefundenen Währungen („diese Verträge sind in CHF und EUR"), und genau die werden angezeigt, nicht „ungültig"; **read-only bis migriert** im SQLite-Modus mit der Begründung des Adapters (Befund 2a); `occupancyRate == null` bei 0 Einheiten wird als „—" gezeigt, nicht als 0 %.
4. **Data density**: `rentRollProvider` (`listSnapshots` = Kopfprojektion, `getSnapshot` = mit Zeilen, `createSnapshot`). Der Screen rechnet **nichts** nach: die Kopfsummen sind serverseitig strukturell an die Zeilen gebunden, das ist im DTO dokumentiert.
5. **Interactions**: Snapshot erzeugen (Stichtag wählen; Währung nur dort abfragen, wo sie nicht ableitbar ist — der leere, vollständig leerstehende Fall); Snapshot öffnen; **keine Bearbeitung, kein Löschen** — die UI erklärt stattdessen, dass ein Snapshot eingefroren ist und eine Korrektur ein neuer Snapshot ist (Befund 2b).
6. **Debt resolved**: V9.1 Punkte 3+4; 0 → volle `Nx*`-Nutzung. **Der Screen muss `isOccupiedButOutsideTerm` erklären** (Spaltenhinweis/Tooltip): eine belegte Einheit mit 0,00 ist kein Rechenfehler, sondern eine Einheit, deren Vertragslaufzeit den Stichtag nicht abdeckt.

## AP7 — SCR-065 RentalOverviewScreen (portfolioweit, Befund 4)

1. **Zielbild**: Die Vermietungssicht über **alle** Objekte: Belegungsquote, Leerstand, Mietvolumen und auslaufende Verträge portfolioweit, mit Absprung ins einzelne Objekt. Wiederbelebung des heute unbenutzten Screens als Portfolio-Unterseite statt als toter Code.
2. **Layout**: `NxPageHeader` + KPI-Kacheln + `NxDataTableShell` je Objekt (Objekt, Einheiten, belegt/leer, Belegungsquote, Mietvolumen). Anbindung an die Portfolio-Navigation — **die einzige additive Navigationsänderung dieser Welle**, vor Umsetzung als solche zu bestätigen.
3. **States**: voller Pflichtsatz; `occupancyRate == null` bei 0 Einheiten als „—".
4. **Data density**: `unitSearchProvider`/`leaseSearchProvider` **ohne** `propertyId` (workspaceweit, Keyset). **Achtung Legacy-Modus:** der Legacy-Adapter fächert dafür über alle Objekte auf (dokumentierte Grenze) — bei großen lokalen Beständen ist das der teuerste Read der Welle und braucht einen Blick auf die Seitengröße.
5. **Interactions**: reine Navigation ins Objekt. Keine Mutation.
6. **Debt resolved**: `DEAD-002` als „angebunden" geschlossen; 0 → volle `Nx*`-Nutzung.

## AP8 — `P2-D05a operations_signals` (Backend, kein Screen)

**Kein Sechs-Punkte-Plan (keine UI), sondern ein eigener Domänen-Increment** nach der verbindlichen Arbeitsordnung: Schema-Migration → pgTAP → Rollback-Test → Contract (`domain`/`application`) → Adapter (Supabase + Legacy) → Adaptertests → realer lokaler Integrationstest → Realtime → CI-Wiring. Erst danach AP9/AP10.

Der Increment deckt **Alerts und Datenqualitätsbefunde gemeinsam** ab, weil sie im Legacy dieselbe berechnete Quelle sind. Die tragende Designfrage ist am **2026-08-04 entschieden: die Ableitung wandert vollständig nach Postgres** (Details und die daraus folgende Paritätstest-Auflage in Befund 1). Weiter gilt für diesen Increment:

- **Stabile Signal-Identität** statt des heutigen inhaltsabgeleiteten Schlüssels (Meldungstext ist heute Teil der ID und verwaist Quittierungen bei jeder Umformulierung).
- **Versionierter, auditierter Zustandsübergang** statt `ConflictAlgorithm.replace`; append-only Audit wie in jeder anderen Cloud-Mutation.
- Default-deny-RLS, workspace-scoped, idempotent über `mutation_receipts`, `expectedVersion` — dieselbe Hülle wie P2-D02/D03/D05.
- **Kein Löschpfad** (`OPN-DOM-005` offen).

## AP9 — SCR-022 OperationsOverviewScreen

1. **Zielbild**: Der operative Einstieg je Objekt: Belegung, auslaufende Verträge, Leerstand, offene Punkte — mit direktem Absprung in die zuständige Fläche. Jede Kachel sagt, woher ihre Zahl kommt.
2. **Layout**: `NxPageHeader` + KPI-Kacheln (`NxCard`/`NxKpiTile`) + zwei kompakte Listen (auslaufende Verträge, längster Leerstand). Desktop 2-spaltig, darunter gestapelt.
3. **States**: voller Pflichtsatz. **Kein „Teilbereich nicht verfügbar" mehr** — Befund 3 wurde zugunsten des vollen Cloud-Gegenstücks entschieden, alle Kacheln kommen aus Contracts.
4. **Data density**: Belegungs-/Vertragskennzahlen aus `unitSearchProvider`/`leaseSearchProvider` (Keyset, kein eigener Aggregat-Read); Alerts und Datenqualität aus dem in AP8 gebauten `P2-D05a`-Contract. **Dieser Screen ist damit von AP8 abhängig und startet nicht davor.**
5. **Interactions**: reine Navigation in AP1/AP3/AP6/AP10. Keine Mutation.
6. **Debt resolved**: 0 → volle `Nx*`-Nutzung; die heutige Vollflächen-Ladeanzeige weicht Sektions-Skeletons.

## AP10 — SCR-032 OperationsAlertsScreen

1. **Zielbild**: Der heute laut V9.1 Punkt 6 leere Alerts-Tab wird eine benutzbare Fläche: offene operative Hinweise je Objekt, nach Schwere sortiert, mit Absprung zur Ursache und Erledigen-Aktion mit Notiz.
2. **Layout**: `NxPageHeader` + Schwere-Filter + `NxDataTableShell` (Schwere als `NxStatusBadge`, Typ, Meldung, Bezug, Status).
3. **States**: voller Pflichtsatz — `forbidden` und `versionConflict` sind hier **echte, testpflichtige Fälle**, weil der `P2-D05a`-Contract permissionsgated und versioniert ist (anders als der ursprünglich vorgeschlagene Legacy-Weg); dazu `read-only bis migriert` für den SQLite-Modus.
4. **Data density**: der in AP8 gebaute `P2-D05a`-Contract. **Dieser Screen ist von AP8 abhängig und startet nicht davor.**
5. **Interactions**: Signal quittieren/erledigen mit Notiz als **versionierter, auditierter Übergang** (nicht das heutige Überschreiben); Absprung zu Einheit/Vertrag/Mieter über die bestehenden Navigationsprovider. Keine Löschung.
6. **Debt resolved**: V9.1 Punkt 6; 0 → volle `Nx*`-Nutzung; der heutige historienlose `ConflictAlgorithm.replace`-Pfad verschwindet zugunsten eines auditierten Übergangs.

---

## Querschnittsthemen der Welle

- **Backend-gewählte Contract-Konsumtion wie Welle 2, ausnahmslos.** Nach den Entscheidungen vom 2026-08-04 liest **kein** W3-Screen im Cloud-Modus ein Legacy-Repo — der zunächst vorgeschlagene Legacy-Sonderweg für SCR-032 und der gemischte Betrieb für SCR-022 sind zugunsten des `P2-D05a`-Increments verworfen.
- **`NxStatusBadge` als einzige Statusquelle** für STM-003 (Einheit), STM-005 (Vertrag), STM-004 (Fall) und die Alert-Schwere — vier Abbildungen, einmal gebaut in `leasing/widgets/`, kein per-Screen-Chip.
- **Abgeleitete Zustände werden erklärt, nicht nur angezeigt**: Belegung folgt aus Verträgen (AGG-004); „belegt, trägt 0,00 bei" folgt aus dem Laufzeitfenster; ein blockierter Pipeline-Schritt nennt die fehlende Voraussetzung. Alle drei sind Stellen, an denen eine wortlose Zahl wie ein Fehler aussieht.
- **Realtime-Disziplin**: ein Kanal, vier Tabellen, Coalescing je Workspace. **Eine Vertragsaktivierung erzeugt zwei Ereignisse** (Vertrag + abgeleitete Einheit) — bewusst, in der Migration offengelegt; die Screens dürfen daraus keinen doppelten Refetch machen.
- **Kein Löschpfad, nirgends** (`OPN-DOM-005` offen). Wo heute eine Löschung existiert (Rent-Roll-Snapshot), entfällt sie — siehe Befund 2b.
- **Keine neuen Backend-Reads**: Textsuche und Sortierung bleiben client-seitig über die geladenen Keyset-Seiten (Welle-2-Präzedenz). Wo das nicht reicht, ist das ein Contract-Thema für einen späteren Increment, keine Screen-Improvisation.
- **Nicht in W3** (bewusst): `lease_rent_schedule`/`lease_indexation_rules` (nicht im P2-D05-Deliverable; die offene Frage „deterministische Engine portieren vs. ihr Ergebnis speichern", `RISK-QA-001`, ist ungelöst und gehört dem, der sie migriert); ContractorsScreen (Welle 4); der tatsächliche Migrationslauf der Dry-Run-Mapper.

## Definition of done

**Je Arbeitspaket:** Sechs-Punkte-Plan im Chat gezeigt → Umsetzung gegen den Feature-Contract → `flutter analyze --no-pub` sauber → gezielte Widget-Tests grün, inklusive `forbidden`/`versionConflict`/`read-only-bis-migriert` und der wellenspezifischen Fälle (zwei wirksame Verträge je Einheit; unzulässiger STM-005-Übergang; blockierte STM-004-Stufe mit Grund; `currencyMismatch` mit den gefundenen Währungen; belegte Einheit mit 0,00) → Responsive-Check an 390×844 / 1024×768 / 1440×900 → manueller Golden-Path im laufenden App-Build (Cloud-Modus für Mutationen) → `00_phase_2_status.md` evidenzbasiert fortgeschrieben. Volle Suite mindestens am Ende jedes Arbeitspakets.

**Für AP8 (Backend) gilt stattdessen das Domänen-Gate:** lokaler `supabase start` → Migration-Reset → `db lint` → Security-/Performance-Advisors → `supabase test db` → neuer Rollback-Test → neuer realer Integrationstest → `flutter analyze` → `flutter test`.

**Wellenabschluss:** AP1–AP10 `done` (inkl. des `P2-D05a`-Backend-Increments); kein W3-Screen nutzt mehr Material-`AppBar`, Farb-Literale oder per-Screen-`TextStyle`s; `BIG-016`/`BIG-018`/`BIG-020` über geteilte `leasing/widgets/`-Bausteine aufgelöst; `DUP-010` UI-seitig abgeschlossen; `FTR-024` als echte Pipeline-Fläche eingelöst; V9.1-Punkte 3, 4 und 6 erledigt; Befunde 1–4 entschieden und ihre Entscheidung umgesetzt **oder** ausdrücklich vertagt; volle Suite + analyze grün; Zusammenfassung und Check-in an der Wellengrenze zu Welle 4.
