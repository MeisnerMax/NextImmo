import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class PasswordHasher {
  const PasswordHasher({this.iterations = 120000, this.keyLength = 32});

  final int iterations;
  final int keyLength;

  String generateSalt({int bytes = 16}) {
    final random = Random.secure();
    final data = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      data[i] = random.nextInt(256);
    }
    return base64Encode(data);
  }

  String hashPassword({required String password, required String salt}) {
    final pwd = utf8.encode(password);
    final saltBytes = base64Decode(salt);
    final derived = _pbkdf2HmacSha256(
      password: pwd,
      salt: saltBytes,
      iterations: iterations,
      keyLength: keyLength,
    );
    return base64Encode(derived);
  }

  bool verify({
    required String password,
    required String salt,
    required String expectedHash,
  }) {
    final computed = hashPassword(password: password, salt: salt);
    return _constantTimeEquals(computed, expectedHash);
  }

  Uint8List _pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    const hashLength = 32;
    final blockCount = (keyLength / hashLength).ceil();
    final output = BytesBuilder(copy: false);

    for (var block = 1; block <= blockCount; block++) {
      final blockIndex =
          Uint8List(4)
            ..[0] = (block >> 24) & 0xff
            ..[1] = (block >> 16) & 0xff
            ..[2] = (block >> 8) & 0xff
            ..[3] = block & 0xff;

      var u = hmac.convert(<int>[...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }

    final bytes = output.toBytes();
    return Uint8List.fromList(bytes.sublist(0, keyLength));
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
