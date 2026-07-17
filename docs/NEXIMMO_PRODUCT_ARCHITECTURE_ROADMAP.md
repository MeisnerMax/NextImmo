# NexImmo Produkt-, Architektur- und Umsetzungsplan

Stand: 12. Juli 2026

## 1. Entscheidung in Kurzform

- **Frontend:** Flutter und Dart beibehalten. Eine gemeinsame Codebasis fuer Windows, macOS, Web, Android und iOS ist fuer NexImmo sinnvoll.
- **Produkte nach Formfaktor:** Desktop/Web als vollstaendige Arbeitsoberflaeche, Tablet fuer operative Arbeit und Freigaben, Smartphone als fokussierte Begleit-App fuer Aufgaben, Tickets, Fotos, Dokumente und Kennzahlen.
- **Backend:** Supabase Pro in der Region Frankfurt als Startpunkt: PostgreSQL, Auth, Storage, Realtime, Edge Functions und taegliche Backups.
- **Architektur:** Modularer Monolith mit klaren Domaenengrenzen. Keine Microservices in der ersten Produktphase.
- **Datenhaltung:** PostgreSQL ist die zentrale Wahrheit. SQLite ist nur noch optionaler lokaler Cache, nicht mehr die alleinige Datenbank.
- **Synchronisation:** Zuerst online-first mit sauberer Konflikt- und Versionslogik. Offline-faehige Teilbereiche spaeter gezielt ueber PowerSync oder eine eigene Outbox, nicht durch eine pauschale Spiegelung aller Tabellen.
- **Produktstrategie:** Erst belastbare Bestandsverwaltung und operative Prozesse, danach Finanzsteuerung, Bewertung/Underwriting und externe Integrationen.

## 2. Befund des aktuellen Projekts

### Staerken

- Rechenkerne fuer IRR, Finanzierung, Sensitivitaet, Covenants und Datenqualitaet sind von der UI getrennt und deterministisch angelegt.
- Repository-Schicht, Migrationen, Audit-Grundlagen, Rollen, Szenario-Versionen und Tests sind bereits vorhanden.
- Der fachliche Umfang deckt Ankauf, Bestand, Vermietung, Instandhaltung, Dokumente, Finanzen, Reporting, ESG und Verkauf ab.
- Riverpod und wiederverwendbare UI-Komponenten sind eine tragfaehige Basis.

### Kritische Strukturprobleme

- Die Anwendung ist technisch Windows-first: Der Startpfad initialisiert SQLite-FFI direkt. Die vorhandene Persistenz funktioniert so nicht als gemeinsame Web-/Mobile-/Mehrbenutzerbasis.
- Die 94 Tabellen sind in einer mehr als 4.200 Zeilen grossen Migrationsdatei gebuendelt. Schema, Domaenen und Migrationen sind dadurch schwer unabhaengig zu pruefen.
- Viele Screens sind zu gross: mehrere Dateien liegen zwischen 2.000 und knapp 4.000 Zeilen. Darstellung, Dialoge, Datenaufbereitung und Workflows sind dadurch zu eng gekoppelt.
- Ein zentrales Provider-Modul registriert fast alle Repositories und Dienste. Domaenen koennen nicht isoliert entwickelt oder getestet werden.
- V1-/V2-Screens, Feature-Flags und Wrapper existieren parallel. Teilweise delegiert V2 nur an V1; teilweise gibt es echte Doppelimplementierungen.
- Lokale Benutzer, lokale Sitzungen und UI-basierte Rollenpruefungen sind keine serverseitige Zugriffskontrolle. Ein unbekannter Rollenname wird in Teilen der Navigation aktuell standardmaessig zugelassen.
- Dokumente liegen lokal im Dateisystem. Mehrbenutzerzugriff, Versionierung, Freigaben, Virenpruefung und sichere Links fehlen als zentrale Dienste.
- Verschluesselung der lokalen Datenbank fehlt; Backup-Hashpruefung ist laut Projektdokumentation nicht zwingend.
- Die vorhandenen Tests sind wertvoll, aber gemessen an mehr als 100.000 Produktionszeilen und dem breiten Datenmodell noch zu schmal fuer eine sichere Cloud-Migration.

