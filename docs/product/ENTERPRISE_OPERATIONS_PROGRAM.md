# NexImmo — Enterprise Property Financial & Operations Program

**Stand:** 2026-09-06 · **Status:** Analyse abgeschlossen, Implementierung nicht begonnen
**Grundlage:** Auftrag „Enterprise Property Financial & Operations Workspace" (10 Module, 11 Phasen)
**Vorgehen:** Dieses Dokument ist die von §0 und §35 des Auftrags geforderte Bestandsaufnahme,
Gap-Analyse und Planung. Es entsteht **vor** der ersten Codezeile, weil der Auftrag parallele
Strukturen verbietet und mehrere der geforderten Module auf Bestand treffen, der entweder
erweitert werden muss oder bewusst nicht erweiterbar ist.

---

## 0. Die fünf Befunde, die den Zuschnitt bestimmen

Die Bestandsaufnahme lief über acht parallele Leser (Finanzschicht, Leasing, Operations,
Notifications, Design System, Dokumente/Parteien, RBAC/Audit, Legacy) plus eine
Rechtsrecherche. Fünf Ergebnisse ändern den Plan gegenüber dem, was der Auftrag annimmt.

### B-1 · Mietverträge haben keine zeitversionierten Komponenten — und sind ab `active` unveränderlich

`public.leases` trägt genau drei Geldkomponenten (`base_rent_monthly`,
`ancillary_charges_monthly`, `parking_other_charges_monthly`) als **je einen Wert am Vertrag**,
ohne jede zeitliche Gültigkeit. `update_lease` verweigert zusätzlich **jede** Änderung ab Status
`active` (`20260730100000_p2_d05_leasing_operations.sql:1980-1984, 2101-2113`) — es gibt nicht
einmal einen destruktiven Weg, eine Vorauszahlung anzupassen. Die einzige Antwort des Schemas auf
geänderte Konditionen ist heute „ein neuer Vertrag".

Damit ist **§4 (Warmmiete), §3.6 (Vorauszahlungen) und §12 (Vorauszahlungsempfehlung) des
Auftrags kein Feature, sondern ein Datenmodell-Ausbau.** Das Beispiel aus dem Auftrag
(Jan–Jun 180 €, Jul–Dez 210 €) ist heute nicht darstellbar.

Das Migrationsteam hat die Lücke selbst benannt: `lease_rent_schedule` (period_key,
rent_monthly, source) und `lease_indexation_rules` existieren im Legacy-SQLite und wurden
**bewusst nicht** migriert (`20260730120000:21-52`), mit offener Designfrage (RISK-QA-001).
Diese Entscheidung wird jetzt fällig.

### B-2 · Stichtagsrechnung ist heute unmöglich: alle Aggregate filtern auf den *aktuellen* Status

Sämtliche As-of-Berechnungen der Leasing-Schicht filtern auf `status = 'active'`, nicht auf den
Status **zum Stichtag** (`20260730120000:761-765`). Ein im Juli beendeter Vertrag trägt zu einer
Abrechnung für März **null** bei.

**Einordnung, damit die Dringlichkeit stimmt:** heute rechnet dadurch nichts falsch. Der einzige
Aufrufer, `OperationsOverviewController.asOfDate`, sendet immer **heute**
(`operations_overview_controller.dart:159-162`), und für den heutigen Stichtag ist die Filterung
auf `status = 'active'` korrekt. B-2 ist also ein **latenter** Defekt: er schlägt in dem Moment
zu, in dem die erste Abrechnung eine vergangene Periode liest — und dann still, weil die Datums-
filter greifen und nur der Statusfilter die Zeilen entfernt.

Der Vorteil daran: eine korrekte Stichtagsauflösung lässt sich heute **ohne Regressionsrisiko**
einziehen, weil keine Live-Fläche einen vergangenen Stichtag anfragt. Deshalb steht V-1 vorn —
nicht als Feuerwehreinsatz, sondern weil es später nicht mehr gefahrlos geht.

Zwei Fragen sind dabei **auseinanderzuhalten**, und die zweite wird in V-1 ausdrücklich nicht
mitentschieden:

1. *Zählt ein Vertrag, der heute nicht mehr `active` ist, für einen vergangenen Stichtag?*
   Ja — wenn er `active` erreicht hatte und sein Wirkungszeitraum den Stichtag deckt. `end_date`
   wird beim Übergang nach `ended` **nicht** angepasst; es gibt stattdessen `move_out_date` und
   `ended_at`. Welches Datum die Mietpflicht beendet, ist damit eine eigene, konservativ zu
   dokumentierende Festlegung.
2. *Zählt ein `active`-Vertrag jenseits seines `end_date`?* Diese Frage ist heute **von zwei
   Flächen unterschiedlich beantwortet**: `property_leasing_summary` weist sie als `expired_open`
   aus und zählt sie, `private.rent_roll_unit_rows` schliesst sie über
   `end_date >= p_as_of_date` aus. Diese Divergenz besteht seit P2-D05b und ist eine
   Produktentscheidung (eine deutsche Miete läuft nach Fristablauf oft kraft Gesetzes weiter) —
   sie gehört nicht still in ein Stichtagspaket.

### B-3 · Das KPI-Modell kann NOI, aber prinzipiell keine Quotienten

`finance_kpi_definitions` + `..._lines` sind eine vorzeichenbehaftete Summe über Ledger-Beträge:
eine Zeile trifft ein Konto **oder** eine Kontoklasse und wirkt `add`/`subtract`/`exclude`. Es
gibt **keinen Divisionsoperator, keinen Operanden ausserhalb des Ledgers, keine Referenz auf eine
andere Kennzahl und keine Annualisierung**.

**LTV, DSCR, ICR und Debt Yield sind damit nicht ausdrückbar** (§14.4 des Auftrags). Das Modell
muss erweitert werden — ein zweites Kennzahlmodell daneben wäre genau die parallele Struktur, die
§0 verbietet.

### B-4 · Es gibt keinen Scheduler. Nirgends.

Kein `pg_cron`, kein `pg_net`, kein `supabase/functions`, kein `cron.schedule` — grep über den
gesamten Baum: null Treffer. Die einzige Notification-Erzeugung im ganzen Cloud-Stack ist **ein
AFTER-Trigger auf `public.tasks`** mit vier hart verdrahteten IF-Zweigen
(`20260903120000_notification_emitter.sql:260-299`). Offen als DEBT-009 / TASK-SCHEDULER-01.

Fristenalarme (§6.2, §9, §14.6) sind heute also **nicht als Push** möglich — wohl aber als
**Pull**, und das existiert bereits viermal serverseitig: `operations_signals` (Schwellen
30/90/180 Tage, Severity critical/warning/info, plus persistierte Quittung),
`property_leasing_summary.decisions` (die Kündigungsfrist ist bereits berechnet, nur nicht
alarmiert), `private.document_requirement_state` (expired/expiring) und die `attention`-Liste in
`property_overview`.

**Konsequenz:** keine neue Alert-Engine (der Auftrag verbietet sie ohnehin), sondern das
`operations_signals`-Muster auf einen workspace-weiten Alert-Reader heben und **genau eine**
Zeitquelle nachrüsten.

### B-5 · Für LTV existiert kein belastbarer Objektwert

Der Legacy-Weg (`property_kpi_snapshots.valuation`) wird **ausschliesslich per CSV-Import**
befüllt und nie von der Bewertungs-Engine. Die Cloud-Übersicht liefert bewusst nur die *Frische*
der Bewertungsarbeit und keinen Wert, weil METHOD-GOV-01 offenlässt, welche Zahl „der" Objektwert
ist (`docs/product/VALUATION_METHOD_GOVERNANCE.md`).

**LTV ist vor dieser Entscheidung nicht ehrlich berechenbar.** Ein Covenant-Modul, das sich einen
Wert aussucht, erfindet die wichtigste Zahl im Modul.

---

## 1. Was wiederverwendet wird — und deshalb nicht neu gebaut werden darf

| Auftragsthema | Vorhandener Bestand | Wie er benutzt wird |
| --- | --- | --- |
| Kostenkategorien (§3.1) | `finance_accounts` mit `code`, `account_type`, **`parent_account_id`** | Umlagefähigkeit und BetrKV-Klassifizierung als Attribut/Mapping **an diesen Baum**. Ein zweiter Kostenartenbaum wäre parallel. Rollup über `parent_account_id` fehlt noch als Contract. |
| Ist-Kosten (§3, §13) | `finance_ledger_entries` mit `property_id`, **`unit_id`, `lease_id`** | Der vorhandene Haken für direkt zurechenbare Kosten. **Planwerte gehören NICHT hier hinein** — sie würden still in jede Ist-Zahl und jede KPI summieren. |
| Budgetperioden (§13) | `finance_periods` (workspace-weit, monatlich, open/closed) | Als **Buchungs**periode wiederverwendbar. **Nicht** als NK-Abrechnungszeitraum: keine Start-/Enddaten, kein Property-Scope, kein abweichendes Wirtschaftsjahr. |
| Kennzahlen (§13, §14) | `finance_kpi_definitions` mit Versionierung, genau einer aktiven Version je Key, unveränderlichen Zeilen | **Erweitern**, nicht duplizieren — siehe B-3. |
| Alle Mutationen | `private.finance_command_gate` / `claim_*` / `finish_*_mutation` (AAL2, Idempotenz, Audit) | Direkt wiederverwendbar, `p_entity_type` ist Parameter. **Kein neuntes `claim_*_mutation` bauen** — es gibt bereits acht Domänen-Kopien. |
| Lieferanten (§6) | `parties` mit `party_type='organization'`, zeitlich begrenzbare `party_roles`, `party_contractor_details` | **Supplier = party.** `maintenance_tickets` und `capex_projects` referenzieren sie bereits per FK. Keine eigene Supplier-Tabelle. |
| Dokumente (§18) | `documents` / `document_versions` / `document_links` / `required_documents` / `document_types`, privater Bucket, 11 auditierte RPCs | Eine zweite Ablage ist unzulässig; `property-media` ist per CHECK auf Bilder beschränkt und nennt sich selbst „not a second document store". |
| Ablaufüberwachung (§9) | `required_documents` + `private.document_requirement_state` (expired/expiring) | Energieausweise und Policen sind fachlich **Pflichtdokumente mit Ablaufdatum** — das Konzept existiert. |
| Alerts (§6.2, §16) | `operations_signals` + `operations_signal_states` (Schwellen, Severity, Quittung) | Das zu hebende Muster. Severity `critical/warning/info` existiert bereits. |
| Designsystem (§23) | `lib/ui/theme/app_theme.dart` (912 Z., „Liquid Enterprise"), 17 `Nx*`-Komponenten, 4 Templates | Tiefe **ausschliesslich** über `glassFill`/`glassStroke`/`innerHighlight`; Schatten und Glow sind ausdrücklich verboten. `AppElevationTokens` ist deklariert, aber nirgends benutzt. |
| Property-Workspace (§2) | Sieben Domänen registriert, Sub-Areas, Permission-Gates, serialisierbarer Host-State, Dirty-Child-Vertrag | Die IA des Auftrags wird **in diese Struktur eingepasst**, nicht daneben gebaut. |

### Legacy: Vorlage, nicht Weiterentwicklung

`lib/core/` und `lib/data/` enthalten fachlich brauchbare Modelle für **Betriebskosten** (mit
Historie, zeitanteiliger Jahreshochrechnung, Umlageschlüssel-Vokabular und einer echten
Einheitenabrechnung samt Vorauszahlungssaldo), **Darlehen/Covenants** (LoanRecord,
CovenantRecord, null-ehrliche DSCR/LTV-Engine, Annuitätenplan) und **Budget/Varianz**
(`BudgetVsActual.computeVariance`, getestet).

Diese hängen an SQLite, das nach DEC-024 entfernt ist und dessen `databaseProvider` zur Laufzeit
wirft. **Wiederverwendung heisst hier Modell- und Regelübernahme in die FINANCE-01-Contracts,
nicht Weiterentwicklung des Codes.** Vier Legacy-Fundstücke dürfen ausdrücklich **nicht**
mitwandern, weil sie Zahlen erfinden (u. a. eine gefälschte Verbrauchsumlage).

### Was nirgends existiert — weder Legacy, noch Cloud, noch Spec

- **Zähler / Ablesung / Verbrauch** (§5) — nur ein Label „Zähler/Versorger", eine Import-Heuristik
  und die erwähnte gefälschte Verbrauchsumlage.
- **Versorger-/Dienstleistervertrag mit Kündigungsfrist** (§6) — Lieferant ist heute ein
  Freitextfeld auf der Kostenzeile.
- **Versicherungspolice** (§10) — nur Freitext plus ein Schadenfall-Flag am Ticket.

**Energieausweis** existiert dreifach halb: als Freitextspalte in Postgres, die kein DTO und kein
Kommando erreicht; als EPC-Feld im Legacy-ESG-Profil; und als Dokumenttyp mit `validUntil` in der
Cloud-Compliance-Fläche. Der dritte Weg ist der richtige.

---

## 2. Rechtsstand (recherchiert 2026-09-06, nicht aus dem Gedächtnis)

Der Auftrag verlangt in §8.2 Verifikation gegen die **jeweils aktuelle** Gesetzesfassung. Das war
notwendig: zwischen Mai 2026 und heute wurde die zentrale Grundlage umgebaut.

| Sachverhalt | Stand | Wirkung auf das Modell |
| --- | --- | --- |
| **GEG heisst seit 23./29.07.2026 GModG** (Gebäudemodernisierungsgesetz, BGBl. 2026 I Nr. 226) | neu | Alle GEG-Verweise umbenennen; Paragraphenstruktur läuft weitgehend fort |
| **CO2KostAufG um §§ 3a, 5a–5d erweitert** (dasselbe Gesetz) | neu | 50/50-Teilung von Netzentgelten und CO₂-Kosten ab 2028, biogene Brennstoffe ab 2029, Härtefall § 5d |
| **§ 556 BGB durch BEG IV geändert, wirksam 01.01.2025** | neu | Belegeinsicht **elektronisch** zulässig (neuer Abs. 4); **alter Abs. 4 → Abs. 5**. Wer auf „§ 556 Abs. 4 = Unwirksamkeitsklausel" verweist, verweist falsch |
| **TV-Nebenkostenprivileg zum 30.06.2024 ausgelaufen** | abgelaufen | Abrechnungen 2024 müssen zeitanteilig trennen |
| **Wärmepumpen-Erfassungspflicht seit 30.09.2025** | abgelaufen | „Wärmepumpenprivileg" entfallen |
| **Fernablesbarkeit gesamter Altbestand bis 31.12.2026** | **läuft in ~4 Monaten ab** | Betrifft die Zählerstammdaten unmittelbar |
| CO₂-Preis 2025: 55 €/t · 2026: 60 €/t · Korridor 55–65 € auch 2027 (ETS2 auf 2028 verschoben) | jährlich | **Als versionierte Stammdaten führen, nie als Konstante** |
| **§ 8 Abs. 4 CO2KostAufG kündigt ein Nichtwohngebäude-Stufenmodell „im Jahr 2025" an — es ist nicht gekommen** | Ankündigung ≠ Rechtslage | Nichtwohngebäude bleiben bei **starr 50/50**. Klassischer Fallstrick |
| BGH VIII ZR 6/24 (20.05.2026) zum Wirtschaftlichkeitsgebot | neu | Einwendungsausschluss gilt auch dafür; Beweislast beim Mieter |

**Bindende Modellkonsequenzen:**

1. **Rechtsstände selbst versionieren.** Abrechnungen für 2024, 2025 und 2026 laufen nach
   unterschiedlichem Recht; eine rückwirkende Korrekturabrechnung muss das **damalige** Recht
   anwenden. Die Compliance-Schicht ist damit zwingend eine Regelmenge mit Gültigkeitszeitraum,
   nicht ein Satz Konstanten.
2. **Formell vs. materiell ist die wichtigste Einzelunterscheidung im ganzen Modul.** Formelle
   Unwirksamkeit macht die Nachforderung nicht fällig und setzt die Einwendungsfrist nicht in
   Gang — nach Fristablauf ist die gesamte Nachforderung verloren. Materielle Fehler sind
   korrigierbar. Ein Validator, der vor Versand die **vier Mindestangaben** erzwingt
   (Gesamtkosten, Verteilerschlüssel mit Erläuterung, Anteilsberechnung, Vorauszahlungsabzug),
   verhindert den teuersten Fehlerfall.
3. **Abrechnungsprinzip pro Kostenart konfigurierbar**, mit hartem Zwang auf das Leistungsprinzip
   für die HeizkostenV-Positionen (BGH VIII ZR 156/11).
4. **Umsatzsteuer ist der grösste Architekturtreiber bei gemischt genutzten Objekten:** optierte
   Gewerbeeinheiten netto mit getrennter USt, Wohnraum brutto — **beide Modi im selben
   Abrechnungslauf**.
5. **Umlageausfallwagnis** nur bei preisgebundenem Wohnraum, gedeckelt auf 2 % (§ 25a NMV 1970 —
   nicht II. BV). Das Feld darf sonst gar nicht aktivierbar sein.
6. **70-%-Zwang der HeizkostenV** ist eine **UND**-Verknüpfung dreier Gebäudemerkmale (kein
   WSchV-1994-Niveau **und** Öl/Gas **und** überwiegend gedämmte freiliegende Leitungen) — also
   drei Stammdatenattribute, nicht ein Schalter.

**Fachliche Freigabe erforderlich, bevor das in Code geht:** GModG/Energieausweise (Quellenlage
widersprüchlich, Paragraphenangaben uneinheitlich), § 7 CO2KostAufG (3-%-Kürzung), Kumulierbarkeit
der Kürzungsrechte § 12 HeizkostenV, BGH VIII ZR 6/24 im Volltext, §§ 5a–5d ohne Kommentarliteratur
(§ 5d ist ein fünfgliedriger kumulativer Tatbestand mit unbestimmten Rechtsbegriffen — **als
Assistenz mit Bestätigung bauen, nicht als automatische Entscheidung**), Umsatzsteuer bei
optierter Gewerbevermietung, BetrKV § 2 im Volltext.

---

## 3. Guardrails, die das Programm einhalten muss

Aus der RBAC-/Audit-/Architektur-Analyse, mit Belegen:

- **Der gültige Berechtigungskatalog steht nicht dort, wo man ihn vermutet.** Die dritte und
  aktuelle Fassung liegt in `20260912100000_finance_01a_ledger_foundation.sql:60-105` (33
  Schlüssel) und `:111-207` (Rollenbündel). Er ist zusätzlich exakt gepinnt in
  `supabase/tests/030_permission_catalog.test.sql:74-138` und clientseitig in
  `lib/core/security/rbac.dart:91-125`. Jede Erweiterung schreibt den Seeder per
  `create or replace` **vollständig neu** und muss von der aktuellen Fassung ableiten.
- **Es gibt genau fünf Rollen** (`admin, manager, analyst, operations, viewer`), per pgTAP als
  „und nur diese" abgesichert. Die im Auftrag genannten sechs Rollen (§19) sind **Personas aus den
  Produktdocs**, keine RBAC-Rollen. „Accounting" und „Finance" existieren serverseitig nicht.
- **PH-01 Entity-Scope ist per CHECK-Constraint ausschliesslich für `entity_type = 'property'`.**
  Neue Entitäten bekommen keinen eigenen Scope, sondern werden über ihre Parent-Property geprüft.
- **AAL2 (DEC-025)** sitzt zentral in `private.has_workspace_permission` plus acht
  `*_command_gate` plus vier Policies. SR-21 lässt keinen neuen public-RPC durch, der keinen
  dieser Guards im Funktionstext nennt.
- **Default-deny RLS** heisst hier: `enable` **und** `force row level security`, genau eine
  SELECT-Policy über `has_workspace_permission`, **keine** INSERT/UPDATE/DELETE-Policy,
  `revoke all … from anon, authenticated` und nur `grant select`.
- **Drei hartkodierte Inventarzahlen** in pgTAP 026 brechen bei jeder neuen Migration:
  SR-20 (SECURITY-DEFINER-Funktionen), SR-22 (Policies), Storage-Policies. Dazu die
  Bündel-Strings in pgTAP 030 und die Registrierung jeder Rollback-Datei **vorn** in der
  CI-Down-Kette.
- **`lib/ui/state/security_state.dart` ist der Legacy-SQLite-Pfad**, nicht der
  Cloud-Berechtigungspfad. Verwechslung ist ein dokumentierter Fallstrick.
- **DEC-011:** Geldbeträge existieren nie ohne Währung, Währungen werden nie still gemischt. Eine
  Abrechnung über ein Objekt mit gemischten Vertragswährungen muss dieselbe Haltung übernehmen —
  verweigern oder null, **niemals** summieren.
- **OPN-DOM-001:** Eine Einheit **darf** mehrere gleichzeitig wirksame Verträge haben
  (Teilflächenvermietung); es gibt bewusst keinen Unique-Index. Die Umlage je Einheit muss damit
  umgehen.
- **Namenskollision mit Fehlerpotenzial:** `rent_roll_snapshots.total_rent_monthly` heisst wie
  „Warmmiete", ist aber base + ancillary + parking **ohne** Heizkosten und **mit** Stellplatz. Ein
  neues Warmmieten-Feld mit anderer Definition daneben ergäbe zwei widersprüchliche
  „Gesamtmieten".
- **DB-Änderungen erreichen Staging nicht automatisch.** Jede Migration geht nach dem Merge
  einzeln über `.github/workflows/staging_db_deploy.yml`.

---

## 4. Zieldatenmodell (Grobschnitt)

Neue Aggregate, jeweils mit der Begründung, warum sie **nicht** in eine vorhandene Tabelle passen.

**Leasing-Erweiterung (Voraussetzung für alles Mietbezogene)**
- `lease_components` — zeitversionierte Mietkomponente: `lease_id`, `component_type`
  (base_rent / service_charge_advance / heating_advance / parking / other), `valid_from`,
  `valid_to`, `amount`, `currency_code`, `vat_mode`. Löst B-1. Ersetzt die drei flachen Spalten
  **nicht** sofort — sie bleiben als aktueller Stand, bis die Ablösung vollständig ist.
- Stichtagsauflösung als Lesefunktion, die auf `valid_from/valid_to` und die
  **Vertragslaufzeit zum Stichtag** filtert, nicht auf den heutigen Status. Löst B-2.

**Service Charges**
- `service_charge_periods` — Abrechnungszeitraum je Objekt mit Start/Ende und dem Statusmodell aus
  §3.4. Fachlich **nicht** `finance_periods` (workspace-weit, monatlich, Buchungsabschluss).
- `cost_pools` — Kostenpool mit Scope (Portfolio/Property/Building/Entrance/Unit/Meter-Gruppe).
- `allocation_keys` — versioniert und zeitabhängig, je Property/Kostenart/Pool/Periode.
- `service_charge_runs` + `..._lines` — der Abrechnungslauf als unveränderliches Ergebnis mit
  vollständiger Herleitung je Position (Gesamtkosten, Pool, Schlüssel, Gesamtbasis, Basis der
  Einheit, Zeitraum, Anteil, Vorauszahlung, Ergebnis). Vorlage: das vorhandene
  Snapshot-Paar `rent_roll_snapshots`.
- Umlagefähigkeit und BetrKV-Zuordnung als Attribut **an `finance_accounts`**, nicht als neuer Baum.

**Utilities**
- `meters` mit Hierarchie (Haupt-/Unter-/Einheitenzähler), `meter_readings` mit `source` und
  `quality_status` (§21 Data Quality). Beides existiert nirgends.

**Contracts / Insurance**
- `supplier_contracts` und `insurance_policies` — beide mit `party_id` auf **`parties`**, nicht mit
  eigener Lieferantentabelle. Fristen (Kündigungsfrist, Verlängerung) werden **abgeleitet
  gelesen**, nicht persistiert.

**Energy**
- Als `document_types` mit `validUntil` über `required_documents` — das Ablaufkonzept existiert.
  Zusätzlich die Kennwerte als Attribute am Objekt.

**Budget / Debt**
- `budget_versions` + `budget_lines` — Planwerte **niemals** in `finance_ledger_entries`.
- `loans`, `loan_schedule_entries`, `covenants`, `covenant_tests`.
- KPI-Modell-Erweiterung für Quotienten (B-3): Operandenquellen ausserhalb des Ledgers,
  Divisionsoperator, Zeitnormierung.

**Registry-Erweiterung (quer)**
- `document_links` kennt heute nur `workspace/property/party/maintenance_ticket/capex_project`.
  Verträge, Einheiten, Policen, Zertifikate, Abrechnungsläufe und selbst der bereits im Enum
  vorhandene Wert `task` laufen in `dependency_conflict`. Die serverseitige Registry muss je
  Paket mitwachsen.

---

## 5. Implementierungsreihenfolge

Der Auftrag gibt in §32 elf Phasen vor. Die Reihenfolge wird an zwei Stellen geändert, weil die
Analyse Abhängigkeiten zeigt, die dort nicht sichtbar waren.

| # | Paket | Warum hier | Blockiert |
| --- | --- | --- | --- |
| **V-1** | **Stichtagsauflösung Leasing** (B-2) | Ohne sie rechnet jede Rückschau falsch, ohne zu scheitern | alles Abrechnungsbezogene |
| **V-2** | **`lease_components`, zeitversioniert** (B-1) | Warmmiete, Vorauszahlungen, Empfehlung hängen daran | §4, §3.6, §12 |
| **V-3** | **Ticket-Kategoriefilter** (§15) | Kleinstes Paket, klar umrissen, Vorbedingung für §11 | Legacy-Removal |
| **V-4** | **Compliance-Regelschicht mit Gültigkeitszeitraum** | Rechtsstände sind versioniert (§2 dieses Dokuments); jede Berechnung baut darauf | §3, §8 |
| P-1 | Property Card View (§1) | UI-only, unabhängig, früher Sichtbarkeitsgewinn — braucht aber Kennzahlen im DTO | — |
| P-2 | Cost Categories + Pools + Allocation Keys (§3.1–3.3) | auf `finance_accounts` aufsetzend | §8 |
| P-3 | Suppliers + Contracts (§6) | `parties` als Basis | §7, §16 |
| P-4 | Meters + Consumption + Import Center (§5) | eigenständig, grösster Neubau | §8.3, §7 |
| P-5 | Settlement Engine (§8) | braucht V-1, V-2, V-4, P-2, P-4 | §12 |
| P-6 | Energy + Insurance (§9, §10) | über `required_documents` | §16 |
| P-7 | Warm Rent (§4) | braucht V-2 | §12 |
| P-8 | Budget + Forecast + Varianz (§13) | braucht KPI-Erweiterung | §16 |
| P-9 | Debt + Covenants (§14) | braucht B-3 **und** B-5 | §16 |
| P-10 | Alert-Reader + Zeitquelle (§16, B-4) | hebt `operations_signals` | — |
| P-11 | Legacy-Removal (§11) | erst nach nachgewiesener Parität | — |

**Jedes Paket** folgt dem etablierten Muster: Migration → pgTAP → Rollback-Test → Eintrag *vorn*
in der CI-Kette → SR-Zähler → Client-Port/Controller/UI → Tests → Docs → PR → Merge →
**manueller Staging-Dispatch**. Ein Paket pro PR, nie zwei Migrationspakete gleichzeitig offen.

---

## 6. Entscheidungen, die dem Owner gehören

Diese treffe ich nicht selbst, weil sie das Produkt festlegen und nicht die Technik.

1. **B-1: Wie werden Mietkomponenten versioniert?** Der Legacy-Weg (`lease_rent_schedule` +
   Dart-Engine) wurde bewusst nicht migriert, mit offener Designfrage (RISK-QA-001): Engine
   portieren oder Ergebnis speichern? Das ist eine Architekturentscheidung mit langem Schatten.
2. **B-5: Welche Zahl ist „der" Objektwert für LTV?** METHOD-GOV-01 lässt das offen. Ohne
   Festlegung ist kein Covenant ehrlich rechenbar.
3. **Rollenmodell (§19):** Der Auftrag nennt sechs Rollen, es gibt fünf. „Accounting" und
   „Finance" existieren serverseitig nicht. Neue Rollen anlegen, oder die geforderten Personas auf
   die bestehenden fünf abbilden?
4. **Wie weit geht die Compliance-Automatik?** § 5d CO2KostAufG ist ein fünfgliedriger kumulativer
   Tatbestand mit unbestimmten Rechtsbegriffen. Mein Vorschlag: Assistenz mit ausdrücklicher
   Bestätigung, keine automatische Entscheidung. Das gilt sinngemäss überall dort, wo das Gesetz
   Wertungen verlangt.
5. **Fachliche Freigabe der Rechtsregeln** (Liste in §2). Ich baue die Schicht so, dass Regeln
   austauschbar sind — aber welche Regel gilt, gehört fachlich abgesegnet.

---

## 7. Was dieses Dokument nicht ist

Es ist keine Zusage, dass zehn Module in einem Zug entstehen. Der Auftrag umfasst mehr Substanz
als die gesamte bisherige Phase-2-Welle. Die Umsetzung erfolgt paketweise, jedes mit Serverlogik,
Tests, Docs und Staging-Rollout, und der Fortschritt wird im
[PRODUCT_RESTORE_TRACKER.md](PRODUCT_RESTORE_TRACKER.md) geführt wie jedes andere Paket auch.

Ein Modul gilt nach §34 des Auftrags erst als fertig, wenn der fachliche Workflow funktioniert,
Serverlogik und UI stehen, Daten verknüpft sind, Permissions und Audit greifen, Empty-/Error-/
Loading-States existieren, Tests laufen, Responsive funktioniert und kein Platzhalter übrig ist.
Diese Messlatte gilt.
