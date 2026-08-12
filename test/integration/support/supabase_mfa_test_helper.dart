import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient createSupabaseTestClient(String url, String publishableKey) {
  return SupabaseClient(
    url,
    publishableKey,
    authOptions: AuthClientOptions(
      pkceAsyncStorage: _InMemoryGotrueAsyncStorage(),
    ),
  );
}

/// A verified TOTP factor plus the secret it was enrolled with, so a second
/// session of the same user can be elevated without enrolling again.
class TotpTestFactor {
  const TotpTestFactor({required this.id, required this.secret});

  final String id;
  final String secret;
}

/// Enrols a fresh TOTP factor and elevates this session to AAL2.
///
/// Only valid for a user that has no verified factor yet: GoTrue answers
/// `403 insufficient_aal` to an enrolment attempt from an aal1 session once
/// one exists. For a second session of the same user use
/// [elevateSupabaseTestClientWithFactor] with the returned factor.
Future<TotpTestFactor> enrolSupabaseTestClientToAal2(
  SupabaseClient client,
) async {
  final enrollment = await client.auth.mfa.enroll(
    factorType: FactorType.totp,
    friendlyName:
        'neximmo-integration-${DateTime.now().microsecondsSinceEpoch}',
  );
  final secret = enrollment.totp?.secret;
  if (secret == null || secret.isEmpty) {
    throw StateError('Supabase did not return a TOTP enrollment secret.');
  }

  final factor = TotpTestFactor(id: enrollment.id, secret: secret);
  await elevateSupabaseTestClientWithFactor(client, factor);
  return factor;
}

/// Elevates a session to AAL2 using an already verified factor -- the flow a
/// real user follows when signing in on a second device.
Future<void> elevateSupabaseTestClientWithFactor(
  SupabaseClient client,
  TotpTestFactor factor,
) async {
  final challenge = await client.auth.mfa.challenge(factorId: factor.id);
  await client.auth.mfa.verify(
    factorId: factor.id,
    challengeId: challenge.id,
    code: _totpCode(factor.secret, DateTime.now().toUtc()),
  );
  final assurance = client.auth.mfa.getAuthenticatorAssuranceLevel();
  if (assurance.currentLevel != AuthenticatorAssuranceLevels.aal2) {
    throw StateError('Supabase session did not reach AAL2.');
  }
}

Future<String> elevateSupabaseTestClientToAal2(SupabaseClient client) async {
  return (await enrolSupabaseTestClientToAal2(client)).id;
}

class _InMemoryGotrueAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }
}

String _totpCode(String secret, DateTime timestamp) {
  final key = _decodeBase32(secret);
  final counter = timestamp.millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final message = Uint8List(8);
  var value = counter;
  for (var index = message.length - 1; index >= 0; index--) {
    message[index] = value & 0xff;
    value >>= 8;
  }

  final digest = Hmac(sha1, key).convert(message).bytes;
  final offset = digest.last & 0x0f;
  final binary =
      ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  return (binary % 1000000).toString().padLeft(6, '0');
}

List<int> _decodeBase32(String encoded) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final output = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final codeUnit in encoded.toUpperCase().codeUnits) {
    final character = String.fromCharCode(codeUnit);
    if (character == '=' || character.trim().isEmpty) {
      continue;
    }
    final decoded = alphabet.indexOf(character);
    if (decoded < 0) {
      throw FormatException('Invalid base32 TOTP secret.');
    }
    buffer = (buffer << 5) | decoded;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
    }
  }
  return output;
}
