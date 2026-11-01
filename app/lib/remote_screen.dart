import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'mirror_client.dart';
import 'protocol.dart';
import 'text_diff.dart';
import 'touch_interpreter.dart';
import 'viewport.dart';

const _presetKey = 'preset';
const _modeKey = 'mode';
const _touchpadSensitivity = 2.0;
const _scrollSensitivity = 3.0;
const _reconnectAttempts = 15;
const _reconnectDelay = Duration(seconds: 2);

// Isi awal kotak ketik agar Backspace tetap terdeteksi saat kotak "kosong".
const _inputSentinel = ' ';
const _inputResetLength = 64;

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.params, required this.client});

  final ConnectionParams params;
  final MirrorClient client;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> implements TouchActions {
  late MirrorClient _client = widget.client;
  late final TouchInterpreter _touch = TouchInterpreter(this);
  final Viewport _viewport = Viewport();
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final FocusNode _keyboardFocus = FocusNode();
  final TextEditingController _keyboardText = TextEditingController(
    text: _inputSentinel,
  );

  ui.Image? _image;
  QualityPreset _preset = QualityPreset.seimbang;
  String _lastText = _inputSentinel;
  Offset _moveRemainder = Offset.zero;
  Offset _scrollRemainder = Offset.zero;
  bool _menuOpen = false;
  bool _keysOpen = false;
  bool _reconnecting = false;
  bool _disconnected = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(WakelockPlus.enable());
    _attach(_client);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _preset =
          QualityPreset.values.asNameMap()[prefs.getString(_presetKey)] ??
          QualityPreset.seimbang;
      _touch.mode =
          TouchMode.values.asNameMap()[prefs.getString(_modeKey)] ??
          TouchMode.touchpad;
    });
    _client.setQuality(_preset);
  }

  void _attach(MirrorClient client) {
    client.onFrame = _onFrame;
    client.onClosed = () => unawaited(_reconnect());
  }

  void _onFrame(MirrorFrame frame) {
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    _image?.dispose();
    _image = frame.image;
    _viewport.image = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    if (_touch.mode == TouchMode.touchpad) {
      _viewport.followCursor(frame.cursor);
    }
    _repaint.value++;
  }

  Future<void> _reconnect() async {
    if (_leaving || !mounted) return;
    setState(() {
      _reconnecting = true;
      _disconnected = false;
    });
    for (var attempt = 0; attempt < _reconnectAttempts; attempt++) {
      await Future<void>.delayed(_reconnectDelay);
      if (_leaving || !mounted) return;
      try {
        final client = await MirrorClient.connect(widget.params);
        if (_leaving || !mounted) {
          client.close();
          return;
        }
        _client = client;
        _attach(client);
        client.setQuality(_preset);
        setState(() => _reconnecting = false);
        return;
      } on MirrorConnectException catch (e) {
        if (e.badCode) break;
      }
    }
    if (!mounted) return;
    setState(() {
      _reconnecting = false;
      _disconnected = true;
    });
  }

  @override
  void dispose() {
    _leaving = true;
    _client.close();
    _image?.dispose();
    _repaint.dispose();
    _keyboardFocus.dispose();
    _keyboardText.dispose();
    unawaited(WakelockPlus.disable());
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // TouchActions

  @override
  void moveCursorBy(Offset delta) {
    final total = delta * _touchpadSensitivity + _moveRemainder;
    final dx = total.dx.truncate();
    final dy = total.dy.truncate();
    _moveRemainder = total - Offset(dx.toDouble(), dy.toDouble());
    if (dx != 0 || dy != 0) _client.moveBy(dx, dy);
  }

  @override
  void moveCursorTo(Offset viewPoint) =>
      _client.moveTo(_viewport.toNormalized(viewPoint));

  @override
  void mouseButton(String name, bool down) => _client.button(name, down);

  @override
  void scrollBy(Offset delta) {
    if (_touch.mode == TouchMode.direct && _viewport.isZoomed) {
      _viewport.panBy(delta);
      _repaint.value++;
      return;
    }
    final total = delta * _scrollSensitivity + _scrollRemainder;
    final dy = total.dy.truncate();
    final dx = total.dx.truncate();
    _scrollRemainder = total - Offset(dx.toDouble(), dy.toDouble());
    // Scroll natural seperti touchpad: konten mengikuti arah jari.
    if (dx != 0 || dy != 0) _client.wheel(dy, -dx);
  }

  @override
  void zoomBy(double factor, Offset focal) {
    _viewport.zoomAt(factor, focal);
    _repaint.value++;
  }

  // Keyboard HP

  void _onKeyboardChanged(String value) {
    final edit = diffText(_lastText, value);
    for (var i = 0; i < edit.backspaces; i++) {
      _client.combo(const [Vk.backspace]);
    }
    if (edit.inserted.isNotEmpty) _client.text(edit.inserted);
    if (value.isEmpty || value.length > _inputResetLength) {
      _keyboardText.value = const TextEditingValue(
        text: _inputSentinel,
        selection: TextSelection.collapsed(offset: _inputSentinel.length),
      );
      _lastText = _inputSentinel;
    } else {
      _lastText = value;
    }
  }

  void _toggleKeyboard() {
    if (_keyboardFocus.hasFocus) {
      _keyboardFocus.unfocus();
    } else {
      _keyboardFocus.requestFocus();
    }
  }

  Future<void> _setPreset(QualityPreset preset) async {
    setState(() => _preset = preset);
    _client.setQuality(preset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, preset.name);
  }

  Future<void> _toggleMode() async {
    final next = _touch.mode == TouchMode.touchpad
        ? TouchMode.direct
        : TouchMode.touchpad;
    setState(() => _touch.mode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, next.name);
  }

  @override
  Widget build(BuildContext context) {
    final isTouchpad = _touch.mode == TouchMode.touchpad;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport.view = constraints.biggest;
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) =>
                      _touch.down(e.pointer, e.localPosition, e.timeStamp),
                  onPointerMove: (e) =>
                      _touch.move(e.pointer, e.localPosition, e.timeStamp),
                  onPointerUp: (e) =>
                      _touch.up(e.pointer, e.localPosition, e.timeStamp),
                  onPointerCancel: (e) => _touch.cancel(e.pointer),
                  child: CustomPaint(
                    painter: _ScreenPainter(this),
                    size: Size.infinite,
                  ),
                );
              },
            ),
          ),
          // Kotak tak terlihat yang menerima ketikan dari keyboard HP.
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: TextField(
                focusNode: _keyboardFocus,
                controller: _keyboardText,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _onKeyboardChanged,
                onSubmitted: (_) => _client.combo(const [Vk.enter]),
                onEditingComplete: () {},
              ),
            ),
          ),
          if (_keysOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _KeyBar(onCombo: (keys) => _client.combo(keys)),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: _Toolbar(
                open: _menuOpen,
                isTouchpad: isTouchpad,
                keysOpen: _keysOpen,
                preset: _preset,
                onToggleMenu: () => setState(() => _menuOpen = !_menuOpen),
                onToggleMode: _toggleMode,
                onToggleKeyboard: _toggleKeyboard,
                onToggleKeys: () => setState(() => _keysOpen = !_keysOpen),
                onResetZoom: () {
                  _viewport.reset();
                  _repaint.value++;
                },
                onPreset: _setPreset,
                onDisconnect: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          if (_reconnecting || _disconnected)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: _disconnected
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Koneksi ke laptop terputus'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => unawaited(_reconnect()),
                              child: const Text('Hubungkan ulang'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Kembali'),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Menghubungkan ulang...'),
                          ],
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScreenPainter extends CustomPainter {
  _ScreenPainter(this.state) : super(repaint: state._repaint);

  final _RemoteScreenState state;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    final image = state._image;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      state._viewport.imageRect,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_ScreenPainter oldDelegate) => false;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.open,
    required this.isTouchpad,
    required this.keysOpen,
    required this.preset,
    required this.onToggleMenu,
    required this.onToggleMode,
    required this.onToggleKeyboard,
    required this.onToggleKeys,
    required this.onResetZoom,
    required this.onPreset,
    required this.onDisconnect,
  });

  final bool open;
  final bool isTouchpad;
  final bool keysOpen;
  final QualityPreset preset;
  final VoidCallback onToggleMenu;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleKeyboard;
  final VoidCallback onToggleKeys;
  final VoidCallback onResetZoom;
  final ValueChanged<QualityPreset> onPreset;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (open) ...[
            IconButton(
              tooltip: isTouchpad ? 'Mode: touchpad' : 'Mode: sentuh langsung',
              onPressed: onToggleMode,
              icon: Icon(isTouchpad ? Icons.mouse : Icons.touch_app),
            ),
            IconButton(
              tooltip: 'Keyboard',
              onPressed: onToggleKeyboard,
              icon: const Icon(Icons.keyboard),
            ),
            IconButton(
              tooltip: 'Tombol khusus',
              isSelected: keysOpen,
              onPressed: onToggleKeys,
              icon: const Icon(Icons.keyboard_command_key),
            ),
            IconButton(
              tooltip: 'Reset zoom',
              onPressed: onResetZoom,
              icon: const Icon(Icons.fit_screen),
            ),
            PopupMenuButton<QualityPreset>(
              tooltip: 'Kualitas',
              icon: const Icon(Icons.tune),
              initialValue: preset,
              onSelected: onPreset,
              itemBuilder: (_) => [
                for (final item in QualityPreset.values)
                  PopupMenuItem(value: item, child: Text(item.label)),
              ],
            ),
            IconButton(
              tooltip: 'Putuskan',
              onPressed: onDisconnect,
              icon: const Icon(Icons.power_settings_new),
            ),
          ],
          IconButton(
            tooltip: open ? 'Tutup menu' : 'Buka menu',
            onPressed: onToggleMenu,
            icon: Icon(open ? Icons.close : Icons.more_horiz),
          ),
        ],
      ),
    );
  }
}

class _KeyBar extends StatelessWidget {
  const _KeyBar({required this.onCombo});

  final ValueChanged<List<int>> onCombo;

  static const _keys = <(String, List<int>)>[
    ('Esc', [Vk.esc]),
    ('Tab', [Vk.tab]),
    ('Alt+Tab', [Vk.alt, Vk.tab]),
    ('Win', [Vk.win]),
    ('Win+D', [Vk.win, Vk.keyD]),
    ('Ctrl+C', [Vk.ctrl, Vk.keyC]),
    ('Ctrl+V', [Vk.ctrl, Vk.keyV]),
    ('Ctrl+Z', [Vk.ctrl, Vk.keyZ]),
    ('Del', [Vk.delete]),
    ('F5', [Vk.f5]),
    ('←', [Vk.left]),
    ('↑', [Vk.up]),
    ('↓', [Vk.down]),
    ('→', [Vk.right]),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.75),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            for (final (label, keys) in _keys)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: OutlinedButton(
                  onPressed: () => onCombo(keys),
                  child: Text(label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
