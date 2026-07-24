# Welle 2 — Detaildokument: contacts_parties + documents_compliance (UI)

Status: `active` (Ausführungsgrundlage der Welle 2)
Stand: 2026-07-24
Bezug: `04_screen_redesign_wave_plan.md` (Wellenzuordnung + zwei Worked Examples als Qualitätsmaßstab), `03_design_system.md` (Sechs-Punkte-Template, Pflicht-Komponenten, Pflicht-Zustände), `00_phase_2_status.md` (Ist-Stand), `10_reference_slice_spec.md` (Backend-gewählte Provider-Wiring-Muster), P2-D02/P2-D03-Contracts unter `lib/features/{contacts_parties,documents_compliance}/`.

## Backend-Voraussetzungen (erfüllt)

- **P2-D02 `contacts_parties` ist `done`** (Contract + Supabase-/Legacy-Adapter + Realtime + Dry-Run-Mapper). Ports: `PartyRepository`, `PartySearchPort`, `PartyRoleRepository`, `DuplicateDetectionPort`; DTOs `PartyDto`/`PartySummaryDto`/`PartyRoleDto`/`ContractorDetailsDto`/`PartyDuplicateCandidate`; Enums `PartyType` (person/organization), `PartyRoleType` (tenant/contractor/buyer/bank/company); Keyset-Suche (`PartyListQuery`/`PartyPageResult`); sealed `PartyRepositoryResult<T>` + `PartyVersionConflict`.
- **P2-D03 `documents_compliance` ist `done`** (Contract + Supabase-/Legacy-Adapter + privater Storage-Bucket + `SignedUrlPort` + Realtime + Dry-Run-Mapper). Sechs Ports: `DocumentRepository`, `DocumentContentPort`, `DocumentLinkPort`, `RequirementPolicyRepository`, `DocumentVerificationPort`, `SignedUrlPort`; DTOs inkl. `DocumentDto`/`DocumentVersionDto`/`RequiredDocumentDto`/`DocumentRequirementProjection`/`SignedDocumentUrl`; Enums `DocumentStatus` (STM-008), `DocumentVerificationStatus`, `DocumentLinkEntityType`, `DocumentRequirementState`; sealed `DocumentRepositoryResult<T>` + `DocumentVersionConflict`. TTL-Clamp (300 s Default / 3600 s Max) lebt in `SignedUrlPort.clampTtl`.
- **`OPEN-001` / `DUP-010` sind bereits entschieden und umgesetzt** (P2-D02, 2026-07-22; `04_duplicate_and_debt_register.md`): gemeinsame Party-ID, fachliche Rollen als `party_roles`, rollenspezifische Attribute in Satelliten. Der neue Parties-Screen **surft** dieses entschiedene Modell, er trifft keine offene Entscheidung — **kein Hard-Stop für OPEN-001**.

## Architektur-Entscheidung dieser Welle (entschieden 2026-07-24, Nutzerbestätigung)

