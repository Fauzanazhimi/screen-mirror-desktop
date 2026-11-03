import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_remote/frame_update.dart';

/// Pesan contoh yang disusun byte demi byte sesuai format di host.
Uint8List message({
  int width = 1280,
  int height = 720,
  List<(int, int, int, int, List<int>)> patches = const [],
}) {
  final bytes = BytesBuilder();
  final header = ByteData(10)
    ..setUint8(0, updateMessageType)
    ..setUint16(1, width)
    ..setUint16(3, height)
    ..setUint16(5, 32768)
    ..setUint16(7, 65535)
    ..setUint8(9, patches.length);
  bytes.add(header.buffer.asUint8List());
  for (final (x, y, w, h, jpeg) in patches) {
    final patchHeader = ByteData(12)
      ..setUint16(0, x)
      ..setUint16(2, y)
      ..setUint16(4, w)
      ..setUint16(6, h)
      ..setUint32(8, jpeg.length);
    bytes
      ..add(patchHeader.buffer.asUint8List())
      ..add(jpeg);
  }
  return bytes.toBytes();
}

void main() {
  test('membaca ukuran, kursor, dan setiap patch', () {
    final update = parseUpdate(
      message(
        patches: [
          (32, 64, 96, 32, [1, 2, 3]),
          (0, 0, 32, 32, [9]),
        ],
      ),
    );
    expect(update.width, 1280);
    expect(update.height, 720);
    expect(update.cursor.dx, closeTo(0.5, 0.001));
    expect(update.cursor.dy, 1);
    expect(update.patches, hasLength(2));
    final first = update.patches.first;
    expect([first.x, first.y, first.width, first.height], [32, 64, 96, 32]);
    expect(first.jpeg, [1, 2, 3]);
    expect(update.patches.last.jpeg, [9]);
    expect(update.isFullFrame, isFalse);
  });

  test('satu patch selebar layar dikenali sebagai frame penuh', () {
    final update = parseUpdate(
      message(
        patches: [
          (0, 0, 1280, 720, [1]),
        ],
      ),
    );
    expect(update.isFullFrame, isTrue);
  });

  test('pembaruan tanpa patch tetap sah', () {
    expect(parseUpdate(message()).patches, isEmpty);
  });

  test('pesan rusak ditolak', () {
    expect(() => parseUpdate(Uint8List(3)), throwsFormatException);

    final wrongType = message()..[0] = 1;
    expect(() => parseUpdate(wrongType), throwsFormatException);

    final truncated = message(
      patches: [
        (0, 0, 32, 32, [1, 2, 3]),
      ],
    );
    expect(
      () => parseUpdate(
        Uint8List.sublistView(truncated, 0, truncated.length - 1),
      ),
      throwsFormatException,
    );

    expect(
      () => parseUpdate(
        message(
          patches: [
            (1270, 0, 32, 32, [1]),
          ],
        ),
      ),
      throwsFormatException,
    );
  });
}