### Konsequenz

Der vorhandene Code ist ein umfangreicher fachlicher Prototyp, kein verlorener Ansatz. Die Rechenkerne und validierten Fachregeln sollten erhalten bleiben. UI, Persistenz, Authentifizierung und Domaenenschnitt muessen schrittweise neu geordnet werden. Ein kompletter Rewrite waere riskanter und teurer als eine kontrollierte modulweise Migration.

## 3. Programmiersprache und Plattformen

### Empfehlung: Flutter/Dart beibehalten

Flutter unterstuetzt Mobile, Web und Desktop aus einer Codebasis. NexImmo ist eine interaktive Fachanwendung, keine SEO-orientierte Inhaltswebsite; damit passt Flutter auch fuer den Web-Client. Die bereits vorhandenen Dart-Rechenkerne koennen unveraendert auf allen Clients genutzt werden.

Nicht empfohlen:

- **Kompletter Wechsel zu React/TypeScript:** bessere Web-Spezialisierung, aber Verlust der vorhandenen Rechenkerne und doppelte Arbeit fuer Desktop/Mobile.
- **Native Apps pro Plattform:** beste Plattformintegration, aber fuer das Projekt unverhaeltnismaessig hoher Entwicklungs- und Testaufwand.
- **Dart-Backend als Pflicht:** technisch moeglich, aber fuer Auth, Storage, SQL, Jobs und Integrationen bringt Supabase/PostgreSQL anfangs mehr Nutzen bei geringerem Betriebsaufwand.

### Ziel je Geraet

| Plattform | Umfang | Bedienkonzept |
|---|---|---|
| Desktop/Web | Vollprodukt | dichte Tabellen, Mehrspaltenansichten, Tastatur, Exporte, Administration |
| Tablet | Operatives Vollprodukt | adaptive Zwei-Spalten-Ansichten, Freigaben, Begehungen, Dokumente |
| Smartphone | Begleit-App | Aufgaben, Tickets, Fotos, Kontakte, Dokumente, schnelle Objekt-KPIs |

Nicht jeder Desktop-Screen wird auf dem Telefon verkleinert. Komplexe Underwriting-Tabellen und Massenimporte bleiben Desktop/Web; mobile Workflows werden auf konkrete Aufgaben zugeschnitten.

## 4. Backendentscheidung

### Empfohlen: Supabase Pro

Supabase liefert eine echte PostgreSQL-Datenbank, Authentifizierung, private Dateispeicher, Realtime und serverseitige Funktionen. Das relationale Modell passt deutlich besser zu Immobilien, Einheiten, Mietvertraegen, Darlehen, Budgets und Buchungen als eine dokumentenorientierte Datenbank.

Empfohlene Startkonfiguration:

- Pro-Tarif, Region `eu-central-1` Frankfurt
- ein Produktionsprojekt, getrennte Entwicklungs- und Staging-Projekte
- PostgreSQL mit Row Level Security auf jeder mandantenbezogenen Tabelle
- Supabase Auth mit E-Mail/Magic Link; MFA fuer Administratoren und Freigeber
- private Storage-Buckets mit signierten, kurzlebigen URLs
- Edge Functions fuer privilegierte Transaktionen, Importe, Exporte und Webhooks
- `pg_cron` oder Queue-basierte Jobs fuer Erinnerungen, Indexierungen und periodische Berechnungen
- zusaetzlicher regelmaessiger Datenbank-Dump und separater Storage-Export; Datenbankbackups allein sichern geloeschte Storage-Objekte nicht

### Kosten- und Eignungsvergleich

