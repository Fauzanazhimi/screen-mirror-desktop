import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'frame_update.dart';
import 'protocol.dart';

const _connectTimeout = Duration(seconds: 8);

// Pong dari laptop bisa tertahan di belakang frame pada jaringan lambat.
// Batas yang terlalu pendek memutus koneksi yang sebenarnya masih hidup.
const _pingInterval = Duration(seconds: 15);

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

/// Satu frame layar utuh. [cursor] ternormalisasi 0..1. [bytes] adalah ukuran
/// pesan pembaruan yang menghasilkan frame ini.
class MirrorFrame {
  const MirrorFrame(this.image, this.cursor, {this.bytes = 0});

  final ui.Image image;
  final ui.Offset cursor;
  final int bytes;
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

  // Pembaruan hanya berisi area yang berubah, jadi tidak boleh ada yang
  // dilewati: semuanya diproses berurutan di atas gambar layar terakhir.
  final Queue<Uint8List> _pending = Queue();
  bool _processing = false;
  ui.Image? _screen;
  bool _fullRequested = false;

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

    socket.pingInterval = _pingInterval;
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
    _pending.add(data);
    if (!_processing) unawaited(_processPending());
  }

  Future<void> _processPending() async {
    _processing = true;
    while (_pending.isNotEmpty && !_closed) {
      await _apply(_pending.removeFirst());
      _ack();
    }
    _processing = false;
  }

  Future<void> _apply(Uint8List data) async {
    final FrameUpdate update;
    try {
      update = parseUpdate(data);
    } on FormatException {
      _requestFullFrame();
      return;
    }

    final images = <ui.Image>[];
    try {
      for (final patch in update.patches) {
        images.add(await _decodeJpeg(patch.jpeg));
      }
    } on Exception {
      // Patch rusak: gambar di HP tidak lagi sama dengan laptop, minta utuh.
      for (final image in images) {
        image.dispose();
      }
      _requestFullFrame();
      return;
    }
    if (_closed) {
      for (final image in images) {
        image.dispose();
      }
      return;
    }

    final ui.Image screen;
    final previous = _screen;
    if (update.isFullFrame) {
      screen = images.single;
      _fullRequested = false;
    } else if (previous == null ||
        previous.width != update.width ||
        previous.height != update.height) {
      for (final image in images) {
        image.dispose();
      }
      _requestFullFrame();
      return;
    } else {
      screen = _composite(previous, update, images);
    }
    previous?.dispose();
    _screen = screen;

    final handler = onFrame;
    if (handler != null) {
      handler(MirrorFrame(screen.clone(), update.cursor, bytes: data.length));
    }
  }

  /// Menempel patch di atas gambar layar terakhir, sepenuhnya di GPU.
  ui.Image _composite(
    ui.Image previous,
    FrameUpdate update,
    List<ui.Image> patches,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();
    canvas.drawImage(previous, ui.Offset.zero, paint);
    for (var i = 0; i < patches.length; i++) {
      final patch = update.patches[i];
      canvas.drawImage(
        patches[i],
        ui.Offset(patch.x.toDouble(), patch.y.toDouble()),
        paint,
      );
      patches[i].dispose();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(update.width, update.height);
    picture.dispose();
    return image;
  }

  Future<ui.Image> _decodeJpeg(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  void _requestFullFrame() {
    if (_fullRequested) return;
    _fullRequested = true;
    _sendJson({'t': 'full'});
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
    _pending.clear();
    _screen?.dispose();
    _screen = null;
    unawaited(_socket.close());
  }
}
