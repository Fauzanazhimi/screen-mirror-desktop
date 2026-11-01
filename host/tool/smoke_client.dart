// Klien uji tanpa HP: login, menerima frame, lalu melaporkan fps dan ukuran.
//   dart run tool/smoke_client.dart <host> <port> <kode> [detik] [simpan.jpg]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mirror_host/auth.dart';

Future<void> main(List<String> args) async {
  final host = args[0];
  final port = args[1];
  final code = args[2];
  final seconds = args.length > 3 ? int.parse(args[3]) : 5;
  final savePath = args.length > 4 ? args[4] : null;

  final socket = await WebSocket.connect('ws://$host:$port/ws');
  var frames = 0;
  var bytes = 0;
  var sawOk = false;
  final clock = Stopwatch()..start();

  socket.listen((message) {
    if (message is String) {
      final json = jsonDecode(message) as Map<String, dynamic>;
      print('<- ${json['t']}');
      if (json['t'] == 'hello') {
        socket.add(
          jsonEncode({
            't': 'auth',
            'mac': computeMac(code, json['nonce'] as String),
          }),
        );
      } else if (json['t'] == 'ok') {
        sawOk = true;
      }
      return;
    }
    final frame = message as Uint8List;
    if (frames == 0) {
      final view = ByteData.sublistView(frame);
      print(
        'frame pertama: ${frame.length} byte, kursor '
        '${view.getUint16(0)},${view.getUint16(2)}, marker '
        '${frame[4].toRadixString(16)}${frame[5].toRadixString(16)}',
      );
      if (savePath != null) {
        File(savePath).writeAsBytesSync(frame.sublist(4));
      }
    }
    frames++;
    bytes += frame.length;
    socket.add('{"t":"ack"}');
  }, onDone: () => print('koneksi ditutup, kode ${socket.closeCode}'));

  await Future<void>.delayed(Duration(seconds: seconds));
  final elapsed = clock.elapsedMilliseconds / 1000;
  print(
    'auth=$sawOk frame=$frames '
    'fps=${(frames / elapsed).toStringAsFixed(1)} '
    'kbps=${(bytes * 8 / 1000 / elapsed).round()}',
  );
  await socket.close();
  exit(sawOk ? 0 : 1);
}
