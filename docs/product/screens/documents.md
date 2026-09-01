# Dokumente & Compliance (DOCUMENTS-V2)

## Metadata

- Package / screen ID: `DOCUMENTS-COMPLETE-01` (Tracker Wave 2, Workspace-/Registry-Teil) / Screen-ID `DOCUMENTS-V2`
- Domain: `documents_compliance`
- Route: `/documents` (`GlobalPage.documents`, Sidebar „Dokumente & Berichte → Dokumente", `routeKey` `documents_reporting.documents`); Surface `/compliance` (`CloudRouteSurface.compliance`). Die objekt-gebundene Surface `/property-documents/<id>` gehört zur freigegebenen Schwester-Spec [PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md) und wird hier nicht neu geplant.
- Current implementation file(s):
  - `lib/ui/screens/docs/documents_workspace_panel.dart` (KEEP, Basis Inkrement A)
  - `lib/ui/screens/docs/compliance_dashboard_screen.dart` (KEEP, Basis Inkrement C)
  - `lib/ui/screens/docs/widgets/*` (Tabelle, Detail, Dialoge, Badges — gemeinsame Widget-Basis)
  - `lib/ui/screens/docs/documents_screen.dart` (4-Tab-Legacy-Host, zur Laufzeit tot — REMOVE)
  - `lib/ui/screens/docs/legacy_document_rules_tabs.dart` (SQLite-Registry-Tabs — Harvest, dann REMOVE; Neubau contract-basiert in B1)
  - `lib/features/documents_compliance/application/document_repository.dart` (Contract, bleibt unverändert)
  - `lib/features/documents_compliance/data/supabase_document_repository_adapter.dart` (Adapter, bleibt unverändert)
- Planning status: APPROVED für die Inkremente **A, B1, C** (2026-09-02); **B2 blocked(product decision)** — siehe Scope-Klassifikation unten
- Dependencies: `UX-FOUNDATION-IMPL-01` merged (`3a11b09`, PR #43) — `NxSplitView`, `NxListSkeleton`, `NxNotice`, `NxLiveUpdatesNotice`, `NxEmptyState.error`, `AppLayout.splitViewMinWidth` sind auf `main`; keine offene Voraussetzung.
- Related screens: [PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md) (Property-Teil desselben Pakets, APPROVED), [PROPERTY_WORKSPACE_V2.md](PROPERTY_WORKSPACE_V2.md) (Rehosting der Objekt-Fläche), `AUDIT-01` (Wave 3), `REALTIME-DEGRADED-WIRING-01` (Wave 1).

Basis der Analyse: `origin/main` `421e6cb` (2026-09-02), revalidiert gegen `2b35d1a` (2026-09-04). Alle Aussagen zu Contract, RPCs, RLS, Storage-Policies und AAL sind gegen Code und Migrationen verifiziert (`20260723100000_p2_d03_documents_compliance.sql`, `20260723110000_p2_d03_document_realtime.sql`, `20260729100000_p2_d03_workspace_requirements.sql`, `20260812100000_security_aal_enforcement.sql`), nicht aus Docs übernommen. `PERMISSION-CATALOG-02` (`20260904100000_permission_catalog.sql`) bestätigt `document.read`/`document.manage`/`document.verify` als exakten Katalog dieser Domäne.

### Inkremente und Scope-Klassifikation (bindender Planungsstand, nicht neu verhandelt)

| Inkrement / Thema | Klassifikation | Inhalt |
|---|---|---|
| `DOCUMENTS-V2-A` — V2-Host + Workspace-Register | **APPROVED** | Tab-Host der Destination, Register-Liste/-Detail inkl. Foundation-Konvergenz, Signed-URL-Open-Flow, Host-/Provider-/Palette-Abriss (§21) |
| `DOCUMENTS-V2-B1` — Registry auf bestehendem Contract | **APPROVED** | Tabs „Typen" und „Pflichtregeln" auf `RequirementPolicyRepository` (Upsert-Semantik, kein Löschen) |
| `DOCUMENTS-V2-B2` — Katalog-Entscheidung | **BLOCKED (product decision)** | offene Produktentscheidung zum Dokumenttyp-Katalog (u. a. kuratierte Standard-/Vorbefüllung); B1 bleibt bis dahin beim per-Workspace-Upsert-Contract |
| `DOCUMENTS-V2-C` — Compliance | **APPROVED** | Compliance-Tab (Konvergenz der bestehenden serverseitigen Auswertung, state-first Navigation) |
| Workspace-/Complete-Query (Volltextsuche, Server-Sort, vollständige Query) | **BLOCKED** → `DOCUMENTS-QUERY-DATA-01` (§14) | keine Suche im freigegebenen Inkrement (§11) |
| Registry-/Link-Realtime | **BLOCKED** → `DOCUMENTS-REALTIME-01` (§14) | Register bleibt Invalidation-only, Registry/Compliance Pull (§9) |
| Ablauf-Reminders | **BLOCKED** → `DOCUMENTS-REMINDERS-01` (§14) | keine Benachrichtigungen aus Compliance-Zuständen |
| Drag & Drop · Inline-PDF-Preview · Retention-Automatik · Custom Lists · Bulk-Aktionen · OCR/AI · Annotationen · Clipboard-Sharing signierter URLs | **FUTURE** | ausdrücklich nicht geplant (§19) |
| Objekt-Medien/Bilder | separates Property-Backend-Paket | `PROPERTY-MEDIA-DATA-01` (bestehend, blocked; „Documents nicht zweckentfremden") |

Diese Klassifikation ist der bereits getroffene Documents-V2-Planungsstand. Diese Datei dokumentiert und präzisiert ihn; sie stuft nichts stillschweigend von BLOCKED/FUTURE auf APPROVED um.

---

## 0. Referenz-Benchmark (SharePoint / Google Drive / Compliance-Tracker) und Adopt/Adapt/Reject

Untersucht wurden die Muster einer **SharePoint/OneDrive-Dokumentbibliothek** (Metadaten-Spalten, Versionshistorie ohne Überschreiben, Genehmigungs-/Prüf-Flows, Aufbewahrungsrichtlinien), **Google Drive** (einfacher Upload, Vorschau, Freigabe-Links) und der Zustandslogik von **Compliance-Trackern** (Vanta/Drata-artige Kontroll-Checklisten; Verwaltungssoftware mit Ablaufverfolgung je Objekt, z. B. Energieausweis-Fristen). Leitidee: **Bibliothek mit Metadaten und unveränderlicher Versionshistorie + Prüf-Workflow + ehrliche Anforderungs-Checkliste** — kein generisches DMS, kein Datei-Explorer.

| Muster | Quelle | Entscheidung | Begründung / NexImmo-Fassung |
|---|---|---|---|
| Bibliothek = Liste mit Metadaten-Spalten + Detailbereich statt Ordnerbaum | SharePoint | **Adopt** | Ist bereits die Gestalt des Workspace-Panels (Spalten Typ/Version/Verifikation/Gültig bis, Split-Detail). Ordner gibt es im Contract nicht; Struktur entsteht über Typen, Ebenen und Entitäts-Verknüpfungen. |
| Versionen werden nie überschrieben; Historie sichtbar | SharePoint | **Adopt** | Bei uns strukturell erzwungen: der `documents`-Bucket hat **keine** UPDATE-/DELETE-Policy, Pfade sind global unique; die UI zeigt die Versionsliste mit Hash/Größe/Dateiname. |
| Genehmigungs-/Prüfschritt mit Vermerk | SharePoint-Approvals | **Adapt** | Zweistufig entlang des Contracts: „Upload bestätigen" (serverseitiger Hash-/Größen-Abgleich) → „Verifizieren/Ablehnen" mit Prüfnotiz, eigene Capability `document.verify`. Kein frei konfigurierbarer Workflow. |
| Compliance-Checkliste mit Zustands-Ampel je Anforderung | Vanta/Drata, Verwalter-Software | **Adopt** | `DocumentRequirementState` (9 Zustände, serverseitig abgeleitet, 45-Tage-Ablauffenster) existiert; der Compliance-Tab zeigt KPI-Zeile + Findings-Tabelle mit ehrlichen Coverage-Hinweisen. |
| Policy-/Regel-Registry als Admin-Fläche (welche Nachweise sind wo Pflicht) | Compliance-Tracker | **Adopt** | Kern von B1: Tabs „Typen" und „Pflichtregeln" auf `RequirementPolicyRepository` (`upsert_document_type`/`upsert_required_document` existieren serverseitig; einzige bisherige UI sind die toten SQLite-Tabs). |
| Volltextsuche über die Bibliothek | SharePoint/Drive | **Reject → BLOCKED-Gap** | Der Contract hat kein Text-Prädikat; eine Client-Suche über geladene Keyset-Seiten würde Vollständigkeit vortäuschen. Suche kommt erst mit `DOCUMENTS-QUERY-DATA-01` (§11/§14). |
| Drag-&-Drop-Multi-Upload | Drive | **Reject → FUTURE** | Der Contract ist Ein-Datei-je-Version (`create_document`/`add_document_version`). |
| In-App-Vorschau (Inline-PDF) | Drive/SharePoint | **Reject → FUTURE** | Freigegeben ist nur das direkte Öffnen über eine unmittelbar zuvor gemintete signierte Kurzzeit-URL (§6.7); ein eingebetteter Viewer ist eine spätere Produktidee. |
| Freigabe-/Sharing-Links, externe Empfänger, Clipboard-Sharing | Drive | **Reject** | Signierte Kurzzeit-URLs sind das einzige Zugriffsmodell und werden weder persistiert noch geloggt noch in die Zwischenablage gelegt (§6.7/§8); Clipboard-Sharing wäre eine neue Produkt-/Security-Entscheidung (FUTURE). |
| Aufbewahrungs-Automatik (Retention-Enforcement, Auto-Löschung) | SharePoint | **Reject → FUTURE** | `retention_until` ist informativ; es gibt **keinen Löschpfad** (OPN-DOM-005 bewusst offen). Die UI erfindet keine Löschung. |
| Ablauf-Erinnerungen/Benachrichtigungen | Verwalter-Software | **Reject → BLOCKED-Gap** | Keine Notification-Pipeline im Contract; `DOCUMENTS-REMINDERS-01` (§14) reitet später auf der Plattform-Pipeline. Das Dashboard zeigt „Läuft ab (in 45 Tagen)" als Pull-Sicht. |
| Papierkorb / Löschen mit Wiederherstellung | Drive/SharePoint | **Reject** | Es existiert kein Delete-RPC, keine DELETE-Storage-Policy, kein `deleted_at`. Archivieren ist terminal und ausdrücklich „Gelöscht wird nichts". |

## 1. Purpose

Der Workspace-Dokumentbereich beantwortet drei Fragen: **Welche Nachweise haben wir (in welcher Version, geprüft oder nicht), welche Nachweise verlangen wir wo, und wo fehlt etwas?** Dieses Paket liefert den noch offenen Workspace-/Registry-Teil von `DOCUMENTS-COMPLETE-01`: Die Registry (Dokumenttypen, Pflichtregeln) bekommt ihre Cloud-UI auf dem seit P2-D03 existierenden Contract (B1), die heute zusammenhanglosen Workspace-Surfaces (Register, Compliance) werden als **eine Destination mit Tabs** erschlossen (A, C), der tote 4-Tab-Legacy-Host samt `documentsRequestedTabProvider` und Palette-Sprung wird abgerissen (A). Die objekt-gebundene Dokumentfläche ist separat freigegeben ([PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md)); Objekt-Medien bleiben das bestehende, geblockte Backend-Paket `PROPERTY-MEDIA-DATA-01`. Es ist bewusst **kein DMS-Klon**: keine Ordner, kein Löschen, kein Sharing, keine Vorschau, keine vorgetäuschte Suche.

Ist-Befund, den dieses Paket behebt: Die Compliance-Fläche ist in der Shell heute faktisch **nur per URL erreichbar** (Sidebar „Dokumente" mountet ausschließlich `DocumentsWorkspacePanel`, `app_scaffold.dart:398-411`); ihr Zeilen-Klick stapelt per `Navigator.pushNamed` eine zweite Shell (`app_scaffold.dart:399-404`, Verstoß gegen Foundation §2); beide Neben-Surfaces hängen in `SingleChildScrollView` mit hartem `EdgeInsets.all(AppSpacing.xl)` (Verstoß §4/§15); die Registry existiert nur als tote SQLite-Tabs mit „Loeschen"-Buttons; die Register-Suche filtert nur bereits geladene Keyset-Seiten und täuscht damit Vollständigkeit vor.

## 2. Primary users and jobs

- **Verwalter:in / Analyst:in** (`document.manage`): pflegt das Workspace-Register (Upload, Versionen, Bestätigen, Ersetzen, Archivieren) und die Registry (Typen, Pflichtregeln); will zuerst die Liste mit Status/Typ/Gültigkeit, dann Aktionen am Detail.
- **Prüfer:in** (`document.verify`): verifiziert oder lehnt inhaltlich bestätigte Versionen ab, mit Prüfnotiz. Verifikation und Ablauf sind getrennt: ein abgelaufenes Dokument kann verifiziert sein, ein verifiziertes kann ablaufen (Contract-Doktrin, Dialog-Copy existiert).
- **Nur-Leser:in** (`document.read`): findet Dokumente über die serverseitigen Filter, öffnet Inhalte über kurzlebige signierte URLs, sieht den Compliance-Stand.
- **Objektverantwortliche:r**: arbeitet auf der Objekt-Dokumentfläche — geplant in [PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md), nicht hier.
- Ein **AAL1-Lese-Modus existiert nicht** (anders als der Members-Screen vor DEC-025): seit `20260812100000` verlangt `private.has_workspace_permission` selbst AAL2 — sämtliche Reads und Mutationen der Domäne sind serverseitig AAL2-gebunden, und die Shell mountet ohnehin erst nach TOTP (`SupabaseSecurityGate`).

## 3. Entry points and navigation

- Sidebar: Gruppe „Dokumente & Berichte" → „Dokumente" (`cloudReadPermissionForPage` = `document.read`; Sidebar versteckt, Deep-Link zeigt Forbidden — Foundation §3, unverändert). Kein Foundation-Amendment nötig: Label, Gruppe und Route bleiben.
- **Eine Destination, vier Tabs** (Foundation §9, ≤ 5): **Dokumente · Typen · Pflichtregeln · Compliance**. Das ersetzt den toten Legacy-Host `DocumentsScreen` durch einen V2-Host auf Contract-Basis. Wie im Property-Workspace gilt: **nicht implementierte Tabs bleiben verborgen** (A kann vor B1/C landen).
- Deep-Links: `/documents` → Tab „Dokumente"; `/compliance` → Tab „Compliance" (bestehende Surface-Auflösung `cloudRouteTargetFromName` bleibt; die Surface wählt nur den initialen Tab). Typen/Pflichtregeln bekommen **keine neuen URLs** bis `SHELL-ROUTING-01`; Tab-Zustand ist nicht URL-persistent, der Screen bleibt ohne URL voll erreichbar (Foundation §2).
- `/property-documents/<id>` bleibt die objekt-gebundene Surface (Schwester-Spec); Rehosting in den Property-Workspace regelt [PROPERTY_WORKSPACE_V2.md](PROPERTY_WORKSPACE_V2.md).
- **Compliance-Zeilen-Klick wird state-first:** statt `Navigator.pushNamed` setzt er das Routing-Ziel über die bestehenden Provider (Objekt-Dokument-Surface), wie es der Legacy-Host bereits vormachte (`documents_screen.dart:118-124`). Kein Screen baut eigene Navigator-Flows (Foundation §2).
- **Abriss:** `documentsRequestedTabProvider` (`app_state.dart:173`) und der Palette-Case `jump_missing_documents` (`navigation_actions.dart:103-106`) entfallen ersatzlos — die Palette ist im Cloud-Modus deaktiviert, ihr Wiedereinstieg ist `SHELL-PALETTE-01`; Tab-Ziele über Int-Provider sind ein totes Muster. Cross-Screen-Ziele laufen ausschließlich über `CloudRouteSurface`.
- Von hier Weiter-Navigation nur: Compliance-Finding → Objekt-Dokumentfläche. Breadcrumbs `['Dokumente & Berichte', 'Dokumente']` sind Labels (Foundation §5).

## 4. Information architecture

1. `NxPageHeader`: Titel „Dokumente", Breadcrumbs, Untertitel „Alle Dokumente des Arbeitsbereichs mit Status, Version und Verifikation an einer Stelle." (bestehende Copy); `secondaryActions` je nach Tab (§5); **Primäraktion folgt dem aktiven Tab** (§20): „Dokument hinzufügen" · „Dokumenttyp anlegen" · „Pflichtregel anlegen" · — (Compliance hat keine Create-Aktion). Es ist stets höchstens ein `FilledButton` sichtbar (Foundation §5), disabled ohne `document.manage`.
2. Notice-Zone unter dem Header: `_ContentRejectedNotice` → `NxNotice` („Upload abgelehnt", schließbar); später `NxLiveUpdatesNotice`, sobald `REALTIME-DEGRADED-WIRING-01` das Degraded-Flag der Domäne verdrahtet (§9).
3. Tabs (`NxCard`-gerahmt, `isScrollable`, `TabAlignment.start` — wie heute im Host).
4. Tab-Inhalt: Liste/Tabelle mit Filterleiste (Dokumente, Typen, Pflichtregeln), KPI-Zeile + Findings-Tabelle (Compliance).
5. Split-Pane-Detail im Dokumente-Tab (Foundation §8): rechts Titel + Status-Badge, Fakten, Verknüpfungs-Zusammenfassung, Aktionen, Versionsliste.

## 5. Layout and interaction model

- **Frame:** `ListFilterTemplate` je Tab-Inhalt, `context.adaptivePagePadding`; die `SingleChildScrollView`-Wrapper mit hartem Padding um die Compliance-Surface entfallen (Scrollen übernehmen die Inhaltsbereiche selbst, Foundation §15).
- **Tab „Dokumente"** (Inkrement A; Basis: bestehendes Panel, Konvergenz statt Neubau):
  - Split per `NxSplitView` ab `AppLayout.splitViewMinWidth` (ersetzt die private `_splitViewBreakpoint = 1200`-Konstante), Verhältnis 3:2, Narrow-Modus ersetzt die Liste mit Rückweg „Zur Liste" (vereinheitlicht die heutige „Zurück zur Liste"-Copy).
  - Tabelle wie heute: Pflichtspalten „Dokument", „Status"; optionale Spalten „Typ", „Version", „Verifikation", „Gültig bis", „Aktualisiert" per Spaltenwähler (Default Typ/Version/Gültig bis); abgelaufenes „Gültig bis" in Fehlerfarbe; `'—'`/„Ohne Typ" für fehlende Werte; `mobileChild`-ListTiles mit `chevron_right` (existiert).
  - Filterleiste ohne Suchfeld (§11): Dokumenttyp-Dropdown (serverseitig, Einträge nach Ebene gruppiert) und Include-Toggle „Ersetzte und archivierte zeigen" ⇄ „Nur aktive zeigen" (serverseitig `includeInactive`). Das bisherige freistehende Ebenen-Dropdown als Listenfilter entfällt (es filterte nur geladene Seiten).
  - Keyset-„Weitere Dokumente laden" (Seitengröße 50, Reihenfolge `id` aufsteigend — dokumentierte Contract-Eigenschaft, §11).
  - Detail-Panel wie heute (Fakten „Aktuelle Version"/„Gültig ab"/„Gültig bis", Verknüpfungs-Satz, Aktionen §6, Versionsliste mit `dataMonoStyle`-Hash-Präfix, Größe, „Upload bestätigt am …", Prüfnotiz, „Öffnen" je Version); Ladeindikator `LinearProgressIndicator` in `NxCard` (Foundation §8).
- **Tab „Typen"** (Inkrement B1, Neubau): `NxDataTableShell` mit Spalten **Name · Key (`dataMonoStyle`) · Ebene · Standard-Gültigkeit („N Monate"/`'—'`) · Status** (`NxStatusBadge` „Aktiv"=success, „Inaktiv"=neutral) und Zeilenaktion „Bearbeiten"; ≤ 6 Spalten, kein Spaltenwähler; `mobileChild` verpflichtend. Filterleiste: Suche über Name/Key (zulässig, weil `listTypes` die **vollständige, nicht paginierte** Liste liefert — keine Keyset-Täuschung) und Toggle „Inaktive zeigen" (Default aus; `listTypes(activeOnly)` existiert). Hinweiszeile am Tab-Ende: „Dokumenttypen werden nie gelöscht — deaktivierte Typen bleiben für bestehende Dokumente und Regeln gültig benannt."
- **Tab „Pflichtregeln"** (Inkrement B1, Neubau): Der Contract listet Regeln **je Ebene** (`listRequirements(entityType erforderlich)`), zurückgezogene Regeln sind serverseitig ausgefiltert („Retired rules are history, not policy"). Deshalb führt eine **Ebenen-Auswahl** (typisiertes Dropdown, Default „Objekt") die Liste; darunter `NxDataTableShell` mit Spalten **Dokumenttyp · Geltung** („Alle {Ebene}" · „Objektart: {scope_key}" · „Instanz: {entityId-Kurzform}") **· Pflicht** („Pflicht"=warning / „Optional"=neutral, bestehende Badges) **· Frist/Gültigkeit** („bis {dueAt}" bzw. „{N} Monate gültig", sonst `'—'`) **· Zustand** („Aktiv" · „Angefordert" · „Nicht relevant" bei Verzicht) und Zeilenaktionen „Bearbeiten", „Zurückziehen". Kein Suchfeld. `mobileChild` verpflichtend.
- **Tab „Compliance"** (Inkrement C; Basis: bestehender Screen): KPI-Zeile auf `NxKpiRow`/`NxKpiTile` (ersetzt das private `_KpiRow`): „Offen" (error, „davon N pflichtig") · „Läuft ab" (warning, „in 45 Tagen") · „In Prüfung" (info, „Upload oder Verifikation offen") · „Erfüllt" (success, „verifiziert und gültig"). Coverage-Hinweise als `NxNotice` (drei bestehende Texte: „Nicht vollständig ausgewertet", „Eingeschränkte Abdeckung", „Teilweise ausgewertet"). Findings-Tabelle (Objekt · Dokumenttyp · Zustand · Fällig · Gültig bis, `minTableWidth` 820, Mobile-Tiles), Zeile → Objekt-Dokumentfläche (state-first, §3). Secondary: „Nur offene anzeigen" ⇄ „Alle anzeigen" (serverseitig `onlyUnmet`), „Aktualisieren".
- Dialoge per `ResponsiveConstraints.dialogWidth`; kein Modal über Modal. Golden-Viewports 390×844 / 1024×768 / 1440×900 + 320-Floor, hell und dunkel, ohne Overflow (Foundation §15).

## 6. Functional requirements

Alle Mutationen laufen ausschließlich über die bestehenden Ports (`DocumentRepository`, `DocumentContentPort`, `DocumentUploadPort`, `DocumentVerificationPort`, `RequirementPolicyRepository`, `SignedUrlPort`, `DocumentLinkPort`) — auditierte, idempotente, versionierte RPCs mit `{ok, entity}`-Envelope. **Keine Funktion wird erfunden:** kein Löschen (weder Dokument noch Typ noch Regel), kein Sharing, keine Vorschau, kein Multi-Upload, keine Volltextsuche. Statusmaschine strikt per Contract: `supersede` nur aus `available`/`verified`, `archive` aus allem außer `archived`; `processing` wird von keinem Kommando erzeugt (reserviert, UI erzeugt es nie und behandelt es nur als Badge).

### 6.1 Dokument hinzufügen
- Trigger: Primäraktion Tab „Dokumente" → Modal (heutiger Dialog): Titel (Pflicht), Dokumenttyp (optional, nur aktive Typen), „Gültig ab"/„Gültig bis" (Datumsauswahl 2000–2100, löschbar; Server erzwingt `valid_until >= valid_from`), Notiz (≤ 10 000), Datei (Pflicht; Client prüft > 0 und ≤ 50 MB mit den bestehenden Sätzen, der Bucket erzwingt das Limit unabhängig).
- **Neu (V2):** Bei Typwahl mit `defaultValidityMonths` und gesetztem „Gültig ab" wird „Gültig bis" vorbelegt (`ab + N Monate`, editierbar) — reine Client-Logik, das Feld existiert exakt dafür.
- Success: Upload in den privaten Bucket (`{workspace}/{scope}/{version}/{datei}`-Konvention) → `create_document`; SnackBar; Liste lädt nach. Der Dialog verknüpft bewusst **keine** Entität — die Erfolgsmeldung verweist wie heute auf den Dokumentbereich der betreffenden Entität.
- Failure: Validierung inline (Eingabe bleibt); `mutationConflict`/`infrastructureFailure` über Action-Feedback; abgelehnter Content-Abgleich → 6.3-Hinweis.
- Permission: `document.manage` (Button disabled mit Tooltip „Benötigt die Berechtigung (document.manage)").

### 6.2 Neue Version
- Trigger: Detail-Aktion „Neue Version" (nur aktive Dokumente) → Modal mit bestehender Copy („Die bisherige Version … bleibt unverändert erhalten und wird als ersetzt markiert.") + Dateiwahl.
- Success: Upload → `add_document_version` mit `expectedVersion` = Dokument-`version`; Versionsliste und Zeile aktualisieren. Ein Upload auf einen existierenden Pfad schlägt fehl statt zu überschreiben (keine UPDATE-Policy) — der Fehler wird als Konflikt erklärt, nie „stumm ersetzt".
- Failure: `versionConflict` → §10-Konflikt-UX. Permission: `document.manage`.

### 6.3 Upload bestätigen
- Trigger: Detail-Aktion, solange die aktuelle Version nicht content-bestätigt ist → Modal (bestehende Erklär-Copy zu Hash-/Größen-Abgleich und möglichem `rejected`).
- Success: `confirm_document_content`; bei Server-Ablehnung wechselt das Dokument auf „Abgelehnt" und die persistente `NxNotice` „Upload abgelehnt" erscheint (bestehendes Verhalten). Permission: `document.manage`.

### 6.4 Verifizieren / Ablehnen
- Trigger: Detail-Aktion „Verifizieren", erst nach Content-Bestätigung → Modal „Version {n} prüfen" (Radio Verifizieren/Ablehnen, Prüfnotiz; bestehende Copy zur Trennung von Ablauf und Verifikation). **Neu (V2):** optionales Feld „Grund (optional, wird protokolliert)" — die RPC nimmt `p_reason` bereits entgegen, kein UI-Pfad setzt ihn heute.
- Success: Badge/Status aktualisieren (`verified`/`rejected`). Permission: **`document.verify`** (eigene Capability; ohne sie ist die Aktion disabled mit Tooltip — sichtbar, damit das Zwei-Stufen-Modell lernbar bleibt).

### 6.5 Ersetzen (supersede)
- Trigger: Detail-Aktion „Ersetzen" → Modal mit Nachfolger-Dropdown (nur andere aktive Dokumente; leere Kandidatenliste → bestehender Hinweis-SnackBar) + optionaler Grund (neu, wie 6.4).
- Success: `transition_document_status(superseded)`; nur aus `available`/`verified` (Server erzwingt es, UI bietet es nur dort an). Failure: `versionConflict` → §10. Permission: `document.manage`.

### 6.6 Archivieren
- Trigger: Detail-Aktion → destruktiver Dialog (Foundation §14): benennt das Dokument, bestehende Konsequenz-Copy („… zählen nicht mehr für Anforderungen und lassen sich nicht wieder aktivieren. Gelöscht wird nichts — die Historie bleibt vollständig erhalten."), optionaler Grund, Confirm „Archivieren" in Fehlerfarbe (irreversibel).
- Success: Status `archived` (terminal); mit „Nur aktive zeigen" verschwindet die Zeile aus der Default-Sicht. Permission: `document.manage`.

### 6.7 Inhalt öffnen (bindende Security-Entscheidung)
- Trigger: Detail-Aktion „Inhalt öffnen" bzw. „Öffnen" je Version.
- Ablauf: `resolve_document_content_ref` + Signed-URL-Mint **unmittelbar vor dem Öffnen**, dann direktes Öffnen über `url_launcher` (Web: neuer Tab; Desktop: Systemhandler). Die signierte URL wird **nicht angezeigt, nicht in die Zwischenablage gelegt, nicht persistiert und nicht geloggt** (auch nicht in Telemetrie/Fehlermeldungen). Der bisherige „Download-Link"-Dialog mit `SelectableText` entfällt.
- Abgelaufene/fehlgeschlagene URL: neuer autorisierter Mint beim nächsten Öffnen — keine gespeicherte URL, kein Retry auf der alten.
- TTL: Default 5 min, Server-Ceiling 1 h, geklemmt (`SignedUrlPort.clampTtl`); für das Sofort-Öffnen genügt der Default.
- Permission: `document.read`. Clipboard-Sharing signierter URLs ist ausdrücklich **nicht** im Scope (FUTURE, eigene Produkt-/Security-Entscheidung).

### 6.8 Dokumenttyp anlegen / bearbeiten / deaktivieren (B1, Neubau)
- Trigger: Primäraktion Tab „Typen" bzw. Zeilen-„Bearbeiten" → Modal: Name (Pflichtfeld, 1–200), **Key** (nur beim Anlegen; Muster `^[a-z0-9]+([._-][a-z0-9]+)*$`, 2–100, je Workspace eindeutig; Vorschlag aus dem Namen; nach dem Anlegen unveränderlich — serverseitig geschützte Spalte — und im Dialog nur noch als `dataMonoStyle`-Anzeige), Ebene (typisiertes Dropdown über die `DocumentLinkEntityType`-Ebenen), Standard-Gültigkeit in Monaten (optional, 1–1200), Schalter „Aktiv" (nur Bearbeiten).
- Success: `upsert_document_type`; Zeile aktualisiert. Failure: Duplikat-Key/Validierung inline (Eingabe bleibt); `versionConflict` → §10.
- Deaktivieren ersetzt das Legacy-„Loeschen" ersatzlos: deaktivierte Typen verschwinden aus Auswahl-Dropdowns (Create-Dialog, Regel-Dialog), bleiben aber an bestehenden Dokumenten/Regeln benannt. Permission: `document.manage`.
- Ein kuratierter Standard-Typenkatalog/Vorbefüllung ist die offene **B2-Katalog-Entscheidung** (blocked) und wird hier nicht vorweggenommen.

### 6.9 Pflichtregel anlegen / bearbeiten (B1, Neubau)
- Trigger: Primäraktion Tab „Pflichtregeln" bzw. Zeilen-„Bearbeiten" → Modal: Ebene (Pflicht; beim Bearbeiten fix), Dokumenttyp (Pflicht; aktive Typen der Ebene, kaskadiert), Geltung „Alle {Ebene}" oder „Nur Objektart …" (`scope_key`, 1–100, Freitext wie legacy „Objektart (optional)"), Schalter „Pflichtdokument" (Default an), Frist (`dueAt`, optional), Gültigkeit in Monaten (optional, 1–1200), Notiz (≤ 4000). Zustands-Schalter beim Bearbeiten: „Angefordert" (`requested`) und „Nicht relevant (Verzicht)" (`waived`) mit **Pflicht-Begründung** (1–2000; Contract-Assertion „A waiver requires a reason (audited decision)").
- Der Tab legt **Workspace-/Objektart-Regeln** an (`entityId` bleibt leer); Instanz-Regeln einzelner Objekte entstehen auf der jeweiligen Entitätsfläche (→ [PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md)/[PROPERTY_WORKSPACE_V2.md](PROPERTY_WORKSPACE_V2.md)), werden hier aber angezeigt und sind zurückziehbar (§20).
- Success: `upsert_required_document` (der partielle Unique-Index hält je Geltung genau eine lebende Regel). Failure: Duplikat/Validierung inline; `versionConflict` → §10. Permission: `document.manage`.
- Feld `ownerUserId` bleibt ohne UI (kein Mitglieder-Verzeichnis-Read unterhalb `security.manage`; §14).

### 6.10 Pflichtregel zurückziehen
- Trigger: Zeilen-„Zurückziehen" → Bestätigungsdialog (Foundation §14): benennt Typ + Geltung, Konsequenz „Die Regel gilt ab sofort nicht mehr; bestehende Dokumente bleiben unberührt. Eine gleiche Regel kann später neu angelegt werden.", optionaler Grund, Confirm „Zurückziehen" in Fehlerfarbe.
- Success: Upsert mit `retired`; die Zeile verschwindet (zurückgezogene Regeln sind Historie und erscheinen nicht wieder — Audit ist die Historienquelle). Permission: `document.manage`.

### 6.11 Compliance auswerten (C)
- Automatisch beim Öffnen des Tabs: `evaluate_workspace_document_requirements` mit Objektverzeichnis aus dem Property-Contract (paginiert 100er-Seiten, Deckel 1000 Objekte) in **einem** Call; Toggle „Nur offene anzeigen" fragt serverseitig neu (`onlyUnmet`); „Aktualisieren" lädt neu. Zeilen-Klick → Objekt-Dokumentfläche (state-first). Coverage-Ehrlichkeit (Objektarten-Regeln nur gezählt; Verzeichnis gedeckelt oder ohne `property.read` nicht verfügbar) bleibt sichtbar. Permission: `document.read` (Objekt-Labels zusätzlich `property.read`, sonst „Eingeschränkte Abdeckung").

### 6.12 Aktualisieren und Filtern
- „Aktualisieren" je Tab; Filter: §11 (ausschließlich serverseitige bzw. auf vollständigen Listen arbeitende Filter).

## 7. Data requirements

Quelle Dokumente-Tab: `documents`-Select (RLS `document.read`) via Keyset; Detail zusätzlich `document_versions` und `document_links`. Felder (alle vorhandenen, keine Schemaänderung):

| Feld | Bedeutung | Quelle | Anzeige |
|---|---|---|---|
| Titel | Anzeigename (1–300) | `documents.title` | Pflichtspalte; Detail-Titel |
| Status | 7-Werte-Enum (STM-008) | `documents.status` | Badge: Hochgeladen/In Verarbeitung=warning, Verfügbar=info, Verifiziert=success, Ersetzt/Archiviert=neutral, Abgelehnt=error (bestehendes Mapping neben dem Enum) |
| Typ | `document_types.name` | Join im Client über geladene Typen | „Ohne Typ"/`'—'`-Fallbacks |
| Version | `current_version_no` | `documents` | numerisch (`tabularNumericStyle`) |
| Verifikation | pending/verified/rejected | `currentVersion.verificationStatus` | Badge „Prüfung offen"/„Verifiziert"/„Abgelehnt"; Spalte default aus (Listenzeilen tragen selten `currentVersion`) |
| Gültig ab/bis, Aufbewahrung bis | `date`-Felder | `documents` | `dd.MM.yyyy`, `'—'`; abgelaufen in Fehlerfarbe |
| Versionszeile | Datei-Metadaten | `document_versions` | `originalFilename ?? mimeType` · Binärgröße · `SHA-256 {12}…` · Bestätigungs-/Prüfdaten |
| Verknüpfungen | Ebenen-Zusammenfassung | `document_links` | „Verknüpft mit: {Ebenen-Labels}" bzw. bestehender Leersatz |
| Concurrency | `version` | `documents` | unsichtbar; nur in Konfliktbannern benannt |

Typen-Tab: `listTypes` (`DocumentTypeDto`: key, name, entityType, isActive, defaultValidityMonths, version) — vollständige Liste. Pflichtregeln-Tab: `listRequirements` je Ebene (`RequiredDocumentDto`: Geltung aus `entityId`/`scopeKey`, isMandatory, dueAt, validityMonths, note, requested/waived/waiverReason; zurückgezogene serverseitig ausgefiltert). Compliance: `WorkspaceDocumentRequirements` (`DocumentRequirementProjection` je lebender Regel: state — 9 Werte inkl. serverseitigem 45-Tage-„Läuft ab"-Fenster —, dueAt, documentId/Status/validUntil, isMandatory; `scopedRuleCount` für den Coverage-Hinweis). Ebenen-Labels: Arbeitsbereich, Objekt, Portfolio, Einheit, Mietvertrag, Partei, Instandhaltung, CapEx-Projekt, Szenario, Aufgabe (bestehend; `task` ist seit `NOTIFICATION-EMITTER-01` nur Registry-Wert — Dokument↔Task-Verknüpfung bleibt serverseitig geblockt, bis `TASK-ENTITY-REGISTRY-01` sie freigibt).

## 8. Permissions and security behavior

- Seite: `cloudReadPermissionForPage(documents)` = `document.read` (Sidebar versteckt; Deep-Link → Forbidden-State „(document.read)").
- Server-Doppelboden: alle fünf Tabellen default-deny mit einziger SELECT-Policy auf `document.read` (`force row level security`); Mutationen nur über `security definer`-RPCs, die `document.manage` (bzw. `document.verify` fürs Prüfen) explizit prüfen; Storage-Policies: SELECT auf `document.read`, INSERT auf `document.manage`, **kein UPDATE/DELETE** — Unveränderlichkeit ist strukturell, nicht UI-Disziplin.
- Capabilities in der UI: `document.read` gated die Seite; `document.manage` gated Anlegen/Version/Bestätigen/Ersetzen/Archivieren und die gesamte Registry; `document.verify` gated ausschließlich Verifizieren/Ablehnen. Auslöser ohne Capability sind **disabled mit Tooltip**, der die Capability nennt (lernbare Aktionen, Foundation §3); es gibt keine Bulk-/Admin-Aktionen, die zu verstecken wären. Die Denial-Copy „Für diese Aktion fehlt die Berechtigung." bleibt.
- **Signed URLs:** kurzlebig, unmittelbar vor dem Öffnen gemintet, direkt geöffnet; niemals persistiert, geloggt, angezeigt oder in die Zwischenablage gelegt (§6.7) — deckungsgleich mit der Regel der Property-Spec („nicht in Telemetrie/Clipboard-Automation/Logs persistieren").
- **AAL (DEC-025):** `private.has_workspace_permission` verlangt seit `20260812100000` AAL2 vor dem Rollen-Join — Reads liefern bei AAL1 nichts (fail closed), Mutationen laufen zusätzlich durch `private.document_command_gate` mit klarer Ablehnung („AAL2 is required for document mutations"). Die Shell ist nur nach TOTP erreichbar; die UI braucht deshalb keinen AAL-Sonderzustand, muss eine `forbidden`-Antwort aber als Forbidden-State rendern statt als generischen Fehler.
- `rbac.dart` trägt seit `PERMISSION-CATALOG-02` den kanonischen `serverCatalog` (für Dokumente exakt `document.read`/`document.manage`/`document.verify`, per Parity-Test und pgTAP gepinnt); die dort verbliebenen Alt-Konstanten `document.create/update/delete` sind Legacy-only und werden von V2 nirgends übernommen.
- Mid-Session-Entzug: Entitlement-Revalidierung räumt fail-closed; nächster Build rendert Forbidden. Client-Gating ersetzt nie RLS/RPC-Gates; dieses Paket ändert **keine** Policy, RPC oder AAL-Grenze.

## 9. Realtime / freshness behavior

- **Ist:** Invalidation-only über die `documents`-Publikation (UPDATE-Events je Workspace, debounced Reload, ein Reconcile pro (Re-)Subscribe). `link_document`/`unlink_document`/`upsert_required_document` (und Typ-Upserts) berühren keine `documents`-Zeile und lösen **keine** Invalidation aus — in Migration und Source dokumentiert; Cross-Table-Invalidation ist auf den P2-D04-`domain_events`-Umschlag vertagt.
- Spec-Verhalten: REST bleibt kanonisch; „Aktualisieren" je Tab; nach jeder eigenen Mutation gezieltes Nachladen des betroffenen Tabs. Registry- und Compliance-Tab sind damit Pull-Flächen — ehrlich, keine „Live"-Suggestion.
- Degraded: Das Controller-Flag und `NxLiveUpdatesNotice` unter dem Header kommen mit `REALTIME-DEGRADED-WIRING-01` (Wave 1); diese Spec ist so geschnitten, dass das Wiring keinen Umbau erfordert. Bis dahin kein Notice — eine „pausiert"-Meldung ohne Live-Kanal wäre gelogen.
- Gap `DOCUMENTS-REALTIME-01` (§14, **BLOCKED** per Planungsstand): Invalidation für Links/Typen/Regeln (Requirements-Frische), erst danach ist der Compliance-Tab live.

## 10. Screen states

Vokabular und Rendering strikt per Foundation §11, je Tab unabhängig (ein kaputter Compliance-Read blockiert nicht die Dokumentliste):

- initial loading: `NxListSkeleton` (alle Listen-Tabs; ersetzt `NxDataTableShell(loading: true)`-Spinner), `LinearProgressIndicator` in `NxCard` im Detail.
- background refresh: sichtbare Daten bleiben stehen; Refresh zeigt Progress.
- idle: „Kein Arbeitsbereich aktiv" (bestehend).
- empty: Dokumente „Noch keine Dokumente" + CTA (capability-gated); Typen „Noch keine Dokumenttypen" + CTA; Pflichtregeln „Noch keine Pflichtregeln für diese Ebene" + CTA; Compliance „Alles erfüllt" (bei „Nur offene") bzw. „Keine Anforderungen hinterlegt", jeweils mit „Zuletzt geprüft: …"-Suffix (bestehend).
- no-match (aktive Filter): Foundation-§7-Standard („Keine Treffer für diesen Filter.", „Filter zurücksetzen") — im Dokumente-Tab nur nach **serverseitig** leerer erster Seite unter Typ-/Include-Filter, nie als Ergebnis clientseitigen Aussiebens.
- forbidden: je Tab mit benannter Capability („(document.read)"; Compliance-Verzeichnis-Sonderfall bleibt der ehrliche Coverage-Hinweis statt Forbidden, §6.11).
- error: `NxEmptyState.error` + `FilledButton.icon(refresh, 'Erneut versuchen')` — der eine Retry-Stil.
- action in progress / success / failure: Action-Feedback-Muster (`ref.listen` → SnackBar, Submit-Buttons mit Progress und disabled).
- **conflict:** Foundation-§10-Konflikt-UX ersetzt den heutigen „Zwischenzeitlich geändert"-Dialog, der Eingaben verwirft: In offenen Dialogen bleibt die Eingabe erhalten (Banner nennt den Serverstand, „Neu laden" / „Erneut speichern"); bei zeilen-/detailbasierten Aktionen ohne Formular lädt das Detail den Serverstand und ein Hinweis erklärt es.
- contentRejected: persistente `NxNotice` „Upload abgelehnt" mit „Hinweis schließen" (bestehend).
- signed URL abgelaufen/fehlgeschlagen: transparenter neuer Mint beim nächsten Öffnen (§6.7), kein Fehlerdialog mit URL-Inhalt.
- realtime degraded: n/a bis zum Degraded-Wiring (§9).

## 11. Search / filter / sort

- **Dokumente (Register): keine Volltextsuche in diesem Inkrement.** `DocumentListQuery` hat kein Text-Prädikat; die bisherige Client-Suche filterte nur bereits geladene Keyset-Seiten und konnte „keine Treffer" behaupten, während ungeladene Server-Seiten Treffer enthalten — dieses Suchfeld entfällt ersatzlos. Ein Load-All-Workaround ist ausdrücklich verboten. Echte Suche/Sortierung/vollständige Query ist der geblockte Gap `DOCUMENTS-QUERY-DATA-01` (§14).
- **Dokumente-Filter (vollständig serverseitig):** Dokumenttyp (`documentTypeId`, Dropdown typisiert nullable, Einträge nach Ebene gruppiert — das bisherige freistehende Ebenen-Dropdown als clientseitiger Listenfilter entfällt mitsamt dem `'__all__'`-Sentinel, `documents_workspace_panel.dart:47`) und Include-Toggle (`includeInactive`, Default aus, aktiver Filter sichtbar). **Keine Spaltensortierung:** die Liste ist ein Keyset nach `id`; Sortierung partiell geladener Seiten ist per Foundation §7 verboten.
- **Typen:** vollständige, nicht paginierte Liste (`listTypes`) — clientseitige Suche über Name/Key und Default-Sortierung Name aufsteigend sind hier zulässig, weil die Daten komplett vorliegen; Toggle „Inaktive zeigen".
- **Pflichtregeln:** Ebenen-Auswahl als führender, serverseitiger Scope (Default „Objekt"); innerhalb der Ebene vollständige Liste, Default-Sortierung Dokumenttyp-Name aufsteigend, Geltung sekundär; kein Suchfeld.
- **Compliance:** „Nur offene anzeigen" (Default an, serverseitig); Reihenfolge wie vom Server geliefert; keine erfundene Client-Sortierung, keine clientseitig errechneten Compliance-Kategorien.
- Filterzustand screen-lokal, Reset bei Workspace-Wechsel; URL-Persistenz erst mit `SHELL-ROUTING-01`.

## 12. Forms and validation

- Pflichtfeld-Validatoren verwenden exakt „Pflichtfeld" (Foundation §10; die heutige Titel-Copy „Bitte einen Titel angeben." konvergiert). Buttons `TextButton('Abbrechen')` + `FilledButton('Anlegen'/'Speichern'/Verb)`; Submit mit Progress und disabled; Dirty-Discard-Bestätigung „Änderungen verwerfen?" beim Schließen mit Eingaben.
- **Dokument-Dialog** (6.1): Datei-Sektion mit bestehender Speicher-Erklär-Copy und Client-Checks (leer / > 50 MB); Gültigkeits-Prefill aus dem Typ (6.1); Server-Validierung mappt auf Felder.
- **Typ-Dialog** (6.8): Key nur beim Anlegen editierbar (Muster-/Längenfehler deutsch, inline), danach read-only; Duplikat-Key inline.
- **Regel-Dialog** (6.9): Geltungswahl „Alle {Ebene}" / „Nur Objektart" (+ Freitextfeld erscheint abhängig); Verzicht erzwingt Begründung („Pflichtfeld"); Duplikat einer lebenden Regel wird als Serverfehler inline erklärt.
- **Bestätigungsdialoge** (Archivieren 6.6, Zurückziehen 6.10, Ersetzen 6.5): Objekt namentlich, Konsequenz in einem Satz, Verb als Confirm in Fehlerfarbe, optionales Grund-Feld (max. 2000, wird als `p_reason` protokolliert).
- **Versionskonflikt** in jedem Formular per Foundation §10 (Banner, „Neu laden"/„Erneut speichern", Eingabe bleibt erhalten).

## 13. Shared components

### Existing components to reuse
`AppScaffold.cloud`-Shell (unverändert), `NxPageHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `ListFilterTemplate`/`ListFilterBar`, `NxDataTableShell` (+ `mobileChild`), `NxCard`, `NxStatusBadge`, `NxEmptyState` (+ `.error`), `NxKpiRow`/`NxKpiTile`, `ResponsiveConstraints`; aus Wave 1 (auf main): `NxSplitView`/`AppLayout.splitViewMinWidth`, `NxListSkeleton`, `NxNotice`, `NxLiveUpdatesNotice` (erst mit Degraded-Wiring).

### Small extensions needed
Keine an Shared-UI.

### New shared component candidate
Keine. Die Feature-lokalen Badges (`DocumentStatusBadge`, `DocumentVerificationBadge`, `DocumentRequirementStateBadge`, `document_badges.dart`) und die Requirement-Tabelle bleiben screen-lokal; Promotion erst bei einem zweiten Konsumenten außerhalb der Domäne (Master Plan §7). Die `NxVersionHistory`-Frage der Property-Spec bleibt dort verortet.

## 14. Backend gaps

**In-Package:** keine — sämtliche Reads und Mutationen der freigegebenen Inkremente existieren serverseitig (Registry-Upserts, Workspace-Evaluation, signierte URLs, Upload-Port). Genau deshalb sind A, B1 und C jetzt implementierbar.

**Gaps (bestehende IDs wiederverwendet; Klassifikation per bindendem Planungsstand):**

| Gap | Klassifikation | Bedarf | Domain | Schema/RLS? |
|---|---|---|---|---|
| `PROPERTY-MEDIA-DATA-01` (bestehendes Backend-Paket, Tracker Wave 2) | blocked(product/contract/security decisions) | privates Property-Media-/Titelbild-Contract; „Documents nicht zweckentfremden" — Bestandsbilder rendern, nichts kann neue hinzufügen (Galerie entfernt 2026-07-29) | portfolio_property | ja |
| `DOCUMENTS-QUERY-DATA-01` | **BLOCKED** | Workspace-/Complete-Query: Text-Prädikat, Sortkey, ebenen-/entitätsweite Filter in `DocumentListQuery`; Voraussetzung für jede Register-Suche (§11) | documents_compliance | RPC/Query ja |
| `DOCUMENTS-REALTIME-01` | **BLOCKED** | Invalidation für `document_links`, `document_types`, `required_documents` (P2-D04-`domain_events`-Umschlag), danach Degraded-Wiring auch für Registry/Compliance | documents_compliance | Publikation/Policies ja |
| `DOCUMENTS-REMINDERS-01` | **BLOCKED** | Ablauf-/Fehlt-Erinnerungen aus Compliance-Zuständen; reitet auf der Plattform-Notification-Pipeline (`TASKS-NOTIFICATIONS-01`/P2-D04) | documents_compliance / platform | ja |
| `DOCUMENTS-ACCESS-AUDIT-01` | optional (offen) | Zugriffs-Protokollierung signierter URLs (in der D03-Migration ausdrücklich als Lücke benannt; gehört zum P2-D04-Event-Umschlag) | documents_compliance | ja |
| `WORKSPACE-DIRECTORY-READ-01` | optional (offen) | Mitglieder-Auswahl für `ownerUserId` bräuchte einen Verzeichnis-Read unterhalb `security.manage` | identity_access | RPC/RLS ja |
| `DOCUMENTS-V2-B2` (Inkrement, kein Backend-Gap) | blocked(product decision) | Katalog-Entscheidung zur Registry (kuratierter Standard-Typenkatalog/Vorbefüllung) | documents_compliance | erst nach Entscheidung |

Keine UI dieses Screens suggeriert Zugriff, den RLS/RPCs nicht gewähren; jede freigegebene Aktion entspricht exakt einer bestehenden RPC bzw. Policy.

## 15. Accessibility and usability

Tokens-Kontrast, Touch-Targets ≥ 44 px, Tooltips auf Icon-Buttons und allen disabled Auslösern (Capability benennend), Fokus-Trap + Escape/Enter in Dialogen, Fokus auf erstem Feld, Badge-Text statt Farbe als Bedeutungsträger (Status, Verifikation, Anforderungszustand), Hash/Größe/Ablauf als Text, DataRow-Semantik text-first, destruktive Klarheit über benannte Objekte + Konsequenzsatz (Foundation §§14/16). „Öffnen" ist eine beschriftete Aktion, kein reines Icon. Die Umlaut-Defekte der Legacy-Tabs („Loeschen") sterben mit ihnen.

## 16. Analytics / audit / history

- Jede Mutation schreibt serverseitig genau ein `audit_events`-Ereignis (Aktion, Akteur, old/new, `mutation_id`/`correlation_id`, optional `reason`) — bereits implementiert, die UI ergänzt nichts und loggt keine Inhalte clientseitig. **Neu:** die optionalen Grund-Felder (§6.4–6.6, 6.10) füllen das bislang ungenutzte `p_reason`.
- Telemetrie/Logs enthalten niemals signierte URLs, Dateinamen-Inhalte oder Prüfkommentare (deckungsgleich mit der Property-Spec); technische Phase/Fehlerklasse genügt.
- Download-Zugriffe sind bewusst nicht auditiert (benannter Gap `DOCUMENTS-ACCESS-AUDIT-01`, §14). Sichtbare Historie im Screen: die Versionsliste je Dokument; das generische Audit-Screen-Paket bleibt `AUDIT-01`.

## 17. Test plan

### Unit/application
- Controller: Phasenübergänge je Tab (idle/loading/ready/empty/forbidden/error/no-match), serverseitige Filterpfade (Typ, includeInactive), Konflikt-Payload (`DocumentVersionConflict` mit Serverstand), Gültigkeits-Prefill aus `defaultValidityMonths`, Registry-Draft-Validierung (Key-Muster, Verzichts-Begründung, Geltungs-Kombinationen), Ebenen-Scope der Regel-Liste, Signed-URL-Flow (Mint unmittelbar vor Open, kein Zwischenspeichern, neuer Mint nach Expiry).

### Widget/UI
- Keys `documents-*` (kebab-case, Foundation §17), keine Copy-Bindings. Die bestehenden Suiten (`documents_screen_states_test.dart`, 24 Tests; `compliance_dashboard_states_test.dart`, 14 Tests) bleiben grün bzw. ziehen auf den V2-Host um. Neu abgedeckt: Tab-Host inkl. Surface→Tab-Mapping (`/compliance`), Primäraktion folgt dem Tab, verborgene nicht-implementierte Tabs, Registry-Tabellen + `mobileChild`, typisierte nullable Dropdowns (Sentinel tot), disabled-mit-Tooltip je Capability (inkl. separatem `document.verify`), Konfliktbanner erhält Eingaben, destruktive Dialoge mit benanntem Objekt und Grund-Feld, **Abwesenheits-Invarianten**: kein Lösch-Auslöser für Dokumente, Typen oder Regeln (OPN-DOM-005), kein `processing`-Erzeuger, **kein Suchfeld im Register**, **kein URL-Dialog, kein Copy-Auslöser und keine URL in Widget-State/Logs**.

### Repository/integration
- Adapter unverändert — bestehende Adapter-/Integrationstests bleiben maßgeblich; pgTAP `011_p2_d03_documents_compliance.test.sql` und `016_p2_d03_workspace_requirements.test.sql` bleiben die Autorität für RPC-/RLS-Verhalten (inkl. AAL2-Gate aus `20260812100000`). Keine neuen Server-Tests nötig, weil keine Server-Änderung stattfindet.

### Staging E2E
- Golden Path: Anlegen mit Upload → „Upload bestätigen" → „Verifizieren" → „Neue Version" → „Ersetzen"/„Archivieren"; Typ anlegen → in Dokument- und Regel-Dropdowns sichtbar → deaktivieren → aus Dropdowns verschwunden; Regel anlegen (Alle/Objektart) → Compliance zeigt „Fehlt" → Upload am Objekt → Zustand wandert bis „Erfüllt"; Regel zurückziehen → Finding verschwindet; „Inhalt öffnen" öffnet direkt (frisch gemintete URL), erneutes Öffnen nach Ablauf mintet neu; Zeilen-Klick landet ohne gestapelte Shell auf der Objekt-Dokumentfläche.
- Negativ: ohne `document.read` Sidebar versteckt + Deep-Link Forbidden + leere RLS-Reads; ohne `document.manage`/`document.verify` disabled-Auslöser und Server-Ablehnung bei erzwungenem Call; AAL1-Session → Reads leer, Mutation „AAL2 is required for document mutations" als Forbidden gerendert; Versionskonflikt durch Parallel-Mutation (Eingabe bleibt erhalten); Upload auf existierenden Pfad schlägt fehl (kein Überschreiben); abgelaufene signierte URL lädt nicht mehr und es existiert nirgends eine gespeicherte/kopierbare URL.

## 18. Acceptance criteria

1. „Dokumente" ist eine Destination mit den Tabs Dokumente/Typen/Pflichtregeln/Compliance (nicht implementierte Tabs verborgen); `/documents` und `/compliance` landen auf dem jeweiligen Tab; der Legacy-Host `DocumentsScreen`, `documentsRequestedTabProvider` und der Palette-Case `jump_missing_documents` existieren nicht mehr im Build.
2. Ein Nutzer mit `document.manage` legt einen Dokumenttyp mit Key, Ebene und Standard-Gültigkeit an, sieht ihn sofort in den Typ-Dropdowns, deaktiviert ihn und sieht ihn dort nicht mehr — nirgends existiert ein Lösch-Auslöser für Typen.
3. Pflichtregeln lassen sich je Ebene anlegen (Alle/Objektart), bearbeiten, anfordern, mit Pflicht-Begründung außer Kraft setzen und zurückziehen; eine doppelte lebende Regel wird serverseitig abgewiesen und inline erklärt.
4. Der Compliance-Tab zeigt KPI-Zeile, Coverage-Hinweise und Findings; „Nur offene anzeigen" fragt serverseitig neu; ein Zeilen-Klick wechselt state-first (ohne `Navigator`-Stapel) zur Objekt-Dokumentfläche.
5. Upload → Bestätigen → Verifizieren funktioniert zweistufig; „Verifizieren" ist ausschließlich mit `document.verify` möglich und sonst disabled mit erklärendem Tooltip.
6. Ein Versionskonflikt verwirft niemals Eingaben: offene Dialoge zeigen den Serverstand als Banner mit „Neu laden" und „Erneut speichern".
7. „Inhalt öffnen" mintet die signierte URL unmittelbar vor dem Öffnen und öffnet sie direkt über `url_launcher`; die URL wird nirgends angezeigt, kopiert, persistiert oder geloggt, und nach Ablauf wird beim nächsten Öffnen neu autorisiert.
8. Es existiert kein Lösch-, Sharing- oder Überschreib-Pfad: Archivieren ist als endgültig beschriftet („Gelöscht wird nichts"), ein Upload auf einen bestehenden Pfad schlägt fehl.
9. Ohne `document.read` ist die Destination unsichtbar und der Deep-Link rendert Forbidden mit „(document.read)"; bei AAL1 liefert der Server nichts bzw. lehnt Mutationen ab, und die UI rendert das als Forbidden-State, nicht als Absturz.
10. Archivierungs-, Ersetzen-, Prüf- und Zurückzieh-Dialoge bieten ein optionales Grund-Feld, das im Audit-Event landet; der Verzicht einer Regel erzwingt eine Begründung.
11. Das Register bietet **keine Volltextsuche** an; gefiltert wird ausschließlich serverseitig (Dokumenttyp, Include-Toggle), der `'__all__'`-Sentinel ist entfernt, und „Keine Treffer" erscheint nur nach serverseitig leerem Filter-Ergebnis.
12. Alle Listen laden mit `NxListSkeleton`, Split-Verhalten läuft über `NxSplitView`/`AppLayout.splitViewMinWidth` (die private 1200er-Konstante ist entfernt), die Compliance-KPIs rendern über `NxKpiRow`; alle drei Golden-Viewports + 320-Floor rendern ohne Overflow und jeder Tabellen-Tab hat einen funktionierenden `mobileChild` mit „Zur Liste"-Rückweg.

## 19. Out of scope

- Jede Server-Änderung: Schema, RLS, RPCs, Storage-Policies, Realtime-Publikationen, Permission-Katalog, AAL-Grenzen.
- Löschen von Dokumenten, Typen oder Regeln (OPN-DOM-005 bleibt bewusst offen).
- **BLOCKED** (eigene Pakete/Entscheidungen, §14): `DOCUMENTS-V2-B2` (Katalog-Entscheidung), `DOCUMENTS-QUERY-DATA-01` (Suche/Query), `DOCUMENTS-REALTIME-01`, `DOCUMENTS-REMINDERS-01`.
- **FUTURE** (ausdrücklich nicht geplant): Drag & Drop, Inline-PDF-Preview, Retention-Automatik, Custom Lists, Bulk-Aktionen, OCR/AI, Annotationen, Clipboard-Sharing signierter URLs.
- Objekt-Medien/Bilder (→ bestehendes `PROPERTY-MEDIA-DATA-01`, blocked); die Objekt-Dokumentfläche selbst (→ [PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md)); Verknüpfungs-UIs auf Entitätsflächen (nicht migrierte Ebenen liefern weiter `dependencyConflict`).
- Der Property-seitige 3-Tab-Host (`property_documents_screen.dart` mit Archiv/Audit/Reports) — sein Abriss reitet auf `AUDIT-01`/P2-D09, nicht hier.
- Der generische Audit-Screen (→ `AUDIT-01`); Degraded-Wiring-Backend (→ `REALTIME-DEGRADED-WIRING-01`, Wave 1).

## 20. Open decisions

Für die freigegebenen Inkremente A, B1, C sind alle materiellen Entscheidungen geschlossen (2026-09-02):

1. **Tab-Schnitt: ENTSCHIEDEN — vier Tabs** (Dokumente/Typen/Pflichtregeln/Compliance) in einer Destination; die Primäraktion folgt dem aktiven Tab; nicht implementierte Tabs bleiben verborgen. Kein Sidebar-Amendment nötig.
2. **Registry-Zuständigkeit: ENTSCHIEDEN** — der Pflichtregeln-Tab legt Workspace-/Objektart-Regeln an; Instanz-Regeln entstehen auf der Entitätsfläche, sind hier aber sichtbar und zurückziehbar. Der Contract erzwingt die Ebenen-Scope-Sicht (`listRequirements` verlangt `entityType`).
3. **„Löschen" der Legacy-Registry: ENTSCHIEDEN — stirbt ersatzlos.** Typen werden deaktiviert, Regeln zurückgezogen; beides Upsert-Semantik des Contracts.
4. **Signed-URL-Flow: ENTSCHIEDEN (bindende Security-Entscheidung)** — Mint unmittelbar vor dem Öffnen, direktes Öffnen via `url_launcher`, keine Anzeige/Persistenz/Protokollierung/Zwischenablage. „Link kopieren" ist aus dem freigegebenen Scope entfernt; Clipboard-Sharing wäre eine neue Produkt-/Security-Entscheidung (FUTURE).
5. **Register-Suche: ENTSCHIEDEN — entfällt im Inkrement** (keine scheinbar vollständige Client-Suche über Keyset-Seiten, kein Load-All); Wiedereinstieg nur über `DOCUMENTS-QUERY-DATA-01`.
6. **Palette-Sprung: ENTSCHIEDEN — ersatzlos entfernt**; Wiedereinstieg gehört zu `SHELL-PALETTE-01` mit Permission-Filterung.

Offen bleibt ausschließlich die **B2-Katalog-Entscheidung** — sie ist als eigenes, geblocktes Inkrement außerhalb des freigegebenen Scopes geführt (wie `PROPERTY_OVERVIEW_V2` neben seinen freigegebenen Geschwistern) und blockiert A/B1/C nicht.

## 21. Implementation handoff

**Paketschnitt (Inkremente = PR-Grenzen):**
- **A — V2-Host + Workspace-Register** (APPROVED): Tab-Host (Surface→Tab-Mapping, Primäraktion je Tab, verborgene nicht-implementierte Tabs), Register-Konvergenz (`NxSplitView`/`splitViewMinWidth` statt 1200er-Konstante, `NxListSkeleton`, §10-Konflikt-UX statt Verwerfen-Dialog, typisiertes nullable Typ-Dropdown statt `'__all__'`, Entfall des Suchfelds und des clientseitigen Ebenen-Listenfilters, „Pflichtfeld"-Copy, Grund-Felder, Gültigkeits-Prefill), Signed-URL-Open-Flow (§6.7), Abriss `DocumentsScreen` + `documentsRequestedTabProvider` + Palette-Case (inkl. zugehöriger Tests), `adaptivePagePadding` statt `SingleChildScrollView`-Wrapper, Keys `documents-*`.
- **B1 — Registry** (APPROVED, eigener PR): Tabs „Typen" und „Pflichtregeln" auf `RequirementPolicyRepository` inkl. Dialoge, Zurückziehen, Verzicht mit Begründung; Abriss `legacy_document_rules_tabs.dart` nach Harvest.
- **B2 — Katalog-Entscheidung** (BLOCKED, product decision): kein Bestandteil der freigegebenen PRs.
- **C — Compliance** (APPROVED, eigener PR): `NxKpiRow`-Konvergenz, `NxNotice`-Coverage-Hinweise, state-first Zeilen-Navigation, Tab-Einbindung.
- Getrennt und nicht Teil dieses Screens: `PROPERTY-MEDIA-DATA-01`, `DOCUMENTS-QUERY-DATA-01`, `DOCUMENTS-REALTIME-01`, `DOCUMENTS-REMINDERS-01`, `DOCUMENTS-ACCESS-AUDIT-01`, `WORKSPACE-DIRECTORY-READ-01`, `REALTIME-DEGRADED-WIRING-01`, [PROPERTY_DOCUMENTS_V2.md](PROPERTY_DOCUMENTS_V2.md).

**Voraussetzungen auf main:** erfüllt (`UX-FOUNDATION-IMPL-01` merged, `3a11b09`). **Abhängigkeit:** `url_launcher` ist die eine neue Client-Dependency des Signed-URL-Flows; sie ist durch die bindende Security-Entscheidung §20.4 ausdrücklich autorisiert (Ausnahme zur No-new-packages-Regel, im PR zu benennen). **Harte Invarianten:** keine Schema-/RLS-/RPC-/Storage-/AAL-Änderungen; kein Lösch-Pfad und kein Overwrite-Pfad; signierte URLs niemals persistieren/loggen/anzeigen/kopieren; `mutationId`/`correlationId`/`expectedVersion`-Envelope bei jeder Mutation; `document.verify` bleibt eine eigene Stufe; fail-closed bei fehlendem Scope; Statusmaschine exakt wie im Contract. **Tests:** §17. Die Implementierungs-Chats inspizieren vor jeder Änderung den dann aktuellen Repo-Stand.