| Option | Staerken | Schwaechen | Urteil |
|---|---|---|---|
| Supabase | PostgreSQL, RLS, Auth, Storage, Realtime, Flutter SDK, Frankfurt | echtes Offline-Sync nicht eingebaut; RLS muss sehr sauber entwickelt werden | beste Startoption |
| Firebase/Firestore | sehr gute Mobile-SDKs und eingebauter Offline-Cache | NoSQL passt schlecht zu Finanz- und Vertragsrelationen; Kosten entstehen pro Lese-/Schreibvorgang; Desktop-Offline eingeschraenkt | nicht empfohlen |
| Appwrite | Auth, Storage, Datenbank, Self-Hosting | kleineres SQL-/Reporting-Oekosystem und mehr Eigenbetrieb | Alternative bei zwingendem Self-Hosting |
| Eigener PostgreSQL-Server plus API | maximale Kontrolle | hoechster DevOps-, Security- und Wartungsaufwand | erst bei nachgewiesenem Bedarf |

Der Supabase-Pro-Tarif startet aktuell bei 25 USD pro Monat und umfasst unter anderem 8 GB Datenbank, 100 GB Dateispeicher und sieben Tage taegliche Datenbankbackups. Fuer ein Produktivsystem sind externe Backups und Monitoring trotzdem Pflicht.

## 5. Zielarchitektur

```text
Flutter Desktop/Web/Tablet/Phone
        |
        | Auth, HTTPS, Realtime
        v
Supabase API Gateway
  |-- Auth und MFA
  |-- PostgreSQL und Row Level Security
  |-- Private Storage Buckets
  |-- Edge Functions / RPC
  |-- Jobs, Webhooks und Realtime
        |
        +-- E-Mail / Push
        +-- DATEV / Banking / externe Datenquellen
        +-- Backup-Ziel ausserhalb Supabase
```

### Clientstruktur

```text
lib/
  app/                 Start, Routing, Session, globale Fehlerbehandlung
  design_system/       Tokens und adaptive Basiskomponenten
  shared/              kleine technische Querschnittsfunktionen
  features/
    portfolio/
    properties/
    leasing/
    maintenance/
    finance/
    documents/
    valuation/
    reporting/
    administration/
```

Jede Domaene enthaelt `domain`, `application`, `data` und `presentation`. Screens greifen nicht auf SQL oder Supabase direkt zu. Repositories werden als Interfaces im Domain-/Application-Layer definiert und durch Remote- bzw. spaeter lokale Sync-Adapter umgesetzt.

### Backendprinzipien

- Modularer Monolith: ein PostgreSQL-Schema mit klaren Modulen und stabilen Schnittstellen.
- Jede fachliche Tabelle besitzt `id`, `workspace_id`, `created_at`, `updated_at`, `created_by`, `updated_by` und eine Versionsnummer.
- Geldwerte werden als `numeric` plus Waehrung gespeichert, niemals als binaerer Gleitkommawert.
- Fachliche Perioden, Buchungsdatum und Zeitstempel werden getrennt modelliert.
- Kritische Vorgaenge laufen atomar in einer Datenbankfunktion oder Edge Function.
- Audit-Ereignisse sind append-only und enthalten Akteur, Mandant, Quelle, Korrelation, Alt-/Neuwert und Begruendung.
- Loeschen erfolgt bei rechtlich/fachlich relevanten Daten ueber Archivierung oder Tombstones.
- RLS verweigert standardmaessig jeden Zugriff. Rechte werden aus Workspace-Mitgliedschaft, Rolle und optionalem Objekt-/Portfolio-Scope abgeleitet.

## 6. Daten- und Synchronisationskonzept

### Stufe 1: Online-first

