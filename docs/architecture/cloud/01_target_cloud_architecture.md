# NexImmo — Autoritative Cloud-Zielarchitektur

Stand: 2026-08-07 · Status: `accepted` für alles, was auf entschiedenen `DEC-*` beruht;
`proposed` nur dort, wo eine offene Entscheidung ausdrücklich benannt ist.

Dieses Dokument ist ab sofort **die** Quelle für das Cloud-Zielbild. Wo ältere Dokumente
ihm widersprechen, gilt dieses hier, und das ältere Dokument ist zu korrigieren.

**Abgrenzung.** Dieses Dokument beschreibt die *Plattform*: System of Record, Clients,
Auth, Autorisierung, Storage, Realtime, Jobs, Umgebungen, Backup, Deployment. Es
beschreibt **nicht** den fachlichen Migrationsfortschritt (→ `phase_2/00_phase_2_status.md`),
den Domänenumfang (→ `phase_2/01_domain_expansion_backlog.md`) oder den SQLite-Rückbau
(→ `phase_2/04y_p2_x02_sqlite_decommission.md`). Es dupliziert sie nicht.

---

## 1. Der aufgelöste Widerspruch

Die Dokumentation trug zwei unvereinbare Zielbilder:

| Quelle | Aussage | Gültigkeit |
|---|---|---|
| `phase_2/00_phase_2_charter.md` Z. 21, `CLAUDE.md` | „offline-first"; je Domäne zwei Adapter (`legacy_sqlite_*` + `supabase_*`); SQLite als dauerhafte lokale Basis | **aufgehoben** durch `DEC-024` |
| `DEC-005` | SQLite als Legacy-Quelle und optionaler späterer Client-Cache | **abgelöst** durch `DEC-024` |
| `DEC-024` (accepted 2026-08-06) | SQLite wird **vollständig entfernt**. Supabase ist die einzige Datenschicht. Offline-Startfähigkeit entfällt ersatzlos | **gültig** |

**Verbindlich: cloud-first / online-first für Web und Windows Desktop.** Es gibt keine
zweite produktive Datenwahrheit. Ein späterer Offline-Cache ist ein eigenständiges
Projekt mit eigenem Sync-, Konflikt- und Tombstone-Design — nicht die Wiederbelebung
von SQLite.

Daraus folgt unmittelbar: **es gibt keinen Legacy-Datencutover.** Die Objektdaten waren
Testdaten und wurden am 2026-08-04 bewusst entfernt (`app_data.db`: 0 Properties,
0 Scenarios, 0 Users). Reconciliation-, Paritäts- und Rollback-Verpflichtungen für
Nutzdaten entfallen; es bleibt reine Code-Entfernung.

Zwei Dokumente hinken diesem Beschluss noch hinterher und werden in `AP-X02-1`
nachgezogen: `phase_2/00_phase_2_charter.md` Z. 21 und der `offline-first`-/
Adapter-Pattern-Abschnitt in `CLAUDE.md`.

---

## 2. System of Record

**Supabase PostgreSQL.** Einzige fachliche Wahrheit für alle Domänen.

Nicht System of Record — bewusst und dauerhaft:

| Komponente | Rolle | Regel |
|---|---|---|
| Realtime | Invalidierungssignal / Domain Event | Kanonischer Read bleibt das Repository (`DEC-018`) |
| Client-Caches (Riverpod) | Darstellung | Bei Entzug fail-closed geleert, dann revalidiert (`DEC-022`) |
| Reporting / KPI-Schicht | abgeleitete Sicht | Schreibt **nie** in Quelldomänen zurück |
| SQLite | — | Wird entfernt (`DEC-024`) |

---

## 3. Clients

| Client | Technologie | Backend | Zustand |
|---|---|---|---|
| Web | Flutter Web | dieselbe Supabase-Umgebung | primärer Zielclient |
| Windows Desktop | Flutter Desktop | dieselbe Supabase-Umgebung | gleichwertig; **keine** Offline-Startfähigkeit mehr |
| Mobile | — | — | nicht in Phase 2 (`DEC-013`) |

