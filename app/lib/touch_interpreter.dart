import 'dart:ui';

enum TouchMode {
  /// Layar HP menjadi touchpad: jari menggerakkan kursor secara relatif.
  touchpad,

  /// Sentuhan langsung mengenai titik yang disentuh pada gambar.
  direct,
}

abstract interface class TouchActions {
  void moveCursorBy(Offset delta);
  void moveCursorTo(Offset viewPoint);
  void mouseButton(String name, bool down);
  void scrollBy(Offset delta);
  void zoomBy(double factor, Offset focal);
}

enum _Phase { idle, single, twoFingerPending, pinch, scroll, ignore }

/// Menerjemahkan pointer mentah menjadi aksi mouse.
///
/// * Tap = klik kiri
/// * Tahan lalu lepas, atau tap dua jari = klik kanan
/// * Tahan lalu geser = drag (mode touchpad); geser langsung = drag (mode sentuh)
/// * Dua jari geser = scroll, cubit = zoom
class TouchInterpreter {
  TouchInterpreter(this.actions);

  static const slop = 10.0;
  static const longPress = Duration(milliseconds: 450);
  static const twoFingerTap = Duration(milliseconds: 300);

  final TouchActions actions;
  TouchMode mode = TouchMode.touchpad;

  final Map<int, Offset> _points = {};
  _Phase _phase = _Phase.idle;
  Offset _start = Offset.zero;
  Offset _last = Offset.zero;
  Duration _startTime = Duration.zero;
  bool _moved = false;
  bool _dragging = false;
  Offset _centroid = Offset.zero;
  double _span = 0;
  double _centroidTravel = 0;
  double _spanTravel = 0;

  void down(int id, Offset position, Duration time) {
    _points[id] = position;
    if (_phase == _Phase.ignore) return;
    switch (_points.length) {
      case 1:
        _phase = _Phase.single;
        _start = position;
        _last = position;
        _startTime = time;
        _moved = false;
        if (mode == TouchMode.direct) actions.moveCursorTo(position);
      case 2:
        _endDrag();
        _phase = _Phase.twoFingerPending;
        _startTime = time;
        _centroid = _currentCentroid;
        _span = _currentSpan;
        _centroidTravel = 0;
        _spanTravel = 0;
      default:
        _endDrag();
        _phase = _Phase.ignore;
    }
  }

  void move(int id, Offset position, Duration time) {
    if (!_points.containsKey(id)) return;
    _points[id] = position;
    switch (_phase) {
      case _Phase.single:
        _moveSingle(position, time);
      case _Phase.twoFingerPending:
        _classifyTwoFingers();
      case _Phase.pinch:
        final span = _currentSpan;
        if (_span > 0) actions.zoomBy(span / _span, _currentCentroid);
        _span = span;
        _centroid = _currentCentroid;
      case _Phase.scroll:
        final centroid = _currentCentroid;
        actions.scrollBy(centroid - _centroid);
        _centroid = centroid;
      case _Phase.idle || _Phase.ignore:
        break;
    }
  }

  void _moveSingle(Offset position, Duration time) {
    final delta = position - _last;
    _last = position;
    if (!_moved) {
      if ((position - _start).distance < slop) return;
      _moved = true;
      final held = time - _startTime >= longPress;
      if (mode == TouchMode.direct || held) {
        _dragging = true;
        actions.mouseButton('left', true);
      }
    }
    switch (mode) {
      case TouchMode.touchpad:
        actions.moveCursorBy(delta);
      case TouchMode.direct:
        actions.moveCursorTo(position);
    }
  }

  void _classifyTwoFingers() {
    final centroid = _currentCentroid;
    final span = _currentSpan;
    _centroidTravel += (centroid - _centroid).distance;
    _spanTravel += (span - _span).abs();
    _centroid = centroid;
    _span = span;
    if (_centroidTravel < slop && _spanTravel < slop) return;
    _phase = _spanTravel > _centroidTravel ? _Phase.pinch : _Phase.scroll;
  }

  void up(int id, Offset position, Duration time) {
    if (!_points.containsKey(id)) return;
    _points.remove(id);
    final phase = _phase;
    if (phase == _Phase.single) {
      if (_dragging) {
        _endDrag();
      } else if (!_moved) {
        _click(time - _startTime < longPress ? 'left' : 'right');
      }
    } else if (phase == _Phase.twoFingerPending &&
        time - _startTime < twoFingerTap) {
      _click('right');
    }
    // Jari yang tersisa dari gestur dua jari tidak boleh menggerakkan kursor.
    _phase = _points.isEmpty ? _Phase.idle : _Phase.ignore;
  }

  void cancel(int id) {
    _points.remove(id);
    _endDrag();
    _phase = _points.isEmpty ? _Phase.idle : _Phase.ignore;
  }

  void _click(String button) {
    actions.mouseButton(button, true);
    actions.mouseButton(button, false);
  }

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    actions.mouseButton('left', false);
  }

  Offset get _currentCentroid {
    var sum = Offset.zero;
    for (final point in _points.values) {
      sum += point;
    }
    return sum / _points.length.toDouble();
  }

  double get _currentSpan {
    final points = _points.values.take(2).toList();
    return points.length < 2 ? 0 : (points[0] - points[1]).distance;
  }
}
