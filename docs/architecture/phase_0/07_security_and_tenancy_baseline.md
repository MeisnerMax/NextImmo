# Security and Tenancy Baseline

Stand: 2026-07-12  
Owner: `data-security-agent`  
Status: `proposed` (Zielkonzept), Ist-Befunde einzeln als `verified` markiert  
Scope: Phase 0, keine produktive Datenbank- oder Cloud-Migration

## 1. Evidenz und Ist-Befund

| ID | Status | Befund | Evidenz |
|---|---|---|---|
| SEC-001 | verified | Authentifizierung, Benutzer, Rollen und Sitzungen sind lokal in SQLite implementiert; ein Default-Workspace und ein passwortloser `admin` werden gebootstrapped. | `lib/data/repositories/security_repo.dart::bootstrapDefaults`, `lib/core/models/security.dart` |
| SEC-002 | verified | RBAC ist eine lokale Rollenmatrix. Unbekannte Rollen und unbekannte Permissions werden abgewiesen; `PermissionContext` wird derzeit nicht zur Scope-Auswertung verwendet. | `lib/core/security/rbac.dart::permissionsForRole`, `canPermission`; `test/core/security/rbac_test.dart` |
| SEC-003 | verified | P1-008 ist gestartet: Der UI-State liefert ohne geladenen Kontext keine Rolle mehr, und unbekannte Rollen werden in der globalen Navigation abgewiesen. Dies bleibt Client-Haertung und ersetzt keine serverseitige Autorisierung. | `lib/ui/state/security_state.dart::activeUserRoleProvider`, `lib/ui/navigation/app_navigation.dart::isPageAllowedForRole`, `test/ui/navigation/app_navigation_test.dart` |
| SEC-004 | verified | Nur `local_users`, `user_sessions` und nachtraeglich `audit_log` tragen `workspace_id`; die uebrigen Fachtabellen sind nicht technisch mandantengetrennt. | `lib/data/sqlite/migrations.dart::_createV1` bis `_createV46`, insbesondere `_createV15`, `_createV20` |
| SEC-005 | verified | Audit-Ereignisse koennen Workspace, Akteur, Rolle, Quelle, Korrelation, Grund sowie Alt-/Neuwert enthalten. Append-only wird durch SQLite-Berechtigungen oder Trigger nicht erzwungen. | `lib/core/models/audit_log.dart`, `lib/core/audit/audit_writer.dart`, `lib/data/repositories/audit_log_repo.dart` |
| SEC-006 | verified | Dokumente referenzieren lokale Dateipfade und besitzen optionale SHA-256-Werte; Updates und Hard Deletes sind moeglich. Dokumenttypen und Pflichtregeln werden separat verwaltet. | `lib/core/models/documents.dart`, `lib/data/repositories/documents_repo.dart`, `lib/data/repositories/workspace_repo.dart` |
| SEC-007 | verified | Das aktuelle System besitzt weder Supabase-/HTTP-Sync noch serverseitige RLS. | `docs/TECHNICAL_SYSTEM_DOCUMENTATION.md`, `lib/data/sqlite/` |

## 2. Kanonisches Mandanten- und Identitaetsmodell

| ID | Zielentitaet | Besitzer | Status | Regel |
|---|---|---|---|---|
| ENT-SEC-001 | `auth.users` | Supabase Auth | proposed | Globale Login-Identitaet. Keine fachlichen Rollen oder Workspace-Rechte als autoritative JWT-Metadaten speichern. |
| ENT-SEC-002 | `user_profile` | `identity_access` | proposed | Globale, minimale Profildaten zu `auth.users.id`; keine Workspace-Berechtigung. |
| ENT-SEC-003 | `workspace` | `identity_access` | proposed | Mandantengrenze. Erstellen, Archivieren und Eigentumswechsel nur ueber privilegierte serverseitige Transaktion. |
| ENT-SEC-004 | `membership` | `identity_access` | proposed | Eindeutig `(workspace_id, user_id)`, Status `invited/active/suspended/revoked`; nur `active` berechtigt. Mindestens ein aktiver Workspace-Admin bleibt erhalten. |
| ENT-SEC-005 | `role` | `identity_access` | proposed | Workspace-lokale oder systembereitgestellte Rolle; Rollenname allein verleiht kein Recht. |
| ENT-SEC-006 | `permission` | `identity_access` | proposed | Stabiler Permission-Key wie `property.read`, `document.verify` oder `scenario.approve`. |
| ENT-SEC-007 | `role_permission` | `identity_access` | proposed | Explizite Allow-Zuordnung. Nicht zugeordnete Rechte sind verweigert. |
| ENT-SEC-008 | `entity_scope` | `identity_access` | proposed | Optionale Allowlist fuer `portfolio`, `property` oder spaeter `region`; gilt zusaetzlich zu Mitgliedschaft und Permission. |
| ENT-SEC-009 | `mutation_receipt` | `platform_audit_jobs` | proposed | Idempotenzbeleg je Workspace und Mutation; enthaelt Request-Hash, Ergebnisreferenz und Status, keine vertrauliche Payload. |
| ENT-SEC-010 | `audit_event` | `platform_audit_jobs` | proposed | Append-only Sicherheits- und Fachaudit; nur serverseitig schreibbar. |

