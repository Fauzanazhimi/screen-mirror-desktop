// Proxy TCP yang meniru jaringan lambat (mis. Tailscale lewat internet):
// arah laptop -> HP dibatasi bandwidth-nya, kedua arah diberi delay.
//   dart run tool/net_sim.dart <port_dengar> <port_host> <kbps> <delay_ms>
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

// Socket klien diterima di zona utama, jadi error tulis dari koneksi yang
// sudah ditutup lawan baru tertangkap bila seluruh proxy dijaga.
void main(List<String> args) => runZonedGuarded(
  () => _run(args),
  (error, _) => print('koneksi uji berakhir: $error'),
);

Future<void> _run(List<String> args) async {
  final listenPort = int.parse(args[0]);
  final hostPort = int.parse(args[1]);
  final bitsPerSecond = int.parse(args[2]) * 1000;
  final delay = Duration(milliseconds: int.parse(args[3]));

  final server = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    listenPort,
  );
  print('net_sim :$listenPort -> :$hostPort, ${args[2]} kbps, ${args[3]} ms');

  await for (final client in server) {
    runZonedGuarded(() async {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        hostPort,
      );
      _Link(client, upstream, delay).attach();
      _Link(upstream, client, delay, bitsPerSecond: bitsPerSecond).attach();
    }, (error, _) => print('koneksi uji berakhir: $error'));
  }
}

/// Satu arah aliran data. Semua potongan diantre FIFO dan dikirim berurutan,
/// karena urutan byte TCP tidak boleh tertukar.
class _Link {
  _Link(this.source, this.sink, this.delay, {this.bitsPerSecond});

  final Socket source;
  final Socket sink;
  final Duration delay;
  final int? bitsPerSecond;

  final Stopwatch _clock = Stopwatch()..start();
  final Queue<(int, List<int>?)> _queue = Queue(); // null = tutup
  Timer? _timer;
  int _linkFreeAtUs = 0;
  bool _closed = false;

  void attach() {
    sink.done.then(
      (_) {},
      onError: (Object _) {
        _closed = true;
        source.destroy();
      },
    );
    source.listen(
      (data) => _enqueue(data),
      onDone: () => _enqueue(null),
      onError: (Object _) => _enqueue(null),
    );
  }

  void _enqueue(List<int>? data) {
    final nowUs = _clock.elapsedMicroseconds;
    var readyUs = nowUs;
    final rate = bitsPerSecond;
    if (data != null && rate != null) {
      // Menunggu giliran di "link" yang bandwidth-nya terbatas.
      final startUs = max(nowUs, _linkFreeAtUs);
      _linkFreeAtUs = startUs + data.length * 8 * 1000000 ~/ rate;
      readyUs = _linkFreeAtUs;
    }
    _queue.add((readyUs + delay.inMicroseconds, data));
    _timer ??= Timer(Duration.zero, _pump);
  }

  void _pump() {
    _timer = null;
    final nowUs = _clock.elapsedMicroseconds;
    while (_queue.isNotEmpty && _queue.first.$1 <= nowUs) {
      final (_, data) = _queue.removeFirst();
      if (_closed) continue;
      if (data == null) {
        _closed = true;
        sink.destroy();
      } else {
        sink.add(data);
      }
    }
    if (_queue.isNotEmpty) {
      _timer = Timer(
        Duration(microseconds: _queue.first.$1 - nowUs + 500),
        _pump,
      );
    }
  }
}
