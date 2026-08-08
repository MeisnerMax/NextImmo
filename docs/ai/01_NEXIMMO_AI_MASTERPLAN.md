# NexImmo Intelligence – verbindlicher Masterplan

Stand: 2026-08-02  
Dokumentstatus: Vorschlag zur Freigabe  
Umsetzungsstatus: Nicht begonnen  
Zielrelease: Kontrollierter KI-MVP für migrierte NexImmo-Cloud-Domains

## 1. Executive Decision

NexImmo Intelligence wird nicht als allgemeiner Chatbot und nicht als autonomer
Agent gebaut. Es wird eine quellengebundene, mandantenfähige Intelligence-Schicht,
die bestehende NexImmo-Fachlogik nutzt, Dokumente strukturiert auswertet,
Auffälligkeiten erklärt und Änderungen als überprüfbare Vorschläge vorbereitet.

Die erste produktive Version ist:

- cloudgebunden, während die übrige Anwendung offline-first nutzbar bleibt,
- lesend und vorschlagsorientiert,
- strikt berechtigungs- und objektspezifisch,
- vollständig quellen- und versionsgebunden,
- providerneutral auf Domain-Ebene,
- mit OpenAI Responses API als erster Provider-Implementierung,
- ohne direkte Schreibrechte des Modells,
- ohne Modellberechnung autoritativer Immobilienkennzahlen.

## 2. Ausgangslage und belegte Repository-Baseline

### 2.1 Branch-Situation

- `main` ist nicht der vollständigste App-Stand.
- `docs/add-claude-md` liegt in der Prüfung 43 Commits vor `main`.
- Drei Marketing-/Branding-Commits liegen nur auf `main`.
- Vor Featurearbeit ist ein kanonischer Branch durch Maintainer-Entscheidung zu
  bestimmen; eine automatische Zusammenführung ist nicht zulässig.

### 2.2 Technischer Stand

- Flutter-Anwendung für Windows/Desktop und Web.
- Historischer SQLite-Kern, inkrementelle Migration zu Supabase/Postgres.
- Deterministische Engines für Bewertung, Finanzierung, Kriterien, Angebote,
  Reporting, Datenqualität und weitere Fachlogik.
- Neue migrierte Features verwenden die Schichten `domain`, `application` und
  `data` sowie backendunabhängige Contracts und Adapter.
- Backendauswahl erfolgt im zentralen Composition Root.
- Kritische Mutationen sind workspacegebunden, versioniert, idempotent und auditierbar.
- Supabase-Migrationen verwenden Default-Deny-RLS, pgTAP- und Rollbacktests.

### 2.3 Bereits nutzbare Cloud-Domains

- Identity und Access
- Portfolio und Property
- Contacts und Parties
- Documents und Compliance
- Platform Audit und Jobs
- Valuation
- Reference Slice

Leasing, Finanzierung, CapEx und weitere operative Domains dürfen erst in die KI
einbezogen werden, nachdem ihre Cloudmigration und Berechtigungsmatrix die
jeweiligen Gates bestanden haben.

### 2.4 Zentrale Vorbedingungen

1. Branch-Konvergenz und grüne reproduzierbare Baseline.
2. Voll funktionsfähiger Desktop-Login und einheitliche Cloud-Shell.
3. Abschluss beziehungsweise bewusste Akzeptanz offener Cloud-, MFA- und
   Datenschutzentscheidungen.
4. Berechtigungssichere Such- und Retrieval-Schicht einschließlich Entity-Scopes.
5. Keine produktive API- oder Cloud-Provisionierung ohne gesonderte Freigabe.

## 3. Produktziel

NexImmo Intelligence soll Asset Manager in fünf Kernaufgaben unterstützen:

1. Informationen aus Immobilienunterlagen schneller erfassen.
2. Fälligkeiten, Lücken und Widersprüche früher erkennen.
3. Objekt- und Portfoliodaten nachvollziehbar abfragen.
4. fachlich berechnete Ergebnisse verständlich erklären.
5. standardisierte Berichte und Änderungsvorschläge vorbereiten.

Leitgedanke:

> Immobilien steuern. Nicht Dokumente durchsuchen oder Tabellen interpretieren.

## 4. Messbare MVP-Ergebnisse

Der MVP ist erfolgreich, wenn ein berechtigter Benutzer für die migrierten Domains:

- ein Dokument hochladen und bestätigen kann,
- nach der Bestätigung einen idempotenten Analysejob erhält,
- Dokumentart und definierte Felder als Vorschlag mit Quellen prüfen kann,
- Vorschläge einzeln annehmen oder ablehnen kann,
- Objektfragen mit belegten Quellen beantwortet bekommt,
- bei fehlenden Belegen eine klare Nicht-Ermittelbarkeit erhält,
- einen Managementkommentar aus deterministischen NexImmo-Kennzahlen erzeugen kann,
- jeden akzeptierten Änderungsvorgang im Audit nachvollziehen kann,
- nie Daten eines anderen Workspaces oder außerhalb seines Entity-Scopes sieht.

## 5. Nichtziele des MVP

