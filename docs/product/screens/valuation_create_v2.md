# Create Valuation V2

## Metadata

- Screen-ID (kein Arbeitspaket): `VALUATION-V2-CREATE-01`
- Implementierungspaket: `VALUATION-REHOST-01B`
- Domain: Valuation, Property
- Route: `/valuations/new`
- Current implementation file: `lib/ui/screens/valuations/valuation_create_dialog.dart`
- Planning status: **APPROVED** für Cloud-Rehost
- Publish-Prüfung: 2026-09-02 auf `origin/main` = `2818ecb1191c837202bd4b57fd019ba12208308d`
- Dependencies: Cloud `PropertyRepository`, Cloud `ValuationCaseRepository`, `VALUATION-REHOST-01A`
- Related screens: [Valuation Queue V2](valuation_queue_v2.md), [Valuation Case Workspace V2](valuation_case_workspace_v2.md), [gemeinsamer Workflow](valuation_v2_workflow.md)

## 1. Purpose

Create Valuation startet für genau ein Cloud-Property in Phase A ausschließlich eine **interne Analyse**, keine indikative oder professionelle Marktwertbewertung. Der Nutzer versteht vor dem Erstellen:

- welches Objekt bewertet wird;
- welchem Arbeitszweck der Case dient;
- welche technische Legacy-Konfiguration das gewählte Template startet;
- welche Werte nur Vorschläge sind und später bestätigt werden müssen.

Der heutige Defekt liegt im Leseweg: Das Dialog schreibt über den Cloud-Contract, lädt Objekte aber über einen Legacy-Provider, der im Cloud-Modus nicht verfügbar ist. V2 ersetzt nur diesen Leseweg und macht Create adressierbar; es erfindet keine neue Bewertungslogik.

## 2. Primary users and jobs

| Nutzer | Job | Zuerst benötigte Information | Entscheidung |
|---|---|---|---|
| Analyst mit `valuation.manage` | neuen Case korrekt aufsetzen | Objekt, Zweck/Case-Art, vorgeschlagene Methoden | Create oder Abbrechen |
| Investment Manager | Ankaufs-/Halteanalyse starten | Property, Template-Erklärung, DCF-/Investmentumfang | Titel/Art prüfen |
| Valuer | technische Market-Valuation-Modellrechnung vorbereiten | Property, Asset-/Gebäudetyp, Methodenkonfiguration | Inputs später fachlich prüfen; keine Indikation freigeben |

Read-only-Nutzer haben keinen Create-Einstieg und keinen Zugriff auf `/valuations/new` als bedienbare Form.

## 3. Entry points and navigation

- Queue-Primäraktion „Neue Bewertung“ öffnet `/valuations/new`.
- Optional kann ein Property Workspace später „Bewertung erstellen“ mit `propertyId` als URL-Vorauswahl öffnen. Die Vorauswahl ist ein Vorschlag und wird autorisiert neu geladen.
- Abbrechen/Back führt zur Queue oder zum sicheren Referrer zurück.
- Erfolg öffnet `/valuations/:newCaseId?section=overview`.
- Reload auf `/valuations/new` stellt keine bereits abgesendete Mutation erneut zu. Lokaler, noch nicht gesendeter Formzustand darf sessionlokal erhalten bleiben.

## 4. Information architecture

1. `NxPageHeader`: „Neue Bewertung“ und kurze Erklärung.
2. Geführter Step 1 „Objekt“.
3. Step 2 „Zweck“ mit vier verständlichen Case-Arten.
4. Step 3 „Startkonfiguration“ mit Titel und read-only technischer Template-Vorschau.
5. Transparenzhinweis: „Interne Analyse – keine Marktwert-/Verkehrswertbewertung“; Vorschläge sind noch keine bestätigten Annahmen.
6. Footer-Aktionen: „Abbrechen“ und einzige Primäraktion „Bewertung erstellen“.

Ein drei Schritte umfassender Create-Flow übernimmt das verständliche Guided-Input-Muster der Referenzen, bleibt aber auf die wenigen Felder begrenzt, die der vorhandene Create-Contract tatsächlich trägt.

## 5. Layout and interaction model

### Desktop

- Eigenständige Route in `NxContentFrame`; maximal lesbare Formularbreite ca. 720 px.
- Steps vertikal untereinander oder als kompakter Stepper, ohne Wizard-Zwang: bereits ausgefüllte Bereiche bleiben sichtbar.
- Property-Auswahl als Such-/List-Dialog auf Cloud-Results; kein unübersichtliches Dropdown mit allen Properties.
- Case-Arten als vier Auswahlkarten mit Name, Nutzerzweck und Methodenvorschau.
- Sticky Action Footer nur, wenn der Viewport sonst die Aktionen verdeckt.

### Tablet

- gleiche Reihenfolge; Case-Art-Karten 2×2.
- Property Picker nutzt volle Dialog-/Sheet-Breite.

### Mobile

- einspaltig; Case-Art-Karten untereinander.
- Property Picker als Fullscreen Sheet mit Suche und „Mehr laden“.
- Footer-Aktionen am unteren Rand, Tastatur darf das aktive Feld nicht verdecken.

Der bestehende 520-px-Dialog kann als kleine Form-Komponente wiederverwendet werden, aber die verbindliche Navigation ist die Route. Wenn das Produkt den Dialog beibehält, muss er denselben Controller, Validation- und Erfolgsvertrag verwenden und Deep-Link/Reload darf nicht fehlen.

## 6. Functional requirements

### Property wählen

- Trigger: Auswahlfeld „Objekt“.
- Voraussetzung: `valuation.manage`, `property.read`, aktiver Workspace.
- Quelle: Cloud `PropertyRepository`/Search Port; niemals Legacy `propertiesControllerProvider`.
- Erfolg: Property-ID und lesbare Zusammenfassung werden übernommen; Asset-/Gebäudetyp-Vorschläge werden neu abgeleitet.
- Fehler: Picker behält Suche/Seite, zeigt Retry; die Form bleibt erhalten.
- Property wurde zwischenzeitlich unzugänglich: Auswahl wird invalidiert und muss neu getroffen werden.

### Case-Art wählen

- Vier Contract-Arten: Ankauf (`acquisition`), Halten (`holding`), Sanieren (`renovation`), Verkauf (`disposition`).
- Jede Karte erklärt den Nutzerjob und zeigt die vom bestehenden Template aktivierte technische Konfiguration.
- Die heutigen Templates mischen Market-Valuation- und Investment-Methoden in einer unzulässigen Reconciliation. Create zeigt deshalb weder Gewichte noch eine fachliche Methodenempfehlung. Der neue Case bleibt eine interne Analyse; Publish/Review/Approval sind bis `VALUATION-METHOD-CONTRACT-01` blockiert.

### Vorschläge prüfen

- Asset-Klasse und Gebäudetyp aus Property-Daten erscheinen als gekennzeichnete Vorschläge.
- Referenzfaktoren, die daraus entstehen, bleiben server-/domainkonform `suggestedDefault` und damit nicht rechenwirksam.
- Die Create-Seite lässt keine stillen Faktorwerte „bestätigen“. Die bewusste Annahme erfolgt im Case mit Herkunftsdarstellung.

### Titel bearbeiten

- Nach Property/Case-Art wird ein Titelvorschlag erzeugt.
- Nutzer kann ihn überschreiben; nach manueller Änderung wird er bei späterem Property-Wechsel nicht still ersetzt.
- „Vorschlag wiederherstellen“ ist explizit möglich.

### Erstellen

- Trigger: Primäraktion.
- Client prüft Pflichtfelder und Titel.
- Command nutzt Workspace/Actor, neue `mutationId`, `correlationId`, Property-ID, Titel, Case-Art und bestehende Template-Config/-Suggestions.
- Währenddessen ist Create gegen Doppelklick gesperrt; Abbrechen löst keine zweite Navigation aus.
- Erfolg: readback/Result liefert Case-ID; Navigation direkt in den neuen Case.
- Server-Validation wird feldnah gemappt.
- `forbidden`: Formdaten ausblenden, Permission State.
- Mutation in progress: Status nach Idempotency-Vertrag weiter auflösen, nicht blind neu erstellen.
- Infrastructure Failure: Form bleibt; Retry verwendet für denselben logischen Versuch dieselbe Mutation-ID, solange Payload unverändert ist.

### Abbrechen / Unsaved changes

- Ohne Änderungen: sofort zurück.
- Mit Änderung an Property, Art oder Titel: Bestätigung „Entwurf verwerfen?“.
- Es existiert noch kein Server-Case; Abbrechen archiviert oder löscht nichts.

## 7. Data requirements

### 7.1 Eingaberegister

| Eingabe | Bedeutung / Einheit | Erforderlich / Validation | Herkunft | Default-Verhalten | Manuell vs Übernahme | Änderungsverfolgung |
|---|---|---|---|---|---|---|
| Property | genau das zu bewertende Cloud-Objekt | ja; gültige ID im Workspace; Nutzer hat `property.read` | Cloud Property Search | kein stiller Default; URL-Property ist Vorauswahl | explizit ausgewählt | Create-Audit enthält Property-ID; keine Property-Kopie |
| Case-Art | Arbeitszweck: Ankauf/Halten/Sanieren/Verkauf | ja; Contract-Enum | Nutzerentscheidung | keine Vorauswahl, damit Zweck bewusst gewählt wird | manuell | Create-Audit + Case Config |
| Titel | verständlicher Case-Name | ja; getrimmt, 1–200 Zeichen | Vorschlag aus Property-Name + Case-Art | Vorschlag; leer bis Property/Art ausreichend | editierbar | finaler Wert im Create-Audit; lokale Dirty-Markierung |
| Asset-Klasse | Referenzkategorie für mögliche Marktannahmen | optional; nur unterstützte Contract-Werte | Property Type Mapping | als „Vorschlag“, niemals still bestätigt | übernehmen, ändern oder leer lassen | Source `property:{id}@version`; Akzeptanz im Case |
| Gebäudetyp | verfeinerte Referenzkategorie | optional; unterstützter Wert | Property/Mapping | als Vorschlag | übernehmen, ändern oder leer lassen | gleiche Source-Regel |
| Template | Startkonfiguration für Case-Art | systembestimmt aus bestehendem Template-Katalog | Domain `valuation_case_templates.dart` | folgt Case-Art | read-only Vorschau | Template-Key/Version muss künftig im Audit nachvollziehbar sein |
| Aktivierte Methoden | technische Engines der Legacy-Startkonfiguration | mindestens eine im bestehenden Contract; keine Eignungs- oder Methodenempfehlung | Template | keine stille UI-Abweichung | read-only in Phase A; erst nach neuem Method Contract editierbar | Case Config/Version/Audit |
| Methodengewichte | fachlich blockierte Legacy-Reconciliation | nicht als UI-Feld anzeigen und nicht als Empfehlung erklären | Template | technisch serverseitig vorhanden | verborgen | Migration durch `VALUATION-METHOD-CONTRACT-01` |
| DCF-Terminalmethode | Exit Cap oder Gordon Growth | gültiger Contract-Wert | Template | Templatewert | read-only in Create | Case Config/Version/Audit |
| Mindest-Comparables | Schwelle Vergleichswert | positive Ganzzahl | Template, aktuell 3 | Templatewert | read-only in Create | Case Config/Version/Audit |
| Scenario-ID | technische Legacy-Verknüpfung | optional im Contract | heutiger Legacy-Analysis-Host | **kein Feld/Default in V2 Create** | nicht übernehmbar | nur für Altbestand lesbar |

### 7.2 Property-Result

| Anzeige | Quelle | Pflicht | Format |
|---|---|---|---|
| Property Name | Cloud Summary | ja | primärer Text |
| Adresse | Cloud Summary, soweit vorhanden | optional | sekundär, lokalisiert |
| Property Status | Cloud Summary | ja | Badge; nicht erlaubte/archivierte Auswahl serverseitig entscheiden |
| Property Type | Cloud Detail/Summary | optional | verständliches Label |
| Units/Area/Baujahr | Cloud Detail | optional | nur Kontext, keine automatische Valuation-Eingabe |

Die Property-Liste muss keyset-/serverseitig paginiert werden. Der Create-Screen lädt nicht alle Objekte und filtert sie lokal.

## 8. Permissions and security behavior

- Route und Create Command: `valuation.manage`.
- Property Picker: zusätzlich `property.read`.
- Kann ein Nutzer Valuations verwalten, aber keine Properties lesen, ist Create **blocked** mit verständlicher Abhängigkeitsmeldung; keine manuelle Property-ID-Eingabe.
- RLS prüft Property- und Workspace-Zuordnung serverseitig beim Create.
- Client übergibt keinen frei wählbaren Actor/Workspace aus einem Textfeld; Context kommt aus Session/Workspace-State.
- Kein AAL2 nach aktuellem Contract.
- Permission-Verlust während Eingabe: Form wird aus der sichtbaren UI entfernt; keine mutation; Rückweg zur Queue/Forbidden.

## 9. Realtime / freshness behavior

- Property Search ist REST-/Repository-kanonisch.
- Realtime muss den Picker nicht live umsortieren. Bei Auswahl und Submit wird Berechtigung/Existenz serverseitig erneut geprüft.
- Workspace-Wechsel verwirft Auswahl und startet den Picker im neuen Workspace.
- `liveUpdatesDegraded` blockiert Create nicht, solange Reads/Command funktionieren; Notice nur, wenn globaler Shell-Vertrag sie verlangt.

## 10. Screen states

| Zustand | Verhalten |
|---|---|
| Initial loading | Session/Permissions und ggf. URL-Property auflösen; Formular-Skeleton |
| Ready, leer | Property und Art noch nicht gewählt; Create disabled mit Gründen |
| Property Picker loading | Suchfeld sichtbar; Results Skeleton |
| Property Picker empty | Workspace hat keine lesbaren Properties; Link/CTA zu Property Create nur, wenn separat berechtigt und geroutet |
| No match | Suchbegriff zurücksetzen, ohne globale Empty Message |
| Partial property data | fehlende optionale Details werden als „nicht hinterlegt“ gezeigt |
| Validation error | feldnah; Summary fokussiert erstes ungültiges Feld |
| Submitting | Primäraktion Progress; Inputs read-only, kein Doppelcommand |
| Success | direkte Case-Navigation, keine Toast-only Sackgasse |
| Recoverable failure | Form vollständig erhalten, Retry |
| Forbidden | keine Form-/Property-Daten |
| Session/workspace transition | Auswahl und lokale Suggestions verwerfen |

## 11. Search / filter / sort

Der Property Picker:

- sucht serverweit über Property-Name und Adresse, soweit der Cloud-Property-Search-Contract dies unterstützt;
- nutzt Statusfilter nur, wenn der Contract ihn anbietet;
- sortiert serverkanonisch, vorzugsweise Name/Adresse;
- zeigt „Mehr laden“ per Cursor;
- täuscht keine lokale Volltextsuche über nur geladene Seiten vor.

Wenn der aktuelle Property-Contract keine Suche trägt, startet Phase A mit paginierter Auswahl und dokumentiert `PROPERTY-LOOKUP-01`; sie reaktiviert nicht den Legacy-Provider.

## 12. Forms and validation

### Controls

- Property: Lookup/Picker, kein freies ID-Feld.
- Case-Art: single-select Cards/RadioGroup.
- Titel: TextField mit Zeichenzähler nahe dem Limit.
- Asset-Klasse/Gebäudetyp: gekennzeichnete Suggestion-Auswahl nur, falls im aktuellen Create Command vorhanden; sonst read-only Vorschau und später im Case.
- Template-Konfiguration: read-only Summary.

### Dependent fields

- Property + Case-Art erzeugen Titelvorschlag.
- Property Type erzeugt Asset-/Gebäudetyp-Vorschlag.
- Case-Art wählt technisch Template, Methoden, Legacy-Gewichte und Terminalmodus; die Vorschau zeigt weder Gewichte noch eine fachliche Empfehlung.
- Wechsel der Case-Art aktualisiert Template-Vorschau; manuell geänderter Titel bleibt, bis Nutzer Vorschlag wiederherstellt.

### Validation

- Property erforderlich.
- Case-Art erforderlich.
- Titel getrimmt 1–200 Zeichen.
- Contract-Enums ausschließlich aus Domain-Katalog.
- Serverfehlerfelder werden auf Control gemappt; unbekannter Fehler als Form Notice.
- Keine Faktorenwerte werden in Create direkt numerisch editiert; das verhindert unvollständige, unquellierte Schnell-Defaults.

## 13. Shared components

### Existing components to reuse

- `NxContentFrame`
- `NxPageHeader`
- bestehende Form Controls / Dialog-Actions
- bestehende Case-Art-/Template-Definitionen
- Cloud Property Lookup/Repository seam, falls als Shared Picker vorhanden
- `NxNotice`

### Small extensions needed

- routefähiger Create Controller statt Dialog-lokaler Provider-Abhängigkeit;
- Property Lookup Adapter auf Cloud-Contract;
- Template Preview mit „technische Startkonfiguration, keine Methodenempfehlung“ und Hinweis „Interne Analyse“.

### New shared component candidate

- `NxEntityLookup<PropertySummary>` nur, wenn auch Documents/Tasks/CapEx denselben keysetfähigen Lookup benötigen. Andernfalls klein und featurelokal halten.

## 14. Backend gaps

| Gap | Bedarf | Blockiert Rehost? |
|---|---|---:|
| `PROPERTY-LOOKUP-01` | serverweite Property-Suche, falls aktueller Search-Port nur List bietet | Nein; Pagination reicht zunächst |
| `VALUATION-TEMPLATE-VERSION-01` | Template-Key/-Version im Case/Audit für spätere Reproduzierbarkeit | Nein; für Version/Audit-Ausbau erforderlich |
| `VALUATION-METHOD-CONTRACT-01` | beschlossene Kategorien/Wertbasen, zulässige Methoden und Approval Classes technisch tragen | Nein für den als interne Analyse gekennzeichneten Create-Rehost; ja für jede indikative/professionelle Bewertung |
| `VALUATION-SOURCE-01` | Source-Snapshot der Property-Vorschläge | Nein; Vorschläge bleiben bis dahin unbestätigt/manuell |

## 15. Accessibility and usability

- Step-/Gruppenüberschriften sind semantisch; Fortschritt wird nicht nur visuell vermittelt.
- Case-Art-Karten bilden eine echte RadioGroup mit Beschreibung.
- Property Result enthält eindeutigen Accessible Name aus Name + Adresse.
- Fokus nach Picker-Auswahl zurück zum Property-Feld; nach Fehler zum ersten ungültigen Feld.
- Submit-Status wird per Live Region angekündigt.
- Abbrechen-Dialog benennt konkret, dass nur lokale Eingaben verworfen werden.

## 16. Analytics / audit / history

- Der serverseitige Create Command schreibt das Domain-Audit mit Case, Property, Art, Actor, Mutation/Correlation und optionalem Grund.
- UI-Analytics darf Start/Abbruch/Erfolg und Fehlerklasse erfassen, aber keine Property-Namen, Adressen oder Faktorwerte.
- Eine nicht abgesendete Form erzeugt keinen Domain-Audit-Eintrag.
- Template-Key/-Version ist Ziel-Gap für spätere Reproduzierbarkeit.

## 17. Test plan

### Unit/application

- Property-/Art-Wechsel und Dirty-Titel-Regel.
- Template Mapping für alle vier Case-Arten.
- Suggested Default bleibt unaccepted/nicht rechenwirksam.
- Idempotent Submit/Retry und stale response handling.
- Workspace-Wechsel verwirft Auswahl.

### Widget/UI

- Vorhandene Template-, Suggestion-, Return-ID-, Read-only- und Serverfehler-Tests an Cloud-Provider anpassen.
- Cloud Property Loading/Empty/No match/Pagination/Retry.
- Pflichtvalidation und Fokus.
- Dirty-discard-Dialog.
- Responsive Desktop/Tablet/Mobile.
- Success navigiert in neuen Case, nicht nur Dialog schließen.

### Repository/integration

- Create mit Property desselben Workspace erfolgreich.
- Cross-workspace/unlesbares Property wird serverseitig abgewiesen.
- Mutation-ID-Deduplizierung erstellt exakt einen Case.
- Actor/Workspace aus Session, Audit vollständig.

### Staging E2E

1. Analyst öffnet `/valuations/new` aus Queue.
2. Property Picker liest Cloud-Properties im aktiven Workspace.
3. Auswahl + jede Case-Art zeigt erwartete Template-Vorschau.
4. Vorschläge sind als unbestätigt markiert.
5. Submit erzeugt exakt einen Case und öffnet seinen Deep Link.
6. Browser Reload zeigt denselben Case.
7. Ohne `property.read` oder `valuation.manage` ist Create nicht ausführbar.
8. Simulierter Infrastrukturfehler erhält die Form; Retry erzeugt keinen Duplicate.

## 18. Acceptance criteria

- Given Cloud-Modus, when Create geöffnet wird, then wird kein Legacy-Property-Provider gelesen.
- Given Property, Art und gültiger Titel, when Create erfolgreich ist, then öffnet die App direkt den zurückgegebenen Case.
- Given ein Property-Type-Vorschlag, then ist er als Vorschlag mit Quelle gekennzeichnet und kein daraus abgeleiteter Faktor rechenwirksam.
- Given der Nutzer hat den Titel manuell geändert, when Property oder Art wechselt, then wird der Titel nicht still überschrieben.
- Given ein doppelter Klick/Retry mit unverändertem Payload, then existiert genau ein Case.
- Given ein serverseitiger Feldfehler, then bleibt die Form erhalten und das zugehörige Feld zeigt den Fehler.
- Given Dirty Form und Abbrechen, then muss der Nutzer das lokale Verwerfen bestätigen.
- Given approved Rehost-Scope, then werden keine neuen Methoden oder Formeln eingeführt.
- Given ein neuer Phase-A-Case, then ist er als interne Analyse gekennzeichnet und bietet keine Marktwert-/Verkehrswert-, Publish-, Review- oder Approval-Zusage.

## 19. Out of scope

- numerische Bewertungsannahmen vollständig im Create eingeben;
- Finanzierung, CapEx oder Lease Modeling beim Create;
- Property-Erstellung im selben Formular;
- Scenario-Lifecycle aus Legacy;
- automatische „beste“ Methode ohne fachliche Governance;
- Reaktivierung der Legacy Inputs-Provider.

## 20. Open decisions

- Soll Create als volle Route gerendert werden oder zusätzlich als Dialog-Entry bestehen? Verbindlich bleibt der Route-/Controller-Vertrag.
- Dürfen archivierte/inaktive Properties gewählt werden, oder weist der Server sie ab?
- Braucht Phase A serverweite Property-Suche oder reicht paginierte Auswahl?

Kein Punkt blockiert den Cloud-Rehost, sofern die konservative Variante gilt: Route, aktive lesbare Properties, Pagination.

## 21. Implementation handoff

- Scope: Legacy-Property-Read entfernen, Cloud Lookup einsetzen, Form/Dirty/Validation ergänzen, Erfolg zum Case routen.
- Wahrscheinliche Dateien: `valuation_create_dialog.dart` oder neuer routefähiger Wrapper/Controller, Property Providers, App Navigation, bestehende Create Widget Tests.
- Voraussetzung: Case Route Contract und Cloud Property Provider im App Backend Wiring.
- Backend-Gaps bleiben getrennt; keine Schemaänderung im Screen-Paket.
- Invarianten: interne Analyse, Suggestions unaccepted, Legacy-Gewichte nicht als Empfehlung, idempotenter Command, RLS autoritativ, kein stiller Default, keine neue Mathematik.
