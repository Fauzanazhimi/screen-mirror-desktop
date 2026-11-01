import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mirror_client.dart';
import 'protocol.dart';
import 'remote_screen.dart';

const _hostKey = 'host';
const _portKey = 'port';
const _codeKey = 'code';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '$defaultPort');
  final _code = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _host.text = prefs.getString(_hostKey) ?? '';
    _port.text = '${prefs.getInt(_portKey) ?? defaultPort}';
    _code.text = prefs.getString(_codeKey) ?? '';
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    final params = ConnectionParams(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      code: _code.text,
    );
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final client = await MirrorClient.connect(params);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, params.host);
      await prefs.setInt(_portKey, params.port);
      await prefs.setString(_codeKey, params.code);
      if (!mounted) {
        client.close();
        return;
      }
      setState(() => _connecting = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RemoteScreen(params: params, client: client),
        ),
      );
    } on MirrorConnectException catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.screenshot_monitor,
                      size: 56,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mirror Remote',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Jalankan mirror_host di laptop, lalu masukkan alamat '
                      'dan kode yang tampil di sana.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Alamat laptop',
                        hintText: '100.x.y.z atau 192.168.x.x',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Isi alamat laptop'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final port = int.tryParse(value?.trim() ?? '');
                        return port == null || port < 1 || port > 65535
                            ? 'Port 1-65535'
                            : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _code,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Kode pairing',
                        hintText: 'XXXX-XXXX-XXXX',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => normalizeCode(value ?? '').isEmpty
                          ? 'Isi kode pairing'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _connecting ? null : _connect,
                      icon: _connecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(
                        _connecting ? 'Menghubungkan...' : 'Hubungkan',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
