import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// Tanpa karakter yang mudah tertukar (0/O, 1/I/L).
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Kode pairing 12 karakter (sekitar 59 bit acak), mis. ABCD-EFGH-JKMN.
String generatePairCode() {
  final random = Random.secure();
  final chars = List.generate(
    12,
    (_) => _alphabet[random.nextInt(_alphabet.length)],
  );
  return [
    chars.sublist(0, 4).join(),
    chars.sublist(4, 8).join(),
    chars.sublist(8, 12).join(),
  ].join('-');
}

String normalizeCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

String generateNonce() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Bukti kepemilikan kode: kode itu sendiri tidak pernah dikirim lewat jaringan.
String computeMac(String code, String nonce) => Hmac(
  sha256,
  utf8.encode(normalizeCode(code)),
).convert(utf8.encode(nonce)).toString();

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Mengunci alamat yang terlalu sering salah kode.
class AuthThrottle {
  AuthThrottle({
    this.maxFailures = 5,
    this.lockout = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxFailures;
  final Duration lockout;
  final DateTime Function() _clock;
  final Map<String, (int, DateTime)> _failures = {};

  bool isLocked(String address) {
    final entry = _failures[address];
    if (entry == null) return false;
    final (count, lastFailure) = entry;
    if (_clock().difference(lastFailure) >= lockout) {
      _failures.remove(address);
      return false;
    }
    return count >= maxFailures;
  }

  void recordFailure(String address) {
    final count = _failures[address]?.$1 ?? 0;
    _failures[address] = (count + 1, _clock());
  }

  void recordSuccess(String address) => _failures.remove(address);
}
