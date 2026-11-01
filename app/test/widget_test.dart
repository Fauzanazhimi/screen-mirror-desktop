import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_remote/connect_screen.dart';
import 'package:mirror_remote/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('form koneksi menolak isian kosong', (tester) async {
    await tester.pumpWidget(const MirrorApp());
    await tester.pumpAndSettle();

    expect(find.byType(ConnectScreen), findsOneWidget);
    await tester.tap(find.text('Hubungkan'));
    await tester.pump();

    expect(find.text('Isi alamat laptop'), findsOneWidget);
    expect(find.text('Isi kode pairing'), findsOneWidget);
  });

  testWidgets('alamat dan kode tersimpan dimuat ulang', (tester) async {
    SharedPreferences.setMockInitialValues({
      'host': '100.64.0.1',
      'port': 9000,
      'code': 'AAAA-BBBB-CCCC',
    });
    await tester.pumpWidget(const MirrorApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '100.64.0.1'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '9000'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'AAAA-BBBB-CCCC'),
      findsOneWidget,
    );
  });
}
