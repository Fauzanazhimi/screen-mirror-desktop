import 'dart:math';
import 'dart:typed_data';

/// Ukuran petak pembanding. Kelipatan 16 agar pas dengan blok JPEG.
const tileSize = 32;
const _maxRects = 24;

/// Bila lebih dari separuh layar berubah, satu frame penuh lebih hemat.
const _fullFrameRatio = 0.5;

class PixelRect {
  const PixelRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get area => width * height;

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PixelRect($x, $y, $width, $height)';
}

/// Membandingkan dua frame per petak dan mengembalikan area yang berubah.
///
/// Petak berubah yang bersebelahan dalam satu baris digabung, lalu digabung ke
/// bawah bila rentang kolomnya sama, agar jumlah JPEG yang dikirim sedikit.
List<PixelRect> changedRects(
  Uint32List current,
  Uint32List previous,
  int width,
  int height,
) {
  final cols = (width + tileSize - 1) ~/ tileSize;
  final rows = (height + tileSize - 1) ~/ tileSize;
  final changed = Uint8List(cols * rows);

  for (var row = 0; row < rows; row++) {
    final yEnd = min(height, (row + 1) * tileSize);
    for (var y = row * tileSize; y < yEnd; y++) {
      final lineStart = y * width;
      for (var col = 0; col < cols; col++) {
        final index = row * cols + col;
        if (changed[index] != 0) continue;
        final end = lineStart + min(width, (col + 1) * tileSize);
        for (var i = lineStart + col * tileSize; i < end; i++) {
          if (current[i] != previous[i]) {
            changed[index] = 1;
            break;
          }
        }
      }
    }
  }

  // Disimpan dalam satuan petak: [kolomAwal, kolomAkhir, barisAwal, barisAkhir).
  final spans = <List<int>>[];
  var open = <int, int>{}; // rentang kolom -> indeks di spans
  for (var row = 0; row < rows; row++) {
    final nextOpen = <int, int>{};
    var col = 0;
    while (col < cols) {
      if (changed[row * cols + col] == 0) {
        col++;
        continue;
      }
      final start = col;
      while (col < cols && changed[row * cols + col] != 0) {
        col++;
      }
      final key = start * (cols + 1) + col;
      final existing = open[key];
      if (existing != null) {
        spans[existing][3] = row + 1;
        nextOpen[key] = existing;
      } else {
        spans.add([start, col, row, row + 1]);
        nextOpen[key] = spans.length - 1;
      }
    }
    open = nextOpen;
  }
  if (spans.isEmpty) return const [];

  final rects = [
    for (final s in spans)
      PixelRect(
        s[0] * tileSize,
        s[2] * tileSize,
        min(width, s[1] * tileSize) - s[0] * tileSize,
        min(height, s[3] * tileSize) - s[2] * tileSize,
      ),
  ];
  final changedArea = rects.fold(0, (sum, r) => sum + r.area);
  if (changedArea > width * height * _fullFrameRatio) {
    return [PixelRect(0, 0, width, height)];
  }
  if (rects.length > _maxRects) return [_bounds(rects)];
  return rects;
}

PixelRect _bounds(List<PixelRect> rects) {
  var left = rects.first.x;
  var top = rects.first.y;
  var right = rects.first.x + rects.first.width;
  var bottom = rects.first.y + rects.first.height;
  for (final r in rects) {
    left = min(left, r.x);
    top = min(top, r.y);
    right = max(right, r.x + r.width);
    bottom = max(bottom, r.y + r.height);
  }
  return PixelRect(left, top, right - left, bottom - top);
}
