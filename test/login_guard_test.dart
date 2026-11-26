import 'package:flutter_test/flutter_test.dart';
import 'package:kiosco_app/services/login_guard_local.dart';

void main() {
  group('lockDurationFor', () {
    test('los dos primeros fallos no bloquean', () {
      expect(lockDurationFor(0), Duration.zero);
      expect(lockDurationFor(1), Duration.zero);
      expect(lockDurationFor(2), Duration.zero);
    });

    test('al tercer fallo bloquea 30 segundos', () {
      expect(lockDurationFor(3), const Duration(seconds: 30));
      expect(lockDurationFor(4), const Duration(seconds: 30));
    });

    test('desde el quinto fallo bloquea 2 minutos', () {
      expect(lockDurationFor(5), const Duration(minutes: 2));
      expect(lockDurationFor(50), const Duration(minutes: 2));
    });
  });
}