- PostgreSQL ist die einzige schreibende Wahrheit.
- Der Client nutzt Query-Caches und optimistische UI, aber keine eigenstaendige zweite Fachdatenbank.
- Realtime aktualisiert nur geoeffnete Listen und Detailansichten; Berichte und grosse Tabellen werden gezielt neu geladen.
- Mutationen tragen eine eindeutige `mutation_id` und eine erwartete Datensatzversion. Wiederholte Requests bleiben idempotent.
- Bei Versionskonflikten zeigt die UI beide Staende; Finanz-, Vertrags- und Freigabedaten werden niemals still per Last-write-wins ueberschrieben.

### Stufe 2: Gezieltes Offline

Offline wird nur fuer klar definierte mobile Workflows eingefuehrt:

- Aufgaben und Checklisten
- Instandhaltungstickets
- Begehungsnotizen und Fotos
- ausgewaehlte Objekt-/Einheit-Stammdaten

PowerSync kann PostgreSQL/Supabase mit einer lokalen SQLite-Datenbank synchronisieren und besitzt ein Flutter SDK. Vor Einfuehrung muessen Sync-Scope, Tombstones, Dateiupload-Warteschlange, Konfliktmatrix und RLS-Testfaelle feststehen. Flutter Web Support ist bei PowerSync derzeit noch als Beta gekennzeichnet; Web sollte deshalb online-first bleiben, bis der konkrete Einsatz getestet ist.

## 7. Vollstaendige Funktionslandkarte

### A. Plattform und Administration

- Organisationen/Workspaces, Benutzer, Einladungen, Rollen und objektbezogene Rechte
- Anmeldung, MFA, Sitzungen, Passwort-/Magic-Link-Prozesse
- Audit, Freigaben, Kommentare, Benachrichtigungen und persoenliche Einstellungen
- globale Suche, gespeicherte Filter, Datenqualitaet, Import-/Export-Jobs
- Mandantenkonfiguration, Nummernkreise, Kategorien und Pflichtfelder

### B. Portfolio- und Objektstamm

- Portfolios, Gesellschaften, Eigentuemerstrukturen und Zuordnungen
- Objektstamm, Adresse, Geodaten, Flaechen, Nutzung, Steuer-/Grundbuch-/Versicherungsdaten
- Gebaeude, Einheiten, Stellplaetze, Keller und technische Bauteile
- Kontakte, Firmen, Banken, Verwalter und Dienstleister als gemeinsame Stammdaten
- Status-, Eigentums- und Aenderungshistorie

### C. Vermietung und Betrieb

- Interessenten, Anfragen, Besichtigungen, Bewerbungen und Vermietungspipeline
- Mieter, Mietvertraege, Kautionen, Laufzeiten, Optionen, Index-/Staffelmieten
- Sollstellung/Rent Roll, Leerstand, Flaechen- und Mieterstruktur, Vertragsfristen
- Forderungen, Zahlungen und Mahnstatus; Buchhaltungsschnittstelle statt vollstaendiger Finanzbuchhaltung im ersten Schritt
- Reservierungen/Gaeste nur als separates Modul fuer entsprechende Nutzungsarten

### D. Instandhaltung und CapEx

- Tickets, Prioritaeten, SLA, Zuweisung, Statushistorie und Kommunikation
- Begehungen, Maengel, Fotos, Bauteile und wiederkehrende Wartungen
- Angebote, Vergabe, Auftraege, Rechnungsbezug und Gewaehrleistungen
- Sanierungs-/CapEx-Projekte mit Budget, Forecast, Ist-Kosten, Terminplan und Freigaben
- Kosten pro Objekt, Einheit, Gewerk und Massnahme sowie erwarteter Wert-/Mieteffekt

### E. Dokumente und Compliance

- zentrale Objektakte mit Dokumenttyp, Version, Gueltigkeit und Verknuepfungen
- Upload, Vorschau, Suche, Tags, Kommentare und Freigabe/Verifikation
- Pflichtdokumente, Ablaufwarnungen und Vollstaendigkeitsstatus
- Vorlagen und Serienerzeugung spaeter; OCR/Klassifikation erst nach sauberer Metadatenbasis
- Aufbewahrung, Loeschkonzept, Export und sichere Freigabelinks

