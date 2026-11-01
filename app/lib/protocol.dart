import 'dart:convert';

import 'package:crypto/crypto.dart';

const protocolVersion = 1;
const defaultPort = 8765;

/// Harus sama dengan implementasi di host/lib/auth.dart.
String normalizeCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

String computeMac(String code, String nonce) => Hmac(
  sha256,
  utf8.encode(normalizeCode(code)),
).convert(utf8.encode(nonce)).toString();

enum QualityPreset {
  hemat('Hemat data', 960, 45, 15),
  seimbang('Seimbang', 1280, 60, 30),
  tajam('Tajam', 1920, 75, 30);

  const QualityPreset(this.label, this.width, this.quality, this.fps);

  final String label;
  final int width;
  final int quality;
  final int fps;
}

/// Kode virtual-key Windows untuk tombol yang tidak ada di keyboard HP.
abstract final class Vk {
  static const backspace = 0x08;
  static const tab = 0x09;
  static const enter = 0x0D;
  static const ctrl = 0x11;
  static const alt = 0x12;
  static const esc = 0x1B;
  static const left = 0x25;
  static const up = 0x26;
  static const right = 0x27;
  static const down = 0x28;
  static const delete = 0x2E;
  static const win = 0x5B;
  static const f5 = 0x74;
  static const keyC = 0x43;
  static const keyD = 0x44;
  static const keyV = 0x56;
  static const keyZ = 0x5A;
}
