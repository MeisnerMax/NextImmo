# Admin-Bereich: Mitglieder & Zugriff (ADMIN-MEMBERS-V2)

## Metadata

- Package / screen ID: `ADMIN-AREA-01` (Tracker Wave 2) / Screen-ID `ADMIN-MEMBERS-V2`
- Domain: `identity_access`
- Route: `/members` (`GlobalPage.adminUsers`, `CloudRouteSurface.members`); Sidebar „Setup & Verwaltung → Mitglieder" (Umbenennung von „Benutzer" per Foundation-Amendment AMD-001, siehe §3)
- Current implementation file(s):
  - `lib/features/reference_slice/presentation/reference_members_screen.dart` (Basis, zieht um)
  - `lib/features/reference_slice/application/members_admin_controller.dart` (Basis, zieht um)
  - `lib/features/identity_access/application/membership_admin_repository.dart` (Contract, bleibt)
  - `lib/features/identity_access/data/supabase_membership_admin_repository_adapter.dart` (Adapter, wird um Reads erweitert)
  - `lib/ui/screens/admin/users_screen.dart` (Legacy SCR-061 — Harvest, dann REMOVE)
- Planning status: APPROVED (2026-08-28; Entscheidungen §20 geschlossen)
- Dependencies: `UX-FOUNDATION-IMPL-01` (NxListSkeleton, NxSplitView, NxNotice) muss vor Implementierungsbeginn auf main sein; Planung/Review unabhängig.
- Related screens: `SupabaseSecurityGate`/Workspace-Auswahl (Invite-Accept-Verlagerung, Paket B — fachlich Core/Auth/Workspace-Gate), `AUDIT-01` (Wave 3, Voll-Audit), `SETTINGS-01` (blocked), `PERMISSION-CATALOG-02` (Backend, separat).

Basis der Analyse: `origin/main` `46effaba` (2026-08-27). Alle Aussagen zu Contracts, RPCs, RLS und Safeguards sind gegen Code/Migrationen verifiziert, nicht aus Docs übernommen.

---

## 0. Referenz-Benchmark (Notion / Slack / GitHub) und Adopt/Adapt/Reject

Untersucht: Notion Workspace-Settings „People/Members" (Members, Guests, Restricted Members, Temporary Members, Workspace Owner, Membership Admin, Groups, Invite-Requests), Slack Rollenmodell (Primary Owner, Workspace Owner/Admin, Full Member, Multi-/Single-Channel Guest, „Invited members", System Roles wie Users/Roles Admin, „Change account type"-Flow, Permissions-by-role-Matrix), GitHub Organization (vordefinierte + Custom Org Roles aus feingranularen Permissions, Least-Privilege-Empfehlung, Rollenzuweisung nur durch Owner, Audit-Log als Who/What/When-Liste, Teams).

Leitidee des Functional Reference Clone: Notions **eine Verwaltungsfläche mit klaren Tabs und Aktionen direkt an der Zeile**, Slacks **Rollenwechsel-Bestätigungen und delegierte Admin-Rolle**, GitHubs **Rolle-als-Capability-Bündel und sichtbares Audit** — ohne daraus ein IAM-Produkt zu machen. Kein Branding, keine 1:1-Oberflächen.