- allgemeiner Wissenschat ohne Objektkontext,
- autonome Agenten mit freier Toolwahl,
- selbstständige Kündigungen, Freigaben, Zahlungen oder Kommunikation,
- Mieterauswahl, Bonitätsentscheidung oder automatisierte Personenbewertung,
- direkte Modellabfragen gegen SQL,
- ungeprüftes Schreiben in fachliche Tabellen,
- Ablösung vorhandener Berechnungsengines,
- cloudbasierte KI im SQLite-Offlinemodus,
- Analyse fachlich noch nicht migrierter Domains,
- kundenübergreifendes Training auf NexImmo-Inhalten,
- Voice, Bilderzeugung oder allgemeine Websuche im MVP.

## 6. Verbindliche Produktprinzipien

### P-01 Fachsystem bleibt Wahrheit

Nur NexImmo-Domaintabellen und deterministische Engines sind autoritativ. KI-Daten
sind abgeleitet, versioniert, löschbar und vollständig neu erzeugbar.

### P-02 Quelle vor Formulierung

Jede materielle Aussage hat mindestens eine Source Reference oder wird sichtbar als
unbelegte Hypothese beziehungsweise nicht ermittelbar gekennzeichnet.

### P-03 Vorschlag vor Mutation

Ein Modell darf Vorschläge erzeugen. Eine akzeptierte Änderung läuft anschließend
durch denselben Domain-Command wie eine manuelle Änderung.

### P-04 Berechtigung pro Werkzeug

`ai.use` öffnet nur die KI-Oberfläche. Jeder Lese- oder Vorschlags-Toolaufruf
benötigt zusätzlich die normale Domainberechtigung und den Entity-Scope.

### P-05 Dokumente sind untrusted

Text aus PDFs, Scans und importierten Dateien ist Dateninhalt, keine Anweisung.
Dokumente können keine Tools freischalten oder Systemregeln überschreiben.

### P-06 Providerneutraler Kern

Domain-, UI- und Persistenzschichten kennen keine OpenAI-SDK-Typen. Providerwechsel
oder Vergleichstests dürfen keinen Umbau der Fachlogik erfordern.

### P-07 Offline bleibt funktionsfähig

Fehlende KI-Verbindung darf bestehende lokale und deterministische Funktionen nicht
blockieren. Die UI zeigt „KI momentan nicht verfügbar“, ohne Fachworkflows zu sperren.

### P-08 Keine stillen Qualitätsverluste

Modell-, Prompt-, Embedding-, Chunking- oder Schemastrategien werden nur nach
Regressionsevaluation geändert.

## 7. Zielgruppen und Rollen

| Rolle | Primäre KI-Nutzung | Ausgeschlossene Aktionen |
| --- | --- | --- |
| Admin | Policies, Budgets, Audit, Modellfreigaben | Keine Umgehung fachlicher Rechte |
| Manager | Portfolio-Brief, Risiken, Berichte, Vorschlagsfreigaben | Keine ungeprüften Massenschreibvorgänge |
| Analyst | Dokumentprüfung, Bewertungserklärung, Datenqualität | Keine administrativen Freigaben |
| Operations | Fristen, Aufgaben, Dokumentlücken | Keine Bewertungs- oder Finanzfreigaben |
| Viewer | belegte Zusammenfassungen und Q&A | Keine Vorschläge annehmen oder Daten ändern |

Die tatsächlichen Capabilities bleiben ausschlaggebend; Rollennamen sind nur
Zusammenfassungen vorhandener Einzelrechte.

## 8. Funktionsportfolio

### 8.1 MVP – Priorität 1

#### F-01 Dokumentklassifikation

- Dokumenttyp aus freigegebener Taxonomie vorschlagen.
- Property-, Party- und optional Portfoliozuordnung vorschlagen.
- Mehrdeutigkeit sichtbar machen.
- Keine automatische finale Klassifikation bei unzureichendem Beleg.

#### F-02 Strukturierte Extraktion

Erste unterstützte Dokumentarten:

- Mietvertrag und Nachtrag,
- Rechnung,
- Versicherungspolice,
- Energieausweis,
- Bewertungsunterlage,
- Darlehensunterlage nur als Dokumentinformation, nicht als autoritative
  Finanzierungsbuchung.

Feldgruppen:

- Parteien und Rollen,
- Objekt-/Einheitenbezug,
- Vertragsbeginn und -ende,
- Kündigungs- und Verlängerungsfristen,
- Beträge, Währung und Periodizität,
- Indexierungs- und Anpassungsklauseln,
- Pflichten, Sicherheiten und relevante Termine,
- Ausstellungs-, Gültigkeits- und Ablaufdaten.

#### F-03 Review Inbox

- Liste offener KI-Artefakte.
- Filter nach Workspace, Property, Typ, Status und Dringlichkeit.
- Feldweiser Vergleich: aktueller Wert, Vorschlag, Quelle.
- Annehmen, ablehnen, korrigieren oder zurückstellen.
- Versionskonfliktprüfung beim Annehmen.
- vollständige Auditspur.

#### F-04 Kontextbezogenes Q&A

