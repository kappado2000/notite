import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notite/services/pin_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('format: exact 6 cifre', () {
    expect(PinLock.isValidFormat('482915'), isTrue);
    expect(PinLock.isValidFormat('48291'), isFalse);
    expect(PinLock.isValidFormat('48291a'), isFalse);
    expect(() => PinLock('u').set('123'), throwsArgumentError);
  });

  test('setare, verificare, amprentă (nu codul în clar)', () async {
    const storage = FlutterSecureStorage();
    final lock = PinLock('u1', storage: storage);
    expect(await lock.isSet(), isFalse);
    await lock.set('482915');
    expect(await lock.isSet(), isTrue);
    final all = await storage.readAll();
    expect(all.values.any((v) => v.contains('482915')), isFalse);
    expect(await lock.verify('482915'), PinResult.ok);
    expect(await lock.verify('482916'), PinResult.wrong);
    // Alt cont pe același dispozitiv are codul lui.
    expect(await PinLock('u2', storage: storage).isSet(), isFalse);
  });

  test(
    'blocare după 5 coduri greșite, resetare după parola contului',
    () async {
      final lock = PinLock('u1');
      await lock.set('482915');
      for (var i = 1; i < PinLock.maxAttempts; i++) {
        expect(await lock.verify('000000'), PinResult.wrong);
        expect(await lock.failedAttempts(), i);
      }
      expect(await lock.verify('000000'), PinResult.lockedOut);
      // Nici codul corect nu mai merge până la parola contului.
      expect(await lock.verify('482915'), PinResult.lockedOut);
      await lock.resetAttempts();
      expect(await lock.verify('482915'), PinResult.ok);
    },
  );

  test('un cod corect șterge greșelile anterioare; eliminare', () async {
    final lock = PinLock('u1');
    await lock.set('482915');
    await lock.verify('111111');
    await lock.verify('222222');
    expect(await lock.verify('482915'), PinResult.ok);
    expect(await lock.failedAttempts(), 0);
    await lock.clear();
    expect(await lock.isSet(), isFalse);
  });
}
