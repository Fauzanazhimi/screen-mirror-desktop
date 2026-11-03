// Mengukur biaya capture dan encode per frame di laptop ini.
//   dart run tool/bench_capture.dart [lebar] [kualitas]
import 'package:mirror_host/screen_capture.dart';
import 'package:mirror_host/win32.dart';

void main(List<String> args) {
  final width = args.isNotEmpty ? int.parse(args[0]) : 1280;
  final quality = args.length > 1 ? int.parse(args[1]) : 60;
  setProcessDpiAwarenessContext(dpiPerMonitorV2);
  final grabber = ScreenGrabber();

  double measure(bool force, void Function(int bytes) onBytes) {
    const rounds = 30;
    final clock = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      final frame = grabber.grab(
        maxWidth: width,
        quality: quality,
        force: force,
      );
      if (frame != null) onBytes(frame.length);
    }
    return clock.elapsedMicroseconds / rounds / 1000;
  }

  measure(true, (_) {}); // pemanasan
  var encodedBytes = 0;
  var encodedFrames = 0;
  final full = measure(true, (bytes) {
    encodedBytes += bytes;
    encodedFrames++;
  });
  final idle = measure(false, (_) {});
  print('lebar=$width kualitas=$quality');
  print('capture+encode penuh : ${full.toStringAsFixed(1)} ms/frame');
  print('capture+bandingkan   : ${idle.toStringAsFixed(1)} ms/frame');
  print(
    'ukuran frame penuh   : '
    '${(encodedBytes / encodedFrames / 1024).toStringAsFixed(0)} KB',
  );
  grabber.dispose();
}
