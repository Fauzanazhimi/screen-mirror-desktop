// Binding FFI minimal untuk API Windows yang dipakai host.
// Ditulis tangan agar hanya memuat yang benar-benar dibutuhkan.
import 'dart:ffi';

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _gdiplus = DynamicLibrary.open('gdiplus.dll');
final _ole32 = DynamicLibrary.open('ole32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _msvcrt = DynamicLibrary.open('msvcrt.dll');

const smCxScreen = 0;
const smCyScreen = 1;
const smCxCursor = 13;
const smCyCursor = 14;
const srcCopy = 0x00CC0020;
const halftone = 4;
const dibRgbColors = 0;
const cursorShowing = 1;
const diNormal = 3;

const esSystemRequired = 0x00000001;
const esDisplayRequired = 0x00000002;

const inputMouse = 0;
const inputKeyboard = 1;
const mouseMove = 0x0001;
const mouseLeftDown = 0x0002;
const mouseLeftUp = 0x0004;
const mouseRightDown = 0x0008;
const mouseRightUp = 0x0010;
const mouseMiddleDown = 0x0020;
const mouseMiddleUp = 0x0040;
const mouseWheel = 0x0800;
const mouseHWheel = 0x1000;
const mouseAbsolute = 0x8000;
const keyExtended = 0x0001;
const keyUp = 0x0002;
const keyUnicode = 0x0004;

/// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
const dpiPerMonitorV2 = -4;

final class BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

final class CursorInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int flags;
  @IntPtr()
  external int hCursor;
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class IconInfo extends Struct {
  @Int32()
  external int fIcon;
  @Uint32()
  external int xHotspot;
  @Uint32()
  external int yHotspot;
  @IntPtr()
  external int hbmMask;
  @IntPtr()
  external int hbmColor;
}

final class GdiplusStartupInput extends Struct {
  @Uint32()
  external int version;
  external Pointer<Void> debugCallback;
  @Int32()
  external int suppressBackgroundThread;
  @Int32()
  external int suppressExternalCodecs;
}

/// EncoderParameters dengan satu parameter (layout x64).
final class EncoderParameters extends Struct {
  @Uint32()
  external int count;
  // EncoderParameter berisi pointer, jadi rata 8 byte. Array<Uint8> di bawah
  // tidak memaksa perataan itu, sehingga padding ditulis eksplisit.
  @Uint32()
  external int padding;
  @Array(16)
  external Array<Uint8> guid;
  @Uint32()
  external int numberOfValues;
  @Uint32()
  external int type;
  external Pointer<Uint32> value;
}

// user32
final setProcessDpiAwarenessContext = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'SetProcessDpiAwarenessContext',
    );
final getSystemMetrics = _user32
    .lookupFunction<Int32 Function(Int32), int Function(int)>(
      'GetSystemMetrics',
    );
final getDC = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final releaseDC = _user32
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'ReleaseDC',
    );
final getCursorInfo = _user32
    .lookupFunction<
      Int32 Function(Pointer<CursorInfo>),
      int Function(Pointer<CursorInfo>)
    >('GetCursorInfo');
final getIconInfo = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<IconInfo>),
      int Function(int, Pointer<IconInfo>)
    >('GetIconInfo');
final drawIconEx = _user32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Int32,
        IntPtr,
        Int32,
        Int32,
        Uint32,
        IntPtr,
        Uint32,
      ),
      int Function(int, int, int, int, int, int, int, int, int)
    >('DrawIconEx');
final sendInput = _user32
    .lookupFunction<
      Uint32 Function(Uint32, Pointer<Uint8>, Int32),
      int Function(int, Pointer<Uint8>, int)
    >('SendInput');
final mapVirtualKey = _user32
    .lookupFunction<Uint32 Function(Uint32, Uint32), int Function(int, int)>(
      'MapVirtualKeyW',
    );

// gdi32
final createCompatibleDC = _gdi32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'CreateCompatibleDC',
    );
final deleteDC = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
final createDIBSection = _gdi32
    .lookupFunction<
      IntPtr Function(
        IntPtr,
        Pointer<BitmapInfoHeader>,
        Uint32,
        Pointer<Pointer<Uint8>>,
        IntPtr,
        Uint32,
      ),
      int Function(
        int,
        Pointer<BitmapInfoHeader>,
        int,
        Pointer<Pointer<Uint8>>,
        int,
        int,
      )
    >('CreateDIBSection');
