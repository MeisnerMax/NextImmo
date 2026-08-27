# NexImmo Product Screen Map (PRODUCT-SCREEN-MAP-01)

Basis: `main` `9003392` (2026-08-27). Methode: Code-Audit aller Screen-Entry-Points (jede Datei gelesen, Routing/Bindings aus `app.dart`, `app_navigation.dart`, `app_scaffold.dart`, `property_page_router.dart` verifiziert). Code ist maßgeblich; ältere Docs wurden nur gegengeprüft. Kein Screen wurde implementiert oder verändert.

**Legende** — Reife: `cloud-contract` (vertragsbasiert, Wellen-Standard) · `legacy-solid` (funktionsreich, SQLite-Ära, zur Laufzeit tot) · `legacy-basic` (dünne CRUD-Hülle) · `orphan` (unreferenziert). Erreichbar: bezieht sich auf die Cloud-Shell heute (`DEC-024`: der Legacy-Pfad existiert nicht mehr; `databaseProvider` wirft). Disposition: KEEP / REDESIGN / REBUILD / REMOVE / MERGE.

**Zählung:** 73 erfasste Einheiten (Screens, Panels, Hosts, Orphans; die 10 Sale-/Hotel-`PropertyDetailPage`-Ziele kollabieren real in 1 Screen). **20 erreichbar** (19 Produktflächen + Security-Gate), **53 unerreichbar**, davon 12 nachweislich referenzlose Orphans.

## 0. Schlüsselbefunde

1. **Cloud-Ist:** 19 erreichbare Produktflächen, davon 16 `cloud-contract` (Wellen 2–5 + Reference Slice + Members) — sie sind das Produkt, das heute existiert. Alles andere ist hinter `migrationRequired` tot.
2. **Der Properties-Contract hat kein Create/Archive/Delete** (`property_repository.dart`: list/getById/update only) — der 12-Schritt-Erstellungs-Wizard und die Archiv-/Löschaktionen der Legacy-Liste haben keinen Cloud-Pfad. Backend-Gap `PROPERTY-DATA-02`.
3. **Gestrandete Cloud-UI:** der komplette Welle-5-Bewertungs-Workflow (`valuation_section_host` + 10 Widgets, ~2k LOC, vertragsbasiert) hängt nur im unerreichbaren Legacy-`AnalysisScreen`; zugleich ist die erreichbare Bewertungs-Queue ein Dead-End (`onOpenCase` nirgends verdrahtet) und ihr Create-Dialog liest den Objekt-Dropdown aus einem Legacy-Provider, der unter DEC-024 wirft. Rehost = ein Paket, schließt drei Lücken.
4. **`platform_audit_jobs`-Adapter (Tasks/Notifications/Imports/Suche/Audit-Lesen) existiert, aber kein Screen konsumiert die Read-Flächen** — Tasks-, Notifications-, Imports-, Audit-Screens lesen noch SQLite. (Einzige Ausnahme: `OperationsAlertsPanel.createTaskFrom` nutzt den Task-Write-Pfad.)
5. **12 Orphans** (referenzlos): `search_screen`, `v2/`-Track (2), Legacy-`SecurityGate`+`LockScreen`, `create_property_dialog` (nur Helper-Exporte leben), `portfolio_pack_screen` (importiert sogar `data/sqlite/migrations.dart` aus UI — Guardrail-Bruch), Legacy-`operations_overview/alerts_screen` (+`operations_detail_support`), dazu der tote Legacy-Shell-Ast (`SecurityGate` ist der einzige Konstruktor von `AppScaffold()` non-cloud — mit ihm stirbt `_buildPage` inkl. Task-Timer).
6. **Permission-Mismatch maintenance:** Seite unter `property.read`, Daten verlangen `maintenance.read` — Nutzer mit nur `property.read` erreicht die Seite und landet in der Forbidden-Sackgasse (Foundation §3 hält das Mapping eingefroren; Fix gehört zu `PERMISSION-CATALOG-02`).
7. **Fabrizierte Zahlen in Legacy-Screens:** `portfolio_detail_screen` erfindet Asset-KPIs aus Konstanten; `budget_vs_actual_screen` synthetisiert Mahnwesen-Alter aus `createdAt % 3`. Beides darf keinen Rebuild überleben.
8. **Sale-/Hotel-Bereich ist ungeplant:** 10 `PropertyDetailPage`-Ziele = 1 read-only Screen mit 5 Queries (Housekeeping/HotelRevenue bzw. ParkingStorage/UnitSaleStatus zeigen wörtlich dieselben Daten unter anderem Titel); kein Backend-Paket (nicht P2-D07/08/09) deckt Verkaufs-Pipeline/Hotelbetrieb. Produktentscheidung nötig, bevor irgendetwas geplant wird.
9. **Property-Media gestrandet:** Bildergalerie 2026-07-29 entfernt; gespeicherte Bilder rendern noch, nichts kann neue hinzufügen — der Documents-Contract kennt keine Bildrollen.
10. **Dokument-Registries ohne UI:** `RequirementPolicyRepository.upsertType/upsertRequirement` existieren serverseitig, die einzige UI dafür sind die toten Legacy-Tabs.

