Vorgehensplan
Phase 1 Quick Fixes in der UI Logik

1 Loan nachträglich änderbar machen

Stelle sicher, dass Financing Inputs im Inputs Screen immer editierbar bleiben.

Wenn aktuell ein Lock aktiv ist: entferne die UI Sperre oder ersetze sie durch eine Warnung, nicht durch Blockade.

Beim Ändern von Financing Mode oder Zinssatz etc. soll sofort re gerechnet werden.

2 Loan Amount automatisch berechnen

Ziel: Loan Amount wird abgeleitet, falls leer oder 0.

Regel:

Wenn Loan Amount leer oder 0, dann:
Loan Amount = (Purchase Price + Rehab Budget + Closing Cost Buy Fixed + Closing Cost Buy Percent Anteil) minus Down Payment Anteil

Down Payment basiert auf Down Payment Prozent auf das Total Acquisition Cost.

Wenn User Loan Amount explizit eingibt, hat das Vorrang.

UI: Loan Amount Feld optional, mit Tooltip Auto Mode wenn leer.

Ergebnis Phase 1:
User kann Loan jederzeit ändern, Loan Amount ist logisch und reproduzierbar.

Phase 2 Versions Verhalten konsistent machen

Problem: Versions nicht löschbar oder änderbar, unklar ob gewollt.

Ziel:
Versionierung als unveränderbare Historie, aber mit klaren Regeln:

Versionen selbst bleiben immutable.

User kann Versionen optional soft löschen oder archivieren.

User kann Labels und Notes ändern, aber nicht den Snapshot Inhalt.

Implementationsplan:
1 Versions UI

Buttons:

Create Version

Restore Version

Rename Version

Add Note

Archive Version
Optional:

Delete Version nur wenn nicht referenced und nicht latest.

2 Datenänderung ohne neue DB Tabellen

Falls bereits Felder vorhanden für label oder flags, nutzen.

Wenn nicht vorhanden, keine Migration machen. Dann nur UI based:

Rename und Notes werden in bestehender Version metadata gespeichert falls Spalten existieren.

Wenn nicht, dann vorerst nur Anzeige und Archiv in app settings pro workspace als local map.

Ergebnis Phase 2:
Versionierung wirkt professionell und nachvollziehbar.

Phase 3 Deal Summary Page erweitern

Ziel: Overview Screen wird zur echten Deal Summary.

Neue Summary Section oben oder rechts:

Purchase Price

Size m²

Price per m²

Monthly Rent

Rent per m²

Rehab Budget

Closing Costs Buy

Total Acquisition Cost

Total Equity Invested

Loan Amount

LTV

Hold Period

Exit Assumption Mode (Appreciation oder Exit Cap)

Berechnungen ohne DB Änderung:

Price per m² = Purchase Price / Size

Rent per m² = Rent Monthly Total / Size

Total Acquisition Cost = Purchase Price + Rehab + Closing Buy Fixed + Purchase Price * Closing Buy Percent

Equity Invested = Total Acquisition Cost minus Loan Amount

LTV = Loan Amount / Total Acquisition Cost

UI Umsetzung:

Add a Summary Card Group im Overview Tab.

Tooltips bei derived values.

Ergebnis Phase 3:
User sieht alles wichtige ohne durch Tabs zu klicken.

Phase 4 Graphs hinzufügen

1 Cashflow Graph
Ziel:
Graph zeigt monthly oder yearly cashflows aus Proforma.

Minimal:

X Achse: Year 1 bis Hold Years

Y Achse: Cashflow

Quelle: bestehende Proforma DTO oder Engine Output

Toggle: Monthly oder Annual wenn Daten vorhanden

2 Rent Projection Graph
Ziel:
Graph zeigt Rent Entwicklung über Hold Period.

Minimal:

Start Rent = Rent Monthly Total

Growth = Rent Growth

Line Chart
Optional:

separate line for Market Rent wenn Comps Estimate vorhanden

UI:

Charts in Analysis Tab oder Overview unter KPIs.

Ergebnis Phase 4:
Risiko und Entwicklung sind visuell schnell verständlich.

Implementations Guidelines

Keine neuen Tabellen oder Migrationen.

Änderungen bevorzugt in core Engine Layer für Berechnungen.

UI verwendet DTOs aus Analysis Engine, keine duplicated math in Widgets.

Tests:

Loan Amount Auto calculation

Summary Derived fields

Graph data series deterministic ordering

Definition of Done

Financing ist nachträglich editierbar.

Loan Amount berechnet sich automatisch, aber ist überschreibbar.

Version Screen hat klare Regeln: immutable snapshot, editable label note, optional archive.

Overview zeigt Deal Summary mit €/m², Total Investment, Rehab, Rent per m².

Cashflow Graph und Rent Projection Graph sind sichtbar und korrekt.