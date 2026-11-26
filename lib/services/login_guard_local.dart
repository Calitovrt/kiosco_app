import 'package:shared_preferences/shared_preferences.dart';

/// Cuánto bloquear según la cantidad de intentos fallidos.
///
/// Misma política que el login del alumno: 3 fallos -> 30s, 5 o más -> 2 min.
Duration lockDurationFor(int failures) {
  if (failures >= 5) return const Duration(minutes: 2);
  if (failures >= 3) return const Duration(seconds: 30);
  return Duration.zero;
}

/// Bloqueo por intentos fallidos del login de administrador.
///
/// Vive del lado del cliente a propósito: el login de admin usa
/// `signInWithPassword` de Supabase Auth, que no pasa por ninguna RPC
/// nuestra, así que no hay dónde contar los intentos en la base.
///
/// No reemplaza el rate limit de GoTrue (hay que configurarlo en el panel
/// de Supabase), pero frena el tecleo repetido y sobrevive al reinicio de
/// la app porque se guarda en SharedPreferences.
class LoginGuardLocal {
  LoginGuardLocal._();

  static final LoginGuardLocal instance = LoginGuardLocal._();

  static const _kFails = 'admin_login_fails';
  static const _kLockedUntil = 'admin_login_locked_until';

  Future<int> failures() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kFails) ?? 0;
  }

  Future<Duration> remainingLock() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kLockedUntil);
    if (until == null) return Duration.zero;
    final diff =
        DateTime.fromMillisecondsSinceEpoch(until).difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Registra un fallo y devuelve cuánto quedó bloqueado (0 si todavía no).
  Future<Duration> registerFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final fails = (prefs.getInt(_kFails) ?? 0) + 1;
    final lock = lockDurationFor(fails);
    await prefs.setInt(_kFails, fails);
    if (lock > Duration.zero) {
      await prefs.setInt(
        _kLockedUntil,
        DateTime.now().add(lock).millisecondsSinceEpoch,
      );
    }
    return lock;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFails);
    await prefs.remove(_kLockedUntil);
  }
}
