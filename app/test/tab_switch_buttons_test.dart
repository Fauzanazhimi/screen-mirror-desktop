import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_remote/protocol.dart';
import 'package:mirror_remote/tab_switch_buttons.dart';

void main() {
  Future<List<List<int>>> tapButton(WidgetTester tester, IconData icon) async {
    final sent = <List<int>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TabSwitchButtons(onCombo: sent.add)),
      ),
    );
    await tester.tap(find.byIcon(icon));
    return sent;
  }

  testWidgets('tombol kanan mengirim Ctrl+Tab', (tester) async {
    expect(await tapButton(tester, Icons.chevron_right), [
      [Vk.ctrl, Vk.tab],
    ]);
  });

  testWidgets('tombol kiri mengirim Ctrl+Shift+Tab', (tester) async {
    expect(await tapButton(tester, Icons.chevron_left), [
      [Vk.ctrl, Vk.shift, Vk.tab],
    ]);
  });

  test('kode tombol sesuai virtual-key Windows', () {
    expect(nextTabKeys, [0x11, 0x09]);
    expect(previousTabKeys, [0x11, 0x10, 0x09]);
  });
}
