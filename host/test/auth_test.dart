import 'package:mirror_host/auth.dart';
import 'package:test/test.dart';

void main() {
  test('kode pairing berformat XXXX-XXXX-XXXX tanpa karakter ambigu', () {
    final code = generatePairCode();
    expect(
      code,
      matches(RegExp(r'^[A-HJKMNP-Z2-9]{4}(-[A-HJKMNP-Z2-9]{4}){2}$')),
    );
  });

  test('MAC mengabaikan huruf kecil dan tanda hubung', () {
    expect(computeMac('abcd-efgh', 'n'), computeMac('ABCDEFGH', 'n'));
  });

  test('MAC cocok dengan HMAC-SHA256 acuan yang dihitung Python', () {
    expect(
      computeMac('abcd-efgh', 'nonce'),
      '70397259b7b69fca4789e24ef544d611f5c42eac22192e72830c3fce86634cce',
    );
  });

  test('MAC berubah bila nonce atau kode berbeda', () {
    expect(computeMac('AAAA', 'n1'), isNot(computeMac('AAAA', 'n2')));
    expect(computeMac('AAAA', 'n1'), isNot(computeMac('BBBB', 'n1')));
  });

  test('constantTimeEquals', () {
    expect(constantTimeEquals('abc', 'abc'), isTrue);
    expect(constantTimeEquals('abc', 'abd'), isFalse);
    expect(constantTimeEquals('abc', 'ab'), isFalse);
  });

  test('throttle mengunci setelah 5 gagal lalu terbuka lagi', () {
    var now = DateTime(2026);
    final throttle = AuthThrottle(clock: () => now);
    for (var i = 0; i < 4; i++) {
      throttle.recordFailure('1.2.3.4');
    }
    expect(throttle.isLocked('1.2.3.4'), isFalse);
    throttle.recordFailure('1.2.3.4');
    expect(throttle.isLocked('1.2.3.4'), isTrue);
    expect(throttle.isLocked('5.6.7.8'), isFalse);
    now = now.add(const Duration(seconds: 61));
    expect(throttle.isLocked('1.2.3.4'), isFalse);
  });
}