## 1. Erreichbare Flächen (Cloud heute)

| Screen | Domain | Route/Surface | Reife | Disposition | Kurzbefund |
|---|---|---|---|---|---|
| Reference Slice Properties (Liste+Detail) | portfolio_property | `properties` (+`/properties[/:id]`) | cloud-contract | KEEP | einzige Properties-Fläche; Detail = flaches Edit-Formular, weit unter dem 32-Seiten-Legacy-Workspace; kein Create; Auth/MFA-UI im selben Screen |
| Parties | contacts_parties | `parties` | cloud-contract | KEEP | Muster-Panel (Duplikaterkennung, Merge, Rollen) |
| Tenants Panel (+Detail) | leasing_operations | `parties`+surface `tenants` (`/tenants`, URL-only) | cloud-contract | KEEP | workspace-weit; liegt im falschen Ordner; Sidebar-Platzierung = §19-Punkt (Einordnung §5) |
| Documents Workspace | documents_compliance | `documents` | cloud-contract | KEEP | vorbildlich; Registry-Flächen (Typen/Pflichtregeln) fehlen als Cloud-UI |
| Property Documents Panel | documents_compliance | `documents`+surface `propertyDocuments` | cloud-contract | KEEP | gleiche Widget-Basis; Media/Bilder ohne Contract |
| Compliance Dashboard | documents_compliance | `documents`+surface `compliance` | cloud-contract | KEEP | serverseitige Auswertung, ehrliche Coverage-Hinweise |
| Units / Leases / Leasing-Pipeline / Rent Roll / Ops-Overview / Ops-Alerts (je +Detail) | leasing_operations | `properties`+surfaces | cloud-contract | KEEP | Welle-3-Standard; kein Delete (OPN-DOM-005), Rent-Schedule/Indexierung bewusst offen |
| Rental Overview | leasing_operations | `rentalOverview` | cloud-contract | KEEP | liegt unter `screens/portfolio/` (nur Ordnername) |
| Maintenance Tickets | maintenance_capex | `maintenance` | cloud-contract | KEEP | Parity-Gaps zum Legacy-Board: Edit, Delete, Doc-/Task-Links, Filtertiefe (→ Spec) |
| Property Maintenance/CapEx | maintenance_capex | `properties`+surface `maintenance` | cloud-contract | KEEP | SCR-034+031-Renovierung, bewusst ohne Sidebar |
| Contractors | contacts_parties | `contractors` | cloud-contract | KEEP | Satelliten-Felder read-only (Contract-Gap: Update/Rating) |
| Valuations Queue | valuation | `valuations` | cloud-contract | KEEP* | *zwei Defekte: `onOpenCase` unverdrahtet (Dead-End), Create-Dialog hängt an totem Legacy-Provider → Rehost-Paket |
| Reference Members | identity_access | `adminUsers` (+`/members`) | cloud-contract | KEEP | Basis des Admin-Bereichs (§5); Ordnername `reference_slice` irreführend; kein Membership-Realtime |
| Help | core | `help` | legacy-basic | KEEP | statisch; Ziel-Links nach `cloudReadinessForPage` filtern |
| SupabaseSecurityGate | core-security | App-Root | cloud-contract | KEEP | korrekt; geliehene Reference-Slice-Auth-Präsentation später als eigene Fläche |

Gemeinsame Lücke aller 16 Contract-Flächen: **kein Screen außer dem Reference Slice zeigt den Degraded-Zustand** (Foundation §13; je-Domäne-Wiring als Folgearbeit).

## 2. Unerreichbare Legacy-Flächen (je Domain)

