// SECURITY-STORAGE-AAL-03.
//
// Everything here goes through the real Supabase Storage HTTP API with real
// GoTrue sessions. That is the point of the file: `set_config('request.jwt.
// claims', ...)` in pgTAP proves what Postgres does with a claim, not whether
// storage-api delivers the same claim in the first place. Only a request that
// travels auth -> JWT -> storage HTTP API -> storage.objects RLS answers that,
// and until this file existed nothing did.
//
// service_role is never used. Fixtures come from
// supabase/tests_integration/storage_aal_03_setup.sql, applied by
// tool/verify_storage_aal_03.ps1 before this runs.
//
// One caveat shapes the assertions below: createSignedUrl answers 404 for an
// object that does not exist *and* for one the caller may not see. A denial on
// a not-yet-uploaded object is therefore ambiguous. The load-bearing aal1 read
// assertion is the one made against an object that demonstrably exists.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const bucket = 'documents';
  const workspaceA = '51000000-0000-0000-0000-000000000001';
  const workspaceB = '52000000-0000-0000-0000-000000000001';
  // Unique per run. `supabase db reset` rebuilds the database but does not
  // clear the storage backend, so a fixed path would collide with the object
  // left by the previous run and answer 409 instead of exercising the policy.
  // Immutability is still asserted inside a run, where the path repeats.
  final scope = 'run-${DateTime.now().microsecondsSinceEpoch}';
  final pathA = '$workspaceA/$scope/1/contract.txt';
  final pathB = '$workspaceB/$scope/1/contract.txt';

  final bytes = Uint8List.fromList(utf8.encode('SECURITY-STORAGE-AAL-03'));

  test(
    'the document storage boundary holds through the real Storage API',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final full = createSupabaseTestClient(url, publishableKey);
      final reader = createSupabaseTestClient(url, publishableKey);
      final foreign = createSupabaseTestClient(url, publishableKey);
      final anonymous = createSupabaseTestClient(url, publishableKey);
      TotpTestFactor? fullFactor;
      TotpTestFactor? readerFactor;
      TotpTestFactor? foreignFactor;

      try {
        // === A. anonymous ===============================================
        await _denied(
          () => anonymous.storage.from(bucket).createSignedUrl(pathA, 60),
          'anonymous signed-url mint',
        );
        await _denied(
          () => anonymous.storage.from(bucket).uploadBinary(pathA, bytes),
          'anonymous upload',
        );

        // === B. aal1, holding BOTH document.read and document.manage =====
        // The denial cannot be a missing membership or a missing permission:
        // the same identity succeeds at aal2 a few lines below.
        await full.auth.signInWithPassword(
          email: 'storage-full@example.test',
          password: 'NexImmo-Test-2026!',
        );
        expect(
          full.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal1,
        );
        await _denied(
          () => full.storage.from(bucket).uploadBinary(pathA, bytes),
          'aal1 upload with document.manage',
        );

        // === C. same user, elevated =====================================
        fullFactor = await enrolSupabaseTestClientToAal2(full);
        expect(
          full.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal2,
        );
        await full.storage
            .from(bucket)
            .uploadBinary(
              pathA,
              bytes,
              fileOptions: const FileOptions(contentType: 'text/plain'),
            );
        final signedByFull = await full.storage
            .from(bucket)
            .createSignedUrl(pathA, 60);
        expect(await _status(signedByFull), 200, reason: 'signed url resolves');

        // === D. the load-bearing aal1 read: the object now EXISTS ========
        // A separate identity with document.read, still at aal1. A denial here
        // cannot be "not found" in the ordinary sense -- the object is there and
        // the same identity reads it successfully after elevation.
        await reader.auth.signInWithPassword(
          email: 'storage-read@example.test',
          password: 'NexImmo-Test-2026!',
        );
        expect(
          reader.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal1,
        );
        await _denied(
          () => reader.storage.from(bucket).createSignedUrl(pathA, 60),
          'aal1 signed-url mint for an existing object',
        );

        readerFactor = await enrolSupabaseTestClientToAal2(reader);
        final signedByReader = await reader.storage
            .from(bucket)
            .createSignedUrl(pathA, 60);
        expect(await _status(signedByReader), 200);

        // === E. permission separation, both arms at aal2 =================
        // document.read does not imply document.manage, and the existing model
        // is respected rather than widened.
        await _denied(
          () => reader.storage
              .from(bucket)
              .uploadBinary('$workspaceA/$scope/2/contract.txt', bytes),
          'aal2 upload without document.manage',
        );

        // === F. tenant isolation ========================================
        await foreign.auth.signInWithPassword(
          email: 'storage-foreign@example.test',
          password: 'NexImmo-Test-2026!',
        );
        foreignFactor = await enrolSupabaseTestClientToAal2(foreign);
        await _denied(
          () => foreign.storage.from(bucket).createSignedUrl(pathA, 60),
          'foreign workspace signed-url mint',
        );
        await _denied(
          () => foreign.storage.from(bucket).uploadBinary(pathA, bytes),
          'foreign workspace upload',
        );
        // Control: the same identity works inside its own workspace, so the
        // denials above are scoping and not a broken session.
        await foreign.storage
            .from(bucket)
            .uploadBinary(
              pathB,
              bytes,
              fileOptions: const FileOptions(contentType: 'text/plain'),
            );

        // === G. path hardening, at aal2 WITH document.manage =============
        // Every denial here is the workspace-prefix parser failing closed.
        for (final badPath in <String>[
          'not-a-uuid/$scope/1/file.txt',
          '$workspaceB/$scope/1/file.txt',
          'file.txt',
          '$workspaceA/file.txt',
          '../$workspaceA/$scope/1/file.txt',
          '$workspaceA/../$scope/1/file.txt',
          '$workspaceA-suffix/$scope/1/file.txt',
        ]) {
          await _denied(
            () => full.storage.from(bucket).uploadBinary(badPath, bytes),
            'upload to malformed path "$badPath"',
          );
        }

        // === H. immutability (DOM-006) ==================================
        await _denied(
          () => full.storage.from(bucket).uploadBinary(pathA, bytes),
          'second upload to an existing path',
        );
        await _denied(
          () => full.storage
              .from(bucket)
              .uploadBinary(
                pathA,
                bytes,
                fileOptions: const FileOptions(upsert: true),
              ),
          'upsert over an existing object',
        );

        // remove() may report per-item results rather than throwing, so the
        // assertion is that the object survives, not that a call threw.
        try {
          await full.storage.from(bucket).remove(<String>[pathA]);
        } catch (_) {
          // Either shape is acceptable; survival is what matters.
        }
        final afterRemove = await full.storage
            .from(bucket)
            .createSignedUrl(pathA, 60);
        expect(
          await _status(afterRemove),
          200,
          reason: 'an authenticated client must not be able to delete an object',
        );
      } finally {
        for (final entry in <List<Object?>>[
          <Object?>[full, fullFactor],
          <Object?>[reader, readerFactor],
          <Object?>[foreign, foreignFactor],
        ]) {
          final client = entry[0]! as SupabaseClient;
          final factor = entry[1] as TotpTestFactor?;
          if (factor != null) {
            await client.auth.mfa.unenroll(factor.id);
          }
          await client.auth.signOut();
        }
      }
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Asserts the storage call is refused. Any success -- including a silently
/// empty result -- fails, so a policy that stops denying cannot pass unnoticed.
Future<void> _denied(Future<Object?> Function() call, String what) async {
  Object? result;
  try {
    result = await call();
  } on StorageException catch (error) {
    // 403 is an RLS refusal, 404 a not-visible object, 400 a rejected request,
    // and 409 the immutability refusal: the object exists and the bucket has no
    // update policy, so storage declines rather than overwriting. All four are
    // refusals; what matters is that none of them is a success.
    expect(
      error.statusCode,
      anyOf('400', '403', '404', '409'),
      reason: '$what should be refused by storage, got ${error.statusCode}',
    );
    return;
  }
  fail('$what was allowed (returned $result) but must be refused.');
}

Future<int> _status(String signedUrl) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(signedUrl));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}
