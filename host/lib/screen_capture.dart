import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dirty_rects.dart';
import 'frame_message.dart';
import 'win32.dart';

const _pixelFormat32bppRgb = 0x00022009;

// CLSID encoder JPEG GDI+ {557CF401-1A04-11D3-9A73-0000F81EF32E}
const _jpegClsid = <int>[
  0x01, 0xF4, 0x7C, 0x55, 0x04, 0x1A, 0xD3, 0x11, //
  0x9A, 0x73, 0x00, 0x00, 0xF8, 0x1E, 0xF3, 0x2E,
];

// EncoderQuality {1D5BE4B5-FA4A-452D-9CDD-5DB35105E7EB}
const _qualityGuid = <int>[
  0xB5, 0xE4, 0x5B, 0x1D, 0x4A, 0xFA, 0x2D, 0x45, //
  0x9C, 0xDD, 0x5D, 0xB3, 0x51, 0x05, 0xE7, 0xEB,
];

/// Saat layar diam, layar dicek ulang paling cepat setiap 50 ms agar CPU
/// laptop tidak terus penuh membaca layar yang tidak berubah.
const _idlePoll = Duration(milliseconds: 50);

/// Mengambil layar utama lalu mengubahnya menjadi JPEG lewat GDI+.
class ScreenGrabber {
  ScreenGrabber() {
    final input = calloc<GdiplusStartupInput>()..ref.version = 1;
    final token = calloc<IntPtr>();
    final status = gdiplusStartup(token, input, nullptr);
    _gdiplusToken = token.value;
    calloc.free(input);
    calloc.free(token);
    if (status != 0) {
      throw StateError('GdiplusStartup gagal: $status');
    }

    final stream = calloc<IntPtr>();
    if (createStreamOnHGlobal(0, 1, stream) != 0) {
      throw StateError('CreateStreamOnHGlobal gagal');
    }
    _stream = stream.value;
    calloc.free(stream);

    for (var i = 0; i < 16; i++) {
      _clsid[i] = _jpegClsid[i];
      _params.ref.guid[i] = _qualityGuid[i];
    }
    _params.ref
      ..count = 1
      ..numberOfValues = 1
      ..type =
          4 // EncoderParameterValueTypeLong
      ..value = _qualityValue;
    _memDc = createCompatibleDC(0);
    setStretchBltMode(_memDc, halftone);
    setBrushOrgEx(_memDc, 0, 0, nullptr);
  }

  late final int _gdiplusToken;
  late final int _stream;
  late final int _memDc;
  final Pointer<Uint8> _clsid = calloc<Uint8>(16);
  final Pointer<EncoderParameters> _params = calloc<EncoderParameters>();
  final Pointer<Uint32> _qualityValue = calloc<Uint32>();
  final Pointer<CursorInfo> _cursor = calloc<CursorInfo>();
  final Pointer<IconInfo> _icon = calloc<IconInfo>();
  final Pointer<Uint64> _seekPos = calloc<Uint64>();
  final Pointer<IntPtr> _outHandle = calloc<IntPtr>();

  int _dib = 0;
  int _oldBitmap = 0;
  Pointer<Uint8> _bits = nullptr;
  Pointer<Uint8> _previous = nullptr;
  int _width = 0;
  int _height = 0;

  /// Diset bila patch gagal dikirim, agar frame berikutnya dikirim utuh.
  bool _needFullFrame = true;

  void _ensureBuffer(int width, int height) {
    if (width == _width && height == _height) return;
    _needFullFrame = true;
    _releaseBuffer();
    final info = calloc<BitmapInfoHeader>();
    info.ref
      ..biSize = sizeOf<BitmapInfoHeader>()
      ..biWidth = width
      ..biHeight =
          -height // negatif = baris teratas lebih dulu
      ..biPlanes = 1
      ..biBitCount = 32;
    final bits = calloc<Pointer<Uint8>>();
    _dib = createDIBSection(_memDc, info, dibRgbColors, bits, 0, 0);
    _bits = bits.value;
    calloc.free(info);
    calloc.free(bits);
    if (_dib == 0) throw StateError('CreateDIBSection gagal');
    _oldBitmap = selectObject(_memDc, _dib);
    _previous = calloc<Uint8>(width * height * 4);
    _width = width;
    _height = height;
  }

  void _releaseBuffer() {
    if (_dib == 0) return;
    selectObject(_memDc, _oldBitmap);
    deleteObject(_dib);
    calloc.free(_previous);
    _dib = 0;
    _previous = nullptr;
    _width = 0;
    _height = 0;
  }

  /// Menggambar kursor ke buffer karena StretchBlt tidak ikut menyalinnya.
  /// Mengembalikan posisi kursor ternormalisasi 0-65535.
  (int, int) _drawCursor(int srcWidth, int srcHeight) {
    final scale = _width / srcWidth;
    _cursor.ref.cbSize = sizeOf<CursorInfo>();
    if (getCursorInfo(_cursor) == 0) return (0, 0);
    final x = _cursor.ref.x;
    final y = _cursor.ref.y;
    if (_cursor.ref.flags & cursorShowing != 0 &&
        getIconInfo(_cursor.ref.hCursor, _icon) != 0) {
      drawIconEx(
        _memDc,
        ((x - _icon.ref.xHotspot) * scale).round(),
        ((y - _icon.ref.yHotspot) * scale).round(),
        _cursor.ref.hCursor,
        max(16, (getSystemMetrics(smCxCursor) * scale).round()),
        max(16, (getSystemMetrics(smCyCursor) * scale).round()),
        0,
        0,
        diNormal,
      );
      if (_icon.ref.hbmMask != 0) deleteObject(_icon.ref.hbmMask);
      if (_icon.ref.hbmColor != 0) deleteObject(_icon.ref.hbmColor);
    }
    return (
      (x * 65535 / srcWidth).round().clamp(0, 65535),
      (y * 65535 / srcHeight).round().clamp(0, 65535),
    );
  }