### 2.1 Autorisierungsformel

`allow = authenticated AND active_membership AND permission_granted AND scope_matches AND row_not_forbidden`

- `authenticated`: `auth.uid()` ist gesetzt. `anon` erhaelt keinen Zugriff auf Fachdaten. (`proposed`)
- `active_membership`: aktive Membership fuer exakt `row.workspace_id`. Suspendiert, widerrufen oder nur eingeladen bedeutet Deny. (`proposed`)
- `permission_granted`: Permission wird serverseitig aus Membership -> Role -> Role-Permission gelesen. Client-Claims und UI-Rollen sind nicht autoritativ. (`proposed`)
- `scope_matches`: Ohne Entity-Scopes gilt Workspace-Scope; existieren Scopes, muss die Zeile ueber Portfolio/Property in der Allowlist liegen. (`proposed`)
- `row_not_forbidden`: Tombstones sind standardmaessig nicht lesbar; sensible Felder werden ueber getrennte Views/RPCs oder Spaltenprivilegien geschuetzt. (`proposed`)

## 3. Default-Deny-RLS

| ID | Status | Verbindliche Regel |
|---|---|---|
| RLS-001 | proposed | RLS ist auf jeder exponierten Tabelle aktiviert und `FORCE ROW LEVEL SECURITY` wird fuer anwendungsnahe Eigentuermerrollen verwendet. Ohne explizite Policy ist jeder Zugriff verweigert. |
| RLS-002 | proposed | `anon` erhaelt keine Grants auf Fachtabellen, Audit, Memberships oder private Storage-Objekte. Oeffentliche Freigaben laufen ausschliesslich ueber kurzlebige, widerrufbare serverseitige Tokens. |
| RLS-003 | proposed | Direkte Workspace-Tabellen pruefen bei `SELECT/UPDATE/DELETE` `workspace_id` und Permission in `USING`; bei `INSERT/UPDATE` wird dieselbe Bedingung in `WITH CHECK` wiederholt. |
| RLS-004 | proposed | Kindtabellen besitzen selbst `workspace_id`; RLS prueft zusaetzlich, dass der Parent im selben Workspace liegt. Fremde oder inkonsistente Parent-IDs werden abgewiesen. |
| RLS-005 | proposed | Globale Referenzkataloge sind explizit klassifiziert: unveraenderliche Systemkataloge read-only fuer Authentifizierte, administrative Kataloge nur ueber privilegierte Mutation. Es gibt keine implizite globale Lesepolicy. |
| RLS-006 | proposed | `membership`, Rollen, Rechte und Scopes sind fuer normale Nutzer maximal im eigenen Workspace lesbar; Aenderungen benoetigen `security.manage`. Letzter aktiver Admin und Selbst-Eskalation werden atomar verhindert. |
| RLS-007 | proposed | `audit_event` ist fuer berechtigte Nutzer lesbar, aber fuer Clients nie aktualisierbar oder loeschbar. Inserts erfolgen nur in derselben serverseitigen Transaktion wie die Fachmutation. |
| RLS-008 | proposed | `service_role` bleibt ausschliesslich in vertrauenswuerdigen Serverkomponenten. Edge Functions validieren Nutzer, Workspace, Permission und Scope erneut; kein Service-Key gelangt in Flutter, Logs oder Exporte. |
| RLS-009 | proposed | Security-Definer-Hilfsfunktionen haben festen `search_path`, qualifizierte Objektnamen, minimale EXECUTE-Grants und duerfen keine vom Client behauptete Workspace-ID ungeprueft uebernehmen. |
| RLS-010 | proposed | Realtime publiziert nur RLS-geschuetzte Zeilen. Kanalnamen, Filter und Payloads ersetzen keine Autorisierung. Tombstones und Rechteentzug muessen bestehende Subscriptions wirksam begrenzen. |
| RLS-011 | proposed | Storage-Policies leiten Workspace und Dokument aus einer serverseitigen Dokumentversion ab; ein vom Client frei gewaehlter Pfadprefix allein ist kein Berechtigungsnachweis. |
| RLS-012 | proposed | Soft-geloeschte Zeilen (`deleted_at IS NOT NULL`) sind nur fuer Restore-/Compliance-Permissions sichtbar. Standard-Queries und Realtime blenden sie aus. |

