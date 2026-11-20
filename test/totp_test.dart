import 'package:flutter_test/flutter_test.dart';
import 'package:notite/services/totp.dart';

void main() {
  // vectorii oficiali RFC 6238 (SHA1, 8 cifre, cheia „12345678901234567890”)
  final t = Totp.parse(
    'otpauth://totp/Test:ana?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8',
  )!;
  DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

  test('coduri RFC 6238', () {
    expect(t.code(at(59)), '94287082');
    expect(t.code(at(1111111109)), '07081804');
    expect(t.code(at(1234567890)), '89005924');
    expect(t.code(at(2000000000)), '69279037');
    // contor peste 32 de biți (partea de sus a numărului)
    expect(t.code(at(20000000000)), '65353130');
  });
}
