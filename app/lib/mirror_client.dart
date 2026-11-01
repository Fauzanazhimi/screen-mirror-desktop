import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'protocol.dart';

const _frameHeaderSize = 4;
const _connectTimeout = Duration(seconds: 8);

class ConnectionParams {
  const ConnectionParams({
    required this.host,
    required this.port,
    required this.code,
  });

  final String host;
  final int port;
  final String code;
}

class MirrorConnectException implements Exception {
  const MirrorConnectException(this.message, {this.badCode = false});

  final String message;
  final bool badCode;

  @override
  String toString() => message;
}

/// Satu frame layar. [cursor] ternormalisasi 0..1.
class MirrorFrame {
  const MirrorFrame(this.image, this.cursor);

  final ui.Image image;
  final ui.Offset cursor;
}

class MirrorClient {
  MirrorClient._(this._socket);

  final WebSocket _socket;

  /// Pemanggil menjadi pemilik image dan wajib mem-dispose-nya.
  void Function(MirrorFrame frame)? onFrame;
  void Function()? onClosed;
  String hostName = '';

  final Completer<void> _ready = Completer<void>();
  bool _closed = false;
  bool _decoding = false;
  Uint8List? _nextFrame;

  static Future<MirrorClient> connect(ConnectionParams params) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        Uri(
          scheme: 'ws',
          host: params.host,
          port: params.port,
          path: '/ws',
        ).toString(),
        compression: CompressionOptions.compressionOff,
      ).timeout(_connectTimeout);
    } on TimeoutException {
      throw const MirrorConnectException(
        'Laptop tidak merespons. Pastikan alamat benar, host berjalan, '
        'dan Tailscale aktif di kedua perangkat.',
      );
    } on WebSocketException {
      throw const MirrorConnectException(
        'Terlalu banyak percobaan. Tunggu satu menit lalu coba lagi.',
      );
    } on SocketException {
      throw const MirrorConnectException(
        'Tidak bisa menghubungi laptop. Pastikan host berjalan dan '
        'firewall Windows mengizinkannya.',
      );
    } on FormatException {
      throw const MirrorConnectException('Alamat laptop tidak valid.');
    }

    socket.pingInterval = const Duration(seconds: 5);
    final client = MirrorClient._(socket);
    client._listen(params.code);
    try {
      await client._ready.future.timeout(_connectTimeout);
    } on TimeoutException {
      client.close();
      throw const MirrorConnectException('Laptop tidak menjawab login.');
    }
    return client;
  }

  void _listen(String code) {
    _socket.listen(
      (message) {
        if (message is String) {
          _onText(message, code);
        } else if (message is Uint8List) {
          _onBinary(message);
        }
      },
      onDone: _onDone,
      onError: (Object _) => _onDone(),
      cancelOnError: true,
    );
  }

  void _onText(String message, String code) {
    final json = jsonDecode(message) as Map<String, dynamic>;
    switch (json['t']) {
      case 'hello':
        if (json['v'] != protocolVersion) {
          _failConnect(
            const MirrorConnectException(
              'Versi host dan aplikasi tidak cocok. Perbarui keduanya.',
            ),
          );
          return;
        }
        _sendJson({
          't': 'auth',
          'mac': computeMac(code, json['nonce'] as String),
        });
      case 'ok':
        hostName = json['name'] as String? ?? '';
        if (!_ready.isCompleted) _ready.complete();
      case 'err':
        _failConnect(
          const MirrorConnectException('Kode pairing salah.', badCode: true),
        );
    }
  }

  void _failConnect(MirrorConnectException error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    close();
  }

  void _onDone() {
    if (!_ready.isCompleted) {
      _ready.completeError(
        const MirrorConnectException('Koneksi ditutup oleh laptop.'),
      );
    }
    if (_closed) return;
    _closed = true;
    onClosed?.call();
  }

  void _onBinary(Uint8List data) {
    if (data.length <= _frameHeaderSize) return;
    if (_decoding) {
      // Dekoder tertinggal: frame lama dibuang agar tampilan tidak tertunda.
      if (_nextFrame != null) _ack();
      _nextFrame = data;
      return;
    }
    unawaited(_decodeFrames(data));
  }

  Future<void> _decodeFrames(Uint8List first) async {
    _decoding = true;
    Uint8List? current = first;
    while (current != null && !_closed) {
      await _decode(current);
      _ack();
      current = _nextFrame;
      _nextFrame = null;
    }
    _decoding = false;
  }

  Future<void> _decode(Uint8List data) async {
    final header = ByteData.sublistView(data, 0, _frameHeaderSize);
    final cursor = ui.Offset(
      header.getUint16(0) / 65535,
      header.getUint16(2) / 65535,
    );
    try {
      final codec = await ui.instantiateImageCodec(
        Uint8List.sublistView(data, _frameHeaderSize),
      );
      final decoded = await codec.getNextFrame();
      codec.dispose();
      final handler = onFrame;
      if (_closed || handler == null) {
        decoded.image.dispose();
        return;
      }
      handler(MirrorFrame(decoded.image, cursor));
    } on Exception {
      // Satu frame rusak tidak perlu memutus sesi; frame berikutnya menyusul.
    }
  }

  void _ack() => _sendJson({'t': 'ack'});

  void _sendJson(Map<String, Object?> message) {
    if (_closed) return;
    _socket.add(jsonEncode(message));
  }

  void setQuality(QualityPreset preset) => _sendJson({
    't': 'cfg',
    'w': preset.width,
    'q': preset.quality,
    'fps': preset.fps,
  });

  void moveTo(ui.Offset normalized) =>
      _sendJson({'t': 'abs', 'x': normalized.dx, 'y': normalized.dy});

  void moveBy(int dx, int dy) => _sendJson({'t': 'rel', 'dx': dx, 'dy': dy});

  void button(String name, bool down) =>
      _sendJson({'t': 'btn', 'b': name, 'd': down});

  void wheel(int dy, int dx) => _sendJson({'t': 'wheel', 'dy': dy, 'dx': dx});

  void combo(List<int> keys) => _sendJson({'t': 'combo', 'vk': keys});

  void text(String value) => _sendJson({'t': 'text', 's': value});

  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_socket.close());
  }
}
