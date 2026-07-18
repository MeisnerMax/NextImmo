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

Future<void> elevateSupabaseTestClientToAal2(SupabaseClient client) async {
  final enrollment = await client.auth.mfa.enroll(
    factorType: FactorType.totp,
    friendlyName:
        'neximmo-integration-${DateTime.now().microsecondsSinceEpoch}',
  );
  final secret = enrollment.totp?.secret;
  if (secret == null || secret.isEmpty) {
    throw StateError('Supabase did not return a TOTP enrollment secret.');
  }

  final challenge = await client.auth.mfa.challenge(factorId: enrollment.id);
  await client.auth.mfa.verify(
    factorId: enrollment.id,
    challengeId: challenge.id,
    code: _totpCode(secret, DateTime.now().toUtc()),
  );
  final assurance = client.auth.mfa.getAuthenticatorAssuranceLevel();
  if (assurance.currentLevel != AuthenticatorAssuranceLevels.aal2) {
    throw StateError('Supabase session did not reach AAL2.');
  }
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
