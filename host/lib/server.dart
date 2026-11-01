import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'auth.dart';
import 'input_injector.dart';
import 'screen_capture.dart';

const protocolVersion = 1;
const _authTimeout = Duration(seconds: 10);
const _pingInterval = Duration(seconds: 5);
const _maxFramesInFlight = 2;
const _maxTextLength = 4096;

class MirrorServer {
  MirrorServer({required this.pairCode});

  final String pairCode;
  final AuthThrottle _throttle = AuthThrottle();
  final InputInjector _input = InputInjector();
  final List<HttpServer> _servers = [];

  late final SendPort _capture;
  _Session? _active;
  bool _frameRequested = false;

  Future<void> start(List<InternetAddress> addresses, int port) async {
    await _startCapture();
    for (final address in addresses) {
      final server = await HttpServer.bind(address, port);
      _servers.add(server);
      server.listen(_onRequest);
    }
  }

  Future<void> _startCapture() async {
    final fromWorker = ReceivePort();
    final failures = ReceivePort();
    failures.listen((error) {
      stderr.writeln('Capture berhenti karena error: $error');
      exit(1);
    });
    await Isolate.spawn(
      captureIsolate,
      fromWorker.sendPort,
      onError: failures.sendPort,
    );
    final ready = Completer<SendPort>();
    fromWorker.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is TransferableTypedData) {
        _onFrame(message);
      }
    });
    _capture = await ready.future;
  }

  void _onFrame(TransferableTypedData data) {
    _frameRequested = false;
    final session = _active;
    if (session == null) return;
    session.send(data.materialize().asUint8List());
    _requestFrame();
  }

  void _requestFrame() {
    final session = _active;
    if (session == null || _frameRequested) return;
    if (session.framesInFlight >= _maxFramesInFlight) return;
    _frameRequested = true;
    _capture.send('next');
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (request.uri.path != '/ws' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final address = request.connectionInfo?.remoteAddress.address ?? '?';
    if (_throttle.isLocked(address)) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
      return;
    }
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );
    } on Exception catch (e) {
      print('Upgrade WebSocket gagal dari $address: $e');
      return;
    }
    socket.pingInterval = _pingInterval;
    _Session(this, socket, address).run();
  }

  void _activate(_Session session) {
    final previous = _active;
    if (previous != null) {
      previous.close();
      _input.releaseAll();
    }
    _active = session;
    _frameRequested = false;
    _throttle.recordSuccess(session.address);
    print('[${_time()}] Terhubung: ${session.address}');
  }

  void _deactivate(_Session session) {
    if (!identical(_active, session)) return;
    _active = null;
    _input.releaseAll();
    print('[${_time()}] Terputus: ${session.address}');
  }

  String _time() => DateTime.now().toIso8601String().substring(11, 19);
}

class _Session {
  _Session(this.server, this.socket, this.address);

  final MirrorServer server;
  final WebSocket socket;
  final String address;
  final String nonce = generateNonce();

  int framesInFlight = 0;
  bool _authed = false;
  bool _closed = false;

  void run() {
    final timeout = Timer(_authTimeout, close);
    _sendJson({'t': 'hello', 'v': protocolVersion, 'nonce': nonce});
    socket.listen(
      (message) {
        if (_closed || message is! String) return;
        final Object? decoded;
        try {
          decoded = jsonDecode(message);
        } on FormatException {
          close();
          return;
        }
        if (decoded is! Map<String, dynamic>) return;
        if (_authed) {
          _onMessage(decoded);
        } else {
          timeout.cancel();
          _onAuth(decoded);
        }
      },
      onDone: () {
        timeout.cancel();
        server._deactivate(this);
      },
      onError: (Object _) => server._deactivate(this),
      cancelOnError: true,
    );
  }

  void _onAuth(Map<String, dynamic> message) {
    final mac = message['mac'];
    final expected = computeMac(server.pairCode, nonce);
    if (message['t'] != 'auth' ||
        mac is! String ||
        !constantTimeEquals(mac, expected)) {
      server._throttle.recordFailure(address);
      print('Kode pairing salah dari $address');
      _sendJson({'t': 'err', 'msg': 'bad_code'});
      close();
      return;
    }
    _authed = true;
    server._activate(this);
    _sendJson({'t': 'ok', 'name': Platform.localHostname});
    server._capture.send({'w': 1280, 'q': 60, 'fps': 30});
    server._requestFrame();
  }

  void _onMessage(Map<String, dynamic> message) {
    final input = server._input;
    switch (message) {
      case {'t': 'ack'}:
        if (framesInFlight > 0) framesInFlight--;
        server._requestFrame();
      case {'t': 'cfg', 'w': int w, 'q': int q, 'fps': int fps}:
        server._capture.send({
          'w': w.clamp(320, 3840),
          'q': q.clamp(10, 95),
          'fps': fps.clamp(1, 60),
        });
      case {'t': 'abs', 'x': num x, 'y': num y}:
        input.moveTo(x.toDouble(), y.toDouble());
      case {'t': 'rel', 'dx': int dx, 'dy': int dy}:
        input.moveBy(dx.clamp(-4000, 4000), dy.clamp(-4000, 4000));
      case {'t': 'btn', 'b': String button, 'd': bool down}:
        input.button(button, down);
      case {'t': 'wheel', 'dy': int dy, 'dx': int dx}:
        input.wheel(dy.clamp(-2400, 2400), dx.clamp(-2400, 2400));
      case {'t': 'key', 'vk': int vk, 'd': bool down}:
        input.key(vk, down);
      case {'t': 'combo', 'vk': List<dynamic> keys}:
        input.combo(keys.whereType<int>().take(6).toList());
      case {'t': 'text', 's': String text} when text.length <= _maxTextLength:
        input.text(text);
    }
  }

  void send(List<int> frame) {
    if (_closed) return;
    framesInFlight++;
    socket.add(frame);
  }

  void _sendJson(Map<String, Object?> message) {
    if (_closed) return;
    socket.add(jsonEncode(message));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(socket.close());
  }
}
