import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceA = '17000000-0000-0000-0000-000000000001';
  const propertyA = '17000000-0000-0000-0000-000000000005';
  const workspaceB = '27000000-0000-0000-0000-000000000001';
  const propertyB = '27000000-0000-0000-0000-000000000005';

  test(
    'raw PostgREST matches anonymous, viewer and tenant authorization',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        publishableKey,
        isNotEmpty,
        reason: 'SUPABASE_PUBLISHABLE_KEY dart define is required.',
      );
      final baseUri = Uri.parse(url);
      expect(
        baseUri.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final managerA = createSupabaseTestClient(url, publishableKey);
      final viewerA = createSupabaseTestClient(url, publishableKey);
      final managerB = createSupabaseTestClient(url, publishableKey);
      final http = HttpClient();
      String? managerAFactorId;
      String? viewerAFactorId;
      String? managerBFactorId;
      try {
        final anonymousList = await _request(
          http,
          method: 'GET',
          uri: _propertyListUri(baseUri, workspaceA),
          publishableKey: publishableKey,
        );
        expect(anonymousList.statusCode, anyOf(401, 403));
        expect(anonymousList.body, isNot(contains(propertyA)));
        expect(anonymousList.body, isNot(contains(propertyB)));

        await Future.wait([
          managerA.auth.signInWithPassword(
            email: 'p1-007@example.test',
            password: 'NexImmo-Test-2026!',
          ),
          viewerA.auth.signInWithPassword(
            email: 'p1-018-viewer@example.test',
            password: 'NexImmo-Test-2026!',
          ),
          managerB.auth.signInWithPassword(
            email: 'p1-011-b@example.test',
            password: 'NexImmo-Test-2026!',
          ),
        ]);
        managerAFactorId = await elevateSupabaseTestClientToAal2(managerA);
        viewerAFactorId = await elevateSupabaseTestClientToAal2(viewerA);
        managerBFactorId = await elevateSupabaseTestClientToAal2(managerB);

        await _expectPropertyIds(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: managerA.auth.currentSession!.accessToken,
          workspaceId: workspaceA,
          expectedIds: const [propertyA],
        );
        await _expectPropertyIds(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: managerA.auth.currentSession!.accessToken,
          workspaceId: workspaceB,
          expectedIds: const [],
        );
        await _expectPropertyIds(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: viewerA.auth.currentSession!.accessToken,
          workspaceId: workspaceA,
          expectedIds: const [propertyA],
        );
        await _expectPropertyIds(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: managerB.auth.currentSession!.accessToken,
          workspaceId: workspaceA,
          expectedIds: const [],
        );
        await _expectPropertyIds(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: managerB.auth.currentSession!.accessToken,
          workspaceId: workspaceB,
          expectedIds: const [propertyB],
        );

        final directPatch = await _request(
          http,
          method: 'PATCH',
          uri: _propertyListUri(baseUri, workspaceA),
          publishableKey: publishableKey,
          accessToken: managerA.auth.currentSession!.accessToken,
          body: const {'name': 'Direct table bypass'},
        );
        expect(directPatch.statusCode, anyOf(401, 403));

        final viewerMutation = await _updateProperty(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: viewerA.auth.currentSession!.accessToken,
          workspaceId: workspaceA,
          propertyId: propertyA,
          mutationId: '18000000-0000-0000-0000-000000000006',
          correlationId: '18000000-0000-0000-0000-000000000007',
          name: 'Viewer must not update',
        );
        _expectRpcError(viewerMutation, 'forbidden');

        final crossTenantMutation = await _updateProperty(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: managerB.auth.currentSession!.accessToken,
          workspaceId: workspaceA,
          propertyId: propertyA,
          mutationId: '28000000-0000-0000-0000-000000000006',
          correlationId: '28000000-0000-0000-0000-000000000007',
          name: 'Foreign manager must not update',
        );
        _expectRpcError(crossTenantMutation, 'forbidden');

        final managerMutation = await _updateProperty(
          http,
          baseUri: baseUri,
          publishableKey: publishableKey,
          accessToken: managerA.auth.currentSession!.accessToken,
          workspaceId: workspaceA,
          propertyId: propertyA,
          mutationId: '18000000-0000-0000-0000-000000000008',
          correlationId: '18000000-0000-0000-0000-000000000009',
          name: 'Raw PostgREST After',
        );
        expect(managerMutation.statusCode, 200);
        final managerResult = managerMutation.json as Map<String, dynamic>;
        expect(managerResult['ok'], isTrue);
        final property = managerResult['property'] as Map<String, dynamic>;
        expect(property['id'], propertyA);
        expect(property['workspace_id'], workspaceA);
        expect(property['name'], 'Raw PostgREST After');
        expect(property['version'], 2);
      } finally {
        if (managerAFactorId != null) {
          await managerA.auth.mfa.unenroll(managerAFactorId);
        }
        if (viewerAFactorId != null) {
          await viewerA.auth.mfa.unenroll(viewerAFactorId);
        }
        if (managerBFactorId != null) {
          await managerB.auth.mfa.unenroll(managerBFactorId);
        }
        await Future.wait([
          managerA.auth.signOut(),
          viewerA.auth.signOut(),
          managerB.auth.signOut(),
        ]);
        http.close(force: true);
      }
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Future<void> _expectPropertyIds(
  HttpClient http, {
  required Uri baseUri,
  required String publishableKey,
  required String accessToken,
  required String workspaceId,
  required List<String> expectedIds,
}) async {
  final response = await _request(
    http,
    method: 'GET',
    uri: _propertyListUri(baseUri, workspaceId),
    publishableKey: publishableKey,
    accessToken: accessToken,
  );
  expect(response.statusCode, 200);
  final records = response.json as List<dynamic>;
  expect(
    records.map((record) => (record as Map<String, dynamic>)['id']).toList(),
    expectedIds,
  );
}

Uri _propertyListUri(Uri baseUri, String workspaceId) {
  return baseUri
      .resolve('/rest/v1/properties')
      .replace(
        queryParameters: {
          'select': 'id',
          'workspace_id': 'eq.$workspaceId',
          'order': 'id.asc',
        },
      );
}

Future<_RawResponse> _updateProperty(
  HttpClient http, {
  required Uri baseUri,
  required String publishableKey,
  required String accessToken,
  required String workspaceId,
  required String propertyId,
  required String mutationId,
  required String correlationId,
  required String name,
}) {
  return _request(
    http,
    method: 'POST',
    uri: baseUri.resolve('/rest/v1/rpc/update_property'),
    publishableKey: publishableKey,
    accessToken: accessToken,
    body: {
      'p_workspace_id': workspaceId,
      'p_property_id': propertyId,
      'p_expected_version': 1,
      'p_mutation_id': mutationId,
      'p_correlation_id': correlationId,
      'p_changes': {'name': name},
      'p_reason': 'P1-018 raw PostgREST parity',
    },
  );
}

void _expectRpcError(_RawResponse response, String code) {
  expect(response.statusCode, 200);
  final result = response.json as Map<String, dynamic>;
  expect(result['ok'], isFalse);
  expect((result['error'] as Map<String, dynamic>)['code'], code);
}

Future<_RawResponse> _request(
  HttpClient http, {
  required String method,
  required Uri uri,
  required String publishableKey,
  String? accessToken,
  Map<String, dynamic>? body,
}) async {
  final request = await http.openUrl(method, uri);
  request.headers.set('apikey', publishableKey);
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  if (accessToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  return _RawResponse(
    statusCode: response.statusCode,
    body: await utf8.decoder.bind(response).join(),
  );
}

final class _RawResponse {
  const _RawResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  Object? get json => jsonDecode(body);
}
