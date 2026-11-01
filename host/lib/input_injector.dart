import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'win32.dart';

const _inputSize = 40; // sizeof(INPUT) pada Windows x64
const _unionOffset = 8;

const vkReturn = 0x0D;

// Tombol navigasi yang harus dikirim sebagai "extended key".
const _extendedKeys = <int>{
  0x21, 0x22, 0x23, 0x24, // PgUp, PgDn, End, Home
  0x25, 0x26, 0x27, 0x28, // panah
  0x2D, 0x2E, // Insert, Delete
  0x5B, 0x5C, // Win
};

class InputInjector {
  final Pointer<Uint8> _buffer = calloc<Uint8>(_inputSize);
  late final ByteData _view = _buffer
      .asTypedList(_inputSize)
      .buffer
      .asByteData(_buffer.asTypedList(_inputSize).offsetInBytes);

  final Set<int> _heldKeys = {};
  final Set<String> _heldButtons = {};

  void _mouse(int flags, {int dx = 0, int dy = 0, int data = 0}) {
    _buffer.asTypedList(_inputSize).fillRange(0, _inputSize, 0);
    _view
      ..setUint32(0, inputMouse, Endian.little)
      ..setInt32(_unionOffset, dx, Endian.little)
      ..setInt32(_unionOffset + 4, dy, Endian.little)
      ..setInt32(_unionOffset + 8, data, Endian.little)
      ..setUint32(_unionOffset + 12, flags, Endian.little);
    sendInput(1, _buffer, _inputSize);
  }

  void _keyboard(int vk, int scan, int flags) {
    _buffer.asTypedList(_inputSize).fillRange(0, _inputSize, 0);
    _view
      ..setUint32(0, inputKeyboard, Endian.little)
      ..setUint16(_unionOffset, vk, Endian.little)
      ..setUint16(_unionOffset + 2, scan, Endian.little)
      ..setUint32(_unionOffset + 4, flags, Endian.little);
    sendInput(1, _buffer, _inputSize);
  }

  /// x dan y ternormalisasi 0..1 pada layar utama.
  void moveTo(double x, double y) {
    _mouse(
      mouseMove | mouseAbsolute,
      dx: (x.clamp(0.0, 1.0) * 65535).round(),
      dy: (y.clamp(0.0, 1.0) * 65535).round(),
    );
  }

  void moveBy(int dx, int dy) => _mouse(mouseMove, dx: dx, dy: dy);

  void button(String name, bool down) {
    final flags = switch ((name, down)) {
      ('left', true) => mouseLeftDown,
      ('left', false) => mouseLeftUp,
      ('right', true) => mouseRightDown,
      ('right', false) => mouseRightUp,
      ('middle', true) => mouseMiddleDown,
      ('middle', false) => mouseMiddleUp,
      _ => 0,
    };
    if (flags == 0) return;
    down ? _heldButtons.add(name) : _heldButtons.remove(name);
    _mouse(flags);
  }

  void wheel(int dy, int dx) {
    if (dy != 0) _mouse(mouseWheel, data: dy);
    if (dx != 0) _mouse(mouseHWheel, data: dx);
  }

  void key(int vk, bool down) {
    if (vk <= 0 || vk > 254) return;
    down ? _heldKeys.add(vk) : _heldKeys.remove(vk);
    var flags = down ? 0 : keyUp;
    if (_extendedKeys.contains(vk)) flags |= keyExtended;
    _keyboard(vk, mapVirtualKey(vk, 0), flags);
  }

  void combo(List<int> keys) {
    for (final vk in keys) {
      key(vk, true);
    }
    for (final vk in keys.reversed) {
      key(vk, false);
    }
  }

  /// Mengetik teks apa adanya, tidak terpengaruh layout keyboard laptop.
  void text(String value) {
    for (final unit in value.codeUnits) {
      if (unit == 0x0A) {
        combo([vkReturn]);
        continue;
      }
      _keyboard(0, unit, keyUnicode);
      _keyboard(0, unit, keyUnicode | keyUp);
    }
  }

  /// Dipanggil saat koneksi putus agar tidak ada tombol yang tertahan.
  void releaseAll() {
    for (final vk in _heldKeys.toList()) {
      key(vk, false);
    }
    for (final name in _heldButtons.toList()) {
      button(name, false);
    }
  }
}