## 4. Permission-Baseline

| Bereich | Read | Mutate | Kritische Zusatzrechte | Status |
|---|---|---|---|---|
| Workspace/Identity | `workspace.read` | `workspace.update` | `security.manage`, `membership.invite`, `membership.revoke` | proposed |
| Portfolio/Property | `property.read` | `property.create/update/archive` | `property.export` | proposed |
| Leasing | `lease.read` | `lease.create/update` | `lease.approve`, `tenant.pii.read` | proposed |
| Maintenance/Tasks | `operations.read` | `operations.manage` | `task.assign`, `task.resolve` | proposed |
| Documents | `document.read` | `document.create/update/archive` | `document.verify`, `document.share` | proposed |
| Finance | `finance.read` | `finance.post` | `finance.approve`, `finance.export` | proposed |
| Valuation | `scenario.read` | `scenario.create/update` | `scenario.approve` | proposed |
| Reporting/Audit | `reporting.read` | `reporting.generate` | `reporting.approve`, `audit.read` | proposed |

Die konkrete Rollenbelegung bleibt `open`; die lokale Rollenmatrix ist nur Inventarevidenz und keine freigegebene Cloud-Matrix.

## 5. Gemeinsame Cloud-Spalten

| Spalte | Zieltyp/Default | Status | Regel |
|---|---|---|---|
| `id` | `uuid`, serverseitig erzeugt | proposed | Stabil, nie wiederverwendet; Import darf eine separate `legacy_id`-Zuordnung nutzen. |
| `workspace_id` | `uuid NOT NULL` | proposed | Direkter FK zur Mandantengrenze, unveraenderlich nach Erstellung. Auch Kindtabellen tragen die Spalte. |
| `created_at` | `timestamptz NOT NULL DEFAULT now()` | proposed | Serverzeit; Clientzeit nur als separates Fachfeld. |
| `updated_at` | `timestamptz NOT NULL DEFAULT now()` | proposed | Nur durch akzeptierte Mutation gesetzt. |
| `created_by` | `uuid` | proposed | `auth.uid()` oder explizite Systemidentitaet; nie ungeprueft aus Clientpayload. |
| `updated_by` | `uuid` | proposed | Wie `created_by`; bei Systemjobs technische Identitaet plus Korrelation. |
| `version` | `bigint NOT NULL DEFAULT 1` | proposed | Erhoeht sich atomar bei jeder fachlichen Aenderung; Mutation verlangt `expected_version`. |
| `deleted_at` | `timestamptz NULL` | proposed | Fuer sync-/aufbewahrungsrelevante Entitaeten; setzt Tombstone statt Hard Delete. |
| `deleted_by` | `uuid NULL` | proposed | Pflicht, sobald `deleted_at` gesetzt ist. |

Append-only-Entitaeten tragen dieselben Herkunftsspalten; `updated_at = created_at`, `updated_by = created_by`, `version = 1` und Updates werden technisch verweigert. Abgeleitete Views erhalten keine kuenstlichen Mutationsspalten.

## 6. Audit und Idempotenz

| ID | Status | Regel |
|---|---|---|
| AUD-001 | proposed | Jede kritische Mutation schreibt Fachzeile, `mutation_receipt` und `audit_event` atomar. Scheitert Audit, scheitert die Mutation. |
| AUD-002 | proposed | Audit enthaelt `workspace_id`, Akteur/Systemidentitaet, Rollen-/Scope-Snapshot, Aktion, Entitaet, Parent, Quelle, `correlation_id`, `mutation_id`, Grund, Zeit und fachlich relevante Alt-/Neuwerte. |
| AUD-003 | proposed | Passwort-/Tokenwerte, Secrets, signierte URLs, binaere Inhalte, vollstaendige Dokumenttexte und unnoetige PII werden nie auditiert. Sensible Diffs verwenden Allowlist, Maskierung oder Feldklassifikation. |
| AUD-004 | proposed | Audit ist append-only, chronologisch stabil und nur ueber Korrekturereignisse korrigierbar. Aufbewahrung und Export werden workspacebezogen protokolliert. |
| IDM-001 | proposed | Jede Clientmutation besitzt eine UUID `mutation_id`, `expected_version` und `device_id`; Eindeutigkeit mindestens `(workspace_id, mutation_id)`. |
| IDM-002 | proposed | Wiederholung mit identischem Request-Hash liefert dasselbe Ergebnis ohne zweite Fachmutation oder zweites Audit. Gleiche `mutation_id` mit anderer Payload wird als Missbrauch/Clientfehler abgewiesen. |
| IDM-003 | proposed | Upload-Initialisierung, Blob-Finalisierung, Importzeilen, Jobs und Webhooks besitzen eigene Idempotenzschluessel und monotone Statusuebergaenge. |

