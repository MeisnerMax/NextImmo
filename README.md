# Deal Analyzer Desktop

Ziel
Eine offlinefähige Desktop App zur Deal Analyse von Immobilien, funktional nahe an bekannten Deal Analyse Tools, aber eigenständig umgesetzt.

Technik
Flutter Desktop (Windows zuerst, später macOS Linux möglich)
Lokale SQLite Datenbank
Lokale PDF Report Generierung
Keine externen APIs erforderlich

Umfang
Globale Navigation
Dashboard
Properties
Compare
Criteria Sets
Report Templates
Settings
Help

Property Detail Bereiche
Overview
Inputs
Analysis
Comps
Criteria Check
Offer Calculator
Scenarios
Reports

Nicht Ziele
Kein 1:1 Clone von UI Texten Branding oder proprietären Workflows
Keine Online Import Provider in Version 1

Build Ziele Version 1
1. Flutter Desktop App startet und zeigt Navigation
2. SQLite Migrationen werden beim Start ausgeführt
3. Property und Scenario CRUD funktioniert
4. Inputs Editing mit Autosave und Debounce
5. Engine berechnet Metrics deterministisch
6. Criteria Evaluation funktioniert
7. Offer Solver liefert MAO
8. PDF Export erzeugt Report im lokalen Dateisystem

Definition of Done
Alle Screens kompilieren
Engine ist durch Unit Tests abgesichert
Keine Magic Defaults, alle Defaults sind in Settings sichtbar

## Workflows V1.2

### 1. Property und Base Scenario
1. Öffne `Properties`.
2. Erstelle ein neues Property.
3. Die App legt ein Base Scenario mit Default-Settings an.

### 2. Inputs und Autosave
1. Öffne im Property Detail `Inputs`.
2. Passe Werte an.
3. Autosave läuft mit Debounce.
4. Über `Apply Current Settings` können globale Settings auf das Scenario geschrieben werden.

### 3. Analysis und Sensitivity
1. Öffne `Analysis`.
2. Prüfe Summary, Proforma, Amortization.
3. Im Tab `Sensitivity`:
   - Metrik wählen
   - Range Preset wählen
   - Recompute ausführen
4. Die Grid-Berechnung ist deterministisch (core) und wird asynchron im UI gezeigt.

### 4. Comps und Overrides
1. Öffne `Comps`.
2. Pflege Sales/Rental Comps mit Auswahl und Gewichtung.
3. Übernehmen von ARV/Rent Overrides ist direkt möglich.

### 5. Criteria Sets und Property Override
1. Öffne `Criteria Sets`.
2. Lege Sets an, editiere Regeln (CRUD), setze Global Default.
3. Im Property Detail `Criteria Check`:
   - Source wählen (Global Default vs Property Override)
   - Override setzen/ändern/entfernen
4. Die Bewertung nutzt zuerst Property Override, sonst Global Default.

### 6. Offer Solver
1. Öffne `Offer Calculator`.
2. Zielmetrik und Zielwert setzen.
3. Solver berechnet MAO inkl. Feasibility/Warnungen.

### 7. Templates und Reports
1. Öffne `Report Templates`.
2. Templates per CRUD verwalten, Sections konfigurieren, Default setzen.
3. Im Property Detail `Reports`:
   - Template auswählen oder globalen Default nutzen
   - PDF/JSON/CSV exportieren
   - Output-Ordner öffnen

### 8. Compare
1. Öffne `Compare`.
2. Scenarios auswählen.
3. Spalten über Chips konfigurieren (persistiert in Settings).
4. CSV Export enthält Property/Scenario-Felder plus sichtbare Metrikspalten.

## Workflows V1.3

### 1. Portfolios
1. Öffne `Portfolios`.
2. Erstelle Portfolio, benenne es um oder lösche es.
3. Füge bestehende Properties zu Portfolio hinzu oder entferne sie.
4. Exportiere im Portfolio-Detail ein `Summary PDF`.

### 2. Notes und Alerts
1. Im Portfolio-Detail `Notes` nutzen (Portfolio- oder Property-Notes).
2. `Generate Alerts` erzeugt Notifications aus Snapshot-Threshold-Regeln.
3. Öffne `Notifications`, filtere unread/read und markiere Einträge als gelesen.

### 3. Data Management (CSV Import + Quality)
1. Öffne `Imports`.
2. Wähle Target (`properties`, `esg_profiles`, `property_kpi_snapshots`).
3. Lade CSV, mappe Spalten, führe Import aus.
4. Import Jobs und Data Quality Issues werden rechts angezeigt.

### 4. ESG Dashboard
1. Öffne `ESG`.
2. Filtere nach Portfolio, fehlendem EPC oder bald ablaufendem EPC.
3. Bearbeite ESG Profile pro Property.
4. Exportiere ESG als CSV oder PDF.

### 5. Demo Seed
1. Aktiviere in `Settings` den Schalter `Enable Demo Seed Button`.
2. Gehe auf `Dashboard` und klicke `Create Demo Portfolio Data`.
3. Die App erstellt Demo-Portfolio mit Properties, ESG, Notes, Notifications.

## Workflows V1.4 (Phase 3)

### 1. Portfolio Reporting Pack
1. Öffne `Portfolios` und wähle ein Portfolio.
2. Klicke `Export Reporting Pack`.
3. Setze Zeitraum, Include-Checkboxen und Zielordner.
4. Exportiere ein ZIP mit:
   - `pdfs/portfolio_summary.pdf`
   - optionalen Asset Factsheets
   - CSVs für Rent Roll, Budget vs Actual, Ledger, Debt, Covenants, ESG
   - `meta/manifest.json` mit Dateiliste und Hashes für PDFs.

### 2. Portfolio Analytics und IRR
1. Öffne im Portfolio `Portfolio Analytics`.
2. Wähle Zeitraum `from/to (YYYY-MM)`.
3. Prüfe KPI-Karten für IRR, Inflows, Outflows, Net Cashflow.
4. Exportiere die verwendete Cashflow-Serie als CSV.
5. Cashflow-Quellen:
   - `ledger_entries` mit `entity_type = asset_property`
   - `capital_events` (akquisitions/disposition/refinance/equity/distribution).

### 3. Exit Cap Bewertung pro Scenario
1. Öffne Property Detail `Inputs`.
2. Nutze Sektion `Valuation / Exit`.
3. Wähle `Appreciation` oder `Exit Cap`.
4. Bei `Exit Cap`:
   - Exit Cap Rate setzen
   - Stabilized NOI Modus wählen (`year1`, `manual`, `average years`)
5. In `Analysis` wird Exit-Breakdown angezeigt:
   - Sale Price, Sale Costs, Loan Payoff, Net Sale, Exit Cashflow.

### 4. Portfolio Data Quality Score
1. Öffne im Portfolio `Data Quality`.
2. Prüfe Portfolio-Score, Issue Count und Modul-Breakdown.
3. Filtere Issues nach Severity/Modul.
4. Nutze `Fix` pro Issue für Navigation in den passenden Screen.
5. Relevante Settings unter `Settings`:
   - Quality EPC Expiry Warning Days
   - Quality Rent Roll Stale Months
   - Quality Ledger Stale Days
