// SECURITY-STORAGE-AAL-03, `property-media` arm.
//
// PROPERTY-MEDIA-DATA-01 added a second private bucket with policies that are
// stricter than the documents bucket's, and pgTAP proved the policies exist and
// what Postgres does with a claim. It did not prove that storage-api delivers
// the same claim: only a request that travels auth -> JWT -> storage HTTP API
// -> storage.objects RLS answers that. This file is that proof for the media
// bucket, and it exists because shipping a bucket with an untested boundary is
// how a private bucket quietly stops being private.
//
// Two things here are not covered by the documents arm at all:
//
//   1. **Entity scope.** The media policies gate on
//      `has_scoped_entity_permission`, not on a workspace permission alone. The
//      `media-scoped` identity holds every permission the INSERT policy asks
//      for and is restricted to one property, so its denial on the *other*
//      property of the same workspace cannot be explained by a missing
//      permission, a missing membership, or the assurance level.
//   2. **No update and no delete policy at all.** The documents bucket relies
//      on the absence of an update policy for immutability; this bucket has
//      neither, so a client cannot overwrite *or* remove, and both are asserted
//      rather than assumed from the migration.
//
// service_role is never used. Fixtures come from
// supabase/tests_integration/storage_aal_03_setup.sql, applied by
// tool/verify_storage_aal_03.ps1 before this runs.
//
// The same caveat as the documents arm shapes the assertions: createSignedUrl
// answers 404 both for an object that does not exist and for one the caller may
// not see, so the load-bearing read denials are made against objects that
// demonstrably exist.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const bucket = 'property-media';
  const workspaceA = '51000000-0000-0000-0000-000000000001';
  const workspaceB = '52000000-0000-0000-0000-000000000001';
  const propertyOne = '54000000-0000-0000-0000-000000000001';
  const propertyTwo = '54000000-0000-0000-0000-000000000002';

  // Unique per run: `supabase db reset` rebuilds the database but does not
  // clear the storage backend, so a fixed path would collide with the object
  // the previous run left behind and answer 409 instead of exercising the
  // policy. Immutability is still asserted inside a run, where a path repeats.
  final scope = 'run-${DateTime.now().microsecondsSinceEpoch}';
  final onePath = '$workspaceA/$propertyOne/$scope/cover.png';
  final twoPath = '$workspaceA/$propertyTwo/$scope/cover.png';

  final bytes = Uint8List.fromList(utf8.encode('PROPERTY-MEDIA-DATA-01'));

  test(
    'the property media boundary holds through the real Storage API',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final manager = createSupabaseTestClient(url, publishableKey);
      final scoped = createSupabaseTestClient(url, publishableKey);
      final reader = createSupabaseTestClient(url, publishableKey);
      final foreign = createSupabaseTestClient(url, publishableKey);
      final anonymous = createSupabaseTestClient(url, publishableKey);
      TotpTestFactor? managerFactor;
      TotpTestFactor? scopedFactor;
      TotpTestFactor? readerFactor;
      TotpTestFactor? foreignFactor;

      try {
        // === A. anonymous ================================================
        await _denied(
          () => anonymous.storage.from(bucket).createSignedUrl(onePath, 60),
          'anonymous signed-url mint',
        );
        await _denied(
          () => anonymous.storage.from(bucket).uploadBinary(onePath, bytes),
          'anonymous upload',
        );

        // === B. aal1, holding both property permissions ==================
        // The denial cannot be a missing membership or a missing permission:
        // the same identity succeeds at aal2 a few lines below.
        await manager.auth.signInWithPassword(
          email: 'media-manager@example.test',
          password: 'NexImmo-Test-2026!',
        );
        expect(
          manager.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal1,
        );
        await _denied(
          () => manager.storage.from(bucket).uploadBinary(onePath, bytes),
          'aal1 upload with property.update',
        );

        // === C. same identity, elevated ==================================
        managerFactor = await enrolSupabaseTestClientToAal2(manager);
        expect(
          manager.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal2,
        );
        await manager.storage
            .from(bucket)
            .uploadBinary(
              onePath,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );
        await manager.storage
            .from(bucket)
            .uploadBinary(
              twoPath,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );
        final signedByManager = await manager.storage
            .from(bucket)
            .createSignedUrl(onePath, 60);
        expect(await _status(signedByManager), 200, reason: 'signed url resolves');

        // === D. the load-bearing aal1 read: the object now EXISTS ========
        await reader.auth.signInWithPassword(
          email: 'media-reader@example.test',
          password: 'NexImmo-Test-2026!',
        );
        expect(
          reader.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal1,
        );
        await _denied(
          () => reader.storage.from(bucket).createSignedUrl(onePath, 60),
          'aal1 signed-url mint for an existing object',
        );

        readerFactor = await enrolSupabaseTestClientToAal2(reader);
        final signedByReader = await reader.storage
            .from(bucket)
            .createSignedUrl(onePath, 60);
        expect(
          await _status(signedByReader),
          200,
          reason: 'property.read is enough to see a picture',
        );

        // === E. read does not imply write ================================
        await _denied(
          () => reader.storage
              .from(bucket)
              .uploadBinary('$workspaceA/$propertyOne/$scope-2/cover.png', bytes),
          'aal2 upload with property.read but without property.update',
        );

        // === F. entity scope, the assertion this file exists for ==========
        // `media-scoped` holds property.read AND property.update, is a member
        // of workspace A, and is at aal2. The only thing separating it from
        // the manager is a scope row naming property one. Every denial below
        // is therefore the entity scope and nothing else — and the successes
        // on property one are the control that proves it.
        await scoped.auth.signInWithPassword(
          email: 'media-scoped@example.test',
          password: 'NexImmo-Test-2026!',
        );
        scopedFactor = await enrolSupabaseTestClientToAal2(scoped);

        final signedByScoped = await scoped.storage
            .from(bucket)
            .createSignedUrl(onePath, 60);
        expect(
          await _status(signedByScoped),
          200,
          reason: 'the scoped identity reads the property it is scoped to',
        );
        await scoped.storage
            .from(bucket)
            .uploadBinary(
              '$workspaceA/$propertyOne/$scope-scoped/cover.png',
              bytes,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );

        await _denied(
          () => scoped.storage.from(bucket).createSignedUrl(twoPath, 60),
          'scoped read of another property in the same workspace',
        );
        await _denied(
          () => scoped.storage
              .from(bucket)
              .uploadBinary(
                '$workspaceA/$propertyTwo/$scope-scoped/cover.png',
                bytes,
              ),
          'scoped upload to another property in the same workspace',
        );

        // === G. tenant isolation =========================================
        await foreign.auth.signInWithPassword(
          email: 'storage-foreign@example.test',
          password: 'NexImmo-Test-2026!',
        );
        foreignFactor = await enrolSupabaseTestClientToAal2(foreign);
        await _denied(
          () => foreign.storage.from(bucket).createSignedUrl(onePath, 60),
          'foreign workspace signed-url mint',
        );
        await _denied(
          () => foreign.storage
              .from(bucket)
              .uploadBinary('$workspaceB/$propertyOne/$scope/cover.png', bytes),
          'foreign workspace upload naming a property it does not own',
        );

        // === H. path hardening, at aal2 WITH property.update =============
        // Every denial here is a path the policy's parser must fail closed on.
        for (final badPath in <String>[
          'not-a-uuid/$propertyOne/$scope/cover.png',
          '$workspaceA/not-a-uuid/$scope/cover.png',
          '$workspaceB/$propertyOne/$scope/cover.png',
          'cover.png',
          '$workspaceA/cover.png',
          '$workspaceA/$propertyOne/cover.png',
          '../$workspaceA/$propertyOne/$scope/cover.png',
          '$workspaceA/../$propertyOne/$scope/cover.png',
          '$workspaceA-suffix/$propertyOne/$scope/cover.png',
        ]) {
          await _denied(
            () => manager.storage.from(bucket).uploadBinary(badPath, bytes),
            'upload to malformed path "$badPath"',
          );
        }

        // === I. no update policy: an object cannot be overwritten =========
        await _denied(
          () => manager.storage.from(bucket).uploadBinary(onePath, bytes),
          'second upload to an existing path',
        );
        await _denied(
          () => manager.storage
              .from(bucket)
              .uploadBinary(
                onePath,
                bytes,
                fileOptions: const FileOptions(upsert: true),
              ),
          'upsert over an existing object',
        );

        // === J. no delete policy: an object cannot be removed =============
        // remove() may report per-item results rather than throwing, so the
        // assertion is that the object survives, not that a call threw.
        try {
          await manager.storage.from(bucket).remove(<String>[onePath]);
        } catch (_) {
          // Either shape is acceptable; survival is what matters.
        }
        final afterRemove = await manager.storage
            .from(bucket)
            .createSignedUrl(onePath, 60);
        expect(
          await _status(afterRemove),
          200,
          reason:
              'the bucket has no delete policy, so no authenticated client can '
              'remove a picture — archiving is a database marker, not an '
              'object deletion',
        );
      } finally {
        for (final entry in <List<Object?>>[
          <Object?>[manager, managerFactor],
          <Object?>[scoped, scopedFactor],
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

/// Asserts the storage call is refused. Any success — including a silently
/// empty result — fails, so a policy that stops denying cannot pass unnoticed.
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