final selectObject = _gdi32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
      'SelectObject',
    );
final deleteObject = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');
final stretchBlt = _gdi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Int32,
        Int32,
        Int32,
        IntPtr,
        Int32,
        Int32,
        Int32,
        Int32,
        Uint32,
      ),
      int Function(int, int, int, int, int, int, int, int, int, int, int)
    >('StretchBlt');
final setStretchBltMode = _gdi32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'SetStretchBltMode',
    );
final setBrushOrgEx = _gdi32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Int32, Pointer<Void>),
      int Function(int, int, int, Pointer<Void>)
    >('SetBrushOrgEx');

// gdiplus
final gdiplusStartup = _gdiplus
    .lookupFunction<
      Int32 Function(
        Pointer<IntPtr>,
        Pointer<GdiplusStartupInput>,
        Pointer<Void>,
      ),
      int Function(Pointer<IntPtr>, Pointer<GdiplusStartupInput>, Pointer<Void>)
    >('GdiplusStartup');
final gdiplusShutdown = _gdiplus
    .lookupFunction<Void Function(IntPtr), void Function(int)>(
      'GdiplusShutdown',
    );
final gdipCreateBitmapFromScan0 = _gdiplus
    .lookupFunction<
      Int32 Function(
        Int32,
        Int32,
        Int32,
        Int32,
        Pointer<Uint8>,
        Pointer<IntPtr>,
      ),
      int Function(int, int, int, int, Pointer<Uint8>, Pointer<IntPtr>)
    >('GdipCreateBitmapFromScan0');
final gdipSaveImageToStream = _gdiplus
    .lookupFunction<
      Int32 Function(
        IntPtr,
        IntPtr,
        Pointer<Uint8>,
        Pointer<EncoderParameters>,
      ),
      int Function(int, int, Pointer<Uint8>, Pointer<EncoderParameters>)
    >('GdipSaveImageToStream');
final gdipDisposeImage = _gdiplus
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'GdipDisposeImage',
    );

// ole32
final createStreamOnHGlobal = _ole32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<IntPtr>),
      int Function(int, int, Pointer<IntPtr>)
    >('CreateStreamOnHGlobal');
final getHGlobalFromStream = _ole32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<IntPtr>),
      int Function(int, Pointer<IntPtr>)
    >('GetHGlobalFromStream');

// kernel32
final globalLock = _kernel32
    .lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('GlobalLock');
final globalUnlock = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');
final setThreadExecutionState = _kernel32
    .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
      'SetThreadExecutionState',
    );

// msvcrt
final memcmp = _msvcrt
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>, IntPtr),
      int Function(Pointer<Uint8>, Pointer<Uint8>, int)
    >('memcmp');
final memcpy = _msvcrt
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, IntPtr),
      Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, int)
    >('memcpy');

// Metode COM IStream dipanggil lewat vtable.
int _vtableEntry(int comObject, int index) {
  final vtable = Pointer<IntPtr>.fromAddress(comObject).value;
  return Pointer<IntPtr>.fromAddress(vtable + index * sizeOf<IntPtr>()).value;
}

typedef _SeekNative = Int32 Function(IntPtr, Int64, Uint32, Pointer<Uint64>);
typedef _SeekDart = int Function(int, int, int, Pointer<Uint64>);
typedef _ReleaseNative = Uint32 Function(IntPtr);
typedef _ReleaseDart = int Function(int);

/// IStream::Seek. origin: 0 = awal, 1 = posisi saat ini.
int streamSeek(int stream, int offset, int origin, Pointer<Uint64> newPos) {
  final fn = Pointer<NativeFunction<_SeekNative>>.fromAddress(
    _vtableEntry(stream, 5),
  ).asFunction<_SeekDart>();
  return fn(stream, offset, origin, newPos);
}

int comRelease(int object) {
  final fn = Pointer<NativeFunction<_ReleaseNative>>.fromAddress(
    _vtableEntry(object, 2),
  ).asFunction<_ReleaseDart>();
  return fn(object);
}
