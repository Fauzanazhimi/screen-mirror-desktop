// Klien uji tanpa HP: login, menerima frame, lalu melaporkan fps, ukuran, dan
// latensi gerak kursor (dari perintah geser sampai posisi baru tampil).
//   dart run tool/smoke_client.dart <host> <port> <kode> [detik] [mode]
// mode: idle (bawaan), move (geser kursor bolak-balik), full (selalu minta
// layar penuh, meniru layar yang terus berubah). Mendukung protokol v1 dan v2.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mirror_host/auth.dart';

const _moveStep = 40;
const _moveEvery = Duration(milliseconds: 400);

Future<void> main(List<String> args) async {
  final host = args[0];
  final port = args[1];
  final code = args[2];
  final seconds = args.length > 3 ? int.parse(args[3]) : 5;
  final mode = args.length > 4 ? args[4] : 'idle';

  final socket = await WebSocket.connect('ws://$host:$port/ws');
  var version = 0;
  var frames = 0;
  var bytes = 0;
  var patches = 0;
  var sawOk = false;
  var closed = false;
  final clock = Stopwatch()..start();

  int? cursorX;
  int? baselineX;
  var direction = 1;
  final sinceMove = Stopwatch();
  final latencies = <int>[];

  void send(Object message) {
    if (!closed) socket.add(jsonEncode(message));
  }

  socket.listen(
    (message) {
      if (message is String) {
        final json = jsonDecode(message) as Map<String, dynamic>;
        if (json['t'] == 'hello') {
          version = json['v'] as int;
          send({'t': 'auth', 'mac': computeMac(code, json['nonce'] as String)});
        } else if (json['t'] == 'ok') {
          sawOk = true;
        } else {
          print('<- $message');
        }
        return;
      }
      final frame = message as Uint8List;
      final view = ByteData.sublistView(frame);
      if (version >= 2) {
        cursorX = view.getUint16(5);
        patches += view.getUint8(9);
      } else {
        cursorX = view.getUint16(0);
        patches++;
      }
      final base = baselineX;
      if (base != null && (cursorX! - base) * direction > 300) {
        latencies.add(sinceMove.elapsedMilliseconds);
        baselineX = null;
      }
      frames++;
      bytes += frame.length;
      send({'t': 'ack'});
      if (mode == 'full' && version >= 2) send({'t': 'full'});
    },
    onDone: () {
      closed = true;
      print('koneksi ditutup, kode ${socket.closeCode}');
    },
  );

  Timer? mover;
  if (mode == 'move') {
    mover = Timer.periodic(_moveEvery, (_) {
      if (!sawOk || baselineX != null || cursorX == null) return;
      direction = -direction;
      baselineX = cursorX;
      sinceMove
        ..reset()
        ..start();
      send({'t': 'rel', 'dx': _moveStep * direction, 'dy': 0});
    });
  }

  await Future<void>.delayed(Duration(seconds: seconds));
  mover?.cancel();
  final elapsed = clock.elapsedMilliseconds / 1000;
  latencies.sort();
  String percentile(double p) => latencies.isEmpty
      ? '-'
      : '${latencies[((latencies.length - 1) * p).round()]}';
  print(
    'v$version auth=$sawOk frame=$frames '
    'fps=${(frames / elapsed).toStringAsFixed(1)} '
    'KB/frame=${frames == 0 ? 0 : (bytes / frames / 1024).toStringAsFixed(1)} '
    'patch/frame=${frames == 0 ? 0 : (patches / frames).toStringAsFixed(1)} '
    'kbps=${(bytes * 8 / 1000 / elapsed).round()}',
  );
  if (mode == 'move') {
    print(
      'latensi kursor ms: median=${percentile(0.5)} '
      'p90=${percentile(0.9)} sampel=${latencies.length}',
    );
  }
  closed = true;
  await socket.close();
  exit(sawOk ? 0 : 1);
}