Welle 2 unterscheidet sich strukturell von Welle 1. Welle 1 war **UI-only auf Legacy-Providern** (`portfolio_property`-Backend war der abgeschlossene Referenzschnitt, die Legacy-Screens lasen weiter `propertiesControllerProvider`). Welle 2 ist der Punkt, an dem das in `00_phase_2_status.md` **bewusst zurückgestellte Provider-/`main.dart`-Wiring** von `contacts_parties` und `documents_compliance` nachgeholt wird (Status-Doc: „Provider-/`main.dart`-Wiring … kommt mit den Welle-2-Screens").

Der tragende Befund: die **Legacy-Adapter beider Domänen sind bewusst read-only** — jede Mutation liefert `dependencyConflict`, weil lokales SQLite den auditierten/versionierten/idempotenten Contract nicht honorieren kann (so gebaut in P2-D02/P2-D03).

**Entschieden (2026-07-24, ausdrückliche Nutzerbestätigung):** Die Screens konsumieren die **Feature-Contracts, Backend-gewählt wie der Referenzschnitt.** Im Supabase-Modus voller CRUD über die Supabase-Adapter; im **SQLite-Modus** lesen die Screens über die Legacy-Adapter und zeigen für Mutationen den **vom Design-System vorgeschriebenen Zustand „read-only bis migriert"** (`03_design_system.md`, Zeile 52 „Offline/legacy-adapter blocked") statt einer still no-oppenden Aktion. Präzedenz: die **P2-D01-Members-Admin-UI ist bereits nur-Supabase** (Status-Doc). Konsequenz — bewusst akzeptiert: **lokales Dokument-/Party-Editieren im SQLite-Modus entfällt** (heute via `documentsRepositoryProvider.createDocument` u. a. vorhanden); der Migrationsrichtung folgend, eine Screen-Implementierung pro Fläche, keine doppelten Pfade. Die verworfene Alternative (Legacy-Screens behalten Legacy-CRUD, Feature-Contract nur Supabase) hätte die `DUP-007`-Duplikation teils zementiert.

Dieses Dokument ist gegen die entschiedene Variante geschrieben: im SQLite-Modus zeigen die States-Abschnitte „read-only-Hinweis statt Mutationsdialog"; die Layout-/Komponentenpläne sind backend-unabhängig.

Unabhängig von der Entscheidung: **keine Datenvertrags-, Schema-, Routen- oder Navigationsänderung** ohne expliziten Auftrag; die neue Parties-Navigation ist die einzige additive Nav-Ergänzung und wird vor Umsetzung als solche bestätigt.

## Scope

| SCR | Screen | Datei (Ist) | LOC (Ist) | nx_-Ist | Status in W2 |
|---|---|---|---|---|---|
| — | *(neu)* PartiesScreen (Directory) | existiert nicht | 0 | — | Arbeitspaket 1 (Pattern-Beweis Feature-Contract-Konsumtion) |
| SCR-052 | ComplianceDashboardScreen | `lib/ui/screens/docs/compliance_dashboard_screen.dart` | 119 | 0 | Arbeitspaket 2 |
| SCR-020 | PropertyDocumentsScreen | `lib/ui/screens/property_detail/property_documents_screen.dart` | 922 | 0 | Arbeitspaket 3 |
| SCR-051 | DocumentsScreen (global) | `lib/ui/screens/docs/documents_screen.dart` | 1196 | 16 (via `ListFilterTemplate`) | Arbeitspaket 4 |
| — | Provider-/`main.dart`-Wiring (beide Domänen, Backend-gewählt) | `lib/main.dart`, `lib/ui/state/app_state.dart` | — | — | Arbeitspaket 0 (Voraussetzung, vor jedem Screen) |

## Reihenfolge und Begründung

0. **Wiring zuerst (Arbeitspaket 0)** — Backend-gewählte Provider für beide Contracts in `main.dart` (Supabase-Overrides analog `referencePropertyRepositoryProvider`) + Default-Legacy-Adapter-Provider. Ohne diese Naht kann kein Screen den Contract konsumieren. Kleiner, isolierter Schritt mit eigenem Funktions-Plan; keine Screen-UI.
1. **PartiesScreen zuerst als Pattern-Beweis** — er ist eine grüne Wiese ohne Legacy-Ballast und damit der sauberste Beweis für „Screen auf Feature-Contract + Backend-Wahl + alle Pflicht-Zustände inkl. `forbidden`/`versionConflict`/`read-only-bis-migriert`". Erst wenn das Muster hier steht, lohnt die Übertragung auf die drei Dokument-Screens.
2. **ComplianceDashboard vor den Dokument-Screens** — mit 119 LOC der kleinste Umbau, heute praktisch ohne Design (`CircularProgressIndicator`, `Text('Error: …')`, `Text('No … found.')`, Material-`Card`/`ListTile`, client-seitige N+1-Prüfung über alle Objekte). Er beweist die `DocumentRequirementProjection`-Konsumtion, die die beiden großen Screens dann wiederverwenden.
3. **PropertyShell-Kontext vor Global** — PropertyDocumentsScreen (objektbezogen, in `PropertyShell` gerendert) vor DocumentsScreen (global). Der objektbezogene Scope ist der engere Fall; der globale Screen verallgemeinert ihn und löst `DUP-007` durch geteilte ViewModels/Widgets.
4. **DocumentsScreen (global) zuletzt** — größter Screen (BIG-022, 1196 LOC), profitiert von allen vorher etablierten geteilten Dokument-Widgets.