Der Backend-Typ bestimmt ausschließlich, welcher Repository-Adapter gewired wird — nicht,
welche Anwendung gebaut wird. Diese Konvergenz ist `P2-X01` (`AP0`–`AP3` `done`): eine
reale Supabase-Session und Workspace-Auswahl führen fail-closed in den kanonischen
`AppScaffold`, mit gemeinsamem Navigationsbaum, expliziter Cloud-Readiness und
Capability-Prüfung je Ziel.

Mit dem Wegfall von `DataBackend.sqlite` (`AP-X02-2`) verschwindet auch diese letzte
Verzweigung: `NEXIMMO_DATA_BACKEND` und `CloudDestinationReadiness` entfallen ersatzlos.

---

## 4. Identity und Autorisierung

| Schicht | Umsetzung |
|---|---|
| Identität | Supabase Auth, passwordless E-Mail-Login (`DEC-016`) |
| Faktoren | TOTP über Supabase AAL; ausstehendes `aal2` blockiert clientseitigen Zugriff |
| Mandantentrennung | Workspace-/Membership-Modell, `auth.uid()`-gebunden |
| Autorisierung | Postgres RLS, **default deny**, serverseitig erzwungen (`DEC-006`) |
| Fehlende Session | keinerlei Rechte (`DEC-007`) |
| Berechtigungen | feingranulare Capabilities (`property.update`, `capex.approve`, …), aggregiert zu Rollen |
| Entzug zur Laufzeit | privater nutzergebundener Realtime-Broadcast → Cache-Leerung → kanonische Revalidation (`DEC-022`) |

**Entschieden (`DEC-016`, accepted 2026-08-08):** Privilegierte Sicherheits- und
Administrationsaktionen verlangen AAL2, **serverseitig und fail-closed** erzwungen über RLS,
RPC-/DB-Guards oder Supabase-Auth-Claims — nie allein im Flutter-Client. Nicht jede
gewöhnliche Aktion verlangt AAL2. Verpflichtend mindestens für Capabilities mit Einfluss auf
Access Control, Memberships, Rollen/Berechtigungen und sicherheitskritische
Workspace-Administration; die Capability-Matrix darf fachlich erweitert werden.

Property-Mutationen erfüllen das bereits. Der Rest ist **Umsetzungsarbeit je Capability**,
keine offene Entscheidung mehr. Die vollständige Rollen-zu-Permission-Matrix und die
Vier-Augen-Freigaben bleiben offen (`DEC-SEC-001`, `partial`).

---

## 5. Mutationen

Jede kritische Mutation erfüllt gleichzeitig:

1. Läuft über Repository-Contract → Adapter → RPC. Kein SQL aus der UI, keine
   Supabase-SDK-Typen in der Application-Schicht.
2. Ist workspace-scoped und an `auth.uid()` gebunden.
3. Trägt `expectedVersion` → optimistische Concurrency, typisierter
   `versionConflict`-Fehler statt Silent Overwrite (`DEC-009`).
4. Trägt `mutationId` → Idempotenz bei Retry.
5. Schreibt atomar einen append-only Audit-Satz mit `correlationId` und `reason`
   (`DEC-010`). Kein Delete-/Edit-Pfad für Audit-Einträge.
6. Geld ist `numeric` + Währungscode, nie `double` (`DEC-011`).

Jede Migration braucht default-deny RLS **und** einen Rollback-Test, der in CI
replayed wird.

---

## 6. Storage

Privater Bucket, Zugriff ausschließlich über kurzlebige Signed URLs (`SignedUrlPort`).
Umgesetzt mit `P2-D03`.

Vor Production zu ergänzen (Phase K): MIME-Allowlist, Größenlimit,
Dateinamen-Sanitizing, kein Overwrite, Content-Hash, Retention (`OPN-DOM-005`),
optional Malware-Scan.

**Ein DB-Backup ist kein Backup der Datei-Bytes.** Storage braucht einen eigenen Export
mit eigenem Inventory, eigenen Checksums und eigenem Restore-Drill.

---

## 7. Serverseitige Jobs

Heute hängt die Erzeugung periodischer Arbeit an der laufenden UI (`DEBT-009`). Das ist
im Cloud-Zielbild unhaltbar: der Client darf nicht entscheiden, ob ein Job stattfindet.

