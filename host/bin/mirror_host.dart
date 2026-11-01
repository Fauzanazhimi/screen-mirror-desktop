import 'dart:convert';
import 'dart:io';

import 'package:mirror_host/auth.dart';
import 'package:mirror_host/server.dart';
import 'package:mirror_host/win32.dart';

const _usage = '''
Mirror Host - bagikan layar laptop ke aplikasi Mirror Remote.

  mirror_host [--port 8765] [--tailscale-only] [--reset-code]

  --port N           Port yang didengarkan (bawaan 8765)
  --tailscale-only   Hanya menerima koneksi lewat alamat Tailscale
  --reset-code       Buat kode pairing baru
  --help             Tampilkan bantuan ini
''';

Future<void> main(List<String> args) async {
  var port = 8765;
  var tailscaleOnly = false;
  var resetCode = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--port' when i + 1 < args.length:
        final parsed = int.tryParse(args[++i]);
        if (parsed == null || parsed < 1 || parsed > 65535) {
          _fail('Port tidak valid.\n\n$_usage');
        }
        port = parsed;
      case '--tailscale-only':
        tailscaleOnly = true;
      case '--reset-code':
        resetCode = true;
      case '--help' || '-h':
        print(_usage);
        return;
      default:
        _fail('Argumen tidak dikenal: ${args[i]}\n\n$_usage');
    }
  }

  // Tanpa ini Windows memberi layar versi terskala dan koordinat kursor meleset.
  setProcessDpiAwarenessContext(dpiPerMonitorV2);

  final code = _loadPairCode(reset: resetCode);
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final addresses = [for (final i in interfaces) ...i.addresses];
  final tailscale = addresses.where(_isTailscale).toList();
  final lan = addresses
      .where((a) => !_isTailscale(a) && !a.isLoopback)
      .toList();

  if (tailscaleOnly && tailscale.isEmpty) {
    _fail('Alamat Tailscale tidak ditemukan. Pastikan Tailscale aktif.');
  }

  final server = MirrorServer(pairCode: code);
  try {
    await server.start(
      tailscaleOnly ? tailscale : [InternetAddress.anyIPv4],
      port,
    );
  } on SocketException catch (e) {
    _fail('Gagal membuka port $port: ${e.message}');
  }

  print('Mirror Host berjalan.\n');
  print('  Kode pairing : $code\n');
  for (final a in tailscale) {
    print('  Tailscale    : ${a.address}:$port');
  }
  if (!tailscaleOnly) {
    for (final a in lan) {
      print('  Jaringan lokal: ${a.address}:$port (tidak terenkripsi)');
    }
  }
  if (tailscale.isEmpty) {
    print('  Tailscale    : tidak aktif');
  }
  print('\nTekan Ctrl+C untuk berhenti.');
}

bool _isTailscale(InternetAddress address) {
  final bytes = address.rawAddress;
  return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127;
}

String _loadPairCode({required bool reset}) {
  final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
  final file = File('$appData\\MirrorHost\\config.json');
  if (!reset && file.existsSync()) {
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final code = saved['pairCode'];
    if (code is String && code.isNotEmpty) return code;
  }
  final code = generatePairCode();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode({'pairCode': code}));
  return code;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