## 7. Tombstones und Loeschung

| ID | Status | Regel |
|---|---|---|
| DEL-001 | proposed | Fachlich, rechtlich, audit- oder sync-relevante Daten werden archiviert beziehungsweise per Tombstone geloescht; Kaskaden-Hard-Deletes sind fuer Cloud-Fachdaten nicht erlaubt. |
| DEL-002 | proposed | Tombstone enthaelt mindestens `id`, `workspace_id`, `deleted_at`, `deleted_by`, letzte `version` und Entitaetstyp; Sync-Clients muessen ihn bestaetigen koennen. |
| DEL-003 | proposed | Physische Bereinigung erfolgt erst nach dokumentierter Aufbewahrungsfrist, abgelaufenem Restore-Fenster und Sync-Watermark aller unterstuetzten Clients. Audit bleibt gemaess eigener Retention erhalten. |
| DEL-004 | proposed | Restore erzeugt eine neue Version und Audit-Ereignis; Wiederverwendung einer geloeschten ID oder stilles Entfernen des Tombstones ist verboten. |
| DEL-005 | open | Konkrete gesetzliche und vertragliche Aufbewahrungsfristen je Entitaets-/Dokumenttyp. Default bis Freigabe: keine automatische physische Loeschung. Entscheidung vor produktiver Phase 2. |

## 8. Dokument- und Storage-Baseline

| ID | Status | Regel |
|---|---|---|
| STO-001 | proposed | Ausschliesslich private Buckets. Der kanonische Objektpfad ist serverseitig erzeugt, z. B. `<workspace>/<document>/<version>/<blob-id>`; Dateiname ist Metadatum, nicht Pfadautoritaet. |
| STO-002 | proposed | Dokumentmetadaten und Blobversion sind getrennt. Blobs sind unveraenderlich; Ersetzen erzeugt eine neue `document_version`, niemals ein Overwrite. |
| STO-003 | proposed | Uploadfluss: Berechtigung/Quota pruefen -> Quarantaene -> Groesse und Magic-Byte/MIME pruefen -> SHA-256 serverseitig berechnen -> Malware-Scan -> atomar finalisieren -> Audit. Bis dahin kein fachlicher Download. |
| STO-004 | proposed | Downloads verwenden kurzlebige signierte URLs oder autorisierte Streaming-Endpunkte. Freigabelinks sind widerrufbar, zweckgebunden, ablaufend und auditiert. |
| STO-005 | proposed | RLS/Storage prueft Workspace, `document.read`, Entity-Scope und aktuellen Dokumentstatus. Kenntnis von Bucket, Objektpfad oder Dokument-ID reicht nicht. |
| STO-006 | proposed | Loeschen setzt Tombstones auf Dokument und Version; Blobbereinigung erfolgt asynchron erst nach Retention. Verwaiste Uploads werden nach Quarantaene-Frist entfernt. |
| STO-007 | proposed | Datenbank-Dump und Storage-Export werden getrennt, verschluesselt und restore-getestet gesichert. Manifest enthaelt Objektpfad, Version, Groesse und Hash. |
| STO-008 | open | Maximalgroessen, erlaubte Dateitypen, Scan-Anbieter, URL-Laufzeit und Aufbewahrung je Dokumenttyp. Restriktiver Default: keine ausfuehrbaren Formate, kein oeffentlicher Zugriff. Entscheidung vor Upload-Pilot. |

## 9. Erforderliche RLS-Negativtests