| Muster | Quelle | Entscheidung | Begründung / NexImmo-Fassung |
|---|---|---|---|
| Eine Admin-Destination „People" mit Tabs statt vieler Einzelseiten | Notion | **Adopt** | Ein Screen `adminUsers` mit Tabs Mitglieder / Einladungen / Rollen (+ Aktivität, Inkrement 2). Foundation §9 erlaubt ≤ 5 Tabs. |
| Pending Invitations sichtbar und verwaltbar im Admin-Bereich | Notion | **Adopt** | Tab „Einladungen" mit Zähler; Revoke direkt an der Zeile. |
| Rollenwechsel als Aktion an der Zeile mit Bestätigung | Notion + Slack | **Adopt** | Zeilenmenü → Dialog „Rolle ändern" mit Vorher/Nachher-Capability-Zusammenfassung (§6.3). |
| Nur Berechtigte verwalten Mitglieder; delegierte Admin-Rolle möglich | Slack (Users Admin), Notion (Membership Admin) | **Adopt** | Deckt sich exakt mit `security.manage` als Gate; keine neue Rolle nötig — jede Rolle mit `security.manage` *ist* der Membership-Admin. |
| Rolle = benanntes Bündel feingranularer Capabilities; Least Privilege als Erklärtext | GitHub | **Adopt** | Tab „Rollen": Role summary → aufklappbare Capability-Liste (read-only). Quelle: bestehende Tabellen `roles`/`role_permissions`/`permissions`. |
| Audit als einfache Who/What/When-Liste im Admin-Kontext | GitHub | **Adopt (Inkrement 2)** | Tab „Aktivität": Membership-Ereignisse aus `audit_events` (RLS `audit.read` existiert). Kein Ersatz für `AUDIT-01`. |
| Optionaler Grund bei administrativen Änderungen, im Audit protokolliert | GitHub-Praxis | **Adopt** | Die RPCs nehmen bereits `p_reason` und schreiben ihn ins Audit-Event; die Dangerous-Action-Dialoge bekommen ein optionales Grund-Feld. |
| Statusgetrennte Sicht „Invited members" | Slack | **Adapt** | Bei uns zwei Datenarten: `invited`-Memberships (Auth-User existiert) erscheinen im Mitglieder-Tab mit Status-Badge; Pre-Auth-E-Mail-Invites (`membership_invitations`) im Einladungen-Tab. Die Trennung folgt ehrlich dem Datenmodell statt sie in einer Liste zu vermischen. |
| Invite-Flow: E-Mail + Rolle, dann E-Mail-Zustellung | Notion/Slack/GitHub | **Adapt** | E-Mail + Rolle als Modal-Dialog. Es gibt **keine E-Mail-Zustellung** (kein SMTP-Flow im Contract): Der Erfolgstext sagt ehrlich, dass die Person die Einladung nach Anmeldung mit dieser E-Mail-Adresse in NexImmo sieht. Zustellung = optionales Gap `INVITE-DELIVERY-01`. |
| „Change account type"-Matrix / Permissions-by-role als Hilfeseite | Slack | **Adapt** | Keine rohe Permission-Matrix als primäre UX. Die Matrix-Information steckt in den aufklappbaren Rollen-Details; ein Hilfetext erklärt das Modell in zwei Sätzen. |
| Primary-Owner-Konzept mit Transfer-Flow | Slack | **Reject** | NexImmo hat keinen Owner-Begriff; die Invariante „mindestens ein aktiver `security.manage`-Inhaber" ist serverseitig durch `would_remove_last_security_manager` erzwungen (Suspend/Revoke **und** Rollenwechsel). Die UI macht die Server-Ablehnung verständlich, führt aber kein Owner-Modell ein. |
| Guests / Restricted Members / seitenweiser Zugriff | Notion, Slack | **Reject** | Kein Backend-Konzept (kein Gast-Status, kein Seiten-Scope). Nicht erfinden. |
| Temporary Members mit Ablaufdatum | Notion | **Reject** | `membership_invitations`/`memberships` haben kein Expiry-Feld. Optionales Gap, nicht planen. |
| Groups / Teams | Notion, GitHub | **Reject → Future/Backend-Gap** | Keine Tabelle, kein Contract (§14). |
| Custom-Role-Builder | GitHub | **Reject** | Rollen-CRUD-RPCs existieren nicht; Rollen entstehen/ändern sich nur über `PERMISSION-CATALOG-02`. Tab „Rollen" ist strikt read-only. |
| Org-Level-People-Dashboard, SCIM/SSO, Sessions-Verwaltung | Notion Enterprise | **Reject** | Weit außerhalb des Produkts; Auth/AAL-Grenzen sind abgeschlossen und werden nicht angefasst. |

## 1. Purpose

Der Admin-Bereich beantwortet drei Fragen einfach und wahrheitsgetreu: **Wer ist in diesem Workspace, was darf diese Person, und wie ändere ich das sicher?** Er ersetzt die Reference-Slice-Präsentation des Members-Screens durch die produktkonforme V2-Fläche (Foundation-Patterns, deutsche Copy) und beerdigt den Legacy-`UsersScreen` endgültig. Er ist bewusst **kein IAM-Produkt**: keine Rollen-Editoren, keine Permission-Matrizen als Arbeitsfläche, keine erfundenen Auth-Funktionen.

## 2. Primary users and jobs