Die drei Dokument-Screens teilen sich Filter-, Dialog- und Tabellenlogik (`DUP-007`): PropertyDocumentsScreen und DocumentsScreen werden auf **gemeinsame ViewModels + Widgets** unter `lib/ui/screens/docs/widgets/` gezogen (scope-spezifische Sichten bleiben), statt die Logik ein drittes Mal zu kopieren. Delegation an je einen Subagenten ist ab Arbeitspaket 3 sinnvoll, sobald das Muster aus 1–2 steht — mit eigenständigem Brief pro Screen.

---

## Arbeitspaket 0 — Provider-/`main.dart`-Wiring (Voraussetzung, kein Screen)

**Kein Sechs-Punkte-Plan (keine UI), sondern die Backend-Naht.** Analog zum Referenzschnitt (`referencePropertyRepositoryProvider` wird in `main.dart` nur im Supabase-Modus mit `SupabasePropertyRepositoryAdapter` überschrieben):

- Neue Provider für die Ports beider Contracts (`partyRepositoryProvider`/`partySearchProvider`/`partyRoleProvider`/`duplicateDetectionProvider` bzw. `documentRepositoryProvider`/`documentContentProvider`/`documentLinkProvider`/`requirementPolicyProvider`/`documentVerificationProvider`/`signedUrlProvider`), Default = jeweiliger Legacy-Adapter (read-only), im Supabase-Modus per `overrideWithValue` auf die Supabase-Adapter gesetzt.
- Realtime-Invalidation-Provider (`DocumentQueryInvalidationSource`/`PartyQueryInvalidationSource`) analog `supabasePropertyQueryInvalidationAdapter`, nur im Supabase-Modus aktiv.
- **Namenskollision vermeiden:** die neuen Provider heißen bewusst nicht wie die bestehenden Legacy-`documentsRepositoryProvider` (Legacy-`DocumentsRepo`) — die Legacy-Provider bleiben unangetastet, bis die Screens umgezogen sind, damit kein anderer Consumer bricht.
- Verifikation: `flutter analyze` sauber, ein schlanker Provider-Wiring-Test (Backend-Wahl liefert im sqlite-Modus den Legacy-Adapter, im supabase-Modus den Supabase-Adapter) — keine Screen-Tests hier.

---

## PartiesScreen (Directory) — Arbeitspaket 1, Pattern-Beweis