### Core & Start
| Screen | Reife | Disposition | Gap/Hinweis |
|---|---|---|---|
| Dashboard (SCR-004, +6 Teilwidgets) | legacy-solid | REBUILD | P2-D09; Attention-List/Severity-Modell als Spec-Basis (Phase C, §19) |
| Notifications | legacy-basic | REBUILD | Adapter existiert (platform_audit_jobs); Deep-Links statt Rohtext |
| Imports (CSV-Wizard) | legacy-solid | REBUILD | Mapping-UX erhalten; Ausführung muss serverseitig werden (direkter Tabellen-Write nicht portierbar) |
| Audit | legacy-solid | REBUILD | Adapter existiert; Filter/CSV-Export erhalten, Cloud-Auditmodell ist reicher |
| Settings (8 Sektionen) | legacy-solid | REBUILD | kein Cloud-Settings-Backend definiert; Backup/App-Lock/Workspace-Pfad/Demo-Seed sterben mit DEC-024 — Workspace-Settings vs. User-Preferences trennen |
| Tasks | legacy-solid | REBUILD | Adapter existiert; 1887 LOC Workflow-Logik als Spec-Futter |
| Task Templates | legacy-solid | MERGE(tasks) | „Jetzt erzeugen" muss Server-Job werden |

### Properties & Property-Detail (Kern)
| Screen | Reife | Disposition | Gap/Hinweis |
|---|---|---|---|
| PropertiesScreen (Legacy-Liste) | legacy-solid | MERGE(reference-slice-properties) | Tabelle/Karten/KPI-Header in die Cloud-Liste harvesten |
| Property Creation Wizard (12 Schritte) | legacy-solid | REDESIGN | sauber gekapselt, ein Injektionspunkt; blockiert von fehlendem Create-Command (`PROPERTY-DATA-02`) |
| CreatePropertyDialog | orphan | REMOVE | nur `propertyTypeOptions`-Helper leben — vor Löschung umziehen |
| PropertyShell + Nav + Router (32 Seiten) | legacy-solid | REBUILD | Typ-abhängige Seitensets + Szenario-Kontext = beste Spec für den Cloud-Property-Workspace; Achtung: Auto-Create „Basis Vermietung" beim Öffnen, erzwungenes Light-Theme |
| Overview (SCR-011, +8 Teilwidgets) | legacy-solid | REBUILD | Sektionsarchitektur als Vorlage; `dart:io`-Coverbild bricht Web |
| Inputs (2880 LOC) | legacy-solid | REBUILD | nach Welle-5-Bewertungsmodell, nicht 1:1 |
| Analysis (+Sensitivität) | legacy-solid | REBUILD | Engines deterministisch/lokal, re-skin |
| Offer Solver | legacy-basic | MERGE(analysis) | Ein-Karten-Tool |
| Scenarios (Workflow/Approve) | legacy-solid | REBUILD | einziger Guardrail-4-Lifecycle im Legacy — Lifecycle in den Cloud-Contract übernehmen |
| Scenario Versions | legacy-solid | REBUILD | append-only + Compare-Dialog erhalten |
| Comps | legacy-basic | REBUILD | P2-D07-Rest; heute nur für `mixed`-Objekte in der Nav |
| Criteria Check | legacy-basic | REBUILD | P2-D07-Rest |
| Property Tasks | legacy-solid | REBUILD | Adapter existiert; gemeinsam mit Workspace-Tasks planen (eine Task-UI) |
| Property Audit / Reports / Property-Documents-Host | legacy | MERGE/REBUILD | drei Nav-Identitäten über einem Tab-Host; Audit → Adapter, Reports → P2-D09, Host löschen (Panel ist direkt gemountet) |
| UnitsScreen (5-Tab-Host) | legacy-basic | REMOVE | Tabs 1–4 sind direkt gemountete Cloud-Panels; nur `LeasingAreaGate`-Konzept behalten |
| Sale-/Hotel-Module (10 Pages → 1 Screen) | legacy-basic | REBUILD⚠ | **ungeplantes Produktgebiet ohne Backend-Domain** — erst Produktentscheidung (§5) |

### Finance (P2-D08 fehlt komplett)
| Screen | Reife | Disposition |
|---|---|---|
| Ledger | legacy-basic | REBUILD |
| Budgets (1398 LOC, Multi-Entity) | legacy-solid | REBUILD (Modellbreite in P2-D08-Spec übernehmen) |
| Budget vs. Actual (3567 LOC, 8 Repos) | legacy-solid | REBUILD (entlang P2-D08-Modulen aufteilen; Fake-Aging entfernen) |
| Covenants | legacy-solid | REBUILD (Generate-from-Inputs-Workflow erhalten) |
| Asset Workbook (4 Tabs) | legacy-solid | REBUILD (Renovierungs-Tab bereits durch Wave 4 ersetzt — nicht wiederbeleben) |