### F. Finanzen und Finanzierung

- Konten-/Kategorienplan, Buchungsimport und Zuordnung zu Objekt/Einheit/Massnahme
- Mieteingaenge, offene Forderungen, Kosten, Cashflow und Liquiditaetsforecast
- Jahres-/Monatsbudgets, Forecast-Versionen und Budget-vs.-Ist
- Darlehen, Tranchen, Zinsbindung, Tilgung, Sondertilgung und Restschuldplan
- LTV, DSCR, Covenants, Fristen, Refinanzierungsszenarien und Warnungen
- Eigenkapital, Kapitalereignisse, Renditen und Portfolio-XIRR
- Nebenkostenabrechnung erst als eigenes fachlich/rechtlich validiertes Projekt; nicht als einfache Ausgabenkategorie behandeln

### G. Bewertung, Ankauf und Verkauf

- Schnellpruefung, Ankaufspipeline und Due-Diligence-Checklisten
- Bewertungsmethoden: Vergleich, Ertrag, Multiplikator und manuelle Gutachten
- Szenarien, Annahmen, Pro-forma, Sensitivitaet, IRR, Exit Cap und Angebotsgrenze
- Marktwert- und Bewertungsverlauf mit Quelle, Methode, Stichtag und Freigabe
- Verkaufspipeline, Interessenten, Angebote, Kosten, Nettoerloes und Exit-Szenarien
- Genehmigte Szenarien werden unveraenderlich; Aenderungen erzeugen eine neue Version

### H. Steuerung, ESG und Reporting

- rollenbezogene Portfoliodashboards mit drill-down-faehigen Kennzahlen
- Marktwert, Cashflow, Rendite, Leerstand, Rueckstand, CapEx und Finanzierungsrisiko
- KPI-Definitionen mit Datenquelle, Formel, Stichtag und Datenqualitaet
- ESG-/Energieprofile, Zertifikate, Verbrauchs-/Emissionsdaten und Massnahmen
- standardisierte Objekt-, Portfolio-, Bank- und Managementberichte
- CSV/XLSX/PDF-Exporte, zeitgesteuerte Report-Pakete und nachvollziehbare Datenstaende

## 8. Produktreihenfolge

### Phase 0 - Produktdefinition und Bereinigung (2-3 Wochen)

- Zielgruppen, Rollen und drei wichtigste Tagesablaeufe verbindlich festlegen
- Datenwoerterbuch, KPI-Katalog und Systemgrenzen definieren
- V1/V2-Entscheidung treffen und Doppelimplementierungen inventarisieren
- Golden-Master-Tests fuer Rechenkerne und wichtige SQLite-Daten erzeugen
- Gate: freigegebener Produktumfang, Domaenenkarte und Migrationsstrategie

### Phase 1 - Cloudfundament (3-5 Wochen)

- Supabase-Projekte, CI/CD, Umgebungen, Secrets und Monitoring
- Auth, Workspace-Mitgliedschaften, RLS und Rollenmatrix
- Basis-PostgreSQL-Schema, Audit, Dateispeicher und API-Konventionen
- Flutter-Routing, Session, Fehlerbehandlung und Repository-Interfaces
- Gate: zwei Mandanten koennen sich technisch nachweisbar nicht gegenseitig lesen oder schreiben

### Phase 2 - Kernprodukt Bestand (5-7 Wochen)

- Portfolio, Objekt, Gebaeude, Einheit, Kontakte und Dienstleister
- adaptive Desktop-/Tablet-/Phone-Shell und ein verbindliches Designsystem
- Dokumente, Aufgaben, Kommentare, Suche und Benachrichtigungen
- SQLite-Importassistent mit Dry Run, Mapping, Fehlerbericht und Wiederholbarkeit
- Gate: ein reales Portfolio kann vollstaendig importiert und im Mehrbenutzerbetrieb verwaltet werden