1. **Zielbild**: Ein zentrales Parteien-Verzeichnis — Personen und Organisationen mit gemeinsamer Identität und ihren fachlichen Rollen (Mieter, Dienstleister, Käufer, Bank, Firma) auf einen Blick, schnelle Keyset-Suche, Dubletten-Warnung beim Anlegen, Zusammenführen zweier Parteien als expliziter, auditierter Vorgang. Löst die heute über `contacts`/`tenants`/`contractors` verstreute, identitätslose Parteienabbildung (`DUP-010`) an einer Stelle auf.
2. **Layout**: `NxPageHeader` (Titel „Parteien", Suche, Primäraktion „Neue Partei", Rollen-Filter als Header-Aktion). Hauptbereich `NxDataTableShell` mit `PartySummaryDto`-Spalten (Anzeigename, Typ als `NxStatusBadge` person/organization, offene Rollen als Rollen-Badges, E-Mail/Telefon); weitere Spalten hinter Column-Picker. Desktop optional Liste+Detail nebeneinander (Detail: Identität + Rollen-Zeitleiste + Contractor-Satellit), Tablet/Phone getrennte Liste→Detail-Route; Tabelle horizontal scrollbar mit gepinnter Namensspalte (Phone).
3. **States**: loading = Tabellen-Skeleton; empty = `NxEmptyState` „Lege deine erste Partei an"; error = Retry ohne Roh-Exception; **forbidden** = explizite „kein Zugriff"-Darstellung (`PartyRepositoryFailureKind.forbidden`, RLS `party.read`); **versionConflict** = expliziter Konflikt-Dialog mit aktueller Partei/Rolle aus `PartyVersionConflict` und Auflösen-Aktion (Merge/Update); **read-only bis migriert** = im SQLite-Modus tragen alle Mutationsaktionen den vorgeschriebenen Hinweis statt still zu no-oppen.
4. **Data density**: `partySearchProvider` (Keyset, `PartyListQuery`/`PartyPageResult` — Cursor-Paginierung wie im Contract), `partyRoleProvider` (Rollen + Contractor-Satellit im Detail), `duplicateDetectionProvider` (Live-Prüfung im Anlege-/Bearbeiten-Dialog). Sortierung + gespeicherte Filter rein UI-seitig; keine neuen Backend-Reads.
5. **Interactions**: Anlegen (`PartyDraft`) mit Dubletten-Warnung vor dem Speichern; Bearbeiten (`PartyUpdateDto`, Optimistic Concurrency mit `expectedVersion`); Rolle zuweisen/beenden (`PartyRoleRepository`, zeitlich begrenzbar); **Merge zweier Parteien nur mit Bestätigung** (auditierter, folgenreicher Vorgang, `expectedTargetVersion`/`expectedSourceVersion`); keine Löschung (Merge/Tombstone ist der Pfad).
6. **Debt resolved**: `DUP-010` wird UI-seitig eingelöst (kanonisches Party-Verzeichnis existiert erstmals); Pattern-Beweis für Feature-Contract-Konsumtion + alle Pflicht-Zustände. **Neuer Widget-Test** über alle Zustände (empty/error/forbidden/versionConflict/read-only + Suche/Merge-Bestätigung). **Bewusst nicht in W2:** TenantsScreen/ContractorsScreen (Wave 3/4) konsumieren dieses Verzeichnis später als Rollen-Sichten — hier wird kein Legacy-Screen migriert.

## SCR-052 — ComplianceDashboardScreen (Arbeitspaket 2)

