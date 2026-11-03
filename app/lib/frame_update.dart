import 'dart:typed_data';
import 'dart:ui';

/// Parser pesan pembaruan layar. Harus sama dengan host/lib/frame_message.dart:
///
///   u8  jenis (2)
///   u16 lebar frame, u16 tinggi frame
///   u16 kursor X, u16 kursor Y (0-65535)
///   u8  jumlah patch
///   per patch: u16 x, u16 y, u16 lebar, u16 tinggi, u32 panjang, data JPEG
const updateMessageType = 2;
const _headerSize = 10;
const _patchHeaderSize = 12;

class FramePatch {
  const FramePatch(this.x, this.y, this.width, this.height, this.jpeg);

  final int x;
  final int y;
  final int width;
  final int height;
  final Uint8List jpeg;
}

class FrameUpdate {
  const FrameUpdate(this.width, this.height, this.cursor, this.patches);

  final int width;
  final int height;

  /// Posisi kursor ternormalisasi 0..1.
  final Offset cursor;
  final List<FramePatch> patches;

  /// Satu patch yang menutupi seluruh layar: tidak perlu gambar sebelumnya.
  bool get isFullFrame =>
      patches.length == 1 &&
      patches.first.x == 0 &&
      patches.first.y == 0 &&
      patches.first.width == width &&
      patches.first.height == height;
}

FrameUpdate parseUpdate(Uint8List data) {
  if (data.length < _headerSize) {
    throw const FormatException('Pesan pembaruan terlalu pendek');
  }
  final view = ByteData.sublistView(data);
  if (view.getUint8(0) != updateMessageType) {
    throw const FormatException('Jenis pesan tidak dikenal');
  }
  final width = view.getUint16(1);
  final height = view.getUint16(3);
  final count = view.getUint8(9);
  final patches = <FramePatch>[];
  var offset = _headerSize;
  for (var i = 0; i < count; i++) {
    if (offset + _patchHeaderSize > data.length) {
      throw const FormatException('Header patch terpotong');
    }
    final x = view.getUint16(offset);
    final y = view.getUint16(offset + 2);
    final w = view.getUint16(offset + 4);
    final h = view.getUint16(offset + 6);
    final length = view.getUint32(offset + 8);
    offset += _patchHeaderSize;
    if (offset + length > data.length || x + w > width || y + h > height) {
      throw const FormatException('Patch di luar batas');
    }
    patches.add(
      FramePatch(
        x,
        y,
        w,
        h,
        Uint8List.sublistView(data, offset, offset + length),
      ),
    );
    offset += length;
  }
  return FrameUpdate(
    width,
    height,
    Offset(view.getUint16(5) / 65535, view.getUint16(7) / 65535),
    patches,
  );
}