### Portfolio & Analytics (P2-D09 fehlt)
| Screen | Reife | Disposition |
|---|---|---|
| Portfolios Landing (+Widgets) | legacy-solid | REBUILD |
| Portfolio Detail (4 Tabs) | legacy-solid | REBUILD (KPIs sind fabriziert; Navigator-Push-Subrouten auflösen) |
| Portfolio Analytics | legacy-solid | MERGE(portfolio-detail, als Tab) |
| Data Quality Dashboard | legacy-solid | MERGE(portfolio-detail; Scoring-Engine wiederverwenden) |
| Portfolio Pack | orphan | REMOVE (Konzept als P2-D09-Deliverable respezifizieren) |
| ESG Dashboard | legacy-solid | REBUILD (braucht ESG-Cloud-Contract) |
| Compare | legacy-solid | REBUILD (P2-D07-Rest; Spaltenkonfig-Idee erhalten) |
| Criteria Sets | legacy-solid | REBUILD (sauberster Legacy-Controller; fast nur Repository-Tausch) |
| Report Templates | legacy-basic | REBUILD (mit P2-D09-Generierungs-Story) |

### Docs/Maintenance/Parties/Admin (Legacy-Reste)
| Screen | Reife | Disposition |
|---|---|---|
| DocumentsScreen (4-Tab-Host) | legacy-basic | MERGE(documents-workspace; Registry-Flächen contract-basiert neu, dann Host + `documentsRequestedTabProvider` löschen) |
| Legacy Typen/Pflichtregeln-Tabs | legacy-basic | REBUILD (als Registry-Flächen des Workspaces; Server-Mutationen existieren) |
| Maintenance Legacy-Board (2899 LOC) | legacy-solid | MERGE(maintenance-tickets-panel; Featureliste harvesten: Edit/Delete/Links/Notifications/Filter) |
| Property Maintenance Legacy (3915 LOC) | legacy-solid | REMOVE (vor Löschung: Bauteilzustand + Gewährleistung gegen Wave-4-Panels diffen — einzige evtl. nicht re-homten Features) |
| Contractors Legacy | legacy-solid | REMOVE (Modell bewusst aufgegeben; Rating-Konzept hängt an Satelliten-Frage) |
| UsersScreen (Legacy-Admin) | legacy-solid | REMOVE (nach Harvest von Rollenfilter/Zeilenlayout; Klartext-Startpasswort-Dialog stirbt ersatzlos) |

### Orphans (sofort löschbar, eigenes Hygiene-Paket)
`search_screen.dart` · `v2/dashboard_screen_v2.dart` (2238 LOC Parallel-Modelle) · `v2/property_detail/property_shell_v2.dart` · `security/security_gate.dart` + `security/lock_screen.dart` (+ toter `_buildPage`-Ast inkl. Task-Timer) · `properties/create_property_dialog.dart` (nach Helper-Umzug) · `portfolio/portfolio_pack_screen.dart` · `property_detail/operations_overview_screen.dart` + `operations_alerts_screen.dart` (+ `operations_detail_support.dart` falls dann referenzlos)

## 3. Screen-Anzahl nach Domain

| Domain | Einheiten | erreichbar | davon cloud-contract |
|---|---|---|---|
| Core & Start (Dashboard, Notifications, Suche, Help, Settings, Imports, Audit) | 7 | 1 | 0 |
| Admin & Security (Members, Users-Legacy, Gates, v2-Orphans) | 7 | 2 | 2 |
| Properties (Liste, Wizard, Shell/Nav/Router, Overview, Dialog) | 6 | 1 | 1 |
| Bewertung & Szenarien (Inputs…Versions, Case-Section, Queue) | 9 | 1 | 2 |
| Property-Detail Docs/Audit/Reports/Tasks | 5 | 1 | 1 |
| Sale-/Hotel-Module | 1 (=10 Pages) | 0 | 0 |
| Vermietung & Betrieb (Leasing/Operations) | 12 | 8 | 8 |
| Instandhaltung & Handwerker | 5 | 3 | 3 |
| Dokumente & Compliance | 4 | 2 | 2 |
| Parteien | 1 | 1 | 1 |
| Finanzen (Ledger, Budgets, BvA, Covenants, Asset Workbook) | 5 | 0 | 0 |
| Portfolio & Analytics/Reporting | 9 | 0 | 0 |
| Tasks & Templates | 2 | 0 | 0 |
| **Summe** | **73** | **20** | **20** |