- Fragen zu freigegebenen Properties, Parties, Dokumenten und Bewertungen.
- Hybrid Retrieval aus strukturierten Tools und Dokumentchunks.
- Quellenpanel mit Dokumentversion, Seite und Textausschnitt.
- Antwortkategorien: belegt, deterministisch abgeleitet, KI-Inferenz,
  nicht ermittelbar.

#### F-05 Bewertungs- und Kennzahlenerklärung

- Bestehende Engineergebnisse über read-only Tools beziehen.
- Rechenschritte und Eingangsdaten aus dem Fachsystem erklären.
- keine eigenständige autoritative Neuberechnung durch das Modell.

#### F-06 Managementkommentar

- Zusammenfassung eines Objekts oder Portfolios.
- Veränderungen, Datenlücken und fachlich erkannte Auffälligkeiten erläutern.
- Ausgabe mit Quellenverzeichnis und Datenstichtag.
- Status „Entwurf“, bis ein Benutzer den Bericht fachlich freigibt.

### 8.2 Nach MVP – Priorität 2

- Portfolio Attention Center.
- Vorschläge für Aufgaben und Compliance-Nachverfolgung.
- Dublettenerkennung bei Parties und Dokumenten.
- semantische Importzuordnung.
- Due-Diligence-Paket über mehrere Dokumente.
- standardisierte Monats- und Quartalsberichte.
- Feedbackgestütztes Modell-/Prompt-Routing.

### 8.3 Erst nach jeweiliger Domainmigration

- Leasing-Fristen und Optionsmanagement.
- Mietrückstands- und Forderungserklärungen.
- Covenant- und Finanzierungsüberwachung.
- CapEx-Risiken und Projektstatus.
- Szenariovergleich und Investment-Memo.

## 9. UX- und Informationsarchitektur

### 9.1 Kein schwebender Universalchat

Die primäre Oberfläche ist ein kontextuelles Intelligence Panel innerhalb der
vereinheitlichten NexImmo-Shell:

- Desktop: rechte, größenveränderbare Seitenleiste.
- Tablet: Drawer oder breites Bottom Sheet.
- Smartphone: eigener Fullscreen-Flow.
- Web und Desktop verwenden dieselben fachlichen Contracts.

### 9.2 Zentrale Oberflächen

#### A. Intelligence Panel

- übernimmt sichtbaren Objekt-/Dokumentkontext,
- zeigt den genauen aktiven Scope,
- erlaubt Kontextwechsel nur auf freigegebene Entitäten,
- führt Antwort, Quellen und mögliche Folgeaktionen getrennt auf.

#### B. Review Inbox

- eigener Arbeitsbereich für KI-Vorschläge,
- keine versteckten Autoänderungen,
- Bulk-Aktionen im MVP deaktiviert,
- Korrekturen als Feedback erfassen.

#### C. Source Drawer

- Dokumentname und immutable Version,
- Seite beziehungsweise Abschnitt,
- markierter Textausschnitt,
- Link zur Originalansicht,
- Kennzeichnung, ob Wert exakt, deterministisch abgeleitet oder inferiert ist.

#### D. Portfolio Attention Center

- bestehende Portfolio-Atlas-Idee als ruhige, hochwertige Navigation beibehalten,
- KI nicht als zusätzliche Kartenflut darstellen,
- nur priorisierte Abweichungen und Handlungsbedarfe,
- Detailpanel ohne Verlust des Portfoliokontexts.

### 9.3 Pflichtzustände

Jede KI-UI benötigt:

- Loading und Streaming,
- Queue/Wartend,
- Empty,
- Forbidden,
- Offline,
- Timeout,
- Providerfehler,
- unlesbares Dokument,
- unzureichende Quellen,
- Versionskonflikt,
- Budgetlimit erreicht,
- abgebrochener und wiederholbarer Job.

## 10. Zielarchitektur

### 10.1 Komponentenfluss

1. Flutter-UI ruft einen backendunabhängigen Application Contract auf.
2. Der Supabase-Adapter ruft eine kontrollierte Edge Function oder einen Worker auf.
3. Die Serverkomponente validiert JWT, Workspace, Capabilities und Entity-Scope.
4. Eine Policy Engine erzeugt die erlaubte Toolliste und Modellrichtlinie.
5. Read-only Domain Tools liefern strukturierte, bereits berechtigte Daten.
6. Dokument-Retrieval liefert nur erlaubte, versionierte Chunks.
7. Die Responses API erzeugt ein strikt strukturiertes Ergebnis.
8. Validatoren prüfen Schema, Quellenabdeckung und zulässige Vorschlagsfelder.
9. Ein immutable KI-Artefakt wird gespeichert und im Review angezeigt.
10. Erst nach Benutzerannahme führt ein normaler Domain-Command die Änderung aus.

### 10.2 Vorgeschlagene Flutter-Modulgrenze

```text
lib/features/ai_orchestration/
  domain/
    ai_artifact_dto.dart
    ai_source_ref_dto.dart
    ai_job_dto.dart
    ai_suggestion_dto.dart
  application/
    ai_query_contract.dart
    ai_job_repository.dart
    ai_review_repository.dart
    ai_feedback_repository.dart
    commands/
    queries/
  data/
    supabase_ai_query_adapter.dart
    supabase_ai_job_adapter.dart
    unavailable_local_ai_adapter.dart
  presentation/
    providers/
    widgets/
    screens/
```

