import 'dart:math';

/// Menurunkan kualitas JPEG saat frame lambat diterima HP, lalu menaikkannya
/// lagi saat jaringan lancar. Ukuran sinyal: waktu dari kirim sampai ack.
///
/// Yang dinilai adalah tambahan latensi di atas latensi dasar (nilai terendah
/// yang pernah terukur), bukan latensi mentah. Link dengan RTT tinggi tetapi
/// stabil, mis. Tailscale lewat relay, tidak dianggap lambat; yang dihindari
/// adalah frame yang mengantre di jaringan.
class AdaptiveQuality {
  AdaptiveQuality({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const minQuality = 20;
  static const _queuedSlowMs = 250.0;
  static const _queuedFastMs = 80.0;
  static const _stepDown = 10;
  static const _stepUp = 5;
  static const _minStepGap = Duration(seconds: 1);

  // Latensi dasar perlahan naik agar perubahan rute jaringan ikut terbaca.
  static const _baselineCreepMs = 0.2;

  final DateTime Function() _clock;
  int maxQuality = 60;
  int quality = 60;
  double? _averageMs;
  double? _baselineMs;
  DateTime? _lastStep;

  double? get averageLatencyMs => _averageMs;

  /// Dipanggil saat HP memilih preset kualitas atau sesi baru dimulai.
  void reset(int max) {
    maxQuality = max;
    quality = max;
    _averageMs = null;
    _baselineMs = null;
    _lastStep = null;
  }

  /// Mengembalikan true bila [quality] berubah.
  bool addSample(Duration latency) {
    final ms = latency.inMicroseconds / 1000;
    final average = _averageMs == null ? ms : _averageMs! * 0.8 + ms * 0.2;
    _averageMs = average;
    final baseline = min(ms, (_baselineMs ?? ms) + _baselineCreepMs);
    _baselineMs = baseline;

    final now = _clock();
    if (_lastStep != null && now.difference(_lastStep!) < _minStepGap) {
      return false;
    }
    final queued = average - baseline;
    final before = quality;
    if (queued > _queuedSlowMs) {
      quality = max(minQuality, quality - _stepDown);
    } else if (queued < _queuedFastMs) {
      quality = min(maxQuality, quality + _stepUp);
    }
    if (quality == before) return false;
    _lastStep = now;
    return true;
  }
}
