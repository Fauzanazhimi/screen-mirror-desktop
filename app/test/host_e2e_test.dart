// Uji MirrorClient melawan mirror_host yang benar-benar berjalan.
// Dilewati kecuali MIRROR_E2E_PORT dan MIRROR_E2E_CODE di-set.
// Catatan: test ini menggeser kursor laptop sedikit.
import 'dart:async';
import 'dart:io';

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
