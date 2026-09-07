# PROPERTY MAINTENANCE & CAPEX (Objektbezogene Instandhaltung und Maßnahmen)

## Metadata

- Package / screen ID: **MAINTENANCE-V2**, Teil 2 — implementiert innerhalb `MAINTENANCE-PARITY-01` (Tracker Wave 2); Screen Map §1 „Property Maintenance/CapEx" (SCR-034 + Renovierungshälfte von SCR-031)
- Domain: `maintenance_capex`
- Route: `/property-maintenance/<propertyId>` (`propertyMaintenanceRouteFor`, `app_navigation.dart:58-70`), Surface `CloudRouteSurface.maintenance` unter `GlobalPage.properties`; gemountet in `app_scaffold.dart:344-346`. **Bewusst ohne eigene Sidebar-Destination** — objektbezogen, erreichbar über die Objektzelle der workspace-weiten Liste und über die Objekt-Navigation.
- Current implementation file(s):
  - UI: `lib/ui/screens/property_detail/property_maintenance_capex_panel.dart` (655 LOC)
  - Controller: `lib/features/maintenance_capex/application/property_maintenance_capex_controller.dart` (498 LOC)
  - Contract/DTOs/Adapter/SQL: wie Schwester-Spec
  - Legacy-Quelle für den Harvest (laufzeit-tot): `lib/ui/screens/property_detail/maintenance_screen.dart` (3915 LOC, 5 Tabs)
- Planning status: **APPROVED** — Final-Approval-Review 2026-08-28; alle drei zuvor offenen Entscheidungen sind in §15 verbindlich geschlossen. Trägt Welle A der Implementierung. Statusabgrenzung: §15.2, Dependency-Matrix: Schwester-Spec §22
- Basis: `origin/main` `3a11b09` (neu gefetcht und verifiziert, 2026-08-28); `UX-FOUNDATION-IMPL-01` liegt seit `791849f` auf `main`
- Dependencies: `UX-FOUNDATION-IMPL-01` · **Schwester-Spec `maintenance_tickets.md`** (Benchmark, Lifecycle, Ticketfelder, Formulare, Berechtigungen gelten hier unverändert)
- Related screens: `maintenance_tickets.md` · Property Workspace (`PROPERTY-WORKSPACE-01`) · Documents · Contractors

**Verhältnis zur Schwester-Spec:** Diese Spec definiert **nicht** noch einmal, was ein Ticket ist. §A (PlanRadar-Benchmark), §B (Adopt/Adapt/Reject), §D (Lifecycle), §7.1 (Ticketfelder), §12 (Formulare) und §8 (Berechtigungen) der Schwester-Spec gelten hier **unverändert**. Diese Spec trägt: den Objektkontext, das **CapEx-Projekt** als zweite Entität, die **Abgrenzung Ticket vs. CapEx**, und die Entscheidung über die beiden Legacy-Funktionen **Gewährleistung** und **Bauteilzustand**.

---

# A. Was diese Fläche ist — und was sie nicht ist

Die workspace-weite Liste (Schwester-Spec) beantwortet *„was liegt heute an?"*. Diese Fläche beantwortet *„wie steht es um dieses Objekt?"*.

Das ist ein anderer Job: nicht Abarbeitung, sondern **Objektzustand und Maßnahmenplanung**. Deshalb trägt sie zwei Entitäten nebeneinander — laufende Instandhaltung (Tickets) und geplante Investitionen (CapEx-Projekte) — und deshalb ist sie tabbasiert statt listenzentriert.

Sie ist **keine** zweite, objektgefilterte Kopie der Ticketliste. Was in beiden Flächen vorkommt (Ticketformular, Statuswechsel, Dokument- und Aufgabenverknüpfung), teilt sich denselben Code; was diese Fläche eigen macht, steht unten.

---

# B. CapEx: die Grenze zwischen Ticket und Maßnahme

Der Auftrag verlangt eine klare Grenze. Hier ist sie.

## B.1 Definition

| | **Maintenance Ticket** | **CapEx-Projekt** |
|---|---|---|
| **Was ist es?** | Ein **Ereignis** an einem bestehenden Objekt: etwas ist kaputt, verschlissen, prüfpflichtig oder gemeldet. | Eine **Absicht**: eine geplante, budgetierte, freigabepflichtige Maßnahme, die den Objektzustand verändert. |
| **Auslöser** | Meldung, Schaden, Prüffrist | Planung, Budgetzyklus, Strategie |
| **Zeithorizont** | Tage bis Wochen; getrieben von einer **Frist** (`due_at`) | Monate; getrieben von **Start-, Plan-Ende- und Ist-Ende-Datum** |
| **Geld** | *ein* Betrag: `cost_estimate` → `cost_actual` | *drei* Beträge: `budget_amount` → `forecast_amount` → `actual_amount` |
| **Freigabe** | keine — `maintenance.manage` reicht durchgehend | **eigene Fähigkeit `capex.approve`** für den Eintritt in `approved` |
| **Verantwortung** | Objektbetreuung | benannter `owner` + `next_step` am Projekt |
| **Buchhaltung** | in aller Regel **Aufwand** (Erhaltungsaufwand) | in aller Regel **aktivierungspflichtig** (Herstellungskosten / nachträgliche Anschaffungskosten) |
| **Lifecycle** | STM-006, verzweigt, mit Reopen | STM-007, **strikt linear, ohne Rückwärtskante und ohne Abbruch** |
| **Aggregat** | `public.maintenance_tickets` | `public.capex_projects` |

## B.2 Der Entscheidungstest (eine Frage)

> **Muss vor Arbeitsbeginn jemand ein Budget freigeben?**
> **Ja → CapEx-Projekt. Nein → Ticket.**

Zwei Kontrollfragen, wenn die erste unklar bleibt:
- *Hat die Sache eine Frist oder ein Zieljahr?* Frist → Ticket. Zieljahr → CapEx.
- *Würde die Buchhaltung sie aktivieren?* Ja → CapEx.

## B.3 Was daraus folgt: Kategorien werden umgehängt

Das Legacy vermischte beides: `renovation` und `modernization` waren **Ticket-Kategorien**, und der CapEx-Tab war eine gefilterte Sicht über Tickets — `status ∈ {planned, idea}` **oder** `category ∈ {renovation, modernization}` (`property_detail/maintenance_screen.dart:587-591`), also nicht einmal deckungsgleich mit den Sanierungskategorien — inklusive eines Status `idea`, den kein Ticket-Dropdown erzeugen konnte, und eines „Freigeben"-Knopfs, der auf `commissioned` sprang (`:703-741`).

**Zielentscheidung:** `renovation` und `modernization` verschwinden aus der Ticket-Kategorienliste (Schwester-Spec §7.2). Eine Sanierung ist ein CapEx-Projekt. Das ist keine Umbenennung, sondern die Auflösung der Doppeldeutigkeit, die im Legacy dazu führte, dass dieselbe Maßnahme in drei Tabs mit drei verschiedenen Zahlen erschien.

**Bestandsdaten:** Der Legacy-Pfad ist laufzeit-tot (DEC-024), es gibt also keinen Live-Bestand zu migrieren. Falls in Staging/Bestand Tickets mit `category='renovation'` existieren, bleiben sie lesbar (die UI toleriert unbekannte Kategoriewerte) — sie werden nicht automatisch konvertiert. Eine Konvertierung wäre eine Datenmigration und gehört nicht in einen Screen-PR.

## B.4 Die Beziehung, die fehlt

Beide Richtungen sind fachlich real und heute **nicht abbildbar**:
- *Aus einer Maßnahme entsteht ein Mangel*: bei der Fassadensanierung wird ein Wasserschaden entdeckt → Ticket, das zum CapEx-Projekt gehört.
- *Aus gehäuften Tickets entsteht eine Maßnahme*: fünf Heizungsstörungen in einem Winter → CapEx-Projekt „Heizungserneuerung", das die auslösenden Tickets benennt.

Es gibt keine Spalte, keine Linktabelle und keinen Enum-Wert dafür. → Backend-Gap **`MAINTENANCE-CAPEX-LINK-01`** (Schwester-Spec §14-G5). Bis dahin: **kein Freitext-Behelf**, keine Konvention im Titel, kein „Projektcode in die Beschreibung schreiben". Die Fläche benennt die Lücke, statt sie zu simulieren.

---

# C. Gewährleistung — Entscheidung

Der Auftrag verlangt, das Legacy-Feature vor einer Löschung zu bewerten. Hier das Ergebnis.

## C.1 Was das Legacy tatsächlich hatte

`property_detail/maintenance_screen.dart:756-881`, Tab „Gewährleistung". Der Befund ist ernüchternder als der Name vermuten lässt:

- **Keine eigene Entität, keine Tabelle, kein Feld.** Es ist eine *abgeleitete Sicht über Tickets*.
- **Auswahl** (`:757-764`): ein Ticket gilt als Gewährleistung, wenn `category == 'warranty'` **oder** wenn es ein abgeschlossener Auftrag ist (`status ∈ {completed, resolved, closed}` ∧ `category ∈ {renovation, modernization, repair}`).
- **Die Frist ist erfunden** (`:798-799`): Beginn = `startDate ?? resolvedAt ?? reportedAt`; Ende = `endDate ?? Beginn + 5 Jahre` — **fest verdrahtete 157 680 000 000 ms**, nicht konfigurierbar, nicht je Gewerk, nicht nach VOB (4 J.) vs. BGB (5 J.) unterschieden.
- **Restlaufzeit-Ampel** (`:801-809`): `< 0` → „Abgelaufen" (rot), `≤ 90 Tage` → gelb, sonst grün mit „N Tage übrig".
- **„Mangel melden"** (`:862-869`) legt ein neues Ticket `category='defect'` an — **ohne jede Rückreferenz** auf die Gewährleistung.
- Der Anlege-Knopf schreibt `category='warranty'` — ein Wert, den **kein einziges Dropdown erzeugen kann** (`:1925-1933`, `:2773-2781`) und für den kein Label existiert; er rendert als roher String `warranty`.

**Bewertung: Der fachliche Bedarf ist echt und wichtig. Die Legacy-Umsetzung ist es nicht.** Sie erzeugt eine rote „Abgelaufen"-Anzeige aus einer geratenen Frist auf einem geratenen Startdatum. Für ein Feature, dessen einziger Zweck der Rechtsnachweis ist, ist das schlechter als nichts: es sieht aus wie eine belastbare Aussage.

## C.2 Entscheidung

**Nicht re-homen. Nicht nachbauen. Als eigenständiges Konzept neu spezifizieren — außerhalb dieser Fläche.**

Begründung im Einzelnen:
1. Eine Gewährleistung gehört **nicht an ein Ticket**, sondern an eine **erbrachte Leistung** — also an ein CapEx-Projekt oder an ein abgeschlossenes Ticket, mit **Gewerk, Auftragnehmer, Abnahmedatum und Fristart (VOB/B §13: 4 Jahre; BGB §634a: 5 Jahre; abweichende Vertragsfrist)**. Nichts davon existiert heute als Feld.
2. Der Nachweiswert entsteht aus der **Abnahme**, nicht aus einem Statuswechsel. NexImmo hat heute keinen Abnahmebegriff (PlanRadar löst das mit „Lock + Sign", Schwester-Spec §A.7).
3. Ein Mangel innerhalb der Frist muss auf die Gewährleistung **zurückverweisen** — genau die Verknüpfung, die auch `MAINTENANCE-CAPEX-LINK-01` braucht.

**Was in v2 trotzdem sofort möglich ist, ohne Schema-Änderung:** die Dokumentrolle `warranty` (Schwester-Spec §7.4) an einem verknüpften Dokument. Eine Gewährleistungsurkunde, eine Abnahmeniederschrift oder ein Wartungsvertrag hängt damit nachweisbar am Vorgang. Das ist **Ablage, nicht Fristüberwachung** — und die Fläche sagt das so, statt eine Ampel zu zeigen, die nichts weiß.

**Folgepaket:** `WARRANTY-01` — eigene Spec, eigenes Backend-Paket, abhängig von `MAINTENANCE-CAPEX-LINK-01`. Umfang mindestens: Gewährleistungs-Entität (Bezug auf Leistung, Auftragnehmer als Party, Gewerk, Abnahmedatum, Fristart, Ablaufdatum, Sicherheitseinbehalt), Restlaufzeit- und Ablaufwarnung, Mangelmeldung mit Rückreferenz, Beleg-Verknüpfung. **Bis dahin gilt: der Legacy-Tab darf gelöscht werden** (§E) — er trägt keine Daten, deren Verlust wehtut, weil er keine speichert.

---

# D. Bauteilzustand — Entscheidung

## D.1 Was das Legacy tatsächlich hatte

`property_detail/maintenance_screen.dart:2836-3392`, Tab „Bauteilzustand", Modell `_BauteilStatusEntry` (`:3870-3915`).

- **Speicher: `final Map<String, _BauteilStatusEntry> _bauteilStatus = {}` — ein Feld im Widget-State** (`:41`). **Keine Tabelle, kein Repository, keine Migration.** Jede Eingabe ist beim Verlassen des Screens weg. Weder `maintenance.dart` noch `maintenance_repo.dart` noch `migrations.dart` kennen es.
- **Katalog: 13 fest verdrahtete Bauteile** (`:2839-2853`): Dach, Fassade, Fenster, Heizung, Elektrik, Sanitär, Böden, Türen, Treppenhaus, Außenanlage, Brandschutz, Aufzug, Keller. Nicht erweiterbar, nicht objekttypabhängig.
- **Je Bauteil:** Ampel `gut / prufen / kritisch`, letzte Wartung, nächste Wartung, Notizen; abgeleitet: Überfälligkeitsanzeige und die Anzahl offener Tickets an diesem Bauteil.
- **Die einzige Persistenz ist zerstörerisch** (`:3273-3276`): der Dialog „Tickets verknüpfen" schreibt bei jedem Häkchen **alle vier** Ortsfelder des Tickets gleichzeitig um — `building = area = technical = outdoor = comp.id` beim Setzen, alle vier `null` beim Entfernen. Ein Ticket, das echte Freitextangaben zu Gebäude, Bereich, Technik oder Außenanlage trug, verliert sie dabei.

**Bewertung: die Idee ist gut, die Umsetzung ist ein Prototyp.** Ein Ampel-Register über die Bauteile eines Objekts, das Wartungshistorie, nächste Fälligkeit und offene Tickets zusammenzieht, ist genau das, was ein Eigentümer sehen will — es ist im Kern ein **Anlagenregister**, also exakt die Lücke, die auch PlanRadar hat (Schwester-Spec §A.8). Aber gespeichert wird nichts, der Katalog ist starr, und die Ticketverknüpfung beschädigt Daten.

## D.2 Entscheidung

**Nicht re-homen. Das Konzept übernehmen, nicht den Code — als Teil des Preventive-Maintenance-Pakets, nicht als Tab dieser Fläche.**

Begründung:
1. Ein Bauteilregister ohne Persistenz ist kein Feature, sondern eine Skizze. Es gibt **nichts zu retten außer der Idee** — und die ist in diesem Dokument jetzt festgehalten.
2. Der eigentliche Wert („wann war die letzte Wartung, wann ist die nächste fällig, was ist offen") ist **dieselbe Frage**, die wiederkehrende Wartung, Prüffristen und Nachweise stellen. Zwei getrennte Modelle dafür wäre ein Konstruktionsfehler.
3. Der Katalog gehört pro Arbeitsbereich konfigurierbar, nicht als 13-Zeilen-Konstante im UI-Code.

**Was übernommen wird (in `MAINTENANCE-PREVENTIVE-01` zu spezifizieren):**
- Eine **Anlagen-/Bauteil-Entität** je Objekt (`property_id`, Bezeichnung, Kategorie, optional Einheit), mit workspace-weit konfigurierbarem Ausgangskatalog statt fester Liste.
- **Zustandsbewertung** mit Zeitstempel und Bewerter (nicht ein überschriebener Ampelwert ohne Historie — sonst ist auch das nicht nachweisfähig).
- **Wartungsintervall** je Bauteil, das Tickets erzeugt (Schwester-Spec §B.2-P5: ein Ticket **je Fälligkeit**, nicht ein wiedergeöffnetes).
- **Ticket → Bauteil als saubere Referenz**, nicht als Überschreibung von vier Freitextfeldern.

**Was nicht übernommen wird:** die 13er-Konstante, die Vier-Felder-Überschreibung, die Ampel ohne Historie.

## D.3 Damit ist die Screen-Map-Auflage erfüllt

Screen Map §2 verlangt vor der Löschung von `property_detail/maintenance_screen.dart`: *„Bauteilzustand + Gewährleistung gegen Wave-4-Panels diffen — einzige evtl. nicht re-homten Features."* Der Diff ist gemacht (§C.1, §D.1). Ergebnis: **beide sind in den Cloud-Panels nicht vorhanden, und beide sollen dort auch nicht in Legacy-Form entstehen.** Beide sind hier dokumentiert, ihre Nachfolgepakete sind benannt (`WARRANTY-01`, `MAINTENANCE-PREVENTIVE-01`). Der Legacy-Screen ist damit **löschbar** — der Löschzeitpunkt hängt nur noch an §15-D3.

---

# E. Parity matrix — cloud vs. legacy vs. target (objektbezogen)

Legende wie Schwester-Spec.

| Bereich | Cloud heute (`property_maintenance_capex_panel.dart`) | Legacy (`property_detail/maintenance_screen.dart`, 5 Tabs) | **Target v2** |
|---|---|---|---|
| **Struktur** | 2 Tabs: Tickets · CapEx-Projekte | 5 Tabs: Tickets · Sanierungen · CapEx-Planung · Gewährleistung · Bauteilzustand | **2 Tabs** (Tickets · Maßnahmen/CapEx) — Sanierungen gehen in CapEx auf (§B.3), Gewährleistung → `WARRANTY-01` (§C), Bauteilzustand → `MAINTENANCE-PREVENTIVE-01` (§D) |
| Kopf | `NxPageHeader(title:)` ohne Breadcrumbs, hartes `EdgeInsets.all(24)` | eigener Kopf mit Breadcrumbs `['Objekte', <Name>, 'Instandhaltung']` | `NxPageHeader` + Breadcrumbs mit **Objektnamen**, `context.adaptivePagePadding` (Foundation §4 — das harte Padding ist dort namentlich als Defekt benannt) |
| Objektname im Kopf | ❌ nur „Instandhaltung & CapEx" | ✅ | ✅ — eine objektbezogene Fläche muss sagen, um welches Objekt es geht |
| **Objekt-KPIs** | ❌ | ✅ 6 Kacheln (Tickets) + 3 CapEx-Kacheln (geplant/beauftragt/investiert) | ✅ 4 Kacheln, §2.2 |
| Ticket-Liste | ✅ 4 Spalten | ✅ + Board + Kalender | ✅ Tabelle + Detail (identisch zur Schwester-Fläche, ohne Objektspalte) |
| Ticket anlegen | ⚠️ 3 Felder | ✅ volles Formular | ✅ Formular der Schwester-Spec §12.1, **Objekt vorbelegt und gesperrt** |
| Ticket bearbeiten | ❌ | ✅ | ✅ (Contract vorhanden) |
| Einheiten-Filter | ❌ | ✅ | ✅ — die einzige zusätzliche Filterdimension, die diese Fläche gegenüber der Schwester-Fläche braucht |
| **CapEx-Liste** | ✅ 5 Spalten (Code, Status, Budget, Ist, Aktion) | ⚠️ abgeleitete Ticket-Sicht mit Abweichungsspalte | ✅ echte `capex_projects` mit Budget/Forecast/Ist/Abweichung, Owner, Nächster Schritt, Termine |
| CapEx anlegen | ⚠️ 3 Felder (Code, Kategorie, Budget); Währung wird **stillschweigend** auf `'EUR'` gesetzt, sobald ein Budget da ist (`:416`) | ⚠️ über Ticket-Dialog | ✅ volles Formular §5.2, **Währung explizit gewählt** |
| CapEx bearbeiten | ❌ (`CapexProjectRepository.update` existiert) | ⚠️ über Ticket-Dialog | ✅ **UI only** |
| CapEx-Detail | ❌ | ❌ | ✅ Split-Pane-Detail |
| **Freigabe** | ✅ korrekt auf `capex.approve` gegated, Knopf deaktiviert ohne die Fähigkeit (testgepinnt) | ⚠️ „Freigeben" sprang auf `commissioned`, ohne eigene Berechtigung | ✅ unverändert übernehmen — **das ist die beste Stelle des heutigen Panels** |
| Statuswechsel CapEx | ✅ genau ein erlaubter Folgeschritt (STM-007 ist linear) | ⚠️ frei | ✅ unverändert |
| Ist-Betrag | ⚠️ Dialog ohne Währung — **gleicher Defektmechanismus wie DEF-1** | ✅ | ✅ Betrag + Währung |
| Dokumente/Aufgaben am Ticket | ❌ | ⚠️ Umhängen | ✅ wie Schwester-Spec §6-F7…F10 |
| Dokumente am CapEx | ❌ | ❌ | ✅ — `capex_project` ist serverseitig ein gültiger Link-Entitätstyp (`20260806100000_...:2077-2085`, pgTAP `023:583-590`) und wird von keinem Aufrufer **geschrieben** (die Documents-Fläche rendert bereits ein Label dafür, `document_badges.dart:71`) |
| Ticket ↔ CapEx | ❌ | ⚠️ implizit über Kategorie | 🔒 `MAINTENANCE-CAPEX-LINK-01` |
| Gewährleistung | ❌ | ⚠️ abgeleitet, Frist geraten | ⛔ hier nicht; → `WARRANTY-01` (§C) |
| Bauteilzustand | ❌ | ⚠️ nur im Arbeitsspeicher | ⛔ hier nicht; → `MAINTENANCE-PREVENTIVE-01` (§D) |
| Getrennte Berechtigungszonen | ✅ Ticket-`forbidden` blockiert den CapEx-Tab **nicht** (testgepinnt) | — | ✅ unverändert erhalten |
| Realtime | ⚠️ abonniert, aber **ohne Aggregat-Unterscheidung**: jede Invalidierung lädt beide Zonen neu (§9) | ❌ | ✅ getrennt je Aggregat + Degraded-Notice |
| Split-Pane/Detail | ❌ | ⚠️ Detailspalte nur für Tickets | ✅ je Tab ein Detail (Foundation §8) |
| Mobile-Fallback | ❌ | ❌ | ✅ Pflicht (Foundation §6) |

## E.1 Bestätigte Defekte im heutigen Panel

| # | Defekt | Beleg |
|---|---|---|
| **DEF-6** | **Ist-Betrag ohne Währung.** `_showAmountDialog` liefert eine nackte Zahl; `transition_capex_project_status` weist `actual_amount` per `coalesce` zu, ohne `currency_code` zu setzen. Hier ist das Serververhalten allerdings *besser* als bei Tickets: es wird explizit geprüft und ein **strukturiertes** `validation_failed` geliefert — Meldung wörtlich „An actual amount requires the project to already carry a currency", `field` = **`actual_amount`** (nicht `currency_code`). Die UI fängt das nicht ab und zeigt eine generische Meldung, statt vorher nach der Währung zu fragen. | `property_maintenance_capex_panel.dart:630-655`; Server `20260806100000_...:1969-1980`, `:1996`; Integrationstest `:358-393` |
| **DEF-7** | **Stille Währungsannahme beim Anlegen:** `currencyCode: result.budgetAmount != null ? 'EUR' : null` (`:416`) — der Nutzer wählt nie eine Währung und erfährt nie, dass EUR gesetzt wurde. Da `update` einen Wert nicht auf null zurücksetzen kann, ist die Annahme danach faktisch dauerhaft. | `:402-419` |
| **DEF-8** | **Hartes `EdgeInsets.all(24)`** statt `context.adaptivePagePadding` — in Foundation §4 namentlich als zu behebender Defekt aufgeführt. | `:62-63` |
| **DEF-9** | Kein `ListFilterTemplate`, keine Filter überhaupt, keine Breadcrumbs, kein Objektname, private `_Skeleton`-Kopie, Inline-Dialoge, kein Mobile-Fallback. | ganze Datei |
| **DEF-10** | Der Konfliktdialog verwirft Eingaben („Lade neu und wiederhole die Änderung") — Foundation §10 verlangt Erhalt. | `:104-126` |

---

## 1. Purpose

Die Fläche zeigt und steuert **den Instandhaltungs- und Investitionsstand eines einzelnen Objekts**: was ist offen, was ist geplant, was ist freigegeben, was wurde investiert. Sie ist die Stelle, an der aus wiederkehrenden Störungen eine Maßnahme wird — und an der die Maßnahme durch die Freigabe geht.

## 2. Primary users and jobs

| Rolle | Job | Braucht zuerst | Entscheidet hier |
|---|---|---|---|
| **Objektbetreuer** | Zustand eines Objekts überblicken | offene und überfällige Tickets dieses Objekts | Priorisierung, Beauftragung |
| **Asset Manager / Eigentümer** | Investitionen planen und verantworten | Budget vs. Forecast vs. Ist über alle Projekte des Objekts | Anlage und Fortschreibung von Maßnahmen |
| **Freigabeberechtigter** (`capex.approve`) | Freigeben | welche Projekte auf Freigabe warten, mit welchem Budget | **Freigabe** — die einzige Aktion dieser Fläche mit eigener Fähigkeit |
| **Kaufmännische Sachbearbeitung** | Abrechnen | abgeschlossene Projekte ohne Ist-Betrag | Ist-Erfassung, Abrechnung |

### 2.2 KPI-Kacheln (vier, objektbezogen)

| Kachel | Definition |
|---|---|
| **Offene Tickets** | Tickets dieses Objekts mit Status ∉ {`resolved`,`invoiced`,`archived`} |
| **Überfällig** | davon mit `dueAt` vor heute — Ton `error`, bei 0 `success` |
| **Geplantes Budget** | Σ `budgetAmount` über Projekte mit Status ∈ {`idea`,`planned`,`quoteRequested`,`approved`} |
| **Investiert** | Σ `actualAmount` über Projekte mit Status ∈ {`completed`,`invoiced`,`archived`} |

Aus dem Legacy **nicht** übernommen: die Dreiteilung geplant/beauftragt/investiert (die mittlere Zahl war eine Restmenge ohne Aussage). Alle vier Zahlen stammen aus dem Contract; es wird **nichts** aus Konstanten berechnet (Screen Map §0.7).

**Währungsregel für alle Summen:** Solange nur eine Währung vorkommt, wird summiert und die Währung genannt. Bei gemischten Währungen wird **nicht** summiert, sondern je Währung ausgewiesen oder „gemischte Währungen" angezeigt. Keine stillschweigende Addition.

## 3. Entry points and navigation

- **Eintritt:** Objektzelle der workspace-weiten Ticketliste (Schwester-Spec §3 — der einzige heutige In-App-Weg, testgepinnt) sowie die Objekt-Navigation des Property Workspace, sobald `PROPERTY-WORKSPACE-01` steht.
- **Keine eigene Sidebar-Destination** — bewusst, weil objektbezogen (Screen Map §1).
- **Ausgänge:** Handwerker-Chip → Contractors · verknüpftes Dokument → Documents · verknüpfte Aufgabe → Tasks · „Alle Tickets" → workspace-weite Liste mit vorgesetztem Objektfilter.
- **Kontext:** Der aktive Tab und die Auswahl überleben Filteränderungen; das Objekt ist fix und wird nie gewechselt.
- **Deep-Link:** Die Route trägt die `propertyId`. Bis `SHELL-ROUTING-01` folgt die Browser-URL der In-Shell-Navigation nicht; die Fläche muss ohne URL vollständig erreichbar bleiben (Foundation §2).

## 4. Information architecture

1. `NxPageHeader` — Titel „Instandhaltung & CapEx", **Untertitel = Objektname**, Breadcrumbs `['Objekte', <Objektname>, 'Instandhaltung']`, Primäraktion tab-abhängig („Ticket anlegen" / „Maßnahme anlegen"), Sekundäraktionen „Alle Tickets", „Aktualisieren".
2. `NxLiveUpdatesNotice` bei degradiertem Live-Zustand.
3. KPI-Zeile (§2.2) — spannt über beide Tabs, weil sie den Objektzustand beschreibt, nicht den Tab.
4. `TabBar` (2 Tabs, `isScrollable`, in `NxCard` — Foundation §9).
5. Je Tab: `ListFilterBar` → Split-Pane (Liste | Detail).

Die Primäraktion bleibt sichtbar, egal welcher Tab aktiv ist (Foundation §9: Tabs verdecken die Primäraktion nie).

## 5. Layout, interaction, functional requirements

Alles Ticketbezogene — Tabelle, Detail, Formular, Statuswechsel, Dokument- und Aufgabenverknüpfung, Filter/Suche/Sortierung, Konfliktbehandlung, Zustände — folgt **unverändert** der Schwester-Spec (§5, §6, §10, §11, §12), mit drei Unterschieden:

1. Keine **Objektspalte** und kein Objektfilter; stattdessen ist der **Einheiten-Filter** erstklassig.
2. Im Anlege-Formular ist das Objekt **vorbelegt und nicht änderbar** (serverseitig ohnehin eine geschützte Spalte).
3. Gelesen wird über `MaintenanceTicketSearchPort.search(MaintenanceTicketListQuery)` — die **objektbezogene** RPC, die zusätzlich `unitId` serverseitig filtern kann (`maintenance_capex_repository.dart:48-62`). Diese Fläche hat damit *mehr* serverseitige Filterkraft als die workspace-weite; das ist kein Fehler, sondern die Folge zweier verschiedener RPCs.

### 5.1 CapEx-Tab: Liste

`NxDataTableShell` + `DataTable`. Spalten: Projektcode · Maßnahme · Status · Budget · Forecast · Ist · **Abweichung** · Plan-Ende. Optional über Spaltenwähler: Kategorie, Owner, Nächster Schritt, Start, Ist-Ende.

- **Abweichung** = `actualAmount − budgetAmount`, nur wenn beide vorhanden; Überschreitung in Fehlerfarbe **mit Vorzeichen und Label**, nie farbe-only.
- Beträge in `context.dataMonoStyle` mit Währung; `'—'` für null.
- Default-Sortierung: Status entlang STM-007, darin Plan-Ende aufsteigend.
- Filter: Status serverseitig (`CapexProjectListQuery.status`); Kategorie, Owner und die Suche über Projektcode/Maßnahme clientseitig über den **vollständig geladenen, objektbezogenen** Satz. Das ist hier zulässig — anders als auf der workspace-weiten Fläche liegt kein teilgeladenes Keyset vor (§15-D1, Schwester-Spec §20-D1). Mit `CAPEX-DATA-01`/`MAINTENANCE-QUERY-01` wandern auch diese Dimensionen auf den Server.
- **Mobile-Fallback Pflicht.**

### 5.2 CapEx-Tab: Formulare

**„Maßnahme anlegen"** (`CapexProjectDraft`):

| Feld | Pflicht | Regel |
|---|---|---|
| Projektcode | ja | 1–100 Zeichen (Server-Check) |
| Maßnahme (Beschreibung) | nein | ≤ 2000 Zeichen |
| Kategorie | nein | 1–100 Zeichen, kuratierte Liste (Dach, Fassade, Heizung/Sanitär, Elektrik, Fenster/Türen, Außenanlage, Brandschutz, Aufzug, Sonstiges) |
| Start / Plan-Ende | nein | Datum; **`capex_projects_planned_end_check` erzwingt `planned_end_date >= start_date` serverseitig als Tabellen-CHECK** (`20260806100000_...:272-274`) — also dieselbe Mechanik wie DEF-1: ein Verstoß wirft, statt `validation_failed` zu liefern. Die UI validiert deshalb clientseitig **vor** dem Absenden |
| Budget / Forecast | nein | ≥ 0 |
| **Währung** | **bedingt** | `^[A-Z]{3}$`, **ohne Vorauswahl**; Pflicht, sobald ein Betrag steht. Trägt das Projekt bereits eine Währung, ist sie autoritativ und wird schreibgeschützt gezeigt. Kein implizites `EUR` (behebt DEF-7, §15.1) |
| Handwerker | nein | Party mit offener `contractor`-Rolle; serverseitig geprüft (`capex_projects_contractor_fkey` + dieselbe Prüffunktion) |
| Owner | nein | ≤ 200 Zeichen (Freitext — es gibt keine Mitglieder-Referenz) |
| Nächster Schritt | nein | Freitext |

Ein neues Projekt startet immer `idea`. `approvedBy`/`approvedAt` sind **nicht setzbar** — sie entstehen ausschließlich aus der Freigabe-Transition.

**„Maßnahme bearbeiten"** (`CapexProjectUpdateDto`): dieselben Felder plus **Ist-Ende** und **Ist-Betrag**, ohne Status. Es gilt dieselbe **Coalesce-Warnung** wie bei Tickets: ein Wert kann per Update nicht auf null zurückgesetzt werden; die UI sagt das, statt einen wirkungslosen Löschknopf anzubieten.

**„Ist-Betrag erfassen"** (bei `completed` / `invoiced`): wird **nur angeboten, wenn das Projekt eine Währung trägt** (§15.1). Dann ein Betragsfeld, Währung schreibgeschützt daneben. Sonst `NxNotice` mit Verweis auf „Maßnahme bearbeiten", wo Betrag und Währung in **einem** Kommando gesetzt werden. **Hinweis zur Fehlerzuordnung**, falls der Fall doch eintritt: der Server meldet `field: actual_amount`, nicht `currency_code` — die UI übersetzt das auf das Währungsfeld.

### 5.3 CapEx-Tab: Statuswechsel und Freigabe

- STM-007 ist **strikt linear**: `idea → planned → quote_requested → approved → in_progress → completed → invoiced → archived`. Es gibt genau einen Folgeschritt (`CapexProjectStatus.nextStatus`), **keine Rückwärtskante und keinen Abbruch**.
- Die Aktion heißt entsprechend `→ <nächster Status>`, außer beim Eintritt in `approved`: dort **„Freigeben"**, hervorgehoben, gegated auf `capex.approve`.
- Ohne `capex.approve` ist der Freigabeknopf **deaktiviert mit Tooltip**, der die Fähigkeit nennt. Das heutige Verhalten ist bereits korrekt und durch `property_maintenance_capex_panel_test.dart:79-105` gepinnt — **es darf nicht regredieren**.
- `capex.manage` allein genügt für die Freigabe **nicht**, und `capex.approve` allein genügt für die übrigen Schritte nicht (pgTAP `023:465`, `:475`). Die UI bildet beide Richtungen ab.
- **Kein Abbruch möglich:** ein irrtümlich angelegtes Projekt kann heute nicht verworfen werden — dieselbe Lücke wie bei Tickets (Schwester-Spec §D.4). Sie wird hier **benannt**, aber **nicht** in `MAINTENANCE-DATA-03` mitbeantragt: STM-007 bewusst ohne Rückwärtskanten zu bauen war eine Entscheidung der Domäne, und ein Abbruchzustand an einem freigegebenen Investitionsvorhaben ist eine eigene fachliche Frage (Freigabe zurückziehen? Budget freigeben?). → §15-D2.
- `actualEndDate` wird beim ersten Eintritt in `completed` serverseitig gestempelt, falls leer — die UI zeigt das an und behauptet nicht, es selbst gesetzt zu haben.

### 5.4 Getrennte Berechtigungszonen

Die beiden Tabs laden unabhängig und scheitern unabhängig: ein `forbidden` auf Tickets (`maintenance.read` fehlt) darf den CapEx-Tab **nicht** blockieren und umgekehrt. Das ist heute korrekt implementiert und durch `property_maintenance_capex_panel_test.dart:25-40` gepinnt. Jeder Tab rendert seinen eigenen Forbidden-State mit dem Namen **seiner** fehlenden Fähigkeit (`maintenance.read` bzw. `capex.read`).

## 6. Data requirements

Ticketfelder: Schwester-Spec §7.1, unverändert.

### 6.1 CapEx-Projektfelder (`public.capex_projects` via `CapexProjectDto`)

| Feld | Bedeutung | Pflicht | Editierbar | Regel |
|---|---|---|---|---|
| `id` | Identität | — | nein | UUID |
| `propertyId` | Objekt | ja | **nein** (geschützte Spalte) | fix aus der Route |
| `projectCode` | Kennung | ja | ja | 1–100 Zeichen |
| `category` | Gewerk/Kategorie | nein | ja | 1–100 Zeichen |
| `measure` | Maßnahmenbeschreibung | nein | ja | ≤ 2000 Zeichen |
| `status` | Lifecycle | ja | **nur per Transition** | STM-007, linear |
| `startDate` / `plannedEndDate` | Planung | nein | ja | `date` |
| `actualEndDate` | Ist-Ende | nein | ja | serverseitig gestempelt bei `completed`, falls leer |
| `budgetAmount` / `forecastAmount` / `actualAmount` | Geld | nein | ja | je ≥ 0, kein NaN |
| `currencyCode` | Währung | bedingt | ja | `^[A-Z]{3}$`; **Pflicht, sobald ein Betrag existiert** (DEC-011, Constraint `capex_projects_currency_required_check`) |
| `contractorPartyId` | Auftragnehmer | nein | ja | Party mit offener `contractor`-Rolle |
| `owner` | Verantwortlich | nein | ja | Freitext |
| `nextStep` | Nächster Schritt | nein | ja | Freitext |
| `approvedBy` / `approvedAt` | Freigabestempel | — | **nein** | nur aus der `approved`-Transition; bleibt bei allen weiteren Vorwärtsschritten erhalten |
| `version` | Optimistic Lock | — | nein | `expectedVersion` |
| `createdAt/By`, `updatedAt/By` | Herkunft | — | nein | Anzeige im Detail |

### 6.2 Beziehungen

```
property 1─n maintenance_ticket ──── ✗ keine Verknüpfung ────┐   🔒 MAINTENANCE-CAPEX-LINK-01
    │                                                        │
    └─n capex_project ───────────────────────────────────────┘
              │
   party(role=contractor, offen) ──┘  (FK capex_projects_contractor_fkey)
              │
   document ──n document_links(entity_type='capex_project') ──┘   (serverseitig gültig, nie geschrieben)
              │
   task(entity_type='capex_project') ─────────────────────────┘   (Enum trägt es, ungenutzt)
              │
   audit_events(entity_type='capex_project') ─────────────────┘   (9 Events im pgTAP-Fixturelauf)
```

**Keine workspace-weite CapEx-Lesefläche.** `CapexProjectListQuery` verlangt eine `propertyId`; ein `workspace_capex_projects`-Gegenstück zu `workspace_maintenance_tickets` existiert nicht (`maintenance_capex_repository.dart:64-70` sagt das ausdrücklich). Eine portfolioweite Investitionsübersicht ist damit heute **unmöglich** — das ist eine echte Lücke für Asset Manager. → §7-G12.

## 7. Backend gaps (zusätzlich zur Schwester-Spec §14)

| ID | Bedarf | Domäne | Schema/RLS/Permission? | Paket |
|---|---|---|---|---|
| **G12** | **Workspace-weite CapEx-Lesefläche** (`workspace_capex_projects`), analog zum bereits existierenden `workspace_maintenance_tickets`. Voraussetzung für jede portfolioweite Investitionsübersicht. | `maintenance_capex` | neue RPC + `capex.read`-Gate + pgTAP + Rollback-Test | `CAPEX-DATA-01` |
| ~~G13~~ | **entfällt.** `create_capex_project` und `update_capex_project` tragen `p_currency_code` bereits (`20260806100000_...:1415`, `:1602`); nach §15.1 Punkt (4) erreicht kein Betrag ohne Währung mehr den Transition-Pfad. Der Fix ist Bestandteil von `MAINTENANCE-PARITY-01` | — | — | — |
| **G14** | **Echter Abbruch-/Storno-Lifecycle für CapEx-Projekte** (§15-D2). Verifiziert: STM-007 ist strikt linear, kennt keinen Abbruch, und die Domäne hat kein Delete. Offene Produktfragen im Paket: darf eine erteilte Freigabe zurückgenommen werden, und was geschieht mit dem Budget | `maintenance_capex` | STM-007-Erweiterung + Command + pgTAP + Rollback-Test | **`CAPEX-CANCEL-01`** |
| **G15** | Gewährleistung als eigenes Konzept (§C.2) | neu | Entität + RLS + Permissions | `WARRANTY-01` |
| **G16** | Anlagen-/Bauteilregister mit Zustandshistorie und Wartungsintervallen (§D.2) | neu | Entität + RLS + Permissions + Generierung | `MAINTENANCE-PREVENTIVE-01` |
| **G17** | `owner` ist Freitext; eine Referenz auf ein Workspace-Mitglied wäre die richtige Modellierung | `maintenance_capex` + `identity_access` | Spaltentyp | mit **`MAINTENANCE-ASSIGNEE-01`** zu bündeln (Schwester-Spec §20-D2 / §14-G18) — dieselbe Modellfrage |

## 8. Permissions

Wie Schwester-Spec §8, plus:

| Aktion | Fähigkeit |
|---|---|
| CapEx lesen | `capex.read` (RLS `capex_projects_select_capex_read`, RPC-Gate) |
| CapEx anlegen/ändern/vorrücken | `capex.manage` |
| **CapEx freigeben** (`→ approved`) | **`capex.approve`** — serverseitig durch Zielverzweigung erzwungen (`20260806100000_...:1880/1888`); `capex.manage` allein reicht nicht, `capex.approve` allein reicht für andere Schritte nicht |
| Seite erreichen | `property.read` (geerbtes Mapping der Objekt-Route) |

Der Berechtigungs-Mismatch (Screen Map §0.6) trifft diese Fläche doppelt: Seite unter `property.read`, Tickets unter `maintenance.read`, Projekte unter `capex.read` — drei Ebenen. **Wird hier nicht gelöst** (`PERMISSION-CATALOG-02`); die Fläche macht ihn stattdessen erklärbar, indem jeder Tab seine eigene fehlende Fähigkeit benennt.

**AAL2 gilt auch hier** für jeden Read und Write (DEC-025).

## 9. Realtime

Beide Aggregate sind in der Publikation, und die Invalidierungsquelle unterscheidet `MaintenanceCapexAggregate.maintenanceTicket` von `.capexProject`.

**Das Panel wertet diese Unterscheidung heute aber nicht aus.** `_subscribeToInvalidation` (`property_maintenance_capex_controller.dart:452-459`) filtert ausschließlich auf `workspaceId` und ignoriert `invalidation.aggregate`; `_scheduleInvalidationReload` (`:462-468`) lädt danach bedingungslos **beide** Zonen neu (`loadTickets()` `:465`, `loadCapexProjects()` `:466`). Der workspace-weite Controller diskriminiert korrekt (`maintenance_tickets_controller.dart:322-325`) — dieses Panel nicht.

**Ziel v2: die Unterscheidung herstellen** — eine Ticketänderung lädt nur den Ticket-Tab nach, eine Projektänderung nur den CapEx-Tab; Reconciliation-Signale laden weiterhin beide.

Wie in der Schwester-Spec: Hintergrund-Reload darf sichtbare Daten **nicht** auf Skeleton zurücksetzen; `liveUpdatesDegraded` fehlt und kommt über `REALTIME-DEGRADED-WIRING-01`.

## 10. Screen states

Wie Schwester-Spec §10, **je Tab getrennt** (§5.4). Zusätzlich:

| Zustand | Rendering |
|---|---|
| CapEx empty | „Noch keine Maßnahme für dieses Objekt" + CTA, auf `capex.manage` gegated |
| CapEx forbidden | „Kein Zugriff auf Maßnahmen" · „… benötigt die Berechtigung (capex.read)." |
| Ein Tab forbidden, der andere ready | beide Tabs bleiben erreichbar; der gesperrte zeigt seinen Forbidden-State (testgepinnt) |
| Projekt ohne Währung, aber mit Betrag | kann serverseitig nicht existieren (Constraint) — tritt nicht auf |
| Gemischte Währungen in einer KPI-Summe | „gemischte Währungen", keine Addition (§2.2) |

## 11. Shared components

Wie Schwester-Spec §13. Zusätzlich geteilt zwischen beiden Flächen (und damit im selben Paket zu bauen, nicht doppelt):

- `maintenance_ticket_dialogs.dart`, `maintenance_ticket_detail.dart`, `maintenance_ticket_table.dart` — **eine** Implementierung, parametriert über „Objektspalte ja/nein" und „Objekt fix/wählbar". Die heutige Verdopplung der Ticket-Tabelle und des Anlege-Dialogs über beide Panels (`maintenance_tickets_panel.dart:403-496` vs. `property_maintenance_capex_panel.dart:478-551`) ist der Anfang derselben Copy-Paste-Krankheit, die das Legacy über 2899 + 3915 LOC verteilt hat. Sie wird jetzt beendet, nicht später.
- Neu: `capex_project_dialogs.dart`, `capex_project_detail.dart`.
- `PartyPickerField` (Kandidat für ein `SHARED-UI-*`-Paket, Schwester-Spec §13).

## 12. Test plan

Zusätzlich zur Schwester-Spec §17:

### Unit / application
- CapEx-KPIs: geplantes Budget und Investiert über gemischte Statusmengen; gemischte Währungen führen **nicht** zu einer Summe.
- Abweichungsberechnung nur bei vorhandenem Budget *und* Ist.
- `nextStatus` liefert genau einen Schritt; `archived` liefert null.
- Freigabe-Gate: `canApproveCapex` steuert ausschließlich den Übergang nach `approved`.
- Getrennte Ladepfade: ein `forbidden` auf Tickets lässt `capexPhase` unberührt.

### Widget / UI
- **Regressionstest erhalten:** „Freigeben" ist mit `{maintenance.read, maintenance.manage, capex.read, capex.manage}` **ohne** `capex.approve` deaktiviert (`onPressed == null`).
- **Regressionstest erhalten:** Ticket-`forbidden` blockiert den CapEx-Tab nicht.
- Beide Tabs in allen Zuständen aus §10, stabile Keys `Key('property-maintenance-<element>')`.
- Objektname erscheint in Kopf und Breadcrumbs.
- Kein Overflow bei 320/390/1024/1440 px, hell und dunkel; unter `tabletMax` ersetzt das Detail die Liste.
- `context.adaptivePagePadding` statt `EdgeInsets.all(24)` (DEF-8).

### Repository / integration
- **Neu:** Transition nach `completed` mit `actualAmount` auf einem Projekt ohne `currencyCode` → `validationFailed` (Bestandsverhalten des Servers, jetzt auch clientseitig abgefangen).
- Dokumentverknüpfung `entity_type='capex_project'` gegen ein existierendes Projekt → `ok`; gegen ein nicht existierendes → `not_found`.
- Freigabe durch einen Nutzer ohne `capex.approve` → `forbidden`; durch einen Freigabeberechtigten → Erfolg, `approvedBy`/`approvedAt` gestempelt.

### Staging E2E
1. Objekt öffnen (aus der workspace-weiten Liste) → Objektname erscheint im Kopf.
2. Ticket mit Einheit anlegen; Einheiten-Filter greift.
3. Maßnahme mit Budget **und explizit gewählter Währung** anlegen.
4. Maßnahme bis `quote_requested` vorrücken; als Nutzer **ohne** `capex.approve` ist „Freigeben" deaktiviert mit Tooltip.
5. Mit `capex.approve` freigeben → `approvedBy`/`approvedAt` sichtbar im Detail.
6. Bis `completed` vorrücken, Ist-Betrag mit Währung erfassen → Abweichung erscheint korrekt vorzeichenbehaftet.
7. Dokument am CapEx-Projekt verknüpfen und wiederfinden.
8. **Negativ:** Nutzer mit `capex.read` ohne `maintenance.read` → Ticket-Tab forbidden, CapEx-Tab funktioniert.
9. Realtime: Ticketänderung in Sitzung A lädt in Sitzung B **nur** den Ticket-Tab nach. **Neue Anforderung, keine Regressionssicherung** — heute lädt jede Invalidierung beide Zonen (§9).

## 13. Acceptance criteria

1. **AC-1** Kopf und Breadcrumbs nennen das Objekt beim Namen.
2. **AC-2** Beide Tabs laden, scheitern und rendern unabhängig; ein fehlendes Leserecht auf der einen Seite sperrt die andere nicht.
3. **AC-3** Ein CapEx-Projekt lässt sich anlegen **und bearbeiten**; die Währung wird sichtbar gewählt, nie stillschweigend gesetzt.
4. **AC-4** „Freigeben" ist ohne `capex.approve` deaktiviert und nennt die Fähigkeit im Tooltip; mit ihr stempelt der Server `approvedBy` und `approvedAt`, und beide sind im Detail sichtbar.
5. **AC-5** Ein Ist-Betrag ohne Währung erreicht den Server nie; erreicht ihn doch einer, wird das serverseitige `validationFailed` (mit `field: actual_amount`) clientseitig auf das Währungsfeld übersetzt und nicht als generischer Fehler gezeigt.
6. **AC-6** Die Abweichung wird nur bei vorhandenem Budget und Ist berechnet, trägt Vorzeichen und Label und ist nicht nur farbcodiert.
7. **AC-7** KPI-Summen addieren niemals über verschiedene Währungen hinweg.
8. **AC-8** Angeboten wird ausschließlich der eine erlaubte Folgeschritt aus STM-007.
9. **AC-9** Ticket-Tabelle, Ticket-Detail und Ticketformulare sind **derselbe Code** wie in der workspace-weiten Fläche; es existiert keine zweite Implementierung.
10. **AC-10** Die Fläche enthält weder einen Gewährleistungs- noch einen Bauteilzustand-Tab und auch keinen Behelf dafür; beide sind in dieser Spec als Folgepakete dokumentiert.
11. **AC-11** Es existiert kein Freitext-Behelf für die fehlende Ticket-↔-CapEx-Verknüpfung.
12. **AC-12** Kein horizontaler Überlauf bei 320/390/1024/1440 px, hell und dunkel; Seitenabstand kommt aus `context.adaptivePagePadding`.

## 13a. Accessibility and usability (Template §15)

Gilt unverändert Schwester-Spec §15. Zusätzlich objektspezifisch: der Objektname im Kopf ist Text, keine Farbe oder Icon; die Abweichungszahl im CapEx-Tab trägt Vorzeichen und Label und ist nie nur farbcodiert; der deaktivierte „Freigeben"-Knopf nennt im Tooltip die fehlende Fähigkeit `capex.approve`.

## 13b. Analytics / audit / history (Template §16)

Gilt unverändert Schwester-Spec §16. Zusätzlich: CapEx-Mutationen sind serverseitig ebenso auditiert wie Ticket-Mutationen (im pgTAP-Fixturelauf 9 `capex_project`-Ereignisse, lesbar mit `audit.read`, `023:556-563`). `approvedBy`/`approvedAt` sind die **einzigen** Freigabespuren, die die UI heute zeigen kann; der vollständige Verlauf kommt mit `AUDIT-01`. Kein clientseitig rekonstruierter Pseudo-Verlauf.

## 14. Out of scope

- Alles aus Schwester-Spec §19.
- **Gewährleistung** (§C) — `WARRANTY-01`.
- **Bauteilzustand / Anlagenregister** (§D) — `MAINTENANCE-PREVENTIVE-01`.
- **Portfolioweite CapEx-Übersicht** — braucht `CAPEX-DATA-01` (G12).
- **CapEx-Abbruch/Storno** — blockiert auf `CAPEX-CANCEL-01` (§15-D2). Blockiert **nur** diese Aktion, nicht das übrige CapEx-Management.
- **Budget-vs-Ist-Auswertung über Objekte hinweg** — Finance-Domäne, P2-D08.
- **Löschung der Legacy-Screens** — eigenes Hygiene-Paket (`UI-HYGIENE-01`), frühestens nach den vier Bedingungen in §15-D3. Nicht Teil des ersten Replacement-PR.

## 15. Closed decisions

Alle drei zuvor offenen Punkte sind am **2026-08-28** im Final-Approval-Review verbindlich entschieden. Die vier Entscheidungen der Schwester-Spec (§20 dort) gelten hier mit.

**D1 — Zwei Flächen: bestätigt, verbindlich.**
Es bleiben **zwei Produktoberflächen**: das workspace-weite Maintenance Center (`maintenance_tickets.md`) und diese objektbezogene Maintenance-/CapEx-Fläche. Sie teilen Domain-Komponenten, Controller- und Repository-Semantik und die Ticket-Detailflows — sie werden aber **nicht** zu einer künstlichen einzelnen Tab-Seite verschmolzen. Innerhalb dieser Fläche bleibt es bei zwei Tabs (Tickets · CapEx), weil beide denselben Objektkontext beschreiben und die KPI-Zeile nur nebeneinander eine Aussage über das Objekt trifft.
Praktische Folge der Entscheidung zum Lesepfad (Schwester-Spec §20-D1): **diese Fläche ist APPROVED und trägt die erste Implementierungswelle**, weil ihre Reads objektbezogen, vollständig und contract-getragen sind. Die workspace-weite Fläche folgt nach `MAINTENANCE-QUERY-01`.

**D2 — CapEx-Abbruch: nur mit echtem Server-Pfad.**
Ein CapEx-Projekt darf erst dann als „abgebrochen" behandelt werden, wenn der Server einen echten Lifecycle-/Command-Pfad dafür besitzt. Geprüft: STM-007 ist strikt linear, kennt keinen Abbruch- oder Storno-Zustand, und die Domäne hat überhaupt kein Delete (OPN-DOM-005). Also **`CAPEX-CANCEL-01`** als eigener Backend-Gap (§7-G14).
Ausdrücklich verboten bis dahin: ein Client-Flag · ein Delete als Ersatz · ein erfundener Status · eine Umdeutung von `archived`. Die Abbruch-**Aktion** ist blockiert — **das übrige CapEx-Management ist es nicht**: Anlegen, Bearbeiten, alle linearen Übergänge, die Freigabe über `capex.approve`, Ist-Betrag und Dokumentverknüpfung sind APPROVED und Bestandteil von Welle A. Die Fläche benennt die Lücke sichtbar, statt sie zu simulieren.

**D3 — Legacy-Löschung: erst nach bewiesenem Ersatz.**
Der Legacy-Maintenance-Screen wird **nicht im ersten Replacement-PR gelöscht**. Die inhaltliche Bewertung (§C, §D) ist abgeschlossen und bleibt gültig; sie ist die Voraussetzung, nicht der Auslöser. Gelöscht wird erst, wenn **alle vier** Bedingungen erfüllt sind:

1. die neue Fläche ist erreichbar,
2. alle bewusst übernommenen Funktionen sind migriert,
3. targeted **und** full tests sind grün,
4. die Staging-E2E des Replacements ist bestanden.

Danach ein **separater Cleanup-/Hygiene-Schritt** (`UI-HYGIENE-01`), nicht als Anhang am Feature-PR. Für den Gewährleistungs- und den Bauteilzustand-Teil gilt: sie dürfen in diesem Cleanup **endgültig entfernt** werden, weil die geretteten Konzepte bereits separat dokumentiert sind (`WARRANTY-01`, `MAINTENANCE-PREVENTIVE-01`) — für sie ist keine Migration abzuwarten, nur die vier Bedingungen oben.

### 15.1 Währung: keine implizite Annahme (DEF-6 / DEF-7)

Verbindlich, parallel zur Ticketseite (Schwester-Spec §20.1):

- `CapexProjectDraft.currencyCode` und `CapexProjectUpdateDto.currencyCode` existieren, und `create_capex_project` wie `update_capex_project` tragen `p_currency_code` (`20260806100000_...:1415`, `:1602`). Der Contract trägt Währung vollständig — der Fix gehört in `MAINTENANCE-PARITY-01`, nicht in ein Folgepaket.
- Das stille `currencyCode: result.budgetAmount != null ? 'EUR' : null` (DEF-7) **entfällt ersatzlos**.
- Die Währung wird zur **echten Pflichteingabe ohne Vorauswahl**, sobald ein Betrag erfasst wird. Trägt das Projekt bereits eine Währung, ist sie die autoritative Quelle und wird schreibgeschützt angezeigt.
- **(4)** Der Ist-Betrags-Dialog wird **nur angeboten, wenn das Projekt eine Währung trägt**; sonst verweist er auf „Maßnahme bearbeiten", wo Betrag und Währung in einem Kommando gesetzt werden. Damit trifft der serverseitige `validation_failed`-Pfad (`field: actual_amount`) in der Praxis nicht mehr auf.
- Es gibt **keine** autoritative Währungsquelle im System: weder `public.workspaces` noch `public.properties` führen eine Währungsspalte. Die Präzedenz des eigenen Codes ist ausdrücklich, in so einem Fall zu fragen statt zu raten (`20260730120000_...:1625`).
- Red-first-Regressionstest ist zwingend (§12).

### 15.2 Statusklassifikation

Diese Fläche ist **APPROVED**. Blockiert sind ausschließlich einzelne Aktionen mit fehlendem Server-Pfad — CapEx-Abbruch (`CAPEX-CANCEL-01`), interner Bearbeiter (`MAINTENANCE-ASSIGNEE-01`), zusätzliche Lifecycle-Kanten (`MAINTENANCE-DATA-03`), Ticket-↔-CapEx-Verknüpfung (`MAINTENANCE-CAPEX-LINK-01`), portfolioweite CapEx-Sicht (`CAPEX-DATA-01`). Die vollständige Dependency-Matrix steht in der Schwester-Spec **§22**; sie gilt für beide Flächen und wird nicht dupliziert.

## 16. Implementation handoff

**Umfang:** Gemeinsam mit der Schwester-Fläche **ein** Paket, **ein** Branch — die geteilten Ticket-Komponenten (§11) machen eine Trennung unwirtschaftlich und wären der direkte Weg in zwei divergierende Implementierungen. **Diese Fläche trägt Welle A**; die workspace-weite Fläche folgt in Welle B nach `MAINTENANCE-QUERY-01` (Schwester-Spec §21/§22).

**Reihenfolge — Welle A:**
1. Geteilte Ticket-Komponenten extrahieren (Tabelle, Detail, Dialoge, Filterleiste) — aus den heutigen zwei Kopien eine.
2. Diese Fläche auf sie umstellen: Objektkontext im Kopf, Einheiten-Filter, Split-Pane-Detail, volles Anlege- **und Bearbeiten**-Formular, Konflikt-UX nach Foundation §10.
3. Währungs-Defekte beheben (§15.1) — **red-first**, Ticket und CapEx.
4. CapEx-Tab ausbauen: Detail, Bearbeiten, volle Spalten, Formulare mit expliziter Währung; `capex.approve`-Gating unverändert erhalten.
5. Dokument- und Aufgabenverknüpfungen.
6. KPI-Zeile.
7. Test-Keys und Zustandsmatrix.

**Welle B (Schwester-Spec):** Rebuild der workspace-weiten Fläche auf denselben Komponenten, nach `MAINTENANCE-QUERY-01`. Der minimale Defektfix im heutigen workspace-weiten Panel ist **Schritt A6 der Welle A** (Schwester-Spec §21) und wartet ausdrücklich nicht auf `MAINTENANCE-QUERY-01`.

**Beteiligte Dateien:**
- Ändern: `property_maintenance_capex_panel.dart` (Rebuild), `property_maintenance_capex_controller.dart` (Filter, Detail-Load, kein Blanking beim Refresh, `update`-Kommandos für beide Aggregate).
- Neu: `lib/ui/screens/property_detail/widgets/capex_project_dialogs.dart`, `capex_project_detail.dart`; geteilte Ticket-Widgets unter `lib/ui/screens/maintenance/widgets/`.
- Unverändert: Contract, DTOs, Adapter, alle Migrationen.

**Harte Invarianten (zusätzlich zu Schwester-Spec §21):**
1. `capex.approve` bleibt die **einzige** Fähigkeit, die den Übergang nach `approved` erlaubt; die UI erfindet keinen zweiten Weg dorthin.
2. `approvedBy`/`approvedAt` werden niemals clientseitig gesetzt oder geschrieben.
3. Die Berechtigungszonen der beiden Tabs bleiben getrennt.
4. STM-007 bleibt linear; die UI bietet nie mehr als `nextStatus`.
5. Kein Behelf für die fehlende Ticket-↔-CapEx-Verknüpfung, keine Wiederbelebung von Gewährleistung oder Bauteilzustand in Legacy-Form.
6. Keine Schema-, RLS- oder Permission-Änderung im Screen-PR.
7. Keine implizite Währung an irgendeiner Stelle; keine Abbruch-Aktion für CapEx ohne `CAPEX-CANCEL-01`; kein interner Bearbeiter ohne `MAINTENANCE-ASSIGNEE-01`.
8. Der Legacy-Screen wird in diesem PR **nicht** gelöscht (§15-D3).
