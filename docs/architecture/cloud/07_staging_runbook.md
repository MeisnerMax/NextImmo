# Staging-Runbook

Stand: 2026-08-09 · Basis `a371d22` · Vorbereitet in `STAGING-PREP-01`

**Nichts hiervon ist ausgeführt.** Dieses Dokument beschreibt, was nach einem ausdrücklichen
`DEC-017`-ACCEPT zu tun ist.

`DEC-017` ist seit dem **2026-08-09 `accepted`** — für genau eine isolierte Umgebung mit
ausschließlich synthetischen Daten. Eine Remote-Umgebung existiert trotzdem **nicht**:
freigegeben ist nicht angelegt.

Zusätzlich gilt die **Kostenregel** aus `DEC-017`: was ohne Zusatzkosten in bestehende
Kontingente passt, darf entstehen; alles mit einem von null verschiedenen Kostenpunkt hält
an und braucht eine gesonderte Freigabe mit Anbieter, Tarif, einmaligen und monatlichen
Kosten und Kündbarkeit. In diesem Runbook betrifft das konkret Supabase (Abschnitt 4),
Custom SMTP (Abschnitt 9) und jede Vercel-Planänderung oder kostenpflichtige
Protection-Funktion (Abschnitt 6).

---

## 1. Was der Deploy-Pfad heute tut

Der Workflow ist **inert** und zwar über zwei voneinander unabhängige Sperren:

1. Die Repository-Variable `STAGING_DEPLOY_ENABLED` muss `true` sein. Sie ist kein Secret,
   und sie ist **nicht gesetzt**.
2. Innerhalb des Environments `staging` müssen **alle fünf** Werte vorhanden sein.

Die erste Sperre existiert nicht nur zur Bequemlichkeit. GitHub legt ein referenziertes
Environment beim ersten Lauf automatisch an — laut Dokumentation „will not have any
protection rules or secrets configured". Solange der Deploy-Job nicht laufen darf, kann er
das Environment auch nicht in diesem ungeschützten Zustand erzeugen.

Es gibt **keinen** automatischen Trigger mehr. Ein Staging-Deploy ist `workflow_dispatch`
mit einem ausdrücklichen Commit-SHA, und der Workflow verweigert die Arbeit, wenn auf
diesem SHA nicht alle vier Required Checks `success` sind.

---

## 2. Reihenfolge der Aktivierung

Diese Reihenfolge ist bewusst: erst die Umgebung, dann die Secrets, dann der Schalter.
Wer den Schalter zuerst setzt, riskiert genau das ungeschützte Auto-Environment.

1. ~~`DEC-017` entscheiden.~~ **erledigt am 2026-08-09, `accepted`.**
2. Supabase-Staging-Projekt anlegen (Abschnitt 4).
3. GitHub-Environment `staging` **manuell** anlegen und konfigurieren (Abschnitt 3).
4. Die fünf Werte als **Environment**-Secrets hinterlegen, nicht repositoryweit.
5. Vercel Deployment Protection klären (Abschnitt 6).
6. `STAGING_DEPLOY_ENABLED=true` setzen.
7. Deploy auslösen, stabile URL feststellen (Abschnitt 7).
8. Erst jetzt Supabase Site URL und Redirects setzen (Abschnitt 8).
9. Golden Paths fahren.

---

## 3. GitHub-Environment `staging`

Das Repository ist **public**; Environments und Schutzregeln stehen damit unabhängig vom
Plan zur Verfügung. (Für private Repositories wäre laut GitHub-Doku mindestens Pro/Team
nötig.)

| Einstellung | Empfehlung | Grund |
|---|---|---|
| Name | `staging` | exakt so referenziert der Workflow |
| Environment-Secrets | die fünf Deploy-Werte | so eng wie möglich gescopet |
| Required reviewers | **ja**, du selbst | ein Remote-Deploy soll eine bewusste Handlung bleiben |
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

1. Supabase CLI prüfen: **genau 2.109.1** (`npx supabase --version`), wie in `package.json`
   gepinnt.
2. Projekt anlegen; Project Ref und Region **doppelt** verifizieren.
3. Bestätigen, dass das Projekt leer ist.
4. Admin-Auth herstellen (`supabase login`), Zugangsdaten nicht dauerhaft ablegen.
5. Projekt kontrolliert linken (`supabase link --project-ref <ref>`).
6. Remote-Migrationshistorie **vor** dem Push auslesen (`supabase migration list --linked`)
   — Erwartung: leer.
7. Lokalen Migrationssatz zählen — Erwartung: **35**.
8. Ausstehende Migrationen prüfen, soweit die CLI das unterstützt.
9. `supabase db push --linked`.
10. Migrationshistorie **danach** vergleichen — Erwartung: dieselben 35, gleiche Reihenfolge.
11. `supabase db lint --linked --level error --fail-on error`.
12. Advisors: `security` und `performance`.
13. pgTAP-Suite.
14. Relevante Integration-Gates.
15. Realtime prüfen.
16. **Erst danach** Auth konfigurieren (Abschnitt 8).
17. **Erst danach** synthetische Golden-Path-Daten erzeugen.

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

---

## 7. Stabile Staging-Adresse

Supabase braucht **eine** Site URL. Wechselnde Deployment-URLs funktionieren nicht.

Laut Vercel-Doku erhält ein CLI-Deployment eine URL der Form
`<project-name>-<scope-slug>.vercel.app` — hier `appneximmode-meisners-projects.vercel.app`.
Die Doku merkt aber an, dass diese URL nach einem Production-Deployment auf Production
zeigt, und das Projekt **hat** historische Production-Deployments aus der Zeit vor
`DEPLOY-DRIFT-01`.

Daraus folgt: **die URL wird nicht vorab festgeschrieben.** Ablauf stattdessen:

1. Ersten Staging-Deploy fahren.
2. Prüfen, welche stabile Adresse tatsächlich auf dieses Deployment zeigt.
3. Zeigt keine stabil darauf, einen expliziten Alias setzen.
4. Erst die so **bewiesene** Adresse wird Site URL.

Keine eigene Domain, kein DNS, nicht `app.neximmo.de`. Ein dediziertes Vercel Custom
Environment mit angehängter Domain wäre die komfortablere Lösung, setzt aber den Pro-Plan
voraus (Pro: 1 Custom Environment pro Projekt) — für den ersten Aufbau nicht nötig.

---

## 8. Auth und Redirects

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

**Signup-Policy:** Die App ruft `signInWithOtp(shouldCreateUser: false)` — sie legt also
selbst nie Nutzer an. Offene Registrierung bleibt deshalb aus; die Testnutzer werden
administrativ erzeugt, ausschließlich synthetisch. Dafür ist **keine** Produktcodeänderung
nötig.

---

## 9. SMTP

Der eingebaute Supabase-Mailversand ist für diesen Zweck unbrauchbar. Die Dokumentation ist
eindeutig: „Supabase Auth will refuse to deliver messages to addresses that are not part of
the project's team", und das Limit liegt bei **2 Nachrichten pro Stunde**.

Der Staging-Golden-Path braucht zwei Benutzer und mehrere Auth-Vorgänge — Anmeldung,
Wiederanmeldung, MFA. Mit eingebautem Versand ist er weder durchführbar noch wiederholbar.
Custom SMTP hebt das Limit laut Doku zunächst auf 30 Nachrichten pro Stunde.

`STAGING-PROVISION-01` braucht dafür: Host, Port, Username, Password, Absenderadresse,
Absendername. Diese Werte leben **ausschließlich** in der Supabase-Auth-Konfiguration bzw.
einem sicheren Admin-Kontext — niemals im Flutter-Client, niemals in einem `--dart-define`.

**Kein Anbieter ausgewählt, kein Account angelegt.**

---

## 10. Deploy-Ablauf, wenn alles steht

```text
workflow_dispatch(sha)
  → Gate 1: STAGING_DEPLOY_ENABLED == true      (außerhalb des Environments, kein Secret)
  → Environment staging                          (Schutzregeln greifen)
  → Checkout genau dieses SHA, verifiziert
  → vier Required Checks auf diesem SHA == success
  → 5/5 Werte vorhanden                          (nur Presence, keine Werte im Log)
  → flutter build web (staging defines)
  → Artefakt-Prüfung: index.html, vercel.json, Rewrite → /index.html,
    keine Server-Credential-Marker, keine git-Policy im Artefakt
  → vercel@58.9.0 deploy build/web               (kein --prod, kein --target)
```

**Vor** jedem Deploy zusätzlich manuell prüfen: richtige App-Project-ID, richtige Team-ID,
Supabase-Host ist die Staging-Instanz, Root-Git-Autodeploy weiterhin deaktiviert.

**Nach** dem Deploy: Deployment-Target ist Preview, URL erreichbar, `/` lädt, `/properties`
lädt, Reload auf `/properties` lädt, Build-SHA notiert, und die App spricht ausschließlich
mit der Staging-Supabase-Instanz.

---

## 11. Was dieses Paket nicht beweisen kann

Vorbereitet und lokal geprüft ist der SPA-Fallback im Artefakt. **Nicht** bewiesen sind:
das Rewrite-Verhalten auf Vercel selbst, die Behebung der Deployment Protection, die
Stabilität der Alias-Adresse, SMTP und die Remote-Migration. Diese Nachweise entstehen erst
in `STAGING-PROVISION-01`, gegen eine reale Umgebung.
