// Uji MirrorClient melawan mirror_host yang benar-benar berjalan.
// Dilewati kecuali MIRROR_E2E_PORT dan MIRROR_E2E_CODE di-set.
// Catatan: test ini menggeser kursor laptop sedikit.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_remote/mirror_client.dart';
import 'package:mirror_remote/protocol.dart';

void main() {
  final port = int.tryParse(Platform.environment['MIRROR_E2E_PORT'] ?? '');
  final code = Platform.environment['MIRROR_E2E_CODE'];
  final skip = port == null || code == null;

  ConnectionParams params([String? overrideCode]) => ConnectionParams(
    host: '127.0.0.1',
    port: port!,
    code: overrideCode ?? code!,
  );

  /// Menunggu frame berikut yang memenuhi syarat.
  Future<MirrorFrame> nextFrame(
    MirrorClient client,
    bool Function(MirrorFrame frame) accept,
  ) {
    final result = Completer<MirrorFrame>();
    client.onFrame = (frame) {
      if (!result.isCompleted && accept(frame)) {
        result.complete(frame);
      } else {
        frame.image.dispose();
      }
    };
    return result.future.timeout(const Duration(seconds: 10));
  }

  /// Rata-rata selisih warna (0-255) dua gambar di kotak sekitar [center].
  Future<double> regionDifference(
    ui.Image a,
    ui.Image b,
    ui.Offset center,
  ) async {
    const half = 40;
    final pixelsA = (await a.toByteData())!;
    final pixelsB = (await b.toByteData())!;
    final cx = (center.dx * a.width).round();
    final cy = (center.dy * a.height).round();
    var total = 0;
    var count = 0;
    for (var y = max(0, cy - half); y < min(a.height, cy + half); y++) {
      for (var x = max(0, cx - half); x < min(a.width, cx + half); x++) {
        final i = (y * a.width + x) * 4;
        for (var c = 0; c < 3; c++) {
          total += (pixelsA.getUint8(i + c) - pixelsB.getUint8(i + c)).abs();
          count++;
        }
      }
    }
    return total / count;
  }

  testWidgets('kode salah ditolak', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      await expectLater(
        MirrorClient.connect(params('SALAH-SALAH')),
        throwsA(
          isA<MirrorConnectException>().having(
            (e) => e.badCode,
            'badCode',
            true,
          ),
        ),
      );
    });
  }, skip: skip);

  testWidgets('pesan beruntun setelah ditolak tidak mematikan host', (
    tester,
  ) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      socket.listen((_) {}, onError: (Object _) {});
      socket
        ..add('{"t":"auth","mac":"salah"}')
        ..add('{"t":"auth","mac":"salah"}')
        ..add('bukan json');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await socket.close();

      final client = await MirrorClient.connect(params());
      client.close();
    });
  }, skip: skip);

  testWidgets('frame terdekode, kualitas berubah, kursor bergerak', (
    tester,
  ) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final client = await MirrorClient.connect(params());

      final first = await nextFrame(client, (_) => true);
      expect(first.image.width, 1280);
      final startCursor = first.cursor;
      first.image.dispose();

      client.setQuality(QualityPreset.hemat);
      final small = await nextFrame(client, (f) => f.image.width == 960);
      small.image.dispose();

      final dx = startCursor.dx > 0.5 ? -60 : 60;
      client.moveBy(dx, 0);
      final moved = await nextFrame(
        client,
        (f) => (f.cursor.dx - startCursor.dx).abs() > 0.005,
      );
      moved.image.dispose();
      client.moveBy(-dx, 0);
      client.close();
    });
  }, skip: skip);

  testWidgets('kursor bergerak: pembaruan kecil dan tempelan patch akurat', (
    tester,
  ) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final client = await MirrorClient.connect(params());
      final first = await nextFrame(client, (_) => true);
      final start = first.cursor;
      first.image.dispose();

      final dx = start.dx > 0.5 ? -120 : 120;
      client.moveBy(dx, 0);
      final moved = await nextFrame(
        client,
        (f) => (f.cursor.dx - start.dx).abs() > 0.02,
      );
      expect(moved.bytes, lessThan(30 * 1024), reason: 'hanya area kursor');

      // Sesi baru selalu dimulai dengan layar utuh: pembanding yang jujur.
      final fresh = await MirrorClient.connect(params());
      final full = await nextFrame(fresh, (_) => true);
      expect(full.image.width, moved.image.width);
      expect(
        await regionDifference(moved.image, full.image, moved.cursor),
        lessThan(8),
        reason: 'kursor di posisi baru harus tampil sama',
      );
      expect(
        await regionDifference(moved.image, full.image, start),
        lessThan(8),
        reason: 'bekas posisi kursor lama harus kembali bersih',
      );

      moved.image.dispose();
      full.image.dispose();
      fresh.moveBy(-dx, 0);
      fresh.close();
      client.close();
    });
  }, skip: skip);

  testWidgets('koneksi baru menggantikan sesi lama', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final first = await MirrorClient.connect(params());
      final closed = Completer<void>();
      first.onClosed = closed.complete;

      final second = await MirrorClient.connect(params());
      await closed.future.timeout(const Duration(seconds: 5));
      final frame = await nextFrame(second, (_) => true);
      frame.image.dispose();
      second.close();
    });
  }, skip: skip);
}