Die genaue Struktur ist erst nach Phase `PH-01` zu bestätigen. Bestehende
Repository- und Featurekonventionen haben Vorrang.

### 10.3 Servergrenze

Vorgeschlagene Funktionen beziehungsweise Worker-Verantwortungen:

- `ai-query`: interaktive, read-only, berechtigungsgebundene Anfragen,
- `ai-document-enqueue`: idempotentes Enqueue nach bestätigter Dokumentversion,
- `ai-document-worker`: Verarbeitung, Validierung und Artefakterzeugung,
- `ai-review-apply`: kein Modellaufruf; validiert Annahme und ruft Domain-Command,
- `ai-feedback`: speichert Korrektur-/Ablehnungsgrund,
- `ai-admin-policy`: Budget, Modellpolicy und Kill-Switch für berechtigte Admins.

Funktionsnamen sind Vorschläge und dürfen an bestehende Konventionen angepasst werden.

### 10.4 Provider-Abstraktion

Interne Schnittstellen:

- `ModelGateway`
- `EmbeddingGateway`
- `DocumentTextExtractor`
- `AiPolicyResolver`
- `AiToolRegistry`
- `AiOutputValidator`
- `AiUsageRecorder`

Nur die Infrastructure-Schicht kennt OpenAI-Endpunkte oder SDK-Typen. Die erste
Implementierung verwendet die OpenAI Responses API mit Function Calling und
Structured Outputs. Ein späterer Claude-Adapter ist nur nach denselben Evals zulässig.

## 11. Datenmodell

Alle Tabellen erhalten Workspace-Scoping, RLS, Auditbezug, Zeitstempel und die im
Repository etablierten Namens-/ID-Konventionen. Die folgenden Namen sind logisch und
vor Migrationserstellung gegen die aktuelle Datenarchitektur zu prüfen.

### 11.1 `ai_jobs`

Pflichtfelder:

- `id`
- `workspace_id`
- `job_type`
- `status`
- `entity_type`, `entity_id`
- `source_version_id`
- `requested_by`
- `model_policy`
- `provider`, `model_snapshot`
- `prompt_version`, `schema_version`
- `input_hash`, `idempotency_key`
- `attempt_count`
- `started_at`, `finished_at`
- `error_code`, redigierte `error_detail`
- `input_tokens`, `output_tokens`, `estimated_cost`
- `correlation_id`

Statusautomat mindestens:

`queued -> running -> succeeded | failed | canceled | superseded`

Erlaubte Retries und Übergänge sind serverseitig zu erzwingen.

### 11.2 `ai_artifacts`

- immutable Ergebnis eines Jobs,
- `artifact_type`, `schema_version`, strukturiertes Payload,
- `status`: `proposed`, `accepted`, `rejected`, `corrected`, `superseded`,
- Quell- und Input-Hashes,
- Erzeugungsmodell und Promptversion,
- kein Überschreiben eines alten Artefakts.

### 11.3 `ai_source_refs`

- Referenz auf Artefakt und einzelne Aussage/Feld-ID,
- `source_type`: Domainfeld oder Dokumentchunk,
- Entität und Version,
- Dokumentversion, Seite, Chunk und optionale Zeichenposition,
- kurzer Anzeigeausschnitt, sofern datenschutzrechtlich zulässig,
- Validatorstatus.

### 11.4 `semantic_chunks`

- Workspace und Source-Entität,
- immutable Source-Version,
- Dokumentseite/Abschnitt,
- normalisierter Text,
- Content-Hash,
- Embedding und Embedding-Version,
- benötigte Permission,
- Entity-Scope-Daten,
- Erstellungs- und Ableitungsstatus,
- Tombstone beziehungsweise `deleted_at` für kontrollierten Reindex.

### 11.5 `ai_feedback`

- Artefakt/Feld,
- Entscheidung und optional korrigierter Wert,
- kategorisierter Ablehnungsgrund,
- Actor, Timestamp und Korrelation,
- Nutzung nur für Evaluation; kein automatisches Training im MVP.

### 11.6 `ai_usage_events`

- Workspace, Benutzer, Use Case,
- Modell und Version,
- Token, Dauer, Erfolg/Fehler und Kosten,
- keine Prompts oder vollständigen Dokumenttexte in Standardlogs.

## 12. Ereignis- und Jobmodell

### 12.1 Startsignal

Nach erfolgreicher Bestätigung einer immutable Dokumentversion wird ein dauerhaftes
Domain Event `document.content_confirmed` beziehungsweise ein gleichwertiges
versioniertes Ereignis veröffentlicht.

### 12.2 Idempotenz

Der eindeutige Verarbeitungsschlüssel basiert mindestens auf:

`workspace + document_version + content_hash + job_type + prompt_version + schema_version`

Ein Retry darf kein zweites fachlich gleiches aktives Artefakt erzeugen.

### 12.3 Verarbeitung