- **Workspace-Administrator:in** (Rolle mit `security.manage`, in der Praxis auch `workspace.read`): sieht das vollständige Mitglieder-Verzeichnis; lädt ein; ändert Rollen; suspendiert, reaktiviert, entzieht Zugriff; widerruft Einladungen; versteht vor jeder Änderung, was eine Rolle bedeutet. Braucht zuerst: Liste mit Name/E-Mail/Rolle/Status, dann Aktionen an der Zeile.
- **Admin ohne AAL2** (angemeldet, aber ohne verifizierten zweiten Faktor): darf lesen, nicht ändern. Sieht den bestehenden MFA-Hinweis; alle Mutations-Auslöser sind disabled mit Tooltip (§8).
- **Prüfende Rolle** (`audit.read`, Inkrement 2): möchte nachvollziehen, wer wann wen eingeladen, geändert, entzogen hat.
- **Eingeladene Person ist ausdrücklich KEIN Nutzer dieses Screens.** Der Accept-Flow („Your invitations") verlässt den Admin-Bereich (§3, Paket B) — heute ist er hinter dem `security.manage`-Gate faktisch gefangen.

## 3. Entry points and navigation

- Sidebar: Gruppe „Setup & Verwaltung" → „Mitglieder" (Sichtbarkeit über `cloudReadPermissionForPage` = `security.manage`; Sidebar versteckt, Deep-Link zeigt Forbidden — Foundation §3, unverändert).
- **Foundation-Amendment AMD-001 (beschlossen 2026-08-28):** Das Sidebar-Ziel `GlobalPage.adminUsers` wird von „Benutzer" auf „Mitglieder" umbenannt (Label + Titel in `appNavigationGroups`, `routeKey` `setup_administration.users` bleibt stabil). Per Foundation §1 ist die Umbenennung einer Destination ein Foundation-Amendment, kein Screen-Detail; das Amendment ist im Amendments-Abschnitt von `PRODUCT_UX_FOUNDATION.md` protokolliert und wird mit Paket A1 implementiert (Ein-Zeilen-Änderung, keine Routen-/Permission-Änderung).
- Deep-Link `/members` → Gate → Shell → dieser Screen. Bis `SHELL-ROUTING-01` bleibt der Screen ohne URL voll erreichbar; Tab-Zustand ist nicht URL-persistent.
- Von hier keine Weiter-Navigation in andere Module; Breadcrumbs `['Setup & Verwaltung', 'Mitglieder']` sind Labels (Foundation §5).
- **Befund + Verlagerung (Paket B):** Die Accept-Zone eigener Einladungen lebt heute im Members-Screen, der auf `security.manage` gegated ist; ein Eingeladener ohne diese Capability erreicht sie über die Shell nicht, und der Empty-Workspace-State der Gate-Ansicht („No workspace access") verdrahtet `onOpenMembers` nicht. Zielbild: Pending-Invitations werden auf der **Workspace-Auswahl-/Gate-Fläche** angezeigt und akzeptiert (`list_my_pending_invitations` ist für jeden Authentifizierten lesbar; `accept_workspace_invitation` ist die Mutation des Eingeladenen selbst). Der Admin-Screen verliert die Zone ersatzlos. Bis Paket B gemerged ist, bleibt die bestehende Zone unverändert in Betrieb — kein Zwischenzustand, in dem Accept nirgends existiert.

## 4. Information architecture

1. `NxPageHeader`: Titel „Mitglieder", Breadcrumbs, Untertitel „Mitglieder von <Workspace-Name>", `secondaryActions`: „Aktualisieren"; `primaryAction`: „Mitglied einladen" (einziger FilledButton, disabled ohne Capability/AAL2).
2. MFA-Hinweis (`NxNotice`, nur wenn `security.manage` vorhanden und AAL < 2): „Richte Multi-Faktor-Authentifizierung ein, um Mitglieder zu ändern. Ansehen ist jetzt möglich."
3. Tabs (`NxCard`-gerahmt, Foundation §9): **Mitglieder** · **Einladungen** (mit Zähler offener Einladungen) · **Rollen** · **Aktivität** (Inkrement 2).
4. Tab-Inhalt: Liste/Tabelle mit Filterleiste (Mitglieder), Liste (Einladungen), aufklappbare Rollen-Karten (Rollen), Ereignisliste (Aktivität).
5. Split-Pane-Detail im Mitglieder-Tab (Foundation §8): rechts Mitglieds-Detail mit Fakten, Rolle inkl. Capabilities und Aktionen.

## 5. Layout and interaction model

- **Frame:** `ListFilterTemplate` je Tab-Inhalt; Seitenpolster `context.adaptivePagePadding`; Tabs nie über der Primäraktion (Header bleibt oben, Foundation §9).
- **Mitglieder (Desktop, `width > AppBreakpoints.tabletMax`):** Split 3:2 (`NxSplitView`). Links `NxDataTableShell` mit Spalten Name, E-Mail, Rolle (`NxStatusBadge` neutral), Status (`NxStatusBadge`), Beigetreten/Eingeladen am (Datum aus `created_at`), Zeilenmenü. Spalten ≤ 6, kein Column-Chooser nötig. Numerik-/ID-Stile per Foundation §6; `'—'` für fehlende Werte (z. B. Name ohne Profil). Rechts Detail-Panel: Titelzeile (Name + Status-Badge), Fakten als Label/Wert (E-Mail, Rolle, Status, Mitglied seit, zuletzt geändert, Version als `dataMonoStyle`-Randnotiz nur im Konfliktfall), Abschnitt „Rolle & Berechtigungen" (Capability-Liste der aktuellen Rolle, read-only), Abschnitt „Aktionen" (Buttons statt verstecktem Menü — Rolle ändern, Suspendieren/Reaktivieren, Zugriff entziehen).
  - **Zeilen-Harvest aus Legacy-`UsersScreen`:** Identität links (Icon + Name + Badge), Controls rechts, Compact-Stacking unterhalb der Kartenbreite — übernommen für den mandatorischen `mobileChild` (ListTile-Liste mit `chevron_right`; Tap öffnet Detail, narrow ersetzt Liste mit „Zur Liste"-Rückweg, Foundation §8).
- **Einladungen:** einfache Kartenliste (kein Table nötig, 3 Datenpunkte): E-Mail, Rolle, „Ausstehend seit <Datum>", Badge `Ausstehend`, Aktion „Widerrufen". Bei `includeResolved` bleibt es beim Default `false` — nur offene Einladungen; erledigte Historie gehört ins Audit.
- **Rollen:** eine `NxCard` je Rolle: Name, Key (`dataMonoStyle`), Mitgliederzahl in dieser Rolle, Kurzsatz („Diese Rolle bündelt N Berechtigungen."), `ExpansionTile`-artige Aufklappung mit der Capability-Liste (Anzeigename + Key). Keine Matrix, kein Edit. Hinweiszeile am Tab-Ende: „Rollen und Berechtigungen werden zentral gepflegt und sind hier nur einsehbar."
- **Aktivität (Inkrement 2):** chronologische Liste (neueste zuerst), je Ereignis: Aktion (verständlicher Text), Ziel (Name/E-Mail), Akteur, Zeitpunkt, optionaler Grund. Keyset-„Weitere laden" (Foundation §6), Seitengröße ~50.
- Dialoge per `ResponsiveConstraints.dialogWidth`; kein Modal über Modal; Bestätigung darf auf Formular-Submit folgen (Foundation §9/§14).
- Golden-Viewports 390×844 / 1024×768 / 1440×900 + 320-Floor, hell und dunkel, ohne Overflow (Foundation §15).

## 6. Functional requirements

Alle Mutationen laufen ausschließlich über `MembershipAdminRepository` (auditierte, idempotente, versionierte RPCs). Keine Funktion wird erfunden; insbesondere gibt es **kein** Passwort-Setzen, keinen Klartext-Startpasswort-Dialog (stirbt ersatzlos mit dem Legacy-Screen) und kein „Einladung erneut senden" (kein Backend; siehe Reject/§14).

### 6.1 Mitglied einladen
- Trigger: Primäraktion „Mitglied einladen" → Modal-Dialog (E-Mail, Rollen-Dropdown mit Kurzbeschreibung „N Berechtigungen", aufklappbare Capability-Vorschau der gewählten Rolle, optionales Feld „Grund (optional, wird protokolliert)").
- Prerequisites: `security.manage` + AAL2; Rollenliste geladen.
- Validation: E-Mail Pflichtfeld + Format (Server validiert erneut: 3–320 Zeichen, `@`); Rolle Pflicht.
- Success: `InviteOutcome` — bei existierendem Auth-User entsteht eine `invited`-Membership (erscheint im Mitglieder-Tab), sonst eine E-Mail-Einladung (erscheint im Einladungen-Tab). SnackBar nennt ehrlich den Pfad: „Einladung angelegt. <E-Mail> sieht sie nach der Anmeldung in NexImmo." Dialog schließt, betroffener Tab lädt nach.
- Failure: `validationFailed` „hat bereits eine Mitgliedschaft" / „Einladung existiert bereits" als Inline-Fehler im Dialog (Eingabe bleibt erhalten); `forbidden`/`failed` über Action-Feedback (§12 der Foundation).
- Permission: `security.manage`; Button ohne Capability disabled mit Tooltip „Benötigt die Berechtigung (security.manage)", ohne AAL2 disabled mit Tooltip auf den MFA-Hinweis.

### 6.2 Einladung widerrufen
- Trigger: „Widerrufen" an der Einladungszeile → Bestätigungsdialog (Foundation §14): benennt die E-Mail-Adresse, Konsequenz „kann später neu eingeladen werden", optionaler Grund; Confirm „Widerrufen" in Fehlerfarbe.
- Success: Zeile verschwindet; Zähler aktualisiert. Failure: `versionConflict` → Liste lädt nach, Hinweis „Die Einladung wurde zwischenzeitlich geändert."; sonst Action-Feedback.
- Permission: `security.manage` + AAL2.

### 6.3 Rolle ändern
- Trigger: Detail-Aktion oder Zeilenmenü „Rolle ändern" → Dialog: aktuelles → neues Rollen-Dropdown, darunter kompakte Änderungszusammenfassung „Hinzu kommen: … / Entfallen: …" (Diff der Capability-Mengen beider Rollen, je max. ~6 Einträge + „und N weitere"), optionaler Grund.
- Prerequisites: Mitglied nicht `revoked`; `security.manage` + AAL2.
- Success: Badge/Detail aktualisieren; SnackBar. Failure: Server-Ablehnung „letzter aktiver Sicherheitsverwalter" (Rollenwechsel weg von `security.manage`) wird als verständlicher Inline-Text gezeigt: „<Name> ist die letzte Person mit Sicherheitsverwaltung in diesem Workspace. Übertrage die Berechtigung zuerst an jemand anderen." `versionConflict`: Dialog bleibt offen, Banner nennt den Serverstand, „Neu laden" / „Erneut speichern" (Foundation §10 — Eingabe wird nie verworfen).
- Zusätzliche Safeguard-Stufe (Client, §Dangerous Actions): Wechsel **auf** eine Rolle mit `security.manage` (Admin-Promotion) und Wechsel **weg** von einer solchen Rolle verlangen den Bestätigungsdialog mit explizitem Konsequenzsatz; neutrale Wechsel (z. B. Viewer→Editor ohne `security.manage`) kommen mit der Dialog-Zusammenfassung ohne zweite Stufe aus.

### 6.4 Suspendieren / Reaktivieren
- Trigger: Detail-Aktion/Zeilenmenü. Suspendieren: Bestätigungsdialog „<Name> verliert den Zugriff, bis er wieder aktiviert wird. Das ist umkehrbar.", Confirm „Suspendieren" (Warnstil, nicht Fehlerfarbe — reversibel). Reaktivieren: Bestätigung „<Name> erhält den vorherigen Zugriff zurück."
- Failure: Last-Manager-Guard wie 6.3; `versionConflict` → Detail lädt Serverstand, Hinweis.
- Permission: `security.manage` + AAL2. Statusübergänge folgen strikt dem Contract (`invited→active` nur durch Accept des Eingeladenen; Admin: `active↔suspended`, `→revoked`).

### 6.5 Zugriff entziehen (revoke)
- Trigger: Detail-Aktion/Zeilenmenü „Zugriff entziehen" → destruktiver Dialog (Foundation §14): benennt die Person, Konsequenz „Endgültig. Die Mitgliedschaft kann nicht wiederhergestellt und die Person mit dieser Mitgliedschaft nicht erneut eingeladen werden.", optionaler Grund, Confirm „Entziehen" in Fehlerfarbe.
- „Restore falls unterstützt": **nicht unterstützt** — `revoked` ist terminal im Contract. Keine Restore-UI. Entzogene Mitglieder bleiben im Verzeichnis sichtbar (Status-Badge `Entzogen`), standardmäßig per Statusfilter ausgeblendet (§11), damit die Historie nicht verschwindet, aber die Arbeitsliste sauber bleibt.
- Permission/Failure wie 6.4 inkl. Last-Manager-Guard.

### 6.6 Eigene Einladung annehmen
- **Verlässt diesen Screen** (Paket B, §3). Bis dahin bleibt die bestehende Zone funktional unverändert.

### 6.7 Aktualisieren, Filtern, Suchen
- „Aktualisieren" lädt Directory, Einladungen, Rollen (und Aktivität) neu — nötig, solange Membership-Realtime fehlt (§9). Filter/Suche: §11.

## 7. Data requirements

Quelle Mitglieder-Tab: RPC `list_workspace_members` (`WorkspaceMemberDirectoryEntry`). Felder:

| Feld | Bedeutung | Quelle | Anzeige |
|---|---|---|---|
| Name | Anzeigename | `user_profiles.display_name` (nullable) | Titel; Fallback E-Mail, dann `'—'` + userId nur im Detail |
| E-Mail | Login-Adresse | `auth.users.email` via RPC (nullable) | Sekundärzeile, ellipsis |
| Rolle | `role_name` (+ `role_key` im Detail) | `roles` via RPC | Badge neutral |
| Status | invited/active/suspended/revoked | `memberships.status` | Badge: Eingeladen=info, Aktiv=success, Suspendiert=warning, Entzogen=error (Mapping neben dem Enum, Foundation §12) |
| Beigetreten/Eingeladen am | `created_at` | RPC | Datum; Label je Status („Eingeladen am" bei invited) |
| Zuletzt geändert | `updated_at` | RPC | nur Detail |
| Version | Optimistic-Concurrency-Token | RPC | unsichtbar; nur in Konfliktbannern benannt |

- **„Letzte Aktivität": entfällt.** Die RPC liefert kein `last_sign_in_at`; nichts Belastbares vorhanden → optionales Backend-Gap (§14), nicht geplant.
- Einladungen-Tab: `listInvitations` (`MembershipInvitation`: email, role, created_at, version). Rollen-Tab: `listRoles` + neue Reads `role_permissions`/`permissions` (§14 „In-Package-Reads"). Aktivität: `audit_events` (workspace-gefiltert, `entity_type in ('membership','membership_invitation')`).
- Keine Schemaänderungen; alles Angezeigte existiert serverseitig.

## 8. Permissions and security behavior

- Seite: `cloudReadPermissionForPage(adminUsers)` = `security.manage` (unverändert; Sidebar versteckt, Deep-Link → Forbidden-State mit „(security.manage)").
- Directory-Read ist zusätzlich serverseitig gated: ohne `security.manage` liefert die RPC `forbidden` — der bestehende Forbidden-State des Screens bleibt als zweite, servergestützte Verteidigungslinie.
- Rollen-Tab-Reads laufen über RLS `workspace.read` (roles/role_permissions) bzw. „authenticated" (permissions). Ein theoretischer Admin ohne `workspace.read` sieht im Rollen-Tab den Forbidden-State mit „(workspace.read)" statt leerer Listen — fail closed, keine stillen Nullen.
- Aktivität-Tab: sichtbar nur mit `audit.read`; ohne die Capability wird der Tab ausgeblendet (Admin-Rauschen-Regel aus Foundation §3), Deep-Zugriff zeigt Forbidden „(audit.read)".
- Mutationen: `security.manage` **und** AAL2 (serverseitig `private.is_aal2` in jeder RPC). UI-Regel: mit Capability aber ohne AAL2 sind alle Auslöser **disabled mit Tooltip** und der `NxNotice`-MFA-Hinweis steht über den Tabs; ohne Capability sind Aktionsauslöser **hidden** (Seite ist ohnehin nur mit `security.manage` erreichbar — die Regel greift bei Mid-Session-Entzug).
- Mid-Session-Revocation: Die bestehende Entitlement-Revalidierung (Broadcast `entitlements:<uid>`) räumt den Scope fail-closed; der Screen kämpft nicht dagegen an (Foundation §3). Nach Entzug rendert der nächste Build den Forbidden-State.
- Client-Gating ersetzt nie RLS/RPC-Gates; AAL/RLS/Auth-Grenzen werden durch dieses Paket in keiner Weise verändert.

## 9. Realtime / freshness behavior

- **Ist:** Keine Realtime-Publikation für `memberships`/`membership_invitations`. Der einzige Kanal ist der Per-User-Entitlement-Broadcast — er revalidiert die Rechte des Akteurs, nicht die Frische des Verzeichnisses.
- **Spec-Verhalten heute:** Kanonischer REST-Read; „Aktualisieren" im Header; nach jeder eigenen Mutation gezieltes Nachladen des betroffenen Tabs. Kein `NxLiveUpdatesNotice`, solange es keinen Live-Kanal gibt — eine „Live-Updates pausiert"-Meldung ohne Live-Updates wäre gelogen.
- **Gap `MEMBERSHIP-REALTIME-01`** (§14): Invalidation-only-Publikation für beide Tabellen im bestehenden Muster (debounced Reload, ein Reconcile pro Reconnect). Erst mit diesem Paket wird das Degraded-Wiring (Foundation §13) hier verdrahtet. Die Spec ist so geschnitten, dass das Nachrüsten keinen UI-Umbau erfordert (Controller-Flag + Notice unter dem Header).

## 10. Screen states

Vokabular und Rendering strikt per Foundation §11; je Tab eigene Zustände:

- initial loading: `NxListSkeleton` (Mitglieder/Einladungen/Aktivität), Karten-Skeleton (Rollen); nie Blank-Spinner.
- background refresh: sichtbare Daten bleiben stehen; Refresh-Button zeigt Progress.
- empty: Mitglieder „Noch keine Mitglieder. Lade die erste Person ein." + CTA (capability-/AAL2-gated); Einladungen „Keine offenen Einladungen."; Aktivität „Noch keine Ereignisse."
- no-match (aktive Filter): Foundation §7-Standard mit „Filter zurücksetzen".
- forbidden: je Tab mit benannter Capability (§8).
- error: `NxEmptyState(Icons.cloud_off_outlined, …)` + `FilledButton.icon(refresh, 'Erneut versuchen')` je Tab unabhängig (ein kaputter Audit-Read darf das Verzeichnis nicht blockieren).
- permission-denied mid-session / auth transition: Forbidden-State bzw. Gate übernimmt.
- action in progress / success / failure / conflict: Action-Feedback-Muster (`ref.listen` → SnackBar, Konflikt per §10-Konflikt-UX); Submit-Buttons zeigen Progress und disablen.
- realtime degraded: n/a bis `MEMBERSHIP-REALTIME-01` (§9).

## 11. Search / filter / sort

- Suche (Mitglieder): clientseitig über Name + E-Mail (das Directory kommt vollständig, keine Keyset-Paginierung — dokumentierte Eigenschaft der RPC; bei künftigen Größenproblemen wird Server-Suche ein Gap, kein Ad-hoc-Query).
- Filter (Mitglieder): Rolle (typisiertes `DropdownButtonFormField<String?>`, `null` = „Alle Rollen" — Harvest des Legacy-Rollenfilters, `'all'`-Sentinel stirbt per Foundation §7) und Status (`MembershipStatus?`, `null` = „Alle aktiven"). **Default: Entzogene ausgeblendet**; expliziter Statusfilter „Entzogen" zeigt sie. Zähler-Badge „N Mitglieder" in der Filterleiste (Legacy-Harvest).
- Sort: Default Name aufsteigend (clientseitig, vollständige Liste), sekundär `created_at`; Spaltensortierung Name/Rolle/Status/Datum clientseitig erlaubt (vollständige Daten, kein Keyset-Verstoß).
- Aktivität: Zeit absteigend, keyset „Weitere laden"; Filter auf Ereignistyp optional erst mit realem Bedarf.
- Filterzustand screen-lokal, Reset bei Workspace-Wechsel.

## 12. Forms and validation

- **Einladen** (Modal, Foundation §10): E-Mail (Pflichtfeld, „Pflichtfeld" / Formatfehler deutsch), Rolle (Pflicht, Default: keine Vorauswahl — bewusst gegen die heutige stille `roles.first`-Vorauswahl, damit die Rollenwahl eine Entscheidung ist; Least-Privilege-Hinweistext „Wähle die Rolle mit den wenigsten nötigen Berechtigungen."), Grund (optional, max. 500). Buttons `TextButton('Abbrechen')` + `FilledButton('Einladen')` mit Progress. Server-Validierung mappt auf Felder (E-Mail-Duplikate inline).
- **Rolle ändern** (Modal): Dropdown + Capability-Diff (§6.3), Grund optional. Versionskonflikt-UX per Foundation §10 (Banner, „Neu laden"/„Erneut speichern", Eingabe bleibt).
- **Bestätigungsdialoge** (Suspendieren/Reaktivieren/Entziehen/Einladung widerrufen): Objekt namentlich, Konsequenz in einem Satz, Verb als Confirm, Grund-Feld optional; destruktiv (Entziehen, Widerrufen) in Fehlerfarbe. Dirty-Discard-Bestätigung bei Dialogschließen mit Eingaben.

## 13. Shared components

### Existing components to reuse
`AppScaffold.cloud`-Shell (unverändert), `NxPageHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `ListFilterTemplate`/`ListFilterBar`, `NxDataTableShell` (+ mandatorischer `mobileChild`), `NxCard`, `NxStatusBadge`, `NxEmptyState`, `ResponsiveConstraints`; aus Wave 1: `NxListSkeleton`, `NxSplitView`, `NxNotice`.

### Small extensions needed
Keine an Shared-UI. (Falls `NxSplitView` bei Implementierungsbeginn noch fehlt, blockiert das Paket auf `UX-FOUNDATION-IMPL-01` statt eine private Kopie zu bauen.)

### New shared component candidate
`RoleCapabilityList` (Anzeige einer Capability-Menge mit Anzeigename+Key, kollabierbar) entsteht **screen-lokal** unter `identity_access/presentation/widgets/`; Promotion zu `Nx*` erst, wenn ein zweiter Konsument existiert (Master Plan §7).

## 14. Backend gaps

**In-Package (keine Server-Änderung, reine Client-Reads auf bestehenden Policies — deshalb kein eigenes Backend-Paket):**
- `MembershipAdminRepository.listRolePermissions(workspaceId)` — Select auf `role_permissions` join `permissions` (RLS `workspace.read` existiert). Für Rollen-Tab und Capability-Diff.
- Membership-Audit-Read (Inkrement 2) — Select auf `audit_events` gefiltert workspace + entity_type, keyset-paginiert (RLS `audit.read` existiert). Bewusst minimal; das generische Audit-Screen-Paket bleibt `AUDIT-01`.

**Echte Gaps (eigene Pakete, hier nur benannt):**

| Gap | Bedarf | Domain | Schema/RLS? | Paket |
|---|---|---|---|---|
| Membership-Realtime | Invalidation-Publikation `memberships` + `membership_invitations`, Degraded-Wiring | identity_access | Publikation/Policies ja | `MEMBERSHIP-REALTIME-01` |
| Einladungs-Zustellung | E-Mail an Eingeladene (SMTP/Edge), erst dann ergäbe „Erneut senden" Sinn | identity_access | Funktion ja | `INVITE-DELIVERY-01` (optional) |
| Letzte Aktivität | `last_sign_in_at` in Directory-RPC | identity_access | RPC-Änderung | `MEMBER-ACTIVITY-01` (optional, nur bei echtem Bedarf) |
| Gruppen/Teams | Tabellen, Contract, RLS, UI | identity_access | ja, substanziell | Future — erst Produktentscheidung; in dieser Spec REJECT |
| Rollen-Pflege, feinere Capability-Zuordnung | Rollen-CRUD, Katalog-Verfeinerung | identity_access | ja | `PERMISSION-CATALOG-02` (existiert, NICHT Teil dieses Pakets) |
| Workspace-Settings | Settings-Contract inkl. Rename | core | ja | `SETTINGS-01` (blocked, unverändert) |
| Einladungs-Ablauf | Expiry-Feld + Enforcement | identity_access | ja | optional, nicht geplant |

Keine UI dieses Screens suggeriert einen Zugriff, den RLS/RPCs nicht gewähren; jede Aktion entspricht exakt einer bestehenden RPC.

## 15. Accessibility and usability

Tokens-Kontrast, Touch-Targets ≥ 44px, Tooltips auf Icon-Buttons und allen disabled Auslösern (Capability/AAL2 benennend), Fokus-Trap + Escape/Enter in Dialogen, Fokus auf erstem Feld, Badge-Text statt Farbe als Bedeutungsträger, DataRow-Semantik text-first (Foundation §16). Destruktive Klarheit über benannte Objekte + Konsequenzsatz statt Tipp-Hürden (Foundation §14; der Audit-Trail ist serverseitig).

## 16. Analytics / audit / history

- Jede Mutation erzeugt serverseitig ein Audit-Event (bereits implementiert: Aktion, Akteur, role_key-Snapshot, old/new, reason, correlation/mutation-id). Die UI ergänzt nichts und loggt keine sensiblen Payloads clientseitig.
- Sichtbar gemacht werden (Inkrement 2, Tab „Aktivität"): Einladung angelegt/angenommen/widerrufen, Rollenwechsel, Suspendierung/Reaktivierung, Entzug — exakt die vom Prompt geforderten Ereignisklassen; Permission-Änderungen an Rollen selbst erscheinen erst, wenn `PERMISSION-CATALOG-02` solche Events erzeugt.

## 17. Test plan

### Unit/application
- Controller: Phasenübergänge je Tab (idle/loading/ready/empty/forbidden/error), Generation-Guards, Action-Phasen inkl. `versionConflict`-Payload; Capability-Diff-Berechnung; Statusfilter-Default (revoked ausgeblendet).

### Widget/UI
- Keys `admin-members-*` (kebab-case, Foundation §17), keine Copy-Bindings. Abgedeckt: Tab-Rendering, Tabelle + `mobileChild`, Filter (typisierte nullable Dropdowns), disabled-mit-Tooltip ohne AAL2, hidden bei Capability-Entzug, Invite-Dialog-Validierung, Rolle-ändern-Dialog inkl. Diff und Konfliktbanner (Eingabe bleibt erhalten), destruktive Dialoge mit benanntem Objekt, Last-Manager-Fehlertext.

### Repository/integration
- Adapter: neue Reads `listRolePermissions`/Audit-Read (Mapping, Fehlerklassen). Bestehende Adapter-/Integrationstests (`supabase_membership_admin_*`) bleiben grün; pgTAP-Suiten 008/009 unverändert maßgeblich für Server-Verhalten.

### Staging E2E
- Golden Path: Einladen (beide Outcomes), Rolle ändern, Suspendieren/Reaktivieren, Entziehen, Einladung widerrufen — je mit Audit-Event-Nachweis.
- Negativ: ohne `security.manage` → Sidebar versteckt + Deep-Link Forbidden + Directory-RPC forbidden; ohne AAL2 → Auslöser disabled und RPC-Ablehnung falls erzwungen; Last-Manager-Guard bei Suspend/Revoke/Rollenwechsel; Versionskonflikt durch Parallel-Mutation; Mid-Session-Entzug räumt fail-closed.
- Paket B: Eingeladener ohne Workspace sieht und akzeptiert seine Einladung auf der Gate-Fläche.

## 18. Acceptance criteria

1. Ein Nutzer mit `security.manage` sieht unter „Mitglieder" das vollständige Verzeichnis mit Name, E-Mail, Rolle, Status und Datum; Entzogene sind per Default ausgeblendet und per Statusfilter sichtbar.
2. Ohne `security.manage` ist die Destination in der Sidebar unsichtbar; `/members` rendert den Forbidden-State mit „(security.manage)"; die Directory-RPC verweigert serverseitig.
3. Mit `security.manage` ohne AAL2 sind sämtliche Mutations-Auslöser disabled mit erklärendem Tooltip, der MFA-Hinweis ist sichtbar, Lesen funktioniert vollständig.
4. Einladen mit existierender Auth-E-Mail erzeugt eine `invited`-Membership im Mitglieder-Tab; mit unbekannter E-Mail eine Einladung im Einladungen-Tab; Duplikate zeigen den Serverfehler inline, ohne Eingabeverlust.
5. Rollenwechsel zeigt vor dem Speichern die hinzukommenden und entfallenden Berechtigungen; Wechsel von/zu einer `security.manage`-Rolle verlangt eine explizite Bestätigung mit Konsequenzsatz.
6. Suspend/Revoke/Rollenwechsel des letzten aktiven `security.manage`-Inhabers wird serverseitig abgelehnt und in der UI mit verständlichem Text erklärt — keine UI verhindert die Aktion nur clientseitig.
7. „Zugriff entziehen" ist als endgültig beschriftet; es existiert keine Restore-Aktion.
8. Ein Versionskonflikt verwirft niemals Eingaben: Dialog bleibt offen, nennt den Serverstand, bietet „Neu laden" und „Erneut speichern".
9. Jede der Mutationen erzeugt genau ein Audit-Event mit Akteur, Ziel und (falls angegeben) Grund; Inkrement 2 zeigt diese Ereignisse mit `audit.read` chronologisch an.
10. Der Rollen-Tab zeigt je Rolle die enthaltenen Berechtigungen read-only; nirgends existiert ein Auslöser zum Anlegen oder Ändern von Rollen.
11. Kein Klartext-Passwort und kein Passwort-Dialog existiert irgendwo im Admin-Bereich; der Legacy-`UsersScreen` ist nach Abschluss aus dem Build entfernt.
12. Alle drei Golden-Viewports + 320-Floor rendern ohne Overflow; der Mitglieder-Tab hat einen funktionierenden `mobileChild` mit „Zur Liste"-Rückweg im Narrow-Detail.

## 19. Out of scope

- Rollen anlegen/ändern/löschen, Capability-Zuordnung, Permission-Matrix-Editor (→ `PERMISSION-CATALOG-02`).
- Gruppen/Teams, Gäste, Restricted/Temporary Members, Owner-/Transfer-Konzepte.
- Workspace-Settings jeder Art (→ `SETTINGS-01`), SSO/SCIM/Sessions.
- E-Mail-Zustellung und „Erneut senden" (→ `INVITE-DELIVERY-01`), Einladungs-Expiry, „Letzte Aktivität".
- Membership-Realtime-Backend (→ `MEMBERSHIP-REALTIME-01`); der generische Audit-Screen (→ `AUDIT-01`).
- Jede Änderung an Auth/AAL/RLS/Storage-Sicherheitsgrenzen.

## 20. Open decisions

Alle materiellen Entscheidungen sind geschlossen (2026-08-28):

1. **Sidebar-Label: ENTSCHIEDEN — „Mitglieder".** Umgesetzt als Foundation-Amendment AMD-001 (§3); implementiert in Paket A1.
2. **Aktivität-Tab: ENTSCHIEDEN — bleibt Inkrement 2 (Paket A2) dieses Admin-Pakets.** Akzeptanzkriterium 9 gilt vollständig.
3. **Ort der Accept-Fläche: ENTSCHIEDEN — Workspace-/Gate-Fläche.** Paket B gehört fachlich zu Core/Auth/Workspace-Gate und wird dort eigenständig geplant/implementiert; die frühere Abstimmungsabhängigkeit zum Property-Workspace-Planungspaket entfällt. Einzige verbleibende Koordinationsregel: Sollte ein anderes Paket dieselbe Gate-Präsentationsdatei parallel anfassen, entscheidet die Integration die Merge-Reihenfolge (Master Plan §6) — das ist Routine, keine Planungsabhängigkeit.

Keine offene Entscheidung blockiert die Implementierung; Status ist APPROVED.

## 21. Implementation handoff

**Paketschnitt:**
- **A1 — Admin-Screen V2** (dieser Spec-Kern): Umzug der Präsentation aus `reference_slice/` nach `lib/features/identity_access/presentation/`, Tabs Mitglieder/Einladungen/Rollen, Split-Detail, Dialoge, Filter-Harvest, deutsche Copy, Keys `admin-members-*`; Adapter-Reads `listRolePermissions`; Foundation-Amendment AMD-001 (Sidebar-Label „Mitglieder", Ein-Zeilen-Änderung in `app_navigation.dart`); Legacy-`UsersScreen` + zugehörige Tests entfernen (Harvest ist mit dieser Spec abgeschlossen).
- **A2 — Aktivität** (Inkrement 2, eigener PR, Bestandteil dieses Admin-Pakets): Audit-Read + Tab.
- **B — Invite-Accept-Verlagerung** (eigener kleiner PR, Domäne Core/Auth/Workspace-Gate): Pending-Zone auf der Workspace-Auswahl-/Gate-Fläche; Entfernen der Zone aus dem Admin-Screen erst in diesem PR. Keine Planungsabhängigkeit zu anderen Wave-2-Paketen.
- Getrennt und nicht Teil dieses Screens: `MEMBERSHIP-REALTIME-01`, `INVITE-DELIVERY-01`, `PERMISSION-CATALOG-02`.

**Voraussetzungen auf main:** `UX-FOUNDATION-IMPL-01` (für A1). **Harte Invarianten:** keine Schema/RLS/RPC-Änderungen; AAL2-/`security.manage`-Gates unangetastet; Contract-Statusmaschine exakt wie dokumentiert; `mutationId`/`expectedVersion`-Envelope bei jeder Mutation; fail-closed bei fehlendem Scope. **Tests:** §17. Die Implementierungs-Chats inspizieren vor jeder Änderung den dann aktuellen Repo-Stand.