### Phase 3 - Vermietung und Betrieb (5-7 Wochen)

- Mieter, Vertraege, Rent Roll, Leerstand und Fristen
- Tickets, Wartungen, Begehungen, Fotos, Angebote und Gewaehrleistungen
- mobile Workflows; Entscheidung ueber PowerSync anhand eines begrenzten Piloten
- Gate: Vermietungs- und Instandhaltungsprozess funktionieren Ende-zu-Ende mit Audit und Rechten

### Phase 4 - Finanzsteuerung (5-7 Wochen)

- Buchungsimport, Kategorien, Budget, Forecast und Cashflow
- Darlehen, Tilgungsplaene, LTV/DSCR/Covenants
- Portfolio-KPIs, Datenqualitaet und Managementberichte
- Gate: jede Dashboardzahl ist bis zum Quelldatensatz nachvollziehbar und mit Referenzfaellen getestet

### Phase 5 - Bewertung und Transaktionen (4-6 Wochen)

- Szenarien, Bewertung, Ankauf, Sensitivitaet und Angebotsrechner
- Verkauf/Exit, genehmigte Versionen und Freigabeworkflow
- bestehende Dart-Rechenkerne gegen Golden-Master-Ergebnisse validieren
- Gate: identische Inputs liefern plattformuebergreifend identische freigegebene Ergebnisse

### Phase 6 - Integrationen und Haertung (fortlaufend, erste Welle 4-6 Wochen)

- DATEV-/Bank-/E-Mail-/Kalender-Schnittstellen nach Prioritaet
- Last-, Sicherheits-, Restore- und Offline-Konflikttests
- Datenschutz, Aufbewahrung, Supportprozesse und Betriebsdokumentation
- Store-/Desktop-Verteilung und kontrollierter Pilotbetrieb

Realistische Gesamtdauer: etwa 7-10 Monate mit einem kleinen eingespielten Team; als Einzelentwicklung eher 12-18 Monate. Jede Phase soll ein nutzbares Produktinkrement liefern.

## 9. Agentenplan

### Feste Agentenrollen

| Agent | Verantwortung | Darf nicht allein entscheiden |
|---|---|---|
| Produkt-/Domaenenagent | User Stories, Begriffe, KPI-Definitionen, Abnahmekriterien | Rechts-/Steuerlogik und Produktprioritaet |
| Architekturagent | Domaenengrenzen, ADRs, Schnittstellen, Abhaengigkeiten | fachliche Regeln ohne Domaenenfreigabe |
| Daten-/Backendagent | PostgreSQL, RLS, Migrationen, Storage, Jobs | UI und unreviewte produktive Migrationen |
| Flutter-/UX-Agent | Designsystem, adaptive Screens, Accessibility, ViewModels | Schemaaenderungen |
| Finance-/Valuation-Agent | Rechenkerne, Referenzfaelle, Rundung, Szenarien | Formeln ohne dokumentierte Quelle/Abnahme |
| QA-Agent | Teststrategie, Regression, E2E, Performance, Testdaten | Produktionscode ausser Testhilfen |
| Security-/Ops-Agent | Threat Model, CI/CD, Secrets, Backup/Restore, Monitoring | fachliche Produktfunktion |
| Integrationsagent | Zusammenfuehrung, Konfliktpruefung, Release Notes | unreviewte Scope-Erweiterung |

### Arbeitsaufteilung

- Ein Agent besitzt pro Auftrag eine klar abgegrenzte Domaene und Dateimenge.
- Gemeinsame Dateien wie Routing, Schema-Registry und Design-Tokens werden seriell durch den Integrationsagenten geaendert.
- Schema-, API- und Rechteaenderungen benoetigen Review von Backend-, Security- und betroffener Domaenenrolle.
- Kein Agent baut einen Screen, bevor Datenvertrag, Leer-/Fehler-/Ladezustand und Abnahmekriterien feststehen.
- Agenten liefern kleine vertikale Schnitte statt grosse parallele Teilgerueste.

## 10. Entwicklungsworkflow pro Funktion

1. **Discovery:** Nutzer, Problem, Datenquelle, rechtliche/fachliche Regeln und Nicht-Ziele klaeren.
2. **Spezifikation:** Akzeptanzkriterien, Statusautomat, Rechte, Audit, Fehlerfaelle und KPI-Definition dokumentieren.
3. **Vertrag:** Domainmodell, API, Ereignisse und Migration als Review-Artefakt festlegen.
4. **Tests zuerst:** Referenzfaelle fuer Rechenlogik, RLS-Negativtests und Migrations-/Rollbacktests erstellen.
5. **Vertikaler Schnitt:** Datenbank, Anwendungsschicht und kleinste nutzbare UI zusammen implementieren.
6. **Qualitaetsgate:** Analyse, Unit-, Widget-, Integrations- und E2E-Tests; responsive Screenshots fuer Desktop, Tablet und Phone.
7. **Securitygate:** Rechte, Mandantentrennung, sensible Logs, Uploads und Audit pruefen.
8. **Pilot:** Feature-Flag, kleine Nutzergruppe, Messwerte und Feedback; danach erst breite Aktivierung.
9. **Betrieb:** Monitoring, Runbook, Backup/Restore und Supportantworten aktualisieren.

Definition of Done fuer jede produktive Funktion:

- kein direkter Datenbankzugriff aus Widgets
- serverseitige Autorisierung und RLS getestet
- Lade-, Leer-, Fehler-, Offline- und Konfliktzustand definiert
- Audit fuer kritische Mutationen vorhanden
- Tastatur-, Tablet- und Smartphone-Verhalten geprueft
- Datenmigration wiederholbar und ruecksetzbar
- fachliche Referenzfaelle automatisiert getestet
- Telemetrie ohne personenbezogene oder vertrauliche Inhalte

## 11. Naechste konkrete Schritte

1. Drei Produktrollen interviewen: Asset Manager, Vermietung/Operations und Buchhaltung/Controlling.
2. Aus dem bestehenden Schema ein Datenwoerterbuch erstellen und jede Tabelle einer Domaene, einem Besitzer und einer Aufbewahrungsregel zuordnen.
3. Ein Supabase-Sandboxprojekt in Frankfurt aufsetzen und nur `workspace`, `membership`, `property` und `unit` als RLS-Prototyp migrieren.
4. Einen vertikalen Referenzschnitt bauen: Anmeldung -> Objektliste -> Objektdetail -> Audit -> Realtime-Aktualisierung.
5. Parallel Golden-Master-Tests fuer alle bestehenden Finanz- und Bewertungsrechner sichern.
6. Erst nach diesem Pilot die Gesamtmigration und UI-Bereinigung beginnen.

## 12. Quellen

- [Flutter: Multi-Platform aus einer Codebasis](https://flutter.dev/)
- [Flutter Web: geeignet fuer appartige SPA/PWA-Anwendungen](https://flutter.dev/development/web)
- [Supabase Preise und enthaltene Kontingente](https://supabase.com/pricing)
- [Supabase PostgreSQL und Sicherheitsmodell](https://supabase.com/docs/guides/database/overview)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Regionen, einschliesslich Frankfurt](https://supabase.com/docs/guides/platform/regions)
- [Supabase Backups und PITR](https://supabase.com/docs/guides/platform/backups)
- [PowerSync Flutter SDK](https://docs.powersync.com/client-sdks/reference/flutter)
- [Supabase-PowerSync-Integration](https://supabase.com/partners/integrations/powersync)
- [Firestore Kostenmodell](https://firebase.google.com/docs/firestore/pricing)
- [Firestore Offline-Unterstuetzung und Plattformgrenzen](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