## 4. Planungs-Reihenfolge, Parallelisierung, Wellen

**Sofort parallel planbar (Backend existiert; unabhängige Flächen):**
1. **Property-Workspace** (Liste+Detail um den Reference Slice; absorbiert PropertiesScreen-Harvest; benennt `PROPERTY-DATA-02` als Gap für Create/Archiv)
2. **Valuation-Rehost** (Case-Section als Queue-Detail, `onOpenCase` + Create-Dialog-Fix — schließt AP4)
3. **Tasks & Notifications** (auf platform_audit_jobs; eine Task-UI für Workspace+Objekt)
4. **Maintenance-Parity** (Edit/Delete/Links/Filter aus dem Legacy-Board in den Contract-Spec)
5. **Documents-Vervollständigung** (Registry-Flächen, Host-Abriss, Media-Gap benennen)
6. **Admin-Bereich** (um ReferenceMembersScreen; UsersScreen-Harvest; Umzug aus `reference_slice/`)

**Erst Shared-UI/Foundation nötig (Wave 1, Foundation §18):** alle sechs obigen konsumieren `NxLiveUpdatesNotice`/`NxListSkeleton`/`NxSplitView` — Wave 1 vor Implementierungsbeginn, Planung darf parallel laufen. Hygiene-Paket (Orphans) hat keine Abhängigkeiten.

**Erst Backend nötig (Planung wartet oder wird Spec-mit-Gap):** Finance-Screens (P2-D08) · Portfolio/ESG/Reports/Dashboard (P2-D09) · Comps/Criteria/Compare (P2-D07-Rest) · Sale/Hotel (Produktentscheidung + neue Domain oder REMOVE) · Settings (Settings-/Preferences-Contract) · Imports (serverseitige Import-Pipeline).

**Wellen-Vorschlag:**
- **Wave 1 — Shared/Core:** Foundation-§18-Backlog, Hygiene-Paket (12 Orphans + toter Shell-Ast), Landing-Fix, Degraded-Wiring je Domäne, Help-Linkfilter.
- **Wave 2 — unabhängige Hauptmodule (parallel, 6 Tracks):** Property-Workspace · Valuation-Rehost · Documents-Vervollständigung · Tasks/Notifications · Maintenance-Parity · Admin-Bereich.
- **Wave 3 — abhängige Module:** Imports+Audit (nach Adapter-Adoption in W2-Tasks), Scenario/Inputs/Analysis-Rebuild (nach Valuation-Rehost + Scenario-Contract), dann je Backend-Landung: Finance (P2-D08), Portfolio/Reporting/Dashboard/ESG (P2-D09), Comps/Criteria/Compare (P2-D07-Rest), Settings, Sale/Hotel (nach Produktentscheidung).

## 5. Einordnung der Foundation-§19-Offenpunkte

- **Dashboard:** REBUILD in Phase C nach P2-D09; das Legacy-Attention-List-/Severity-Modell (BIG-007-Split) ist die Spec-Basis. Bis dahin Landing = `properties` (Foundation §2).
- **Admin-Bereich:** `ReferenceMembersScreen` ist die faktische Basis (versioniert, auditiert, AAL2-gated). Empfehlung: Admin-Workspace wächst um ihn herum (Members + später Audit/Settings-Tabs); `UsersScreen` wird nach Harvest entfernt; Code zieht von `reference_slice/` in eine `identity_access`-Präsentation um.
- **Tenants:** bleibt fachlich eine Parties-Rollen-Sicht (workspace-weit). Empfehlung: eigene Sidebar-Destination „Mieter" unter *Tagesgeschäft*, die die bestehende `parties`+`tenants`-Surface öffnet (heute URL-only `/tenants`); Ordner-Umzug aus `property_detail/leasing/`. Finale Entscheidung in der Tenants-/Parties-Screen-Spec.

---
*Dispositionen sind Phase-B-Empfehlungen auf Code-Basis; die verbindliche Feinentscheidung je Screen fällt in dessen Phase-C-Spec (Template §20). Fortschritt wird ausschließlich in `PRODUCT_RESTORE_TRACKER.md` geführt.*
