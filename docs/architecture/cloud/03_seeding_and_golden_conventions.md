# Konventionen: Datenbank-Seeding und Pixel-Goldens

Stand: 2026-08-07 · Commit `ada10fb`
Zweck: Zwei Konventionen, die 2026-08-07 geändert wurden und deren Verletzung nicht
sofort auffällt. Beide waren drei Wochen lang Ursache eines roten Hosted-CI-Laufs
(`C-01`, `C-02` in `05_phase_a_log.md`).

---

## 1. Seeding: `supabase db reset` erzeugt **keine** Daten mehr

### Die Regel

`supabase/config.toml` enthält seit `b3d613a`:

```toml
[db.seed]
enabled = false
```

**Ein `supabase db reset` liefert ab jetzt ein leeres Schema — keine Workspaces, keine
Rollen, keinen Rechtekatalog, keinen Admin-Benutzer.** Das gilt auch ohne `--no-seed`,
und es gilt genauso für `supabase migration down` und `supabase migration up`.

Wer nach einem Reset einen Admin-Login oder einen Workspace erwartet, bekommt ihn nicht.
Das ist Absicht, kein Defekt.

### Warum

`supabase migration down` ist kein reiner Rollback — es setzt die Datenbank auf eine
frühere Version zurück und **seedet dabei mit**, ohne ein eigenes `--no-seed` zu besitzen.
Gemessen am lokalen Stack, vor der Änderung:

| Schritt | `select count(*) from public.permissions` |
|---|---|
| `npx supabase db reset --local --no-seed` | 0 |
| danach `npx supabase migration down --local --last 1` | **29**, Ausgabe `Seeding data from supabase/seed.sql...` |

Der CI-Rollback-Replay startete damit ungeseedet und wurde durch seinen ersten
Down-Schritt stillschweigend zu einem geseedeten Lauf. Der abschließende
`supabase test db --local` starb daraufhin in 25 pgTAP-Dateien an
`duplicate key value violates unique constraint "permissions_key_unique"` — denn die
Migrationen säen `public.permissions` **bewusst nicht** (siehe
`supabase/migrations/20260806100000_p2_d06_maintenance_capex.sql` Z. 35–38), damit jede
pgTAP-Datei ihren eigenen Rechtekatalog anlegen kann.

Nach der Änderung: `permissions` bleibt über Reset und Down hinweg bei 0, die Zeile
`Seeding data from …` verschwindet, und der vollständig lokal nachgefahrene CI-Replay
(27 Down-Schritte, `migration up`, volle Suite) liefert `Files=25, Tests=1246,
Result: PASS` statt `Tests=472, Result: FAIL`.

### `seed.sql` ist ein manuelles Bootstrap-Fixture

Das stand schon vorher im Kopf der Datei — die Konfiguration widersprach ihm nur:

> „Run with `psql -v ON_ERROR_STOP=1 -f supabase/seed.sql` for manual local bootstrapping."

`seed.sql` legt einen lokalen Admin (`admin@neximmo.com`), einen Workspace (`neximmo`),
Rollen, den Rechtekatalog und die Mitgliedschaft an. Es ist ein **Entwickler-Bequemlichkeits-Fixture
für den lokalen Stack**, kein Bestandteil des Schemas und keine produktive
Bootstrap-Funktion.

### Wer `seed.sql` einspielt

Genau ein Prozess, und der tat es schon immer explizit:

```powershell
./tool/bootstrap_p2_x01_local.ps1
```

Das Skript startet den Stack falls nötig, fährt `npx supabase migration up --local`,
kopiert `supabase/seed.sql` per `docker cp` in den DB-Container und wendet es mit
`psql -v ON_ERROR_STOP=1 -f` an. Anschließend verifiziert es das Ergebnis
(Auth-User, Identity, Workspace, aktive Admin-Mitgliedschaft, Admin-Rechte) und wirft bei
Abweichung.

**Es hat nie auf automatisches Seeding gebaut.** Deshalb geht mit `enabled = false` keine
Bootstrap-Fähigkeit verloren — der eine Weg, der Bootstrap-Daten erzeugt, ist unverändert
und ab jetzt der einzige.

Manuell, ohne Skript:

```bash
docker exec -i supabase_db_neximmo-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /path/to/seed.sql
```

`seed.sql` darf **keine** psql-Meta-Kommandos enthalten (`\set` etc.): der CLI-Seeding-Pfad
sendet die Datei als rohes SQL. Der Dateikopf erklärt, warum — ein früherer `\set` in
Zeile 1 hat genau diesen Pfad mit einem Syntaxfehler gebrochen.

### Was auf dem ungeseedeten Zustand beruht

| Konsument | Warum |
|---|---|
| Alle 25 pgTAP-Dateien in `supabase/tests/` | Jede legt ihren eigenen Rechtekatalog und ihre eigenen Workspaces/Rollen an. Ein geseedeter Katalog kollidiert auf `permissions_key_unique` |
| CI-Job `database`, Schritt „Reset and apply migrations" | `supabase db reset --local --no-seed` |
| CI-Job `database`, Rollback-Replay (27 Schritte) | Der eigentliche Auslöser dieser Änderung |
| Alle 14 `tool/verify_*.ps1` / `tool/test_*.ps1` | Jedes beginnt mit `npx supabase db reset --local --no-seed` und baut seine Fixtures selbst |
| `supabase/tests_integration/*_setup.sql`, `tests_concurrency/`, `tests_performance/` | Eigene Fixtures, eigene Rechte |

Kein Test und kein Job erwartet geseedete Daten. Das `--no-seed` in all diesen Aufrufen
bleibt stehen — es ist jetzt redundant, aber es dokumentiert die Absicht an der
Aufrufstelle und schützt gegen ein Wiedereinschalten der Option.

---

## 2. Goldens: Linux ist die kanonische Plattform

### Die Regel

Pixel-Goldens werden **auf Linux** erzeugt und sind nur dort autoritativ. Die sechs
Reference-Slice-Golden-Tests laufen ausschließlich unter Linux; auf Windows und macOS
werden sie übersprungen.

### Warum Windows-Goldens nicht autoritativ sind

Ein Golden ist ein Byte-Vergleich zweier PNGs. Textrasterung — Hinting, Subpixel-Kanten,
Antialiasing — unterscheidet sich zwischen Windows und dem Linux-Runner. Dieselben Bilder
bestehen dort, wo sie erzeugt wurden, und scheitern überall sonst, ohne dass sich am
Widget-Baum etwas geändert hätte.

Genau das war der Zustand: die Goldens lagen seit `3a7e5e8`/`25f6269` als
Windows-Artefakte im Baum, waren lokal grün und haben Hosted CI seit **2026-07-18 in
sechs aufeinanderfolgenden Läufen** rot gemacht. Ein plattformübergreifend geteiltes
Golden ist strukturell nicht haltbar; genau eine Plattform muss die Referenz sein, und das
ist sinnvollerweise die, auf der CI läuft.

Der Diff-Nachweis vor der Übernahme: die `isolatedDiff`-Bilder zeigten ausschließlich
Glyphenkanten und Text-Unterstriche, nichts verschoben, nichts fehlend, und
`masterImage`/`testImage` lagen in der Dateigröße unter 100 Byte auseinander
(z. B. 46488 gegen 46479). Rasterung, kein Layout-Regress.

### Was übersprungen wird und was nicht

Übersprungen auf Nicht-Linux (`test/features/reference_slice/reference_slice_screen_test.dart`):

- `matches ready (phone|tablet|desktop) golden`
- `matches ready dark (phone|tablet|desktop) golden`

**Alles andere in derselben Datei läuft überall weiter** — Rendering-Zustände,
passwordless/TOTP-Aktionen, Filter, das Phone-Umschalten zwischen Liste und Detail, die
`has no overflow at $viewport`-Prüfungen über alle drei Breakpoints, Konflikt- und
Fehlerzustände. Das Plattform-Gate betrifft nur den Byte-Vergleich, nicht die
Layout-, Overflow- oder Verhaltensabdeckung.

Lokal auf Windows: 13 grün, 6 übersprungen. In CI: alle 19 grün.

Die Umsetzung ist bewusst minimal — ein `final skipOffLinux = !Platform.isLinux;` und
`skip: skipOffLinux` an den beiden Schleifen. **Keine weitere Plattformlogik**, keine
Toleranz-Comparators, keine plattformspezifischen Golden-Verzeichnisse, solange es dafür
keinen konkreten Bedarf gibt.

### Kontrolliert neu erzeugen

Nie lokal `flutter test --update-goldens` — das verschiebt die Diskrepanz nur auf die
andere Plattform und macht CI erneut rot.

Stattdessen einen `goldens/**`-Branch pushen:

```bash
git push origin HEAD:refs/heads/goldens/regen-<datum>
```

Das startet `.github/workflows/goldens.yml` auf ubuntu. Der Job

1. fährt die Golden-Tests normal und lädt die Diffs als Artefakt `golden-diffs` hoch,
2. regeneriert mit `--update-goldens`,
3. prüft, dass die neuen Bilder auf Linux bestehen,
4. lädt sie als Artefakt `goldens-linux` hoch.

Danach: `gh run download <id>`, **die `isolatedDiff`-Bilder ansehen**, und erst wenn sie
nur Rasterung zeigen, die PNGs aus `goldens-linux` in
`test/features/reference_slice/goldens/` übernehmen und committen. Zuletzt den
temporären Branch löschen.

Der Diff-Schritt ist der Punkt der ganzen Übung: `--update-goldens` zementiert einen
Layout-Regress genauso stillschweigend wie einen Rasterungsunterschied. Wer ihn
überspringt, hat die Goldens nicht regeneriert, sondern abgeschafft.

Der Workflow triggert zusätzlich auf `workflow_dispatch`, was aber erst greift, wenn er
auf dem Default-Branch liegt — GitHub bietet Dispatch nur für Workflows an, die dort schon
existieren.

Für Golden-Tests außerhalb des Reference Slice gilt dieselbe Regel, sobald es welche gibt:
Linux erzeugt, Nicht-Linux überspringt.