1. Dateityp und technische Lesbarkeit prüfen.
2. Text/OCR-Ergebnis mit Herkunftspositionen erzeugen.
3. Inhalt normalisieren und chunken.
4. Embeddings erzeugen und Chunks speichern.
5. Klassifikation und Extraktion ausführen.
6. Schema und Quellenabdeckung validieren.
7. Artefakt immutable speichern.
8. Realtime-Invalidation beziehungsweise Benachrichtigung auslösen.
9. Nutzungs- und Auditmetadaten schreiben.

### 12.4 Fehlerbehandlung

- technische Fehler sind retryfähig mit begrenztem Backoff,
- fachlich unlesbare Inhalte sind nicht automatisch retryfähig,
- Fehlercodes sind stabil und UI-fähig,
- Rohantworten und sensible Inhalte erscheinen nicht in Standardlogs,
- ein neuer Dokumentstand supersediert alte offene Vorschläge, löscht sie aber nicht.

## 13. Retrieval-Architektur

### 13.1 Warum der aktuelle `search_index` nicht genügt

- eine grobe Zeile pro Entität statt dokumentseitiger Chunks,
- begrenzter Body ohne robuste Seiten-/Versionsreferenz,
- keine nachgewiesene hybride Text-/Vektorsuche,
- generische Suchberechtigung statt belegter fachlicher Zugriffsmatrix,
- kein ausreichender Receipt für Modell- und Retrievalevaluation.

### 13.2 Retrieval-Pipeline

1. Benutzer- und Workspacekontext validieren.
2. Anfrage klassifizieren: strukturierte Domainfrage, Dokumentfrage oder Hybrid.
3. Erlaubte Entity-Typen und Capabilities bestimmen.
4. Metadatenfilter und Entity-Scopes vor Retrieval anwenden.
5. Volltext- und Vektorkandidaten getrennt bestimmen.
6. Ergebnisse deterministisch zusammenführen und optional reranken.
7. Quellenpaket mit stabilen IDs an das Modell geben.
8. Antwortzitate gegen das tatsächlich bereitgestellte Quellenpaket validieren.

### 13.3 Verbotene Retrieval-Shortcuts

- nachträgliches Filtern erst nach tenantübergreifender Suche,
- Verwendung eines Service-Role-Clients ohne erneute Scopeprüfung,
- ungefilterte Übergabe vollständiger Workspace-Dokumentbestände,
- Zitate auf Dokumente, die der Benutzer nicht öffnen darf,
- Retrieval aus gelöschten oder supersedierten Versionen ohne expliziten Auditfall.

## 14. Domain Tools

### 14.1 Read-only Tools im MVP

- Property Summary lesen,
- Portfolio Summary lesen,
- Party Summary lesen,
- Dokumentmetadaten und freigegebene Version lesen,
- Dokumentanforderungen/Compliance lesen,
- Valuation Result und Provenance lesen,
- offene Tasks und relevante Auditereignisse lesen,
- erlaubte Semantic Chunks suchen.

### 14.2 Proposal Tools

- Dokumentklassifikation vorschlagen,
- Feldänderung vorschlagen,
- Zuordnung vorschlagen,
- Aufgabenentwurf vorschlagen,
- Berichtsentwurf speichern.

Proposal Tools schreiben ausschließlich in KI-Artefakte, nie in Fachentitäten.

### 14.3 Nicht erlaubte Tools im MVP

- beliebiges SQL,
- Datensatz löschen,
- Zahlung auslösen,
- Vertrag kündigen,
- Bericht final freigeben,
- Benutzer oder Berechtigungen ändern,
- externe Nachricht senden,
- Websuche mit Objekt- oder Personendaten.

## 15. Modell- und Promptpolicy

### 15.1 Routing

- Standardmodell: ausgewogenes Modell für Q&A, Zusammenfassung und Extraktion.
- Volumenmodell: nur nach bestandenem Feld- und Dokumenttyp-Eval.
- Spitzenmodell: nur für explizit schwierige Multi-Dokument-Fälle.
- Keine produktive Modellalias-Nutzung ohne gepinnte, reproduzierbare Version.

Aktueller Planungsstart:

- GPT-5.6 Terra: Standard,
- GPT-5.6 Luna: evaluierte Massenvorgänge,
- GPT-5.6 Sol: komplexe Due Diligence und Ausnahmefälle.

Die konkrete Produktionsfreigabe erfolgt ausschließlich anhand Qualität, Latenz,
Datenschutz und Kosten des NexImmo-Evalsets.

### 15.2 Promptaufbau

- kleine, use-case-spezifische Systemanweisung,
- klar getrennte Policy, Daten und Benutzerfrage,
- Dokumenttext in eindeutig als untrusted gekennzeichneten Datenblöcken,
- strikt definiertes Ausgabeschema,
- erlaubte Tools dynamisch und minimal,
- keine versteckte Fachlogik im Prompt, wenn sie deterministisch implementierbar ist.

### 15.3 Versionierung

Jede produktive Antwort erhält:

- Provider und Modellsnapshot,
- Promptversion,
- Toolschema-Version,
- Retrieval-/Chunking-Version,
- Eingabe- beziehungsweise Quellenhash,
- Korrelations-ID.

## 16. Sicherheit und Datenschutz