1. **Zielbild**: Compliance-Status über den Bestand auf einen Blick: welche geforderten Dokumente fehlen, laufen ab (45-Tage-Fenster) oder sind unverifiziert — pro Objekt gruppiert, mit direktem Absprung zur betroffenen Stelle. Ersetzt die heutige undesignte Liste (Vollflächen-Spinner, roher `Error:`-Text, bare `Text`-Empty, Material-`Card`) durch eine ruhige, statusgeführte Sicht auf die **serverseitige** `DocumentRequirementProjection`.
2. **Layout**: `NxPageHeader` („Compliance", Refresh als Sekundäraktion); Kopf-KPIs als `NxCard`-Tiles (offen/ablaufend/erfüllt) mit `NxStatusBadge` je Schwere; Befundliste als `NxDataTableShell` (Objekt, Dokumenttyp, Zustand via `NxStatusBadge` aus `DocumentRequirementState`, Fällig-/Ablaufdatum). Desktop optional 2-spaltig (KPIs + Liste), Tablet/Phone gestapelt.
3. **States**: loading = Skeleton statt `CircularProgressIndicator`; **empty = positiver Leerzustand** „Alles erfüllt" mit letzter Prüfzeit statt `Text('No … found.')`; error = Retry ohne Roh-Exception (heute `Text('Error: $_error')`); **forbidden** = explizit (`document.read` fehlt); versionConflict n. a. (lesende Projektion). read-only bis migriert nur relevant, falls „Fix"-Aktion mutiert (siehe Interactions).
4. **Data density**: statt heutiger **client-seitiger N+1-Schleife** über alle Objekte (`checkComplianceForEntity` je Property) die **serverseitige** `evaluate_document_requirements`-Projektion über den `RequirementPolicyRepository`/`DocumentRepository`-Port — eine Abfrage, workspace-scoped, keine Client-Aggregation. Das 45-Tage-`expiring`-Fenster kommt aus dem Contract (verbatim aus der Legacy-Logik übernommen), nicht neu erfunden.
5. **Interactions**: Befund-Zeile navigiert zum Quell-Objekt/-Dokument (bestehende `globalPageProvider`/`propertyDetailPageProvider`-Navigation); „Fix" führt zum Upload-/Anforderungs-Flow des betroffenen Objekts (im SQLite-Modus read-only-Hinweis). Kein destruktiver Pfad.
6. **Debt resolved**: kein `BIG-*`/`DUP-*`-Eintrag, aber der Screen geht von „faktisch undesignt + N+1-Client-Prüfung" auf Systemstandard + Server-Projektion. **Erster dedizierter Widget-Test** (heute keiner). Der Screen wird die geteilte Requirement-/Status-Badge-Abbildung etablieren, die die beiden Dokument-Screens wiederverwenden.

## SCR-020 — PropertyDocumentsScreen (Arbeitspaket 3)

1. **Zielbild**: Die Dokumente **eines Objekts** als ruhige, statusgeführte Fläche: hochgeladene Dokumente mit Version/Verifikationsstatus, geforderte-aber-fehlende Dokumente sichtbar getrennt, Upload → Content-Bestätigung → Verifikation als klarer Workflow (STM-008), Zugriff auf Inhalte ausschließlich über kurzlebige Signed-URLs. Ersetzt den heutigen `TabController`-Eigenbau ohne `nx_*`-Komponenten.
2. **Layout**: `NxPageHeader` als Objekt-Dokumentkopf (Titel + Primäraktion „Dokument hinzufügen"); Sektionen mit `NxSectionHeader`: (1) Anforderungen (fehlend/ablaufend als `NxStatusBadge`), (2) vorhandene Dokumente als `NxDataTableShell` (Typ, Status STM-008, Version, Verifikation, Gültig-bis). Upload-/Detail-Interaktionen in `NxFormSectionCard`/Dialogen. Rendert in `PropertyShell` (Kopf-Fläche knapp halten, siehe W1-AP2). Phone: Tabelle horizontal scrollbar, gepinnte Typspalte.
3. **States**: loading = Sektions-Skeletons; empty = `NxEmptyState` „Noch keine Dokumente — erstes hinzufügen"; error = Retry ohne Roh-Exception; **forbidden** = `document.read` fehlt → explizit; **versionConflict** = `DocumentVersionConflict` (trägt immer das aktuelle Dokument) mit Auflösen-Aktion; **read-only bis migriert** = SQLite-Modus zeigt Upload/Verify als deaktiviert mit Hinweis (Legacy-Adapter → `dependencyConflict`); **MIG-BND-003-Fehlerpfad** = ein deklariertes, aber nicht hochgeladenes Objekt endet sichtbar in `rejected` (kein stiller Erfolg).
4. **Data density**: `documentRepositoryProvider` (Dokumente + Versionen), `documentLinkProvider` (Objektbindung), `requirementPolicyProvider` (geforderte Dokumente je `scope_key`/Objekt), `documentVerificationProvider`, `signedUrlProvider` (TTL-Clamp lebt im Port, Screen re-implementiert ihn nicht). Entity-Scope = aktuelles Objekt aus `selectedPropertyIdProvider`.
5. **Interactions**: Dokument anlegen → Version hochladen → **Content bestätigen** (`confirm_document_content` prüft die reale Storage-Zeile) → verifizieren; Supersede/Archive als Statusübergänge (STM-008) mit Bestätigung; Inhalt öffnen nur über Signed-URL (nie roher Pfad); `OPN-DOM-005`-Default: **keine Löschung**, `archived` ist terminal — UI bietet Archivieren mit Bestätigung, keinen Delete.
6. **Debt resolved**: `DUP-007` (Filter-/Dialog-/Tabellenlogik) wird durch geteilte Dokument-ViewModels/Widgets mit SCR-051 aufgelöst; `DUP-011` (Onboarding-Checkliste vs. Compliance-Modell) UI-seitig eingelöst — die Anforderungs-Sektion ist die **abgeleitete Projektion** (angefordert/nicht-relevant verlustfrei), keine zweite Wahrheit. 3 Farb-Literale → Tokens; `TabController`-Eigenbau → `nx_*`. Widget-Test über alle Zustände (heute keiner).

## SCR-051 — DocumentsScreen (global) — Arbeitspaket 4

1. **Zielbild**: Der workspace-weite Dokument-Arbeitsplatz: Suche/Filter über alle Dokumente aller Entitäten, dieselbe statusgeführte Darstellung wie der objektbezogene Screen, plus Entity-Filter (Objekt/Einheit/Lease/Partei…). Verallgemeinert SCR-020 statt dessen Logik zu duplizieren.
2. **Layout**: bereits `ListFilterTemplate` (kapselt `NxPageHeader`) + 16 `nx_*`-Nutzungen — die Komposition ist der am weitesten fortgeschrittene der drei Dokument-Screens; W2 vereinheitlicht sie auf die **geteilten** Dokument-Widgets aus AP3 (`docs/widgets/`) und bringt die Tabelle auf denselben `NxDataTableShell`-Stand. Entity-Filter über die `DocumentLinkEntityType`-Registry (kontrolliert, kein Freitext). Breakpoints wie AP3.
3. **States**: identischer Pflicht-Zustandssatz wie AP3 (loading/empty/error/forbidden/versionConflict/read-only-bis-migriert); zusätzlich **leerer Filter-Treffer** als eigener `NxEmptyState` („keine Dokumente für diesen Filter") getrennt vom „noch keine Dokumente".
4. **Data density**: dieselben Ports wie AP3, Scope = Workspace statt Einzelobjekt; Keyset-Suche des `DocumentRepository`-Contracts (Cursor-Paginierung), Entity-Filter als Inner-Join-Embed über `document_links` (im Supabase-Adapter bereits vorhanden). Column-Picker für Spalten jenseits Typ/Status/Verifikation/Datum.
5. **Interactions**: wie AP3 (Anlegen/Version/Confirm/Verify/Supersede/Archive, alle mit Bestätigung wo folgenreich; Signed-URL-Zugriff); zusätzlich globale Filter-/Sortier-Persistenz als UI-Schicht.
6. **Debt resolved**: **BIG-022** (1196 LOC) — Split in schlanke Orchestrierung + geteilte `docs/widgets/`-Bausteine (mit AP3 gemeinsam genutzt); **`DUP-007`** endgültig aufgelöst (globaler + objektbezogener Dokument-Screen teilen ViewModels/Widgets, Scope-Sichten bleiben). 4 Farb-Literale → Tokens. Bestehende Tests erhalten/erweitert um die Pflicht-Zustände.

---

## Querschnittsthemen der Welle

- **Backend-gewählte Feature-Contract-Konsumtion** (neu gegenüber W1): jeder W2-Screen liest die neuen Provider (Arbeitspaket 0), nicht die Legacy-Repos. Der SQLite-Modus ist über die read-only-Legacy-Adapter lesefähig; Mutationen tragen den Pflicht-Zustand „read-only bis migriert" (abhängig von der oben zu bestätigenden Architektur-Entscheidung).
- **Geteilte Dokument-Bausteine (`DUP-007`)**: PropertyDocumentsScreen + DocumentsScreen + ComplianceDashboard teilen Status-Badge-Abbildung (STM-008 / `DocumentRequirementState`), Upload-/Verify-Dialoge und die Requirement-Projektion über `docs/widgets/` — einmal gebaut, dreifach genutzt.
- **`NxStatusBadge` als einzige Statusquelle**: STM-008 (Dokumentstatus), `DocumentVerificationStatus`, `DocumentRequirementState` und `PartyType`/`PartyRoleType` bekommen je eine konsistente Badge-Abbildung — kein per-Screen-Chip.
- **Signed-URL-Disziplin**: Dokumentinhalt wird nie über rohe Pfade angezeigt; ausschließlich `SignedUrlPort` mit dem im Port gekapselten TTL-Clamp. Kein Screen re-implementiert die TTL-Regel.
- **Pflicht-Zustände vollständig** (inkl. der in W1 selteneren `forbidden`/`versionConflict`): diese Domänen sind mutierend und versioniert, daher sind Konflikt- und Zugriffszustände hier **echte, testpflichtige** Fälle, nicht „n. a.".
- **Token-/`AppBar`-Hygiene**: PropertyDocuments (3) + Documents (4) Farb-Literale → Tokens; ComplianceDashboard von Material-`Card`/roh auf `nx_*`. Kein W2-Screen nutzt am Ende Material-`AppBar`, Farb-Literale oder per-Screen-`TextStyle`s.
- **Realtime**: Dokument-/Party-Invalidation-Provider werden im Supabase-Modus verdrahtet (Arbeitspaket 0); die cross-table-Invalidation für Link/Requirement liegt in der P2-D04-`domain_events`-Envelope (bereits `done`) und kann von den Screens optional konsumiert werden — nicht Pflicht der Welle.
- **Nicht in W2** (bewusst): Migration der Legacy-`documentsRepositoryProvider`-/`DocumentsRepo`-Definition selbst (die Legacy-Repos bleiben bis alle Consumer umgezogen sind); TenantsScreen/ContractorsScreen (Wave 3/4); `AuditScreen`/`TasksScreen`-Anteil von `DUP-007` (Wave 7); tatsächlicher Migrationslauf der Dry-Run-Mapper (getrennt vom UI).

## Definition of done

**Je Screen:** Sechs-Punkte-Plan im Chat gezeigt (ein Plan pro Arbeitspaket) → Umsetzung gegen den Feature-Contract → `flutter analyze --no-pub` sauber → gezielte Widget-Tests grün (inkl. neuer Zustands-Tests, inkl. `forbidden`/`versionConflict`/`read-only-bis-migriert`) → Responsive-Check an 390×844 / 1024×768 / 1440×900 in allen drei Dichte-Modi → manueller Golden-Path im laufenden App-Build (Supabase-Modus für Mutationen) → `00_phase_2_status.md` evidenzbasiert fortgeschrieben. Volle Suite (`flutter test --no-pub`) mindestens am Ende jedes Arbeitspakets.

**Wellenabschluss:** Arbeitspaket 0 + alle vier Screen-Pakete `done`; kein W2-Screen nutzt mehr Legacy-Dokument-/Party-Repos, Material-`AppBar`, Farb-Literale oder per-Screen-`TextStyle`s; `DUP-007`/`DUP-010`/`DUP-011`/`BIG-022` wie oben aufgelöst; volle Suite + analyze grün; Zusammenfassung + Check-in beim Nutzer an der Wellengrenze (Hard-Stop) — Welle 3 startet erst nach Freigabe, nach ihrem eigenen Detaildokument und nach grünem Gate von `P2-D05`.
