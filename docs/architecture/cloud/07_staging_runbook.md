# Staging-Runbook

Stand: 2026-08-23 (`DOCS-CURRENCY-01`) · Basis `4a1e5ef` · Vorbereitet in `STAGING-PREP-01` (2026-08-09, `a371d22`)

`DEC-017` ist seit dem **2026-08-09 `accepted`** — für genau eine isolierte Umgebung mit
ausschließlich synthetischen Daten.

**Ausführungsstand (2026-08-09):** Abschnitt 4 Schritte **1–13 und 15** sind erledigt.
`STAGING-PROVISION-01` Phase 1 hat das Projekt `NexImmo Staging` (`vhxdgchhgyzbjnogjicb`,
`eu-central-1`, Free, `ACTIVE_HEALTHY`) angelegt; Phase 3 hat es gelinkt und die 35
Migrationen angewandt und verifiziert — 35/35 remote, 0 pending, kein Seed, keine Daten,
Lint/Advisors/pgTAP grün.

**Ausführungsstand (2026-08-26):** Remote stehen **36/36** Migrationen (neueste
`20260812100000_security_aal_enforcement`). Die Abschnitte 3, 6, 7 und 10 sowie die Schritte
16 (Auth, 2026-08-10) und 17 (synthetische Basisdaten) sind ausgeführt; Staging deployt seit
2026-08-10 automatisch auf `neximmo-staging.vercel.app`. Die **Realtime-Zustellung an einen
echten Staging-Client ist seit 2026-08-23/24 bewiesen** (Schritt 15; Live-Zustellung,
Auth-/RLS-Negativgrenze und Reconnect-Recovery, `REALTIME-STAGING-FIX-01` Remote-Closeout PASS).
**Weiterhin offen:** Schritt **14** (Integration-Gates — keines der Skripte ist remote
ausführbar, siehe unten), das Remote-E2E der fünf Schwester-Invalidation-Adapter (blockiert
ausschließlich durch fehlende Staging-Daten/Permissions dieser Domänen, kein bekannter Defekt),
Site URL / Redirect-Allowlist (Abschnitt 8) und SMTP (Abschnitt 9). Jede weitere Phase braucht
eine gesonderte Freigabe. Protokoll: [05_phase_a_log.md](05_phase_a_log.md).

Zusätzlich gilt die **Kostenregel** aus `DEC-017`: was ohne Zusatzkosten in bestehende
Kontingente passt, darf entstehen; alles mit einem von null verschiedenen Kostenpunkt hält
an und braucht eine gesonderte Freigabe mit Anbieter, Tarif, einmaligen und monatlichen
Kosten und Kündbarkeit. In diesem Runbook betrifft das konkret Supabase (Abschnitt 4),
Custom SMTP (Abschnitt 9) und jede Vercel-Planänderung oder kostenpflichtige
Protection-Funktion (Abschnitt 6).

---

## 1. Was der Deploy-Pfad heute tut

**Entscheidung (2026-08-10, Owner):** Staging aktualisiert sich **automatisch** nach
einem grünen protected-main-Lauf. Kette: PR → Required CI → Merge auf `main` → der
`Flutter`-Workflow läuft auf diesem Push → bei Erfolg feuert `Web App Deploy` über
`workflow_run` und deployt genau diesen Commit als Vercel **Preview**. Der manuelle
Environment-Reviewer für Staging entfällt damit. **Production bleibt vollständig manuell und
weiterhin nicht autorisiert.**

**Am 2026-08-10 real durchlaufen** (Merge-SHA `00b19d3…`, `Flutter` 31408857987,
`Web App Deploy` 31410150765, Deployment `dpl_DREwbgxwtECmLRacGJsRfNPRSpzT`, Target `preview`).
Aktivierungszustand seither:

| Schalter | Wert |
|---|---|
| `STAGING_DEPLOY_ENABLED` | `true` |
| `VERCEL_STAGING_ALIAS` | `neximmo-staging.vercel.app` |
| Staging-Secrets | 5/5 |
| Vercel Authentication (SSO) auf dem App-Projekt | **deaktiviert** (projektweit, nach `DEC-017` akzeptiert) |

**Stabile Staging-Adresse: `https://neximmo-staging.vercel.app`.** Jeder erfolgreiche
Auto-Deploy verschiebt diesen Alias auf den neuesten Preview. Diese Adresse ist der Kandidat
für die Supabase Site URL — **noch nicht gesetzt**, das gehört in das Auth-Paket.

Vercel baut den Flutter-Source **nicht** selbst: der autoritative Pfad bleibt GitHub Actions
→ Flutter 3.29.2 → `flutter build web` → `build/web` → Vercel CLI (nur Upload). Die Vercel
Git-Integration bleibt **disconnected** (`DEPLOY-DRIFT-02`), und die Root-`vercel.json` behält
zusätzlich `git.deploymentEnabled=false`.

Der Workflow ist trotz Automatik **fail-closed** über zwei voneinander unabhängige Sperren:

1. Die Repository-Variable `STAGING_DEPLOY_ENABLED` muss `true` sein. Sie ist kein Secret
   und steht seit dem 2026-08-10 auf `true`.
2. Innerhalb des Environments `staging` müssen **alle fünf** Werte vorhanden sein.

Die erste Sperre existiert nicht nur zur Bequemlichkeit. GitHub legt ein referenziertes
Environment beim ersten Lauf automatisch an — laut Dokumentation „will not have any
protection rules or secrets configured". Solange der Deploy-Job nicht laufen darf, kann er
das Environment auch nicht in diesem ungeschützten Zustand erzeugen.

Weil ein `workflow_run`-Workflow laut GitHub-Doku **Zugriff auf Secrets** erhält (anders als
der auslösende Lauf), ist das Eligibility-Gate bewusst streng: deployt wird nur ein
`event == 'push'`, `conclusion == 'success'` auf `head_branch == 'main'` **dieses** Repos
(kein Fork), nur der SHA aus `github.event.workflow_run.head_sha`, nur solange dieser noch die
aktuelle Spitze von `main` ist (Stale-Main-Guard), und nur wenn die vier Required Checks auf
genau diesem SHA `success` sind. Kein Artefakt des vorherigen Laufs wird übernommen; der
Source wird über den exakten SHA frisch ausgecheckt.

---

## 2. Reihenfolge der Aktivierung

Diese Reihenfolge ist bewusst: erst die Umgebung, dann die Secrets, dann der Schalter.
Wer den Schalter zuerst setzt, riskiert genau das ungeschützte Auto-Environment.

1. ~~`DEC-017` entscheiden.~~ **erledigt am 2026-08-09, `accepted`.**
2. ~~Supabase-Staging-Projekt anlegen (Abschnitt 4).~~ **erledigt am 2026-08-09.**
3. ~~GitHub-Environment `staging` **manuell** anlegen und konfigurieren (Abschnitt 3).~~ **erledigt am 2026-08-10** (ohne Required Reviewer, siehe Abschnitt 1).
4. ~~Die fünf Werte als **Environment**-Secrets hinterlegen, nicht repositoryweit.~~ **erledigt am 2026-08-10** (5/5).
5. ~~Vercel Deployment Protection klären (Abschnitt 6).~~ **erledigt am 2026-08-10** (SSO-Protection deaktiviert).
6. ~~`STAGING_DEPLOY_ENABLED=true` setzen.~~ **erledigt am 2026-08-10.**
7. ~~Deploy auslösen, stabile URL feststellen (Abschnitt 7).~~ **erledigt am 2026-08-10** (`neximmo-staging.vercel.app`).
8. Erst jetzt Supabase Site URL und Redirects setzen (Abschnitt 8). — **offen** (Site URL weiterhin `http://localhost:3000`; der Passwort-Login braucht keinen Redirect).
9. Golden Paths fahren. — **teilweise**: Auth-/MFA-Closeouts gegen Staging am 2026-08-23 gefahren (`05_phase_a_log.md`); der fachliche Web-/Windows-Golden-Path (`GP-STAGING-WEB`/`-WINDOWS`) steht aus.

---

## 3. GitHub-Environment `staging`

Das Repository ist **public**; Environments und Schutzregeln stehen damit unabhängig vom
Plan zur Verfügung. (Für private Repositories wäre laut GitHub-Doku mindestens Pro/Team
nötig.)

| Einstellung | Empfehlung | Grund |
|---|---|---|
| Name | `staging` | exakt so referenziert der Workflow |
| Environment-Secrets | die fünf Deploy-Werte | so eng wie möglich gescopet |
| Required reviewers | **nein** (am 2026-08-10 für den Auto-Deploy entfernt; ursprüngliche Empfehlung: ja) | Automatik nach grünem protected-main-Lauf, siehe Abschnitt 1 |
| Prevent self-review | **nein** | bei einem Ein-Personen-Repo würde es jeden Deploy blockieren |
| Deployment branch restriction | nur `main` | ein Staging-Deploy soll nur geprüfte Commits sehen |
| Admin bypass | erlauben | Notausstieg; die Sperre ist ohnehin die Variable |
| Production-Secrets | **niemals** | Production existiert nicht und gehört nicht hierher |

Die vier bereits vorhandenen Environments — `Preview`, `Production`,
`Preview – app.neximmo.de`, `Production – app.neximmo.de` — bleiben **unangetastet**. Die
beiden letzten sind Rückstände der abgeschalteten Vercel-Git-Integration; über ihr Löschen
wird separat entschieden. Alle vier haben derzeit **null** Schutzregeln.

---

## 4. Supabase-Staging-Projekt

Separates Projekt, kein Branch. Branching hängt immer an einem Elternprojekt — dieses
müsste erst entstehen und wäre faktisch Production, was ausdrücklich nicht gewollt ist.
Dazu kommen Kosten: Branching wird laut Preisseite auf Pro/Team mit `$0.01344` pro Branch
und Stunde abgerechnet.

Region: **Central EU (Frankfurt), `eu-central-1`**. Ein Projekt ist auf Infrastrukturebene
an seine Region gebunden — ein späterer Wechsel ist eine Migration, keine Einstellung.

### Ablauf, exakt

1. ~~Supabase CLI prüfen: **genau 2.109.1**~~ **erledigt** (`2.109.1`).
2. ~~Projekt anlegen; Project Ref und Region **doppelt** verifizieren.~~ **erledigt am
   2026-08-09**: `NexImmo Staging` / `vhxdgchhgyzbjnogjicb` / `eu-central-1`.
3. ~~Bestätigen, dass das Projekt leer ist.~~ **erledigt**: `ACTIVE_HEALTHY`, ohne angewandte
   NexImmo-Anwendungsmigrationen und ohne NexImmo-Daten. Plattform- und Systemschemas bringt
   jedes frische Supabase-Projekt mit; „leer" meint hier ausschließlich die Anwendungsseite.
4. ~~Admin-Auth herstellen (`supabase login`)~~ **erledigt**, Zugangsdaten nicht abgelegt.
5. ~~Projekt kontrolliert linken.~~ **erledigt** — `link --project-ref vhxdgchhgyzbjnogjicb`
   gelingt **ohne Passwort**; nur der Access Token wird gebraucht.
6. ~~Remote-Migrationshistorie **vor** dem Push auslesen.~~ **erledigt**: 35 lokale Einträge,
   alle mit leerem `remote` → **0 angewandt**; `supabase_migrations` existierte nicht.
7. ~~Lokalen Migrationssatz zählen.~~ **erledigt**: **35**, unverändert seit `a371d22`.
8. ~~Ausstehende Migrationen prüfen.~~ **erledigt**: `db push --linked --dry-run` meldet
   **genau 35**, dateiidentisch, aufsteigend, ohne Seed-/Roles-Schritt.
9. ~~`supabase db push --linked`.~~ **erledigt am 2026-08-09**: Exit 0, 35 angewandt.
   Passwort über `SUPABASE_DB_PASSWORD`, nicht über `argv`.
10. ~~Migrationshistorie **danach** vergleichen.~~ **erledigt**: 35/35, IDs identisch,
    gleiche Reihenfolge; erneuter Dry Run meldet `Remote database is up to date`.
11. ~~`db lint --linked`.~~ **erledigt**: PASS, keine Befunde.
12. ~~Advisors.~~ **erledigt**: Security 1 `INFO` + 65 `WARN` (ausschließlich
    `authenticated_security_definer_function_executable` — die bestehende
    `SECURITY DEFINER`-RPC-Architektur, lokal wie remote je 65 Funktionen), Performance
    85 `INFO`. **Kein `ERROR`.** Keine Empfehlung umgesetzt.
    **Nachgereicht:** die Regelklasse wurde am 2026-08-10 in `REMOTE-SECURITY-GATE-01`
    bewertet — **PASS**, 0 Blocker, 0 unproven. Damit ist die Sperre vor Schritt 16/17
    aufgehoben.
13. ~~pgTAP-Suite.~~ **erledigt**: 26 Dateien, 1274 Prüfungen, 0 Failures — vorher als
    remote-sicher auditiert (alle Dateien `begin;`/`rollback;`, kein `commit;`), danach
    empirisch bestätigt, dass nichts zurückblieb.
14. **OFFEN — Relevante Integration-Gates.** Von den 19 Skripten des `database`-Jobs (Stand 2026-08-09; am 2026-08-23 sind es 21, alle weiterhin lokal) sind
    **0 remote ausführbar**: 17 lösen den lokalen Container über
    `label=com.supabase.cli.project=neximmo-local` auf bzw. rufen `db reset --local`, 2 sind
    reine Parameterguards ohne DB. Keines kennt `--linked`. Ein Remote-Lauf setzt einen Umbau
    voraus, der bewusst nicht Teil von Phase 3 war.
    **`Remote application Golden Path / authenticated integration remains intentionally deferred.`**
15. ~~Realtime **DB-seitig** prüfen.~~ **erledigt**: `supabase_realtime` enthält exakt die 11
    erwarteten Tabellen, namensidentisch zur lokalen Basis — das Anwendungsschema ist korrekt
    migriert. **Die Zustellung ist damit nicht geprüft.** `realtime.messages` ist eine
    Plattformstruktur; auf dem frischen Projekt fehlte die Tagespartition, weshalb die
    DB-seitigen Broadcast-Versuche warnten (`WarnSendingBroadcastMessage`). Dabei war **kein
    echter WebSocket-Client verbunden**.
    **`Realtime delivery remains UNPROVEN until a real connected staging client exercises the
    broadcast path.`** Vor `GP-STAGING` zu beweisen. Keine Partition von Hand erzeugt, kein
    Eingriff in das Plattformschema.
    **Erledigt am 2026-08-23/24:** Zustellung mit einem echten authentifizierten `aal2`-Client
    live bewiesen (Property-Update ohne Reload empfangen), Auth-/RLS-Negativgrenze anonym
    dicht (privater Kanal „Unauthorized", `postgres_changes` ohne Grant abgewiesen), und die
    Reconnect-Recovery über eine echte Netz-Lücke nachgewiesen (genau ein Catch-up-Readback
    nach Rejoin, ohne Interaktion). Die Tagespartitionen von `realtime.messages` existieren
    inzwischen plattformseitig. Details: `05_phase_a_log.md`.
16. ~~**Erst danach** Auth konfigurieren (Abschnitt 8).~~ **erledigt am 2026-08-10**
    (`STAGING-PASSWORD-AUTH-01`: E-Mail/Passwort als primärer Login, Signup aus, TOTP
    enroll/verify an). Dass GoTrue auf Staging `aal2` korrekt ausstellt, ist am 2026-08-23
    remote bewiesen (`SECURITY-AAL-CLIENT-03`-Closeout: Session `aal2` nach TOTP-Verify und
    nach Re-Login). **Offen bleibt** nur Site URL / URI-Allowlist (Abschnitt 8).
17. ~~**Erst danach** synthetische Golden-Path-Daten erzeugen.~~ **erledigt** — Basisbestand
    auf Staging (read-only erhoben am 2026-08-23, `05_phase_a_log.md`): 3 `auth.users`
    (2 Basisnutzer mit verifiziertem TOTP + 1 Repro-Nutzer), 1 Workspace, 1 Rolle,
    3 Permissions, 2 Memberships, Golden Property v11, 10 `audit_events`, 0 Storage-Objekte.

**PostgreSQL-Major-Version — entschieden, nicht mehr offen.** Das Projekt läuft auf
**17.6.1.155**, die lokale Basis stand auf `major_version = 15`. `STAGING-PROVISION-01`
Phase 2 hat lokale und CI-Basis auf **17** angeglichen, statt gegen eine ungeprüfte Version zu
pushen: frischer Stack auf PostgreSQL 17.6, alle 35 Migrationen **unverändert** von null
angewandt, vollständige pgTAP-, Rollback- und Integrationsmatrix grün. Vor Schritt 9 ist damit
nichts mehr zu entscheiden.

**Verboten:** Production-Project-Ref, echter Datenseed, Aufheben von
`[db.seed] enabled = false`, Service-Role-Key im Flutter-Build, dauerhaftes Speichern des
DB-Passworts.

---

## 5. Destructive-Migration-Audit

Vor dem ersten Remote-`db push` durchgeführt, Stand `a371d22`, 35 Migrationen:

| Muster | Treffer | Bewertung |
|---|---:|---|
| `DROP TABLE`, `DROP COLUMN`, `DROP SCHEMA`, `DROP TYPE` | 0 | — |
| `DROP FUNCTION`, `DROP TRIGGER`, `DROP INDEX`, `DROP CONSTRAINT` | 0 | — |
| `ALTER COLUMN … TYPE`, `SET NOT NULL` | 0 | — |
| `TRUNCATE` | 2 | **nicht destruktiv**: einmal `revoke … truncate … from anon, authenticated` — also das Gegenteil —, einmal das Wort „truncated" in einem Spaltenkommentar |
| `DELETE FROM` | 150 | **alle** in Funktions- oder `DO`-Rümpfen, also Laufzeitlogik; **0** auf Migrations-Top-Level |
| `DROP POLICY` | 4 | jeweils unmittelbar gefolgt von `create policy` gleichen Namens — kontrollierter Austausch |

**Ergebnis: keine destruktive Migrationsoperation.** Das Zielprojekt ist ohnehin neu und
leer; die Prüfung bleibt trotzdem fester Bestandteil des Release-Verfahrens, weil sich das
mit jeder künftigen Migration ändern kann.

---

## 6. Vercel Deployment Protection

**Beobachtung am 2026-08-09:** `appneximmode-meisners-projects.vercel.app` und
`appneximmode-git-main-meisners-projects.vercel.app` antworten mit `302` auf
`vercel.com/sso-api`. `appneximmode.vercel.app` antwortet `404` — öffentlich erreichbar,
aber leer.

Das passt exakt zu **Standard Protection**: sie schützt laut Vercel-Doku „all domains
except production domains" und ist auf allen Plänen verfügbar.

**Warum das den Golden Path bricht:** Web sendet kein `emailRedirectTo` (siehe Abschnitt 8),
der Magic Link landet also auf der Site URL. Liegt diese hinter Vercel-SSO, bekommt der
Browser eine Weiterleitung auf eine Login-Seite statt der App — die Session entsteht nie.

Deployment Protection wird **projektweit** konfiguriert, nicht pro Environment. Damit:

| Option | Bewertung |
|---|---|
| Protection auf **None** setzen | minimal und ausreichend. Die Staging-App wird öffentlich erreichbar; sie enthält ausschließlich synthetische Daten, und der Zugriff auf Daten hängt weiterhin an Supabase-Auth und RLS, nicht an der Erreichbarkeit der Seite |
| Deployment Protection Exceptions | Pro-Add-on, laut Doku **$150/Monat**, mindestens 30 Tage Bindung — unverhältnismäßig |
| Protection Bypass for Automation | löst das Problem **nicht**: es hilft automatisierten Requests, nicht einem Menschen, der im Browser einem Magic Link folgt |

**Empfehlung:** Protection auf dem App-Projekt deaktivieren, bevor der erste Web-Golden-Path
läuft — und diese Entscheidung im Provisionierungspaket bewusst treffen, nicht nebenbei.
Production ist davon nicht betroffen, weil Standard Protection Production-Domains ohnehin
offen lässt und es keine Production-Domain gibt.

**In `STAGING-PREP-01` wurde nichts verändert.**

**Ausgeführt am 2026-08-10 in `STAGING-DEPLOY-ACTIVATION-01`:** SSO-Protection auf dem
App-Projekt deaktiviert (`ssoProtection: null`, `gitForkProtection` unverändert). Die
Magic-Link-Begründung oben ist historisch; primärer Login ist seit
`STAGING-PASSWORD-AUTH-01` E-Mail + Passwort.

---

## 7. Stabile Staging-Adresse

Supabase braucht **eine** Site URL. Wechselnde Deployment-URLs funktionieren nicht.

Laut Vercel-Doku erhält ein CLI-Deployment eine URL der Form
`<project-name>-<scope-slug>.vercel.app` — hier `appneximmode-meisners-projects.vercel.app`.
Die Doku merkt aber an, dass diese URL nach einem Production-Deployment auf Production
zeigt, und das Projekt **hat** historische Production-Deployments aus der Zeit vor
`DEPLOY-DRIFT-01`.

Daraus folgt: **die URL wird nicht vorab festgeschrieben.** Ablauf stattdessen:

1. ~~Ersten Staging-Deploy fahren.~~ **erledigt 2026-08-10.**
2. ~~Prüfen, welche stabile Adresse tatsächlich auf dieses Deployment zeigt.~~ **erledigt.**
3. ~~Zeigt keine stabil darauf, einen expliziten Alias setzen.~~ **erledigt 2026-08-10:**
   `neximmo-staging.vercel.app`, als Repository-Variable `VERCEL_STAGING_ALIAS` persistiert;
   jeder Auto-Deploy verschiebt den Alias.
4. Erst die so **bewiesene** Adresse wird Site URL. — **offen.**

Keine eigene Domain, kein DNS, nicht `app.neximmo.de`. Ein dediziertes Vercel Custom
Environment mit angehängter Domain wäre die komfortablere Lösung, setzt aber den Pro-Plan
voraus (Pro: 1 Custom Environment pro Projekt) — für den ersten Aufbau nicht nötig.

---

## 8. Auth und Redirects

**Stand 2026-08-10 (`STAGING-PASSWORD-AUTH-01`):** primärer Login ist E-Mail + Passwort →
`aal1` → TOTP → `aal2`; MFA/TOTP aktiv und Signup aus sind remote **gesetzt**. Site URL und
`neximmo://auth/callback` sind weiterhin **offen** und folgen mit dem Recovery-Paket. Der
folgende Befund beschreibt den Magic-Link-Pfad, der nur noch für Recovery relevant ist.

**Der bestimmende Codebefund:** `_platformPasswordlessRedirectTo()` liefert auf Web `null`.
Web sendet also **kein** `emailRedirectTo`; der Magic Link landet ausschließlich auf der
Site URL des Projekts.

| Einstellung | Wert |
|---|---|
| Site URL | die in Abschnitt 7 bewiesene stabile Staging-Adresse |
| Zusätzliche Redirect-URLs | `neximmo://auth/callback` |
| MFA / TOTP | aktivieren |
| Offene Registrierung | **aus** |

`neximmo://auth/callback` ist nicht optional: ohne diesen Eintrag verwirft GoTrue den
Redirect und der Windows-Login gegen Staging bricht.

Von Redirect-Wildcards wird abgeraten. Sie weiten die Allowlist und bringen für unseren
Flow nichts, weil Web gar keinen Redirect mitschickt.

**Signup-Policy:** Die App ruft für den primären Login `signInWithPassword`; der OTP-Pfad
`signInWithOtp(shouldCreateUser: false)` bleibt nur für Recovery — sie legt also
selbst nie Nutzer an. Offene Registrierung bleibt deshalb aus; die Testnutzer werden
administrativ erzeugt, ausschließlich synthetisch. Dafür ist **keine** Produktcodeänderung
nötig.

---

## 9. SMTP

Der eingebaute Supabase-Mailversand ist für diesen Zweck unbrauchbar. Die Dokumentation ist
eindeutig: „Supabase Auth will refuse to deliver messages to addresses that are not part of
the project's team", und das Limit liegt bei **2 Nachrichten pro Stunde**.

Seit `STAGING-PASSWORD-AUTH-01` (2026-08-10) hängt der normale Login nicht mehr an SMTP:
Anmeldung, Wiederanmeldung und MFA laufen über Passwort + TOTP, und die Auth-/MFA-Closeouts
vom 2026-08-23 liefen mit SMTP `NOT CONFIGURED`. Custom SMTP wird erst für
Passwort-Recovery-/Magic-Link-Flows gebraucht; es hebt das Limit laut Doku zunächst auf
30 Nachrichten pro Stunde.

Custom SMTP braucht dafür: Host, Port, Username, Password, Absenderadresse,
Absendername. Diese Werte leben **ausschließlich** in der Supabase-Auth-Konfiguration bzw.
einem sicheren Admin-Kontext — niemals im Flutter-Client, niemals in einem `--dart-define`.

**Kein Anbieter ausgewählt, kein Account angelegt.**

---

## 10. Deploy-Ablauf, wenn alles steht

```text
workflow_run(Flutter, push auf main, success)   → SHA = head_sha, Stale-Main-Guard
  → Gate 1: STAGING_DEPLOY_ENABLED == true      (außerhalb des Environments, kein Secret)
  → Environment staging                          (Branch-Policy main, kein Reviewer)
  → Checkout genau dieses SHA, verifiziert
  → vier Required Checks auf diesem SHA == success
  → 5/5 Werte vorhanden                          (nur Presence, keine Werte im Log)
  → flutter build web (staging defines)
  → Artefakt-Prüfung: index.html, vercel.json, Rewrite → /index.html,
    keine Server-Credential-Marker, keine git-Policy im Artefakt
  → vercel@58.9.0 deploy build/web               (kein --prod, kein --target)
  → vercel alias set <preview-url> neximmo-staging.vercel.app
```

(Seit `STAGING-DEPLOY-ACTIVATION-01` am 2026-08-10; der ursprünglich vorbereitete
`workflow_dispatch(sha)`-Einstieg ist durch `workflow_run` ersetzt.)

**Vor** jedem Deploy zusätzlich manuell prüfen: richtige App-Project-ID, richtige Team-ID,
Supabase-Host ist die Staging-Instanz, Root-Git-Autodeploy weiterhin deaktiviert.

**Nach** dem Deploy: Deployment-Target ist Preview, URL erreichbar, `/` lädt, `/properties`
lädt, Reload auf `/properties` lädt, Build-SHA notiert, und die App spricht ausschließlich
mit der Staging-Supabase-Instanz.

---

## 11. Was dieses Paket nicht beweisen kann

Vorbereitet und lokal geprüft war in `STAGING-PREP-01` der SPA-Fallback im Artefakt.
**Seither bewiesen** (2026-08-09/10/23/24, `05_phase_a_log.md`): die Remote-Migration (36/36),
das Rewrite-Verhalten auf Vercel (`/`, `/properties`, Reload, `/properties/abc123` → `200`),
die Behebung der Deployment Protection, die Stabilität der Alias-Adresse (bei jedem
Auto-Deploy neu gesetzt), die `aal2`-Ausstellung durch GoTrue sowie die Realtime-Zustellung
an einen echten Staging-Client inklusive Reconnect-Recovery und anonym dichter
Auth-/RLS-Grenze. **Weiterhin nicht bewiesen:** SMTP (nicht konfiguriert), die
Remote-Integration-Gates (Schritt 14) und das Remote-E2E der fünf
Schwester-Invalidation-Adapter (blockiert nur durch fehlende Staging-Daten/Permissions).

---

## 12. Supabase-Migrationen nach Staging (`staging_db_deploy.yml`)

Seit `STAGING-DB-MIGRATION-DEPLOY-01` rollt ein eigener, **manueller** Workflow die
Migrationen kontrolliert aus — die bisherigen Remote-Pushes waren beaufsichtigte
Einzelaktionen aus lokalen Sitzungen (Abschnitt 4). Der Zielzustand der Pipeline:

```text
STAGING
  PR → vollständige CI → Merge auf main
    → Web-Staging automatisch (web_deploy.yml, Abschnitt 10)
    → Supabase-Migrationen manuell: Actions → „Supabase Staging Migrations"
      → Run workflow auf main
    → Staging-E2E

PRODUCTION
  NICHT automatisch. Eine separate, zukünftige Release-/Promotion-Stufe mit
  eigener Entscheidung (DEC-017: Production bleibt nicht autorisiert).
```

**Staging DB deployment must never infer or reuse production project credentials.**

Ablauf des Workflows, fail-closed in dieser Reihenfolge:

```text
workflow_dispatch (nur main; jeder andere Ref ⇒ FAIL)
  → Gate: STAGING_DB_DEPLOY_ENABLED == "true"       (Repo-Variable, bewusst ungesetzt
                                                     bis ein Owner sie aktiviert)
  → Checkout genau des Dispatch-SHA, verifiziert und geloggt
  → vier Required Checks auf diesem SHA == success
  → Environment `staging`: SUPABASE_ACCESS_TOKEN,
    SUPABASE_PROJECT_REF_STAGING, SUPABASE_DB_PASSWORD_STAGING
    (nur Presence-Prüfung, nie Werte im Log)
  → Project-Ref-Allowlist: der Secret-Wert muss exakt das dokumentierte
    Staging-Projekt (Abschnitt 4) sein — ein vertauschtes Secret kann den
    Workflow nicht auf ein anderes Projekt richten. Wird Staging je neu
    provisioniert, ändert sich dieser Pin in einem eigenen Review-Commit.
  → Supabase-CLI exakt aus package.json (npm ci + Versions-Drift-Guard,
    wie der database-Job in flutter.yml)
  → supabase link --project-ref <Staging>            (Token genügt; Passwort nie argv)
  → History-Gate (tool/staging_migration_history_gate.sh before):
    lokal+remote / pending / remote-only / divergent strikt getrennt;
    remote-only, Mismatch, Ordnungslücke oder unlesbarer Zustand ⇒ STOP.
    Kein migration repair, kein Überspringen, kein --force, kein manuelles
    Eintragen in die History — dafür braucht es eine separate Owner-Freigabe.
  → supabase db push --linked --dry-run              (Preview: Anzahl + Versionen)
  → supabase db push --linked                        (forward-only; ohne
                                                     --include-all/-roles/-seed)
  → History-Gate (after): 0 pending, kein Mismatch; zweiter Dry-Run muss
    „up to date" melden
  → Read-only-Schema-Dump, geprüft auf erwartete Artefakte, danach verworfen
```

Rollback-Strategie: **forward-only.** Down-Migrationen laufen nie gegen Staging; die
Down-Pfade bleiben CI-Beweis (`supabase/tests_rollback/`, database-Job). Schlägt ein Push
fehl, endet der Run rot und der Zustand wird dokumentiert — kein automatisches
`db reset`, kein automatisches Down, kein `migration repair`.

Ein automatischer Staging-DB-Deploy nach jedem grünen Main-Lauf (analog Abschnitt 10)
darf erst aktiviert werden, nachdem der manuelle Pfad mindestens einmal nachweislich
erfolgreich gelaufen ist.

Aktivierung (einmalig, nach dem Merge dieses Workflows):

1. Environment-Secrets `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF_STAGING`,
   `SUPABASE_DB_PASSWORD_STAGING` im Environment `staging` hinterlegen.
2. Repo-Variable `STAGING_DB_DEPLOY_ENABLED=true` setzen.
3. Actions → „Supabase Staging Migrations" → Run workflow → Branch `main`.
4. Erster-Lauf-QC: der Dry-Run muss als pending exakt `20260903100000` und
   `20260903120000` zeigen (Remote-Head 36/36, Abschnitt 11). Zeigt er etwas
   anderes: Run abbrechen lassen bzw. FAIL akzeptieren, Zustand berichten,
   nichts reparieren.