### 16.1 Berechtigungsmodell

- neue Capability `ai.use` nur als Eingangstor,
- use-case-spezifische Rechte, soweit nötig, etwa `ai.document.extract`,
  `ai.report.draft` und `ai.policy.manage`,
- zusätzlich normale Domainrechte wie `document.read`, `property.read`,
  `valuation.read`,
- Akzeptieren eines Vorschlags benötigt dieselben Mutationsrechte wie manuelle Änderung,
- Entity-Scopes serverseitig erzwingen und negativ testen.

### 16.2 Geheimnisse

- OpenAI-Schlüssel ausschließlich serverseitig,
- niemals in `--dart-define`, Flutter, Git, Logs oder Clientkonfiguration,
- Schlüsselbereitstellung erst nach eigener ausdrücklicher Entscheidung,
- getrennte Keys/Projekte für lokale Entwicklung, Staging und Produktion,
- Rotation und Widerruf im Runbook.

### 16.3 Datenminimierung

- nur für den Use Case nötige Felder übertragen,
- Personeninformationen wenn möglich maskieren,
- keine Rohinhalte in Telemetrie,
- Chat-/Konversationspersistenz standardmäßig deaktivieren oder kurz halten,
- Lösch-, Retention- und Legal-Hold-Entscheidung vor Pilot dokumentieren,
- OpenAI-Request standardmäßig mit `store:false`, vorbehaltlich finaler
  Datenschutz- und Vertragsprüfung.

### 16.4 Prompt-Injection-Schutz

- Dokumenttext erhält niemals Instruction-Priorität,
- Toolallowlist wird außerhalb des Modells festgelegt,
- keine URL-/Webaufrufe aus Dokumentanweisungen,
- Ausgaben werden schema- und policyvalidiert,
- risikoreiche Aktionen benötigen menschliche Bestätigung,
- adversariale PDFs sind Pflichtteil jeder Release-Evaluation.

## 17. Beobachtbarkeit, Qualität und Kosten

### 17.1 Metriken

- Erfolgsquote und Fehlertyp je Use Case,
- Queuezeit, Ausführungszeit und Time-to-first-token,
- Input-/Outputtokens und Kosten,
- Anteil angenommener, abgelehnter und korrigierter Vorschläge,
- Quellenabdeckung und Zitatkorrektheit,
- Abstention Rate,
- Retrieval Recall/Precision auf Goldset,
- Versionskonflikte und Retries.

### 17.2 Budgetkontrollen

- Limit pro Anfrage,
- Tages-/Monatslimit pro Workspace,
- Warnschwellen,
- harte Sperre und Admin-Kill-Switch,
- teures Modell nur für erlaubte Use Cases,
- Batchverarbeitung nur für nicht zeitkritische Jobs und nach Datenschutzprüfung.

### 17.3 Feedback

Feedback dient zunächst ausschließlich:

- Fehleranalyse,
- Evalset-Erweiterung,
- Prompt-/Schemaverbesserung,
- Modellvergleich.

Kein automatisches Fine-Tuning oder Training aus Kundendaten im MVP.

## 18. Phasen und Gates

### PH-00 – Repository-Konvergenz und Baseline

Ziel: Ein eindeutig reproduzierbarer Ausgangsstand.

Schritte:

1. Branchgraph, Working Trees, Tags und offene PRs erfassen.
2. Differenz `main` gegen aktuellen App-Zweig fachlich klassifizieren.
3. Maintainerentscheidung zum kanonischen Branch einholen.
4. Marketing-/Branding-Commits kontrolliert integrieren oder bewusst abgrenzen.
5. Flutter-, Dart-, Node-, Supabase- und Windows-Toolchain reproduzierbar herstellen.
6. alle vorhandenen CI-Gates lokal und in CI ausführen.
7. aktuellen roten Vercel-Status separat klären.
8. Baselinebericht mit bekannten Skips und Risiken erstellen.

Gate: Kein KI-Code, bevor Branch, Toolchain und Baseline bestätigt sind.

### PH-01 – Cloud- und Sicherheitsvoraussetzungen

Ziel: Einheitliche, fail-closed Plattform für KI-Features.

Schritte:

1. Phase-Status und offene `DEC-*`/`RISK-*` prüfen.
2. Desktop-Login und Rückkehrfluss belegen.
3. einheitliche Cloud-Shell und Navigation planen/umsetzen.
4. Entity-Scope-Durchsetzung vollständig negativ testen.
5. Retrieval-Berechtigungsmatrix definieren.
6. Datenschutz-, Retention-, PII- und Datenregionsentscheidungen dokumentieren.

Gate: Kein produktnahes Retrieval ohne belegte negative RLS-Matrix.

### PH-02 – Providerneutrale KI-Grundlage

Ziel: Vollständig testbare Orchestrierung ohne Live-Provider.

Schritte:

1. Contracts und DTOs definieren.
2. unavailable/local Adapter für SQLite-Modus.
3. Fake Model und Embedding Gateway.
4. Tool Registry, Policy Resolver und Output Validator.
5. Job-, Artefakt-, Quellen-, Feedback- und Usage-Schema entwerfen.
6. Forwardmigration, RLS, RPCs, pgTAP und Rollbacktests.
7. Kill-Switch und Budgets.

