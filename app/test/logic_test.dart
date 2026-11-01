import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_remote/protocol.dart';
import 'package:mirror_remote/text_diff.dart';
import 'package:mirror_remote/touch_interpreter.dart';
import 'package:mirror_remote/viewport.dart';

class _Recorder implements TouchActions {
  final List<String> events = [];
  Offset moved = Offset.zero;
  Offset scrolled = Offset.zero;
  double zoom = 1;

  @override
  void moveCursorBy(Offset delta) => moved += delta;

  @override
  void moveCursorTo(Offset viewPoint) => events.add('to');

  @override
  void mouseButton(String name, bool down) =>
      events.add('$name ${down ? 'down' : 'up'}');

  @override
  void scrollBy(Offset delta) => scrolled += delta;

  @override
  void zoomBy(double factor, Offset focal) => zoom *= factor;
}

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  group('TouchInterpreter', () {
    late _Recorder actions;
    late TouchInterpreter touch;

    setUp(() {
      actions = _Recorder();
      touch = TouchInterpreter(actions);
    });

    test('tap menjadi klik kiri', () {
      touch.down(1, Offset.zero, ms(0));
      touch.up(1, Offset.zero, ms(100));
      expect(actions.events, ['left down', 'left up']);
    });

    test('tahan lalu lepas menjadi klik kanan', () {
      touch.down(1, Offset.zero, ms(0));
      touch.up(1, Offset.zero, ms(600));
      expect(actions.events, ['right down', 'right up']);
    });

    test('geser menggerakkan kursor tanpa klik', () {
      touch.down(1, Offset.zero, ms(0));
      touch.move(1, const Offset(30, 0), ms(50));
      touch.move(1, const Offset(50, 0), ms(80));
      touch.up(1, const Offset(50, 0), ms(100));
      expect(actions.moved, const Offset(50, 0));
      expect(actions.events, isEmpty);
    });

    test('tahan lalu geser menjadi drag dan dilepas saat jari diangkat', () {
      touch.down(1, Offset.zero, ms(0));
      touch.move(1, const Offset(30, 0), ms(500));
      touch.up(1, const Offset(30, 0), ms(700));
      expect(actions.events, ['left down', 'left up']);
    });

    test('tap dua jari menjadi klik kanan', () {
      touch.down(1, Offset.zero, ms(0));
      touch.down(2, const Offset(50, 0), ms(10));
      touch.up(1, Offset.zero, ms(100));
      touch.up(2, const Offset(50, 0), ms(110));
      expect(actions.events, ['right down', 'right up']);
    });

    test('dua jari searah menjadi scroll', () {
      touch.down(1, Offset.zero, ms(0));
      touch.down(2, const Offset(50, 0), ms(0));
      touch.move(1, const Offset(0, 30), ms(50));
      touch.move(2, const Offset(50, 30), ms(50));
      touch.move(1, const Offset(0, 60), ms(100));
      touch.move(2, const Offset(50, 60), ms(100));
      expect(actions.scrolled.dy, greaterThan(0));
      expect(actions.zoom, 1);
    });

    test('dua jari menjauh menjadi zoom', () {
      touch.down(1, const Offset(100, 0), ms(0));
      touch.down(2, const Offset(200, 0), ms(0));
      touch.move(1, const Offset(80, 0), ms(50));
      touch.move(2, const Offset(220, 0), ms(50));
      touch.move(1, const Offset(60, 0), ms(100));
      touch.move(2, const Offset(240, 0), ms(100));
      expect(actions.zoom, greaterThan(1));
    });

    test('jari sisa gestur dua jari tidak menggerakkan kursor', () {
      touch.down(1, Offset.zero, ms(0));
      touch.down(2, const Offset(50, 0), ms(0));
      touch.up(2, const Offset(50, 0), ms(500));
      touch.move(1, const Offset(100, 0), ms(600));
      expect(actions.moved, Offset.zero);
    });

    test('mode sentuh: tap memindahkan kursor lalu klik', () {
      touch.mode = TouchMode.direct;
      touch.down(1, const Offset(5, 5), ms(0));
      touch.up(1, const Offset(5, 5), ms(100));
      expect(actions.events, ['to', 'left down', 'left up']);
    });

    test('pointer batal melepas tombol yang tertahan', () {
      touch.mode = TouchMode.direct;
      touch.down(1, Offset.zero, ms(0));
      touch.move(1, const Offset(40, 0), ms(50));
      touch.cancel(1);
      expect(actions.events.last, 'left up');
    });
  });

  group('Viewport', () {
    Viewport make() => Viewport()
      ..view = const Size(2000, 1000)
      ..image = const Size(1600, 900);

    test('gambar diletakkan di tengah dengan rasio asli', () {
      final rect = make().imageRect;
      expect(rect.height, 1000);
      expect(rect.width, closeTo(1777.8, 0.1));
      expect(rect.center.dx, 1000);
    });

    test('titik tengah tampilan sama dengan tengah layar laptop', () {
      expect(
        make().toNormalized(const Offset(1000, 500)),
        const Offset(0.5, 0.5),
      );
    });

    test('titik di luar gambar dijepit ke tepi', () {
      expect(make().toNormalized(Offset.zero).dx, 0);
    });

    test('zoom mempertahankan titik fokus', () {
      final viewport = make();
      const focal = Offset(1200, 600);
      final before = viewport.toNormalized(focal);
      viewport.zoomAt(2, focal);
      final after = viewport.toNormalized(focal);
      expect(after.dx, closeTo(before.dx, 0.001));
      expect(after.dy, closeTo(before.dy, 0.001));
    });

    test('zoom dibatasi dan geser tidak melewati tepi', () {
      final viewport = make()..zoomAt(100, const Offset(1000, 500));
      expect(viewport.scale, Viewport.maxScale);
      viewport.panBy(const Offset(100000, 100000));
      expect(viewport.imageRect.left, 0);
      expect(viewport.imageRect.top, 0);
    });

    test('tampilan mengikuti kursor saat zoom', () {
      final viewport = make()..zoomAt(3, const Offset(1000, 500));
      final before = viewport.imageRect.left;
      viewport.followCursor(const Offset(1, 0.5));
      expect(viewport.imageRect.left, lessThan(before));
    });
  });

  group('diffText', () {
    void check(String before, String after, int backspaces, String inserted) {
      final edit = diffText(before, after);
      expect(edit.backspaces, backspaces);
      expect(edit.inserted, inserted);
    }

    test('menambah karakter', () => check(' ab', ' abc', 0, 'c'));
    test('menghapus karakter', () => check(' abc', ' ab', 1, ''));
    test('menghapus sentinel', () => check(' ', '', 1, ''));
    test('koreksi kata', () => check(' teh', ' the', 2, 'he'));
  });

  test('MAC cocok dengan HMAC-SHA256 acuan yang dihitung Python', () {
    expect(
      computeMac('abcd-efgh', 'nonce'),
      '70397259b7b69fca4789e24ef544d611f5c42eac22192e72830c3fce86634cce',
    );
  });
}
