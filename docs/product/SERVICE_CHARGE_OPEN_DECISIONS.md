# Zwei offene Entscheidungen der Betriebskostenabrechnung

**Stand 2026-09-08. Vorlage zur Entscheidung — dieses Dokument entscheidet
nichts.** Es beschreibt, was die Software heute tut, welche Optionen es gibt,
was jede kostet und was bis zur Antwort gesperrt bleibt. Die Entscheidungen
selbst stehen als `DEC-031` und `DEC-032` im Register
([`phase_0/11_decision_register.md`](../architecture/phase_0/11_decision_register.md))
und sind dort `open`.

Umgesetzte Grundlage: `SERVICE-CHARGE-PREVIEW-01` (Migration 71) in der
geltenden Fassung `SERVICE-CHARGE-UNIT-POOL-01` (Migration 72).

---

## Warum das jetzt entschieden werden muss

Die Vorschau rechnet. Sie ist ausdrücklich **keine Abrechnung**: nichts wird
gespeichert, nichts ist versioniert, nichts ist zustellbar, und der
Vorauszahlungsabzug — eine der vier Mindestangaben — fehlt vollständig. Der
Schritt von der Vorschau zum Dokument ist der Schritt, an dem diese beiden
Fragen unausweichlich werden: ein Dokument trägt eine Nachforderung, und eine
Nachforderung braucht eine Zahl, die jemand vertreten kann.

Teuer wird das über § 556 Abs. 3 BGB. Der Vermieter hat zwölf Monate ab Ende
des Abrechnungszeitraums für eine Nachforderung; danach ist sie ausgeschlossen,
sofern er die Verspätung zu vertreten hat (Satz 3). Der Mieter hat zwölf Monate
ab Zugang für Einwendungen (Satz 6). Abs. 5 macht Abweichungen **zum Nachteil
des Mieters** unwirksam. Ein zu großer Nenner benachteiligt nur den Vermieter —
er fällt deshalb niemandem auf und verfällt still.

---

## Frage 1 (`DEC-031`) — der Bemessungswert, der sich im Zeitraum ändert

### Was die Software heute tut

Die Vorschau löst Zähler und Nenner **beide zum Ende des Zeitraums** auf
(`allocation_basis_resolution(..., p_to)` für den Nenner, `validity @> p_to`
für den Zähler) und verweigert die Verteilung mit `basis_changed_in_window`,
sobald für eine Einheit des Objekts eine Wertzeile den Zeitraum überlappt, ohne
ihn zu decken.

Das ist heute also faktisch ein **Stichtagsverfahren mit Sicherung** — kein
neutraler Ausgangspunkt, sondern bereits eine der Optionen unten, ergänzt um
eine Weigerung, sie anzuwenden, wenn sie strittig würde.

### Die Lücke ist größer als bisher berichtet

Der Wächter prüft **nur Wertzeilen in `unit_basis_values`**, und die gibt es nur
für `fixed_share`, `persons` und `co_ownership_share`. Für `area_sqm` und
`unit_count` existiert kein datierter Wert.

Wichtiger, und bisher von mir zu schwach dargestellt: **die Menge der Einheiten
im Nenner trägt bei _keiner_ Bemessung ein Datumsprädikat.** Beide Abfragen
lauten schlicht `from public.units where workspace_id = … and property_id = …`.
Eine im August 2024 angelegte Einheit steht damit auch unter einem
Personenschlüssel im Nenner einer Abrechnung für Januar 2024, und der Wächter
sieht Ein- und Austritte von Einheiten nicht. Der Wert ist für drei Bemessungen
datiert; der **Bestand** für keine.

### Was rechtlich feststeht — und was nicht

**Im Wortlaut geprüft** (gesetze-im-internet.de):

- § 556a Abs. 1 BGB macht die Wohnfläche zum Maßstab, **„haben die
  Vertragsparteien nichts anderes vereinbart"** und „vorbehaltlich anderweitiger
  Vorschriften". Ein Personenschlüssel existiert also nur, weil ihn jemand
  vereinbart hat.
- § 556a Abs. 3 BGB gilt für vermietetes Wohnungseigentum **ebenfalls nur
  mangels abweichender Vereinbarung**; widerspricht der Eigentümermaßstab
  billigem Ermessen, wird **ganz** nach Abs. 1 umgelegt. Abs. 4 erklärt nur eine
  von **Absatz 2** abweichende Vereinbarung für unwirksam, nicht eine von Abs. 3.
  Für das Modell heißt das: `co_ownership_share` ist ein *Default*, den der
  Vertrag verdrängt — kein gesetzlich fixierter Nenner.
- § 556a Abs. 2 BGB regelt eine **einseitige Erklärung in Textform** und bindet
  nur diese an den Beginn eines Abrechnungszeitraums. Er sagt nichts über die
  Bewegung eines Messwerts *innerhalb* der Periode und ist keine allgemeine
  Regel „der Maßstab ist an der Periodengrenze eingefroren".

**Aus dem Urteil geprüft** — BGH 30.05.2018, VIII ZR 220/17: maßgeblich ist die
**tatsächliche** Fläche an der **tatsächlich vorhandenen** Gesamtfläche der
Wirtschaftseinheit; die frühere 10-%-Toleranz ist für die Betriebskostenumlage
**aufgegeben**. Der Streitfall *war* der Fall der vertraglich vereinbarten
Fläche (74,59 m² vereinbart, 78,22 m² tatsächlich) und ist gegen sie
entschieden. Außerhalb des Leitsatzes bleibt allein ein vertraglich vereinbarter,
von § 556a Abs. 1 abweichender **Umlagemaßstab** — nicht die Fläche.

> Daraus folgt unmittelbar: mit dem heutigen Bestand einen vergangenen Zeitraum
> zu rechnen ist nicht bloß unschön. Wenn eine Wohnung 2024 60 m² hatte und
> heute 75 m² hat, ist 75 im Anwendungsbereich des gesetzlichen Schlüssels der
> falsche Nenner, und es gibt keine Toleranz, in der das verschwindet.

**Nicht belegt:** kein Gesetz und keine gefundene Entscheidung sagt, **wie** ein
im Zeitraum geänderter Messwert zu aggregieren ist. Gezielt gesucht wurde nach
einer Entscheidung, die Zeitgewichtung verlangt oder einen reinen Stichtag
verwirft — Ergebnis „nicht gefunden", ausdrücklich nicht „existiert nicht".

**Aus Sekundärquellen, nicht im Volltext geprüft:** VIII ZR 181/09 soll beide
Pole benennen („taggenau" oder Stichtage) und die Wahl der *inhaltlichen*
Richtigkeit zuordnen, nicht der formellen Wirksamkeit; VIII ZR 97/14 soll die
bloße Angabe „Personenmonate" genügen lassen; VIII ZR 82/07 soll Melderegister
als Quelle verwerfen und die Feststellung „zu Stichtagen" als möglichen Weg
nennen. Diese drei tragen keine Entscheidung, sie geben nur den Rahmen.

### 1A — Welche Aggregationsregel gilt?

Jede Option nach demselben Schema. **A1 ist heute gebaut.**

| | tut | braucht | baut | Folge für die Zahl |
|---|---|---|---|---|
| **A1 Stichtag** | ein Datum bestimmt den Wert für den ganzen Zeitraum | je Einheit einen Wert, der dieses Datum deckt | nichts an der Rechnung; zu entfernen ist der Wächter, zu benennen das Datum | hängt am gewählten Datum; ein Wechsel einen Tag davor oder danach ändert sie ganz |
| **A2 Zeitgewichtung** | jeder Wert geht mit der Zahl seiner Tage im Zeitraum ein | datierte Intervalle je Einheit, in Zähler **und** Nenner | Auflösung über den Zeitraum statt über einen Tag | folgt der Dauer; kein Sprung an einem Stichtag |
| **A3 Mittel mehrerer Stichtage** | mehrere Momentaufnahmen werden gemittelt | je Einheit einen Wert je Stichtag | Auflösung je Stichtag plus Mittelung; die Stichtage sind zu benennen | trifft A2 bei gleichen Abständen und einem Wechsel genau auf einem Stichtag, weicht sonst ab |
| **A4 Teilperioden** | der Zeitraum wird am Änderungsdatum geteilt, jede Teilperiode bekommt eigenen Zähler und Nenner | dieselben datierten Intervalle wie A2 | Auflösung je Teilperiode, Zusammenführung der Zeilen, Rundung je Teilperiode | mehrere Zeilen statt einer gewichteten; die Analogie zu § 9b HeizkostenV |
| **A5 keine Regel** | die heutige Verweigerung bleibt | nichts | nichts | für betroffene Zeiträume entsteht keine Zahl |

### 1B — Wo wohnt die Regel?

Unabhängig von 1A zu beantworten; jede Regel ist mit jedem Ort kombinierbar.

| | tut | braucht | baut | Folge |
|---|---|---|---|---|
| **B1 Hauskonstante** | eine Regel für alle Verträge und Kostenarten | nur die Wahl aus 1A | die gewählte Regel im Rechenlauf | ein abweichender Vertrag ist nicht abbildbar |
| **B2 Versionierte Regel nach `DEC-014`** | Aggregation je Vertrag und Kostenart als Datum mit Gültigkeitszeitraum | eine Regelzeile je Vertrag und Kostenart | Regeltyp, Schreibpfad, Bestätigungsereignis, Auflösung im Rechenlauf, Fall „nicht gesetzt" | verschiedene Verträge rechnen verschieden; jede Herleitung muss die angewandte Regelversion nennen |

Für `co_ownership_share` spricht der Vertragsvorbehalt aus § 556a Abs. 3 eher
für B2 als für B1 — der Eigentümermaßstab ist ein Default, den der Mietvertrag
verdrängen kann.

### 1C — Was geschieht mit dem fehlenden datierten Bestand?

| | tut | braucht | baut | Folge |
|---|---|---|---|---|
| **C1 nichts bauen** | die Asymmetrie bleibt | nichts | nichts | ein vergangener Zeitraum rechnet mit dem heutigen Bestand — im Anwendungsbereich von VIII ZR 220/17 angreifbar |
| **C2 aus dem Bestand rekonstruieren** | der frühere Wert wird aus vorhandenen Quellen gelesen: `rent_roll_snapshot_lines` friert je Einheit eine `area_sqm` ein, und `private.unit_snapshot` trägt sie bei jedem `unit.update` als `old_values` und `new_values` nach `audit_events` | keine neuen Daten | eine Leseschicht, die den Audit-Trail rückwärts abspielt oder den passenden Snapshot wählt | beide Quellen sind unvollständig — Snapshots nur wo genommen, Audit nur was durch die Kommandos lief; ein append-only-Auditlog wird Quelle einer Abrechnungsarithmetik |
| **C3 Gültigkeitsintervalle** | Fläche **und** die Zugehörigkeit einer Einheit zur Abrechnungseinheit bekommen datierte Intervalle nach dem Muster von `unit_basis_values` | für die Zukunft nichts, für die Vergangenheit ein gesetztes `valid_from` oder eine Ableitung aus C2 | Tabelle/Spalten, Constraint, RLS, Migration mit Rollback-Test, Backfill, Schreibpfad auf `public.units`, jeden Leser von `units.area_sqm`, Datumsprädikat für den Einheitenbestand | ein vergangener Nenner ist berechenbar; erst damit sind A2, A3 und A4 **für jede Bemessung** vollständig rechenbar |
| **C4 beim Erteilen einfrieren** | die erteilte Abrechnung speichert Zähler, Nenner, Bemessungsgrundlage und die angewandte Regel | keine Historie in den Stammdaten | `service_charge_runs` + `_lines` wie im Programm vorgesehen, plus den Schreibpfad | eine erteilte Abrechnung bleibt nachvollziehbar; eine **erstmalige** Abrechnung für einen vergangenen Zeitraum bleibt so falsch wie unter C1 |

**Abhängigkeit zwischen 1A und 1C.** Der Bestand der Einheiten ist heute für
*jede* Bemessung undatiert. Unter **C1** und **C4** ist deshalb **keine** der
Regeln A2, A3, A4 vollständig rechenbar — auch nicht für die drei Bemessungen
mit gespeichertem Wert, weil deren Nenner dieselbe undatierte Einheitenmenge
verwendet. Vollständig rechenbar werden sie erst unter **C3**, für C2 nur so
weit, wie die Quellen reichen. A1 und A5 sind unter jeder C-Option wählbar.

### 1D — Wo wird die Zähler/Nenner-Invariante durchgesetzt?

Zähler und Nenner **müssen dieselbe Aggregation verwenden**, sonst summieren
sich die Anteile nicht auf eins und die Differenz landet unbemerkt bei
irgendjemandem. Das ist keine Wahl. Zu entscheiden ist nur **wo** es erzwungen
wird: schreibseitig (eine Konfiguration setzt beide Seiten gemeinsam) oder
leseseitig (der Rechenlauf verweigert, wenn sie auseinanderfallen).

---

## Frage 2 (`DEC-032`) — die nur teilweise vermietete Einheit

### Was die Software heute tut

Die Zeilen lauten auf die **Einheit**. Je Einheit werden `days_let` und
`days_in_window` gemeldet; **geteilt wird nichts**, und keine Zahl wird mit
diesen Tagen multipliziert.

Eine Ehrlichkeit dazu: unter einem **Personenschlüssel** trägt eine Einheit, die
mit erfasster Null geführt wird, heute schon nichts — derselbe Wert steht im
Zähler und im Nenner. Die übrigen Mieter absorbieren ihren Anteil also bereits.
Das ist eine Tatsache über den heutigen Zustand, keine Bewertung.

### Was rechtlich feststeht

- § 9b Abs. 1 HeizkostenV macht die **Zwischenablesung bei Nutzerwechsel zur
  Pflicht** („hat … vorzunehmen"), vorbehaltlich der Ausnahmen in Abs. 3 und
  der Kostenregel in Abs. 4. Für Wärme und Warmwasser ist eine rein
  zeitanteilige Aufteilung deshalb **keine gleichwertige Option**, sondern nur
  der Weg für den Fall, dass die Ablesung unmöglich oder unverhältnismäßig ist.
- § 7 Abs. 1 HeizkostenV verteilt die Heizkosten zu 50–70 % nach erfasstem
  Verbrauch; die übrigen Kosten nach Wohn-/Nutzfläche **oder umbautem Raum**
  (Satz 5). § 8 Abs. 1 verteilt die Warmwasserkosten ebenso zu 50–70 % nach
  Verbrauch, die übrigen aber **nur nach Wohn- oder Nutzfläche** — „umbauter
  Raum" ist dort **kein** zulässiger Schlüssel.
- Personen sind unter der HeizkostenV **nie** ein zulässiger Schlüssel
  (außerhalb des vom Vermieter selbst bewohnten Zweifamilienhauses, § 2).

### 2A — Wer trägt den Anteil einer leerstehenden Einheit?

| | tut | Folge |
|---|---|---|
| **A1 Eigentümer** | der Anteil der leerstehenden Einheit wird ausgewiesen und keinem Mieter belastet | die Einheit erscheint mit ihrer Summe; die Abrechnung eines Mieters ändert sich durch den Leerstand nicht |
| **A2 auf die übrigen Mieter** | der Leerstandsanteil erhöht die Anteile der vermieteten Einheiten | die Abrechnung eines Mieters hängt davon ab, wie voll das Haus war |
| **A3 Status quo** | Zeilen bleiben auf der Einheit, es wird nichts zugeordnet | die Frage bleibt beim Leser der Abrechnung; unter einem Personenschlüssel mit erfasster Null findet A2 heute bereits statt |

### 2B — Wie wird bei Mieterwechsel geteilt?

**Getrennt nach Kostenart, weil das Recht sie trennt.**

Für Wärme und Warmwasser: die Zwischenablesung ist die Pflichtform (§ 9b Abs. 1
HeizkostenV); die zeitanteilige Aufteilung ist die Ersatzform für die Fälle des
Abs. 3. Zu entscheiden ist, ob das Produkt die Zwischenablesung **verlangt**
(und ohne sie verweigert) oder sie **anbietet** und den Ersatzweg zulässt.

Für alle übrigen Betriebskosten:

| | tut | braucht |
|---|---|---|
| **B1 zeitanteilig** | der Anteil der Einheit wird nach Tagen auf die Mietverhältnisse verteilt | die Laufzeiten, die vorhanden sind |
| **B2 nach Abrechnungsprinzip** | Leistungsprinzip zeitanteilig, Abflussprinzip nach Zahlungszeitpunkt | das je Kostenart schon konfigurierte Prinzip |
| **B3 Status quo** | keine Aufteilung; die Zeile bleibt auf der Einheit | nichts |

### 2C — Die Lücke zwischen zwei Mietverhältnissen

Der praktische Regelfall ist nicht „vermietet" oder „leer", sondern **Mieter A —
Lücke — Mieter B**. Diese Dreiteilung fällt heute zwischen 2A und 2B. Zu
entscheiden ist, ob die Lücke wie Leerstand behandelt wird (2A) oder einem der
beiden Mietverhältnisse zugeschlagen wird.

### 2D — Endet das Produkt bei der Einheit?

Die Frage, die die anderen begrenzt: **soll die Abrechnung überhaupt auf einen
Mieter lauten?** Lautet die Antwort „das Produkt endet bei der Einheit, die
Zuordnung zum Mieter macht ein Mensch", entfallen 2B und 2C vollständig und 2A
reduziert sich auf eine Darstellungsfrage. Diese Frage ist deshalb **zuerst** zu
beantworten.

---

## Was bis zur Antwort gesperrt bleibt

Je Unterfrage, damit erkennbar ist, was eine Teilantwort freigibt.

| Sperre | hängt an | fällt mit |
|---|---|---|
| Keine gespeicherte, versionierte oder zustellbare Abrechnung | 1A, 1C, 2D | einer Antwort auf alle drei |
| `basis_changed_in_window` wird nicht entfernt oder aufgeweicht | 1A | einer Antwort auf 1A |
| Keine weitere Bemessung mit **Stammdaten**wert ohne dieselbe Sicherung | 1A | einer Antwort auf 1A |
| Jede Abrechnung, deren Zeitraum vor dem heutigen Tag endet, muss auf dem Ergebnis ausweisen, dass sie mit dem heutigen Bestand gerechnet ist | 1C | einer Antwort auf 1C |
| Kein Multiplizieren einer Zeile mit `days_let` | 2A, 2B, 2C | einer Antwort auf 2D und dann 2A/2B/2C |

**`consumption` fällt ausdrücklich nicht unter diese Sperren.** Ein
Verbrauchswert ändert sich definitionsgemäß innerhalb des Zeitraums; die Regel
dafür ist § 9b HeizkostenV, nicht diese Entscheidung. Die Bemessung hängt an
P-4 (Zähler), nicht an Frage 1.

---

## Was hier ausdrücklich nicht zur Entscheidung steht

- **Die Erläuterung des Verteilerschlüssels als Pflichtangabe.** `DEC-014`,
  Konsequenz 2, ist freigegeben und gebaut: `allocation_keys.explanation` ist
  `not null`. Eine Lockerung wäre eine Änderung an `DEC-014` und dort zu
  vermerken.
- **Die Zähler/Nenner-Invariante selbst** (siehe 1D) — nur ihr Durchsetzungsort.
- **Der `unit`-Kostenstellen-Defekt** — behoben in Migration 72.