Gate: Alle Flows müssen mit Fakes vollständig testbar sein, bevor ein echter Key
verwendet wird.

### PH-03 – Dokumentingestion und Retrieval

Ziel: Berechtigungssichere, reproduzierbare Dokumentbasis.

Schritte:

1. bestätigtes Dokumentereignis und idempotentes Enqueue.
2. Text-/OCR-Adapter mit Seitenpositionen.
3. Chunking, Hashing und Embeddingversionierung.
4. `semantic_chunks` mit Default-Deny-RLS.
5. hybride Suche mit Berechtigungs- und Entity-Filtern vor Ranking.
6. Löschung, Superseding und Reindex.
7. deutsches Retrieval-Goldset.

Gate: Null Cross-Workspace-/Cross-Scope-Treffer im adversarial Test.

### PH-04 – Extraktion und Review Inbox

Ziel: Erstes vollständiges, wertschöpfendes KI-Feature.

Schritte:

1. Dokumenttaxonomie und Schemas pro Dokumenttyp.
2. providerseitige strukturierte Extraktion.
3. Quellenvalidator und Normalisierung.
4. immutable Artefakte.
5. Review Inbox und Source Drawer.
6. Feldweise Annahme über normale Domain-Commands.
7. Versionskonflikte, Feedback und Audit.

Gate: Keine unbelegte oder nicht autorisierte Änderung kann akzeptiert werden.

### PH-05 – Kontextcopilot und Bewertungserklärung

Ziel: Belegtes Q&A über migrierte Domains.

Schritte:

1. read-only Domain Tools.
2. Queryklassifikation und minimale Toolauswahl.
3. Hybridantworten aus Fachsystem und Dokumenten.
4. Antwort-/Quellen-UI.
5. Bewertungsprovenance und Kennzahlenerklärung.
6. Abstention- und Konfliktlogik.

Gate: Fachkennzahlen stimmen zu 100 Prozent mit den deterministischen Engines überein.

### PH-06 – Reporting und Attention Center

Ziel: Fachlich kontrollierte Managementunterstützung.

Schritte:

1. Reportentwürfe mit Datenstichtag und Quellen.
2. deterministische Auffälligkeitsregeln anbinden.
3. KI-Erklärung und Priorisierung.
4. Aufgaben nur als Vorschlag.
5. Export-/Freigabestatus und Audit.

Gate: Kein KI-Entwurf kann ohne menschliche Freigabe als finaler Bericht erscheinen.

### PH-07 – Hardening und Pilot

Ziel: Kontrollierter Einsatz mit drei bis fünf Pilotkunden/Workspaces.

Schritte:

1. gesamtes automatisiertes und manuelles Testprogramm.
2. Security Red Team und Prompt-Injection-Korpus.
3. Performance-, Last- und Kostenprofil.
4. Datenschutz-/Retention-/Löschprüfung.
5. read-only Shadow Pilot.
6. limitierter Proposal Pilot.
7. Feedbackauswertung und Releaseentscheidung.

Gate: Produktionsfreigabe nur bei erfüllter Definition of Done.

### PH-08 – Domainerweiterungen

Je Domain eigener Gate-Prozess:

- Leasing Operations,
- Finance/Covenants,
- CapEx/Maintenance,
- Szenarien und Due Diligence.

Keine dieser Erweiterungen wird allein durch das Ende von PH-07 automatisch freigegeben.

## 19. Rolloutstrategie

1. **Developer Mode:** Fakes und anonymisierte Testdaten.
2. **Local Integration:** lokaler Supabase-Stack und kontrollierte API-Sandbox.
3. **Staging:** synthetische plus freigegebene Referenzdokumente.
4. **Shadow Pilot:** Antworten sichtbar für Reviewer, ohne Vorschlagsannahme.
5. **Proposal Pilot:** einzelne freigegebene Workspaces und Dokumenttypen.
6. **Limited Availability:** Workspace-Kill-Switch und enge Budgets.
7. **General Availability:** erst nach stabilen Qualitäts-, Kosten- und Securitywerten.

Der Pilot soll mit drei bis fünf kontrollierten Kunden beziehungsweise Workspaces
erfolgen. Reale interne Projektnamen wie „Allee 7“ dürfen nicht in öffentlicher Demo
oder allgemein zugänglichen Evaldaten erscheinen.

## 20. Risikoregister