Serverseitig zu verlagern: wiederkehrende Task-Erzeugung, Lease-Expiry, Document-Expiry,
Compliance-Scans, später Covenant-Checks, Notification-Fan-out wo passend.

Mittel: pg_cron / Supabase Cron plus DB-Funktion. Edge Function nur, wenn externer
Zugriff oder längere Logik es erzwingt. Idempotenz über den bestehenden `generated_key`.

**Gate:** App vollständig geschlossen → fällige Jobs entstehen trotzdem korrekt.

---

## 8. Umgebungen

Drei strikt getrennte Umgebungen mit eigener DB, eigenen Keys, eigenem Storage, eigenen
Auth-Redirects, eigenem SMTP:

| Umgebung | Zweck | Zustand |
|---|---|---|
| `local` | Entwicklung gegen den Docker-Stack | **existiert** |
| `staging` | Integration, E2E, Abnahme | **existiert nicht** — gegated durch `DEC-017`. Region: dieselbe regulatorisch-geografische Zielregion wie Production, soweit das Supabase-Environment-Modell das zulässt (`DEC-015`) |
| `production` | Echtdaten, EU-Region mit Zielregion Frankfurt (`DEC-015`, **accepted**) | **existiert nicht** |

Client-Konfiguration ausschließlich über vier `--dart-define`:
`NEXIMMO_ENV`, `NEXIMMO_DATA_BACKEND`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`.
`AppEnvironment` schlägt bei fehlenden oder unbekannten Werten **fehl**, ohne Fallback
zwischen Umgebungen oder Backends.

Niemals im Flutter-Client, in `supabase/config.toml`, im Log oder in einem `--dart-define`:
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_DB_PASSWORD`,
`SUPABASE_ACCESS_TOKEN`.

---

## 9. Deployment

Marketing-Seite und Produkt-App sind zwei getrennte Vercel-Projekte. Sie teilen ein
Repository, aber weder Build noch Domain noch Freigabe.

| | Marketing | Produkt-App |
|---|---|---|
| Technologie | Next.js | Flutter Web |
| Root | `marketing/` | Repo-Root, Artefakt `build/web` |
| Build | Vercel baut selbst | **GitHub Actions baut**, Vercel deployt prebuilt |
| Konfiguration | `marketing/vercel.json` | `.github/workflows/web_deploy.yml` |
| Preview | Vercel-Standard | PR-Preview, sobald Secrets existieren |
| Production | Vercel-Standard | manuelle, geprüfte Promotion eines freigegebenen Commits |
| Domain | öffentliche Marketing-Domain | eigene App-Subdomain (z. B. `app.*`) |

**Warum die App nicht in Vercel gebaut wird:** das Vercel-Build-Image hat keine
Flutter-Toolchain. Ein dort nachinstalliertes SDK würde von der in CI getesteten Version
abdriften und Artefakte deployen, die nie ein Gate durchlaufen haben. Der Build gehört
dorthin, wo die Version gepinnt ist.

`marketing/vercel.json` überspringt Builds für Commits, die `marketing/` nicht berühren —
sonst würde jeder Flutter-Commit ein Marketing-Deployment auslösen.

Der Deploy-Workflow ist **inert**, bis Vercel-Projekt, Repository-Secrets und eine
provisionierte Supabase-Umgebung existieren. Er hat bewusst **keinen** Production-Pfad.

---

## 10. CI-Gates

`.github/workflows/flutter.yml`, vier Jobs:

| Job | Deckt ab |
|---|---|
| `verify` | Lockfile-Restore, `flutter analyze`, volle Testsuite (inkl. Golden-/Responsive-Tests), Web-Build, Web-Build mit gesetzten Cloud-Dart-Defines |
| `marketing` | `npm ci` + `next build` aus demselben Root, aus dem Vercel baut |
| `supply_chain` | gitleaks über die volle History, `npm audit --audit-level=high` |
| `database` | Supabase-Reset, `db lint`, Security- und Performance-Advisor, pgTAP, 27 Migrations-Rollback-Replays, reale Integrationsskripte (Concurrency, PostgREST, Realtime, je Domäne), Backup/Restore- und Crash-Recovery-Drills, Performance-Profil |

`pull_request` greift ungefiltert; `push` deckt `main` und `cloud/**` ab.
Dependabot deckt `pub`, `npm` und `github-actions` ab.

**Nutzeraktion erforderlich, außerhalb des Repositories:** Branch Protection auf `main`
mit `verify`, `marketing`, `supply_chain` und `database` als Required Checks.
Hinweis: `gitleaks-action@v2` ist für persönliche Accounts und öffentliche Repositories
lizenzfrei; für Organisationen verlangt es `GITLEAKS_LICENSE`.

---

## 11. Backup und Disaster Recovery

Lokal nachgewiesen (`P1-014`, `DEC-020`): schema-scoped logischer Restore in eine frische
Wegwerf-Datenbank, Realtime-Publication aus versionierten Migrationen rekonstruiert und
reconciled, plus Guards gegen korrupte Archive und harte Abbrüche.

Vor Production zusätzlich nötig: automatische DB-Backups, PITR je nach Plan, **separater**
Storage-Export mit Inventory und Checksums, ein Restore-Drill in eine frische isolierte
Umgebung über Schema, Daten, RLS, auth-nahe Metadaten, Storage, Dokumentlinks, Counts und
Checksums — sowie dokumentierte RPO, RTO und Verantwortlichkeit.

---

## 12. Legacy-Retirement

Vollständig in `phase_2/04y_p2_x02_sqlite_decommission.md`. Kurzfassung: früher Schnitt
(`AP-X02-2`) streicht `DataBackend.sqlite` **vor** den restlichen Domänenarbeiten und
entfernt damit 9 Legacy-Adapter, 6 Cutover-Mapper und den Backend-Switch in einem Zug,
statt weiter Adapter zu bauen, die anschließend gelöscht werden.

Bewusst in Kauf genommen: die noch nicht migrierten Ziele sind bis zu ihrer Welle in
keinem Modus erreichbar. Tragfähig, weil keine Nutzdaten existieren, deren
Erreichbarkeit zu verteidigen wäre.

---

## 13. Guardrails

1. UI ruft keine Datenbank direkt auf.
2. Application-Schicht enthält keine Supabase-SDK-Typen.
3. Kritische Mutation nur über Repository / Service / RPC.
4. RLS default deny; fremder Workspace fail closed.
5. Versionierte Mutation trägt `expectedVersion` **und** `mutationId`.
6. Audit ist append-only.
7. Realtime ist Invalidierung, kein zweites System of Record.
8. Geld ist `numeric` + Währung.
9. Kein Secret im Flutter-Client.
10. Keine zweite fachliche KPI-Wahrheit in Reporting oder UI.
11. Keine Migration ohne Rollback-Test.
12. Kein Production-Deploy ohne Staging.
13. Kein `done` ohne ausgeführte Evidenz.

---

## 14. Offene Entscheidungen, die dieses Zielbild noch blockieren

| ID | Frage | Blockiert |
|---|---|---|
| `DEC-017` | Freigabe für Remote-Provisioning (erst Staging, dann Production) | jede nicht-lokale Umgebung |
| `OPN-DOM-004` | Freigabegrenzen | `P2-D08` Finance/Debt |
| `OPN-DOM-005` | Retention-Policy | Storage-Hardening |

Solange `DEC-017` offen ist, endet die Plattform beim lokalen Stack. Alles in diesem
Dokument, was Staging oder Production betrifft, ist Zielbild, nicht Ist-Zustand.

**`DEC-015` und `DEC-016` sind am 2026-08-08 entschieden und stehen hier nicht mehr.** Die
drei sind bewusst zu trennen: `DEC-015` entscheidet **wo** produktiv gelaufen wird,
`DEC-016` **wie** privilegierter Zugriff gesichert wird, `DEC-017` ob überhaupt eine
Remote-Ressource **angelegt** werden darf. Die ersten beiden zu entscheiden ändert an der
Sperre der dritten nichts — es gibt weiterhin kein Production-Projekt, keine bezahlte
Ressource, keine Production-Secrets, keine Datenmigration und keinen DNS-Cutover.
