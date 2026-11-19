import 'package:flutter/material.dart';

import 'protocol.dart';

/// Shortcut standar Windows untuk pindah tab di browser, VS Code, File
/// Explorer, dan sebagian besar aplikasi bertab.
const nextTabKeys = [Vk.ctrl, Vk.tab];
const previousTabKeys = [Vk.ctrl, Vk.shift, Vk.tab];

/// Tombol yang selalu tampil untuk pindah ke tab sebelumnya atau berikutnya
/// tanpa perlu menggeser kursor ke deretan tab.
class TabSwitchButtons extends StatelessWidget {
  const TabSwitchButtons({super.key, required this.onCombo});

  final ValueChanged<List<int>> onCombo;

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
          TextButton.icon(
            onPressed: () => onCombo(previousTabKeys),
            icon: const Icon(Icons.chevron_left),
            label: const Text('Tab'),
          ),
          Container(width: 1, height: 24, color: Colors.white24),
          TextButton.icon(
            onPressed: () => onCombo(nextTabKeys),
            icon: const Icon(Icons.chevron_right),
            iconAlignment: IconAlignment.end,
            label: const Text('Tab'),
          ),
        ],
      ),
    );
  }
}
