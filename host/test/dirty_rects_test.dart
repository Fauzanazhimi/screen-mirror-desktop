import 'dart:typed_data';

import 'package:mirror_host/adaptive_quality.dart';
import 'package:mirror_host/dirty_rects.dart';
import 'package:mirror_host/frame_message.dart';
import 'package:test/test.dart';

void main() {
  const width = 320;
  const height = 200; // tidak habis dibagi 32: baris petak terakhir terpotong

  late Uint32List previous;
  late Uint32List current;

  setUp(() {
    previous = Uint32List(width * height);
    current = Uint32List(width * height);
  });

  void paint(int x, int y) => current[y * width + x] = 0xFFFFFF;

  group('changedRects', () {
    test('frame sama tidak menghasilkan area', () {
      expect(changedRects(current, previous, width, height), isEmpty);
    });

    test('satu piksel berubah menjadi satu petak', () {
      paint(40, 70);
      expect(changedRects(current, previous, width, height), [
        const PixelRect(32, 64, 32, 32),
      ]);
    });

    test('petak bersebelahan digabung mendatar dan menurun', () {
      for (final (x, y) in [(5, 5), (40, 5), (5, 40), (40, 40)]) {
        paint(x, y);
      }
      expect(changedRects(current, previous, width, height), [
        const PixelRect(0, 0, 64, 64),
      ]);
    });

    test('area terpisah tetap terpisah, tepi bawah terpotong', () {
      paint(5, 5);
      paint(300, 199);
      expect(changedRects(current, previous, width, height), [
        const PixelRect(0, 0, 32, 32),
        const PixelRect(288, 192, 32, 8),
      ]);
    });

    test('lebih dari separuh berubah menjadi satu frame penuh', () {
      for (var i = 0; i < current.length ~/ 2 + width * 40; i++) {
        current[i] = 1;
      }
      expect(changedRects(current, previous, width, height), [
        const PixelRect(0, 0, width, height),
      ]);
    });

    test('terlalu banyak area kecil digabung menjadi satu kotak', () {
      // Pola papan catur 5 baris: 25 petak yang tidak bersentuhan.
      for (var row = 0; row < 5; row++) {
        for (var col = row % 2; col < 10; col += 2) {
          paint(col * 32, row * 32);
        }
      }
      final rects = changedRects(current, previous, width, height);
      expect(rects, [const PixelRect(0, 0, width, 160)]);
    });
  });

  test('buildUpdate menulis header dan patch sesuai format', () {
    final message = buildUpdate(
      width: 1280,
      height: 720,
      cursorX: 100,
      cursorY: 200,
      patches: [
        EncodedPatch(
          const PixelRect(32, 64, 96, 32),
          Uint8List.fromList([1, 2, 3]),
        ),
      ],
    );
    final view = ByteData.sublistView(message);
    expect(view.getUint8(0), updateMessageType);
    expect(view.getUint16(1), 1280);
    expect(view.getUint16(3), 720);
    expect(view.getUint16(5), 100);
    expect(view.getUint16(7), 200);
    expect(view.getUint8(9), 1);
    expect(
      [
        view.getUint16(10),
        view.getUint16(12),
        view.getUint16(14),
        view.getUint16(16),
      ],
      [32, 64, 96, 32],
    );
    expect(view.getUint32(18), 3);
    expect(message.sublist(22), [1, 2, 3]);
  });

  group('AdaptiveQuality', () {
    const fast = Duration(milliseconds: 50);
    const slow = Duration(milliseconds: 1500);

    test('turun saat frame mengantre, naik lagi saat lancar, dalam batas', () {
      var now = DateTime(2026);
      final adaptive = AdaptiveQuality(clock: () => now)..reset(60);
      adaptive.addSample(fast); // latensi dasar

      expect(adaptive.addSample(slow), isTrue);
      expect(adaptive.quality, 50);

      // Perubahan berikutnya ditahan minimal satu detik.
      expect(adaptive.addSample(slow), isFalse);

      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(seconds: 2));
        adaptive.addSample(slow);
      }
      expect(adaptive.quality, AdaptiveQuality.minQuality);

      for (var i = 0; i < 60; i++) {
        now = now.add(const Duration(seconds: 2));
        adaptive.addSample(fast);
      }
      expect(adaptive.quality, 60);
    });

    test('RTT tinggi tapi stabil tidak menurunkan kualitas', () {
      var now = DateTime(2026);
      final adaptive = AdaptiveQuality(clock: () => now)..reset(60);
      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(seconds: 2));
        adaptive.addSample(const Duration(milliseconds: 400));
      }
      expect(adaptive.quality, 60);
    });
  });
}