  /// Mengembalikan pesan pembaruan berisi area yang berubah saja, atau null
  /// bila layar tidak berubah atau tidak bisa dibaca (mis. saat layar kunci
  /// atau prompt UAC tampil). [force] mengirim seluruh layar.
  Uint8List? grab({
    required int maxWidth,
    required int quality,
    required bool force,
  }) {
    // Tanpa ES_CONTINUOUS: cukup mereset timer idle selama sesi aktif.
    setThreadExecutionState(esSystemRequired | esDisplayRequired);

    final srcWidth = getSystemMetrics(smCxScreen);
    final srcHeight = getSystemMetrics(smCyScreen);
    if (srcWidth <= 0 || srcHeight <= 0) return null;
    final width = min(maxWidth, srcWidth) & ~1;
    final height = (srcHeight * width / srcWidth).round() & ~1;
    _ensureBuffer(width, height);

    final screenDc = getDC(0);
    if (screenDc == 0) return null;
    final copied = stretchBlt(
      _memDc,
      0,
      0,
      width,
      height,
      screenDc,
      0,
      0,
      srcWidth,
      srcHeight,
      srcCopy,
    );
    releaseDC(0, screenDc);
    if (copied == 0) return null;

    final (cursorX, cursorY) = _drawCursor(srcWidth, srcHeight);

    final byteCount = width * height * 4;
    final List<PixelRect> rects;
    if (force || _needFullFrame) {
      rects = [PixelRect(0, 0, width, height)];
    } else {
      if (memcmp(_bits, _previous, byteCount) == 0) return null;
      rects = changedRects(
        _bits.cast<Uint32>().asTypedList(width * height),
        _previous.cast<Uint32>().asTypedList(width * height),
        width,
        height,
      );
      if (rects.isEmpty) return null;
    }
    memcpy(_previous, _bits, byteCount);

    _qualityValue.value = quality;
    final patches = <EncodedPatch>[];
    for (final rect in rects) {
      final jpeg = _encodeRegion(rect);
      if (jpeg == null) {
        _needFullFrame = true;
        return null;
      }
      patches.add(EncodedPatch(rect, jpeg));
    }
    _needFullFrame = false;
    return buildUpdate(
      width: width,
      height: height,
      cursorX: cursorX,
      cursorY: cursorY,
      patches: patches,
    );
  }

  /// Encode satu area langsung dari buffer DIB tanpa menyalin piksel.
  Uint8List? _encodeRegion(PixelRect rect) {
    final stride = _width * 4;
    if (gdipCreateBitmapFromScan0(
          rect.width,
          rect.height,
          stride,
          _pixelFormat32bppRgb,
          _bits + (rect.y * stride + rect.x * 4),
          _outHandle,
        ) !=
        0) {
      return null;
    }
    final bitmap = _outHandle.value;
    streamSeek(_stream, 0, 0, _seekPos);
    final status = gdipSaveImageToStream(bitmap, _stream, _clsid, _params);
    gdipDisposeImage(bitmap);
    if (status != 0) return null;

    streamSeek(_stream, 0, 1, _seekPos);
    final size = _seekPos.value;
    if (getHGlobalFromStream(_stream, _outHandle) != 0) return null;
    final memory = _outHandle.value;
    final data = globalLock(memory);
    if (data == nullptr) return null;
    final jpeg = Uint8List.fromList(data.asTypedList(size));
    globalUnlock(memory);
    return jpeg;
  }

  void dispose() {
    _releaseBuffer();
    deleteDC(_memDc);
    comRelease(_stream);
    gdiplusShutdown(_gdiplusToken);
    for (final p in <Pointer<NativeType>>[
      _clsid,
      _params,
      _qualityValue,
      _cursor,
      _icon,
      _seekPos,
      _outHandle,
    ]) {
      calloc.free(p);
    }
  }
}

/// Pesan ke isolate: 'next' meminta satu pembaruan; 'full' meminta layar utuh;
/// {w, q, fps} mengubah setelan; {q} hanya mengubah kualitas JPEG.
///
/// Capture dan encode berjalan di isolate terpisah supaya pekerjaan FFI yang
/// sinkron ini tidak menahan event loop jaringan dan input di isolate utama.
void captureIsolate(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort);

  final grabber = ScreenGrabber();
  final sinceFrame = Stopwatch()..start();
  var maxWidth = 1280;
  var quality = 60;
  var interval = const Duration(milliseconds: 33);
  var pending = false;
  var force = true;
  Timer? timer;

  void tick() {
    timer = null;
    if (!pending) return;
    final wait = interval - sinceFrame.elapsed;
    if (wait > Duration.zero) {
      timer = Timer(wait, tick);
      return;
    }
    sinceFrame.reset();
    final frame = grabber.grab(
      maxWidth: maxWidth,
      quality: quality,
      force: force,
    );
    if (frame == null) {
      timer = Timer(interval > _idlePoll ? interval : _idlePoll, tick);
      return;
    }
    pending = false;
    force = false;
    toMain.send(TransferableTypedData.fromList([frame]));
  }

  port.listen((message) {
    switch (message) {
      case 'next':
        pending = true;
      case 'full':
        force = true;
      case {'w': int w, 'q': int q, 'fps': int fps}:
        maxWidth = w;
        quality = q;
        interval = Duration(milliseconds: 1000 ~/ fps);
        force = true;
      case {'q': int q}:
        quality = q;
    }
    if (pending && timer == null) tick();
  });
}