| ID | Erwartung | Status |
|---|---|---|
| RLS-T001 | `anon` kann keine Fach-, Identity-, Audit- oder Storage-Daten lesen oder schreiben. | proposed |
| RLS-T002 | Nutzer A in Workspace A kann bekannte IDs aus Workspace B weder lesen, einfuegen, aendern, loeschen noch ueber RPC/Realtime/Storage erkennen. | proposed |
| RLS-T003 | `INSERT`/`UPDATE` mit fremder `workspace_id`, fremdem Parent oder nachtraeglichem Workspace-Wechsel scheitert. | proposed |
| RLS-T004 | Eingeladene, suspendierte, widerrufene und geloeschte Memberships erhalten keinen Zugriff; bestehende Realtime-Verbindungen liefern danach keine Daten. | proposed |
| RLS-T005 | Rolle ohne konkrete Permission scheitert fuer jede Mutation, auch bei direktem REST-Aufruf und gueltigem Workspace. | proposed |
| RLS-T006 | Property-/Portfolio-Scope kann weder durch manipulierte `property_id` noch durch indirekte Kindrelationen umgangen werden. | proposed |
| RLS-T007 | Nutzer kann eigene Rolle, Membership, Scopes oder `created_by/updated_by` nicht selbst eskalieren/faelschen. | proposed |
| RLS-T008 | Letzter aktiver Admin kann nicht entfernt, suspendiert oder herabgestuft werden; parallele Requests umgehen die Invariante nicht. | proposed |
| RLS-T009 | Client kann Audit nicht einfuegen, aendern oder loeschen und keine Mutation ohne korrespondierendes Audit committen. | proposed |
| RLS-T010 | Geloeschte Zeilen sind fuer Standardrollen unsichtbar; Restore-/Compliance-Zugriff bleibt explizit berechtigt und auditiert. | proposed |
| RLS-T011 | Storage verweigert fremde Pfade, manipulierte Prefixe, nicht finalisierte/infizierte Uploads, abgelaufene Links und Dokumente ausserhalb des Entity-Scopes. | proposed |
| RLS-T012 | Service-Role-Endpoint verweigert fehlende/ungueltige Nutzerclaims, Workspace-Mismatch und nicht erlaubte Mutation trotz technischer DB-Berechtigung. | proposed |
| RLS-T013 | Unbekannte Rolle, Permission, Entity-Type oder Policy-Hilfsfunktion faellt auf Deny, nicht auf Allow. | proposed |
| RLS-T014 | Wiederholte Mutation erzeugt genau eine Fachwirkung und ein Audit; gleiche `mutation_id` mit abweichender Payload scheitert. | proposed |
| RLS-T015 | Listen, Counts, Suche, Exporte und Fehlertexte leaken weder Existenz noch Anzahl fremder Datensaetze. | proposed |

## 10. Akzeptanzgate Phase 1

- Zwei isolierte Test-Workspaces bestehen `RLS-T001` bis `RLS-T015`. (`proposed`)
- Der Referenzschnitt `Login -> Workspace -> Property -> Mutation -> Audit -> Realtime` nutzt ausschliesslich serverseitige Autorisierung. (`proposed`)
- Kein Flutter-Build enthaelt Service-Key, Storage-Admin-Key oder autoritative Rollenlogik. (`proposed`)
- Alle exponierten Tabellen sind in einer automatisierten Policy-Inventur enthalten; neue Tabelle ohne RLS laesst CI fehlschlagen. (`proposed`)
- Storage-Restore wird gemeinsam mit Datenbank-Restore anhand Hash/Manifest nachgewiesen. (`proposed`)

## 11. Offene Entscheidungen

| ID | Status | Auswirkung | Default-Annahme | Spaetester Zeitpunkt |
|---|---|---|---|---|
| DEC-SEC-001 | open | Konkrete Rollen-zu-Permission-Matrix und Vier-Augen-Freigaben | Lokale Rollen nur als Migrationsinput, keine automatische 1:1-Uebernahme | vor RLS-Prototyp-Abnahme |
| DEC-SEC-002 | open | Objekt-/Portfolio-Scope-Vererbung bei Mehrfachzuordnung | Zugriff nur, wenn mindestens ein explizit erlaubter Scope den Datensatz eindeutig umfasst | vor Phase-2-Import |
| DEC-SEC-003 | open | PII-Klassifikation und Feldmaskierung fuer Mieter/Kontakte | Least privilege; separate Permission fuer sensible Kontaktdaten | vor Leasing-Migration |
| DEC-SEC-004 | open | Retention, Legal Hold und physische Loeschung | Keine automatische physische Loeschung | vor produktiver Dokumentmigration |
| DEC-SEC-005 | open | Upload-Maximalgroessen, Dateitypen, Malware-Scan und Laufzeit signierter URLs | Keine ausfuehrbaren Formate, kein oeffentlicher Zugriff | vor Upload-Pilot |
