import 'dart:typed_data';

import 'dirty_rects.dart';

/// Format pesan biner pembaruan layar (big-endian):
///
///   u8  jenis (2)
///   u16 lebar frame, u16 tinggi frame
///   u16 kursor X, u16 kursor Y (0-65535)
///   u8  jumlah patch
///   per patch: u16 x, u16 y, u16 lebar, u16 tinggi, u32 panjang, data JPEG
///
/// Harus sama dengan parser di app/lib/frame_update.dart.
const updateMessageType = 2;
const _headerSize = 10;
const _patchHeaderSize = 12;

class EncodedPatch {
  const EncodedPatch(this.rect, this.jpeg);

  final PixelRect rect;
  final Uint8List jpeg;
}

Uint8List buildUpdate({
  required int width,
  required int height,
  required int cursorX,
  required int cursorY,
  required List<EncodedPatch> patches,
}) {
  var size = _headerSize;
  for (final patch in patches) {
    size += _patchHeaderSize + patch.jpeg.length;
  }
  final message = Uint8List(size);
  final view = ByteData.sublistView(message)
    ..setUint8(0, updateMessageType)
    ..setUint16(1, width)
    ..setUint16(3, height)
    ..setUint16(5, cursorX)
    ..setUint16(7, cursorY)
    ..setUint8(9, patches.length);
  var offset = _headerSize;
  for (final patch in patches) {
    view
      ..setUint16(offset, patch.rect.x)
      ..setUint16(offset + 2, patch.rect.y)
      ..setUint16(offset + 4, patch.rect.width)
      ..setUint16(offset + 6, patch.rect.height)
      ..setUint32(offset + 8, patch.jpeg.length);
    offset += _patchHeaderSize;
    message.setRange(offset, offset + patch.jpeg.length, patch.jpeg);
    offset += patch.jpeg.length;
  }
  return message;
}
