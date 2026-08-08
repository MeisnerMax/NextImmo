# PH-01-T02 Auth- und Sessionevidenz

Stand: 2026-08-02  
Branch: `codex/ai-ph00-baseline`  
Status: `implemented_build_verified`

## RUN-LOCAL

| Nachweis | Ergebnis |
| --- | --- |
| Auth-/Identity-/Controller-/Responsive-Suite | PASS, 59 Tests |
| Passwordless-Anforderung ohne implizites Signup | PASS |
| TOTP Enrollment, Challenge und AAL2 Verify | PASS |
| AAL1 blockiert Property-Mutation | PASS, realer lokaler Supabase-Client |
| AAL2 erlaubt autorisierte Property-Mutation | PASS, realer lokaler Supabase-Client |
| Logout leert die lokale Session | PASS |
| Sessionverlust/-downgrade verwirft spaete Daten | PASS |
| Rollen-/Membership-Entzug leert Client-Caches | PASS, realer Zwei-Client-Test |
| Fremder Workspace und fremde Entitlement-Payloads | PASS, fail closed |
| Phone-/Tablet-/Desktop-Authzustaende ohne Overflow | PASS |
| Lokaler Magic-Link enthaelt `neximmo://auth/callback` | PASS, reale Mailpit-Nachricht |
| Windows-Callback persistiert die erfolgreiche Session | PASS, gestarteter Release-Build; Testsession anschliessend entfernt |
| Windows registriert `neximmo://` per-user beim Start | IMPLEMENTED, Release-Build PASS |

Ausgefuehrte Befehle:

```text
flutter test --no-pub test/app_runtime_test.dart \
  test/features/identity_access/supabase_identity_access_repository_adapter_test.dart \
  test/features/identity_access/supabase_entitlement_invalidation_adapter_test.dart \
  test/features/reference_slice/reference_slice_controller_test.dart \
  test/features/reference_slice/reference_slice_screen_test.dart
tool/verify_p1_007_integration.ps1
tool/verify_p1_011_e2e.ps1
```

## NOT-RUN

- kontrollierter Ablauf eines realen Refresh-/Access-Tokens,
- OS-Cold-Start ueber den registrierten `neximmo://`-Handler (Testfreigabe wurde vor Ausfuehrung abgelehnt),
- Remote-/Staging-Auth,
- produktive E-Mail-Zustellung,
- allgemeine privilegierte Rollen-/AAL2-Matrix.

## Gate-Bewertung

Die lokale Auth-, MFA-, Logout-, Callback- und Entitlement-Grundlage ist technisch belastbar.
Der reale lokale Magic-Link wurde bis zur gestarteten Windows-Anwendung und persistierten Session
verfolgt. Die per-user Windows-Protokollregistrierung ist implementiert und build-verifiziert; ihr
OS-Cold-Start konnte wegen der abgelehnten Systemfreigabe nicht ausgefuehrt werden. `PH-01-T02`
bleibt bis genau zu diesem Nachweis bedingt. Remote- und Produktionsevidenz bleiben getrennte Gates.
