@echo off
setlocal
cd /d "%~dp0.."
echo Repo: %CD%
echo.
echo Pushe Branch docs/tasks-notifications-screens-01 nach origin ...
echo.
git push -u origin docs/tasks-notifications-screens-01
echo.
if errorlevel 1 (
  echo FEHLGESCHLAGEN - siehe Meldung oben.
) else (
  echo OK - Branch ist auf GitHub. PR anlegen:
  echo https://github.com/MeisnerMax/NextImmo/compare/main...docs/tasks-notifications-screens-01
)
echo.
pause
