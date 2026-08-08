# PH-00 Toolchain- und CI-Bericht

Stand: 2026-08-02  
Evidenz: `RUN-LOCAL`, soweit nicht anders markiert

## Toolchain

| Werkzeug | Version/Status |
| --- | --- |
| Flutter | 3.29.2 |
| Dart | 3.7.2 |
| Node.js | 24.11.1 |
| npm | 11.10.0 |
| Supabase CLI | 2.109.1, durch `package.json` gepinnt |
| Docker Client/Server | 29.6.1 / 29.6.1 |
| PowerShell | 7.6.3 |
| Git | 2.52.0.windows.1 |
| Visual Studio | Community 2022, 17.14.36717.8 |
| Windows C++/CMake/SDK | installiert und durch Windows-Build belegt |

Flutter benoetigt Schreibzugriff auf seinen SDK-Cache ausserhalb des Repository-Sandboxes.
Docker Desktop wurde fuer die lokale Baseline im Hintergrund gestartet.

## CI-Abgleich

`.github/workflows/flutter.yml` definiert:

1. Flutter: locked Pub-Aufloesung, Analyze, Gesamttests, Web-Build.
2. Datenbank: Start, Reset, Lint, Security-/Performance-Advisors, pgTAP.
3. Rollback-Replays fuer alle aktuellen P1-/P2-Migrationen.
4. Concurrency-, PostgREST-, Realtime- und Domainintegrationstests.
5. Backup/Restore, Korruptionsschutz, Crash-Recovery und Performancekalibrierung.

Die lokale Ausfuehrung entsprach dieser Reihenfolge. GitHub-CI und offene PRs bleiben `NOT-RUN`.
Vercel wurde read-only ueber Projekt-, Deployment- und Buildlog-Metadaten geprueft: Produktion
auf `main` ist `READY`; App-Zweig-Previews scheitern am fehlenden Root Directory `marketing`.
