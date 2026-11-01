@TestOn('windows')
library;

import 'dart:ffi';

import 'package:mirror_host/input_injector.dart';
import 'package:test/test.dart';

const _vkF24 = 0x87; // Tombol yang tidak dipakai aplikasi mana pun.

final _getAsyncKeyState = DynamicLibrary.open(
  'user32.dll',
).lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');

bool _isDown(int vk) => _getAsyncKeyState(vk) & 0x8000 != 0;

void main() {
  test('key mengubah status tombol dan releaseAll melepasnya', () {
    final input = InputInjector();
    expect(_isDown(_vkF24), isFalse);

    input.key(_vkF24, true);
    expect(_isDown(_vkF24), isTrue);

    input.releaseAll();
    expect(_isDown(_vkF24), isFalse);
  });

  test('vk di luar rentang diabaikan', () {
    final input = InputInjector();
    input.key(0, true);
    input.key(999, true);
    input.releaseAll();
  });
}
