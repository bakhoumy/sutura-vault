/// Garde de session anti-coupure pour actions externes autorisées (SEC-09).
///
/// Utilise un compteur de références pour supporter sans risque plusieurs
/// opérations imbriquées (caméra, galerie, partage natif).
class SecurityGuard {
  SecurityGuard._internal();
  static final SecurityGuard instance = SecurityGuard._internal();

  int _activeProtectedOps = 0;
  DateTime? _backgroundTimestamp;

  bool get isExternalActionInProgress => _activeProtectedOps > 0;

  /// Exécute une action externe (ex: image_picker, share_plus) sans déclencher
  /// le verrouillage automatique au retour dans l'application.
  Future<T> runProtected<T>(Future<T> Function() action) async {
    _activeProtectedOps++;
    try {
      return await action();
    } finally {
      if (_activeProtectedOps > 0) {
        _activeProtectedOps--;
      }
      _backgroundTimestamp = null;
    }
  }

  /// Appelé quand l'application passe en arrière-plan (`paused` / `hidden`).
  void markBackgrounded() {
    if (isExternalActionInProgress) return;
    _backgroundTimestamp ??= DateTime.now();
  }

  /// Indique si le coffre doit être verrouillé au retour au premier plan.
  bool shouldLockOnResume({required int autoLockTimeoutSeconds}) {
    if (isExternalActionInProgress) {
      _backgroundTimestamp = null;
      return false;
    }
    final pausedAt = _backgroundTimestamp;
    _backgroundTimestamp = null;
    if (pausedAt == null) return false;

    if (autoLockTimeoutSeconds <= 0) {
      return true; // Verrouillage instantané (0s)
    }

    final elapsed = DateTime.now().difference(pausedAt).inSeconds;
    return elapsed >= autoLockTimeoutSeconds;
  }

  void reset() {
    _activeProtectedOps = 0;
    _backgroundTimestamp = null;
  }
}