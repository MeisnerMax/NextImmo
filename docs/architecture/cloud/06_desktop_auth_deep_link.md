# Desktop Auth Deep Link (AUTH-DL-01)

Stand: 2026-08-08 · Branch `auth/desktop-deep-link` · Basis `3a2985c`

Windows schließt den Supabase-Authentifizierungsflow über einen eigenen URI-Handler ab.
Der Browser führt die Anmeldung durch, der Callback landet in der Desktop-App, und die
bestehende Cloud-Security-Architektur entscheidet über den nächsten Screen.

## Kanonische Callback-URI

```text
neximmo://auth/callback
```

Es gibt genau diese eine. Sie ist an drei Stellen verankert und muss dort synchron bleiben:

| Ort | Rolle |
| --- | --- |
| `lib/features/identity_access/application/desktop_auth_callback.dart` | `desktopAuthCallbackUri`, die Quelle der Wahrheit |
| `windows/runner/main.cpp` | `kAuthScheme`, Registrierung des Schemes bei Windows |
| `supabase/config.toml` | `additional_redirect_urls`, ohne die GoTrue den Redirect verwirft |

Eine zweite parallele Callback-URI wird nicht eingeführt. Die Redirect-Allowlist ist eine
Sicherheitsgrenze; jeder zusätzliche Eintrag weitet sie auf.

## Flow

```text
App: signInWithOtp(emailRedirectTo: neximmo://auth/callback)
  ↓
Browser / Mailclient öffnet den Magic Link
  ↓
GoTrue redirected auf neximmo://auth/callback?code=...
  ↓
Windows URI-Handler (HKCU\Software\Classes\neximmo)
  ↓
warm: zweiter Prozess leitet per WM_COPYDATA weiter und beendet sich
cold: Prozess startet, app_links liest die URI von der Kommandozeile
  ↓
DesktopAuthDeepLinkObserver  →  classifyDesktopAuthCallback (fail closed)
  ↓
getSessionFromUrl  →  Session  →  onAuthStateChange
  ↓
SupabaseSecurityGate  →  Workspace/App
```

## Warm Start

Ein Klick auf den Link, während die App läuft, startet zunächst einen **zweiten** Prozess —
Windows kennt keine laufende Instanz, es startet schlicht den registrierten Befehl.
`ForwardAppLinkToRunningInstance()` in `windows/runner/main.cpp` fängt das ab: existiert
bereits ein Fenster der Klasse `FLUTTER_RUNNER_WIN32_WINDOW` mit dem Titel `neximmo_app`,
übergibt der neue Prozess seine Kommandozeile per `SendAppLink()` (exportiert vom
`app_links`-Plugin, intern `WM_COPYDATA`) und beendet sich, bevor er irgendetwas erzeugt.

Der Weiterleitungspfad greift **nur** bei Protokollstarts. Die Prüfung spiegelt exakt
`AppLinksPlugin::GetLink()`: genau ein Argument, und dieses muss mit einem URI-Scheme
beginnen. Ein normaler zweiter Start der App verhält sich unverändert.

## Cold Start

Ist keine Instanz offen, registriert der startende Prozess das Scheme neu (`HKCU`, ohne
Elevation) und läuft normal hoch. `app_links` liest die URI aus der Kommandozeile und gibt
sie in dem Moment in den Stream, in dem Dart sich abonniert — also während
`Supabase.initialize()`, vor `runApp`. Die initiale URI kann daher nicht verloren gehen.

## Deduplication

Beide Wege können denselben Klick beschreiben, und ein PKCE-Code ist einmal einlösbar. Ein
zweiter Austausch scheitert am verbrauchten Code und würde einem bereits angemeldeten
Nutzer als Anmeldefehler erscheinen.

`DesktopAuthDeepLinkObserver` merkt sich deshalb die eingelösten Credentials — Schlüssel ist
`code:<wert>` bzw. `access_token:<wert>`, also genau das, was nicht zweimal eingelöst werden
darf. Vermerkt wird **vor** dem Austausch, nicht danach: die zweite Zustellung kann
eintreffen, während der erste Austausch noch läuft. Der Speicher ist auf 32 Einträge
begrenzt, weil das Scheme systemweit offen ist und eine feindliche Seite sonst unbegrenzt
viele verschiedene Links erzeugen könnte.

## Fail closed

`supabase_flutter` bringt einen eigenen Deep-Link-Observer mit, der **jede** URI mit einem
`code`-Parameter an den Session-Austausch weiterreicht — ohne Scheme, Host oder Pfad zu
prüfen (`_isAuthCallbackDeeplink` in `supabase_auth.dart`). Sobald die App `neximmo:`
systemweit registriert, kann jede Webseite eine solche URI erzeugen.

Deshalb ist dieser Observer auf Desktop abgeschaltet (`detectSessionInUri: kIsWeb`) und die
App klassifiziert selbst. `classifyDesktopAuthCallback` prüft in dieser Reihenfolge und
lehnt beim ersten Treffer ab:

| Fall | Ergebnis |
| --- | --- |
| Scheme ≠ `neximmo` | ignoriert |
| Host ≠ `auth` | ignoriert |
| Pfad ≠ `/callback` (tiefer oder anders) | ignoriert |
| URI unparsebar oder Query nicht dekodierbar | ignoriert |
| keine Auth-Parameter | ignoriert |
| `error` / `error_code` / `error_description` gesetzt | kontrollierter Auth-Fehler, **kein** Austausch |
| `code` oder `access_token` vorhanden | Austausch |

Ein Callback, der einen Fehler meldet und trotzdem einen `code` mitführt, wird als Fehler
behandelt — der Code gehört zu einer Anfrage, die der Provider abgelehnt hat.

## Web

Web bleibt unverändert. `detectSessionInUri` ist dort weiterhin `true`, weil der Browser den
Redirect selbst besitzt und der SDK-Pfad der richtige ist. `emailRedirectTo` bleibt auf Web
`null`, also die Site URL des Projekts: ein Custom Scheme würde den Browser auf eine URL
schicken, die er nicht öffnen kann. Die Plattformweiche sitzt in
`_platformPasswordlessRedirectTo()` und ist per `debugDefaultTargetPlatformOverride`
getestet, damit die Erwartung auf jedem Host gilt und nicht nur auf Windows.

## Rescue-Matrix

Der Bestand aus `rescue/codex-ai-ph00-baseline` wurde vollständig gelesen und gegen `3a2985c`
bewertet, nicht cherry-gepickt.

### PORTED

- `neximmo://auth/callback` als kanonische URI
- `emailRedirectTo`-Durchreichung Gateway → Adapter (Parameter am Gateway heißt jetzt
  `redirectTo`, damit die GoTrue-Semantik nicht durch die Schichten durchpaust)
- `_platformPasswordlessRedirectTo()` — Windows ja, Web und Rest nein
- `additional_redirect_urls` in `supabase/config.toml`
- `RegisterAuthProtocol()` im Windows-Runner; das Scheme kommt jetzt aus einer Konstante
  statt dreifach als Literal

### REIMPLEMENTED

- Warm-Start-Weiterleitung an die laufende Instanz — im Rescue **nicht vorhanden**; ohne sie
  startet ein Klick bei laufender App eine zweite Instanz
- Fail-closed-Validierung von Scheme, Host, Pfad und Parametern — im Rescue **nicht
  vorhanden**; der SDK-Observer prüft keine Herkunft
- Deduplication/Replay-Schutz — im Rescue **nicht vorhanden**
- `app_links` direkt statt nur transitiv, weil der neue Observer importiert

### SUPERSEDED

- alter `CloudAppScaffold`
- alte `app.dart`
- Backend-Switch und SQLite-Runtimepfad (AP-X02-2b, `DEC-024`)
- alte Workflow-/Timeout-Konfiguration

### NOT PORTED

- `docs/ai/**` inklusive `auth_session_evidence.md` — eigenes, gesperrtes Arbeitspaket; nur
  als Audit-Quelle gelesen
- Rescue-`pubspec.lock` — anderer Auflösungsstand

Ausdrücklich bestätigt: kein alter `CloudAppScaffold`, keine alte `app.dart`, kein alter
Workflow und kein Timeout daraus, und keine veraltete SQLite-Backendannahme sind in dieses
Paket zurückgekommen.

## Dependency

`app_links` war bereits als transitive Abhängigkeit von `supabase_flutter` in Version 6.4.1
im Baum und wird dort für genau diesen Zweck verwendet. Für den Import ist sie jetzt direkt
deklariert. Das Lockfile-Delta ist eine Zeile — `dependency: transitive` →
`dependency: "direct main"` — es kommt kein neues Paket in den Build.

## Windows Protocol Handler Smoke (2026-08-08)

Ausgangszustand read-only geprüft: `HKCU\Software\Classes\neximmo` existierte nicht, kein
HKLM-Eintrag, keine laufende Instanz — FALL A. Die Registration wurde von der App selbst
erzeugt (Start des Release-Builds dieses Worktrees, `HKCU`, keine Elevation) und nach dem
Test vollständig entfernt; der Endzustand entspricht exakt dem Ausgangszustand.

Beobachtungskanal war das lokale GoTrue. Ein zugestellter Implicit-Flow-Callback erreicht
`getUser(accessToken)` und erzeugt genau einen `GET /auth/v1/user`; ein abgelehnter Callback
erzeugt keinen. Verwendet wurden synthetische Tokens, die GoTrue erwartungsgemäß mit
`bad_jwt` zurückweist — es entstand keine echte Session, und es waren keine
Produktions-Credentials im Spiel.

| Schritt | Beobachtung | Bewertung |
| --- | --- | --- |
| Cold Start `neximmo://auth/callback#access_token=…` | Windows startet die Exe (PID 33960), **1** `/user`-Request | Callback erreicht den Auth-Layer, kein Crash |
| Warm Start, zweiter Callback | PID-Liste vor und nach identisch (nur 33960), **1** `/user`-Request | **keine zweite Prozessinstanz**, Delivery nicht verloren |
| Duplicate: identischer Callback erneut | **0** zusätzliche Requests | Replay-Guard greift zur Laufzeit |
| Fremder Host `neximmo://evil/callback` | **0** Requests | fail closed |
| Fremder Pfad `neximmo://auth/other` | **0** Requests | fail closed |

Die fremden URIs wurden von Windows tatsächlich dispatcht und über `SendAppLink` an die
laufende Instanz weitergereicht — die Ablehnung passiert im Validator der App, nicht dadurch,
dass die URI nie ankam. Das ist der eigentliche Punkt des Tests.

Zählweise: GoTrue schreibt für einen abgelehnten Request zwei Logzeilen mit `"path":"/user"`
(Fehlerzeile und `request completed`), für einen erfolgreichen eine. Die beobachteten Deltas
von 2 entsprechen damit je genau einem HTTP-Request.

Die automatisierten Dedup-/Replay-Tests bleiben die primäre Evidenz; der Smoke ist
zusätzliche Runtime-Evidenz.

## Bewiesen / noch offen

### Proven now

- URI-Klassifikation inkl. fremdem Scheme/Host/Pfad, unparsebarer URI, nicht dekodierbarer
  Query, fehlender Auth-Parameter, Provider-Fehler
- Deduplication sequentiell und nebenläufig
- Session-Handoff-Logik des Observers inkl. Fehlerpfaden
- plattformabhängige Auflösung des Redirects
- Windows-Release-Build mit Cloud-Defines; `neximmo_app.exe` importiert `SendAppLink` aus
  `app_links_plugin.dll`, der Warm-Start-Pfad ist also im Binary verlinkt
- lokaler Windows-Smoke: Development-Registrierung, Cold- und Warm-Delivery, Replay-Guard
  und Fail-closed-Verhalten (siehe oben)

Der Nachweis lautet damit ausschließlich:
`Development Windows protocol registration and warm/cold URI delivery verified locally.`

### Requires Staging

- echter Supabase-OAuth/PKCE-Browser-Roundtrip gegen eine Remote-Umgebung
- produktive E-Mail-Zustellung

### Production installer registration still open

Die Registrierung erfolgt heute beim Start unter `HKCU` und deckt damit Entwicklung und
lokal gestartete Release-Builds ab. Ein Installer/MSIX muss das Scheme zur Installationszeit
registrieren — vermutlich unter `HKLM` — und diesen Weg gibt es noch nicht. Der
Startup-Pfad ist ausdrücklich **kein** Nachweis für Production-Packaging.

## Environment-Setup später

Beim Aufsetzen von Staging und Production muss `neximmo://auth/callback` in die erlaubten
Redirect-URLs des jeweiligen Supabase-Projekts aufgenommen werden. Ohne diesen Eintrag
verwirft GoTrue den Redirect und die Mail zeigt auf die Site URL. Remote-Konfiguration
bleibt bis zum vorgesehenen Staging-Schritt unangetastet (`DEC-017` offen).
