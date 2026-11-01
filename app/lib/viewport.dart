import 'dart:math';
import 'dart:ui';

/// Menghitung posisi gambar layar laptop di layar HP, termasuk zoom dan geser.
class Viewport {
  static const maxScale = 5.0;
  static const _followMargin = 0.15;

  Size view = Size.zero;
  Size image = const Size(16, 9);
  double scale = 1;
  Offset _offset = Offset.zero;

  bool get isZoomed => scale > 1.01;

  Size get _scaledSize {
    if (view.isEmpty || image.isEmpty) return Size.zero;
    final fit = min(view.width / image.width, view.height / image.height);
    return image * fit * scale;
  }

  /// Letak seluruh gambar laptop dalam koordinat tampilan HP.
  Rect get imageRect {
    final size = _scaledSize;
    return Rect.fromLTWH(
      (view.width - size.width) / 2 + _offset.dx,
      (view.height - size.height) / 2 + _offset.dy,
      size.width,
      size.height,
    );
  }

  /// Mengubah titik sentuh menjadi koordinat layar laptop 0..1.
  Offset toNormalized(Offset point) {
    final rect = imageRect;
    if (rect.isEmpty) return Offset.zero;
    return Offset(
      ((point.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((point.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  void zoomAt(double factor, Offset focal) {
    final anchor = toNormalized(focal);
    scale = (scale * factor).clamp(1.0, maxScale);
    final size = _scaledSize;
    _offset = Offset(
      focal.dx - anchor.dx * size.width - (view.width - size.width) / 2,
      focal.dy - anchor.dy * size.height - (view.height - size.height) / 2,
    );
    _clampOffset();
  }

  void panBy(Offset delta) {
    _offset += delta;
    _clampOffset();
  }

  /// Menggeser tampilan saat kursor mendekati tepi ketika sedang di-zoom.
  void followCursor(Offset normalized) {
    if (!isZoomed) return;
    final rect = imageRect;
    final x = rect.left + normalized.dx * rect.width;
    final y = rect.top + normalized.dy * rect.height;
    final marginX = view.width * _followMargin;
    final marginY = view.height * _followMargin;
    var dx = 0.0;
    var dy = 0.0;
    if (x < marginX) dx = marginX - x;
    if (x > view.width - marginX) dx = view.width - marginX - x;
    if (y < marginY) dy = marginY - y;
    if (y > view.height - marginY) dy = view.height - marginY - y;
    panBy(Offset(dx, dy));
  }

  void _clampOffset() {
    final size = _scaledSize;
    final limitX = max(0.0, (size.width - view.width) / 2);
    final limitY = max(0.0, (size.height - view.height) / 2);
    _offset = Offset(
      _offset.dx.clamp(-limitX, limitX),
      _offset.dy.clamp(-limitY, limitY),
    );
  }

  void reset() {
    scale = 1;
    _offset = Offset.zero;
  }
}