| ID | Risiko | Schwere | Behandlung |
| --- | --- | --- | --- |
| AI-R01 | Branchdivergenz erzeugt Regressionen | Kritisch | PH-00-Gate, kanonischer Branch |
| AI-R02 | Cross-Tenant-/Scope-Leak im Retrieval | Kritisch | Default-Deny-RLS, negative Matrix, kein Post-Filtering |
| AI-R03 | Prompt-Injection aus Dokumenten | Kritisch | untrusted Content, Toolallowlist, Red Team |
| AI-R04 | Modell schreibt falsche Fachdaten | Kritisch | Proposal-only, Domain-Command, menschliche Freigabe |
| AI-R05 | Gemischte SQLite-/Cloud-Daten führen zu falschen Antworten | Hoch | KI nur auf vollständig migrierten Domains |
| AI-R06 | Halluzinierte Quellen | Hoch | stabile Source IDs und serverseitiger Zitatvalidator |
| AI-R07 | Kosten laufen unkontrolliert | Hoch | Routing, Limits, Usage Events, Kill-Switch |
| AI-R08 | Modell-/Promptupdate verschlechtert Qualität | Hoch | gepinnte Versionen und Regressionsevals |
| AI-R09 | Personen-/Vertragsdaten werden übermäßig übertragen | Hoch | Datenminimierung, Retention, Datenschutzgate |
| AI-R10 | OCR-/Scanfehler werden als sicher übernommen | Hoch | Confidence aus Validatoren, Reviewpflicht |
| AI-R11 | UI wird überladen | Mittel | kontextuelles Panel, Review Inbox, progressive disclosure |
| AI-R12 | KI-Ausfall blockiert das Fachsystem | Hoch | unavailable Adapter und offline-fähige Kernflows |

## 21. Offene Entscheidungen vor Umsetzung

| Decision | Frage | Spätestes Gate |
| --- | --- | --- |
| AI-DEC-001 | Welcher Branch wird kanonischer Entwicklungsstand? | PH-00 |
| AI-DEC-002 | Welche Remote-Region und Vertragskonfiguration werden freigegeben? | PH-01 |
| AI-DEC-003 | Welche Dokumentarten gehören verbindlich in MVP 1? | PH-03 |
| AI-DEC-004 | Welche PII darf je Dokumenttyp übertragen werden? | PH-03 |
| AI-DEC-005 | Aufbewahrung für Jobs, Artefakte, Quellen und Chatverlauf? | PH-02 |
| AI-DEC-006 | Welche Entity-Scopes gelten je Rolle? | PH-01 |
| AI-DEC-007 | Welche Felder dürfen als Proposal übernommen werden? | PH-04 |
| AI-DEC-008 | Qualitätsgrenzen pro Dokumenttyp/Feld? | PH-04 |
| AI-DEC-009 | Kostenlimit pro Workspace und Use Case? | PH-02 |
| AI-DEC-010 | Dürfen Pilotdaten für interne Evaluation gespeichert werden? | PH-07 |

## 22. Definition of Done für den MVP

Der MVP ist nur fertig, wenn:

- alle Tasks `PH-00` bis `PH-07` entweder abgeschlossen oder ausdrücklich als
  nicht zutreffend dokumentiert sind,
- Flutter Analyze, Tests und Web-Build grün sind,
- Supabase Lint, Advisors, pgTAP, Rollback-, Integration-, Concurrency-, Backup-
  und Performancegates grün sind,
- keine kritische oder hohe offene KI-Sicherheitslücke besteht,
- die negative RLS-Matrix null unberechtigte Datensätze liefert,
- kritische extrahierte Felder die freigegebenen Qualitätsgrenzen erreichen,
- jede materielle Antwort belegbar ist oder korrekt abstinent bleibt,
- autoritative Kennzahlen exakt aus vorhandenen Engines stammen,
- kein Modell direkt Fachentitäten ändern kann,
- Budgetlimit und Kill-Switch praktisch getestet sind,
- Löschung, Retention, Reindex und Restore nachweislich funktionieren,
- Windows, Web, Tablet und Smartphone gemäß bestehendem Repository-Standard
  getestet sind,
- der Pilot ein dokumentiertes Go/No-Go erhält,
- Architektur-, Betriebs- und Anwenderdokumentation aktualisiert sind.

## 23. Quellen der technischen Produktempfehlung

- OpenAI Codex Best Practices und Projektanweisungen:
  https://learn.chatgpt.com/docs/best-practices
- OpenAI Codex Projects und Chats:
  https://learn.chatgpt.com/docs/projects
- OpenAI Responses/Agent Workflows:
  https://developers.openai.com/api/docs/guides/agents
- OpenAI Function Calling:
  https://developers.openai.com/api/docs/guides/function-calling
- OpenAI Structured Outputs:
  https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI Data Controls:
  https://developers.openai.com/api/docs/guides/your-data
- OpenAI Agent Safety:
  https://developers.openai.com/api/docs/guides/agent-builder-safety
- OpenAI Evaluation Best Practices:
  https://developers.openai.com/api/docs/guides/evaluation-best-practices
- Supabase Edge Functions:
  https://supabase.com/docs/guides/functions
- Supabase pgvector:
  https://supabase.com/docs/guides/database/extensions/pgvector
- Supabase RAG mit Permissions:
  https://supabase.com/docs/guides/ai/rag-with-permissions
- Supabase Storage Access Control:
  https://supabase.com/docs/guides/storage/security/access-control

## 24. Änderungsregel für diesen Masterplan

Eine Änderung an Sicherheitsprinzipien, Source-of-Truth, Proposal-only-Ansatz,
Berechtigungsmodell, Testgates oder Domainumfang benötigt eine explizite Entscheidung.
Codex darf solche Vorgaben nicht im Zuge einer technischen Vereinfachung selbst ändern.
