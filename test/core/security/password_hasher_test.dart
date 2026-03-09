import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/security/password_hasher.dart';

void main() {
  test('password hash verify succeeds and fails deterministically', () {
    const hasher = PasswordHasher(iterations: 1000, keyLength: 32);
    final salt = hasher.generateSalt();
    final hash = hasher.hashPassword(password: 'secret-123', salt: salt);

    expect(
      hasher.verify(password: 'secret-123', salt: salt, expectedHash: hash),
      isTrue,
    );
    expect(
      hasher.verify(password: 'wrong', salt: salt, expectedHash: hash),
      isFalse,
    );
  });
}
