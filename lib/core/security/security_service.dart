import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sutura_vault/core/crypto/crypto_engine.dart';
import 'package:sutura_vault/core/database/database_helper.dart';

/// Abstraction de stockage sécurisé (permet les tests unitaires sans Keystore).
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Implémentation matérielle Android Keystore / iOS Keychain.
class HardwareKeyValueStore implements SecureKeyValueStore {
  HardwareKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Erreur métier levée si Master PIN == Decoy PIN (SEC-05).
class PinCollisionException implements Exception {
  const PinCollisionException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum PinAuthStatus {
  masterSuccess,
  decoySuccess,
  invalidPin,
  lockedOut,
}

class PinAuthResult {
  const PinAuthResult({
    required this.status,
    this.derivedKey,
    this.remainingLockoutSeconds = 0,
    this.failedAttempts = 0,
  });

  final PinAuthStatus status;
  final String? derivedKey;
  final int remainingLockoutSeconds;
  final int failedAttempts;
}

/// Service central du Bouclier : PIN Master, Decoy PIN, Biométrie/Zone Hostile,
/// Anti-Force Brute (Lockout) et Préférences de sécurité.
class SecurityService {
  SecurityService({
    SecureKeyValueStore? store,
    LocalAuthentication? localAuth,
    DateTime Function()? clock,
  })  : _store = store ?? HardwareKeyValueStore(),
        _localAuth = localAuth ?? LocalAuthentication(),
        _clock = clock ?? DateTime.now;

  static final SecurityService instance = SecurityService();

  static const String _kMasterPinHash = 'sutura_master_pin_hash';
  static const String _kDecoyPinHash = 'sutura_decoy_pin_hash';
  static const String _kBioMasterKey = 'sutura_bio_master_key';
  static const String _kBioUserAllowed = 'sutura_bio_user_allowed';
  static const String _kScramblePad = 'sutura_scramble_pad';
  static const String _kAutoLockSeconds = 'sutura_autolock_seconds';
  static const String _kClipboardSeconds = 'sutura_clipboard_seconds';
  static const String _kFailedAttempts = 'sutura_failed_attempts';
  static const String _kLockoutUntilMs = 'sutura_lockout_until_ms';

  static final RegExp _pin6Digits = RegExp(r'^\d{6}$');

  final SecureKeyValueStore _store;
  final LocalAuthentication _localAuth;
  final DateTime Function() _clock;

  /// Valide strictement qu'un PIN fait exactement 6 chiffres (SEC-03).
  static bool isValidPinFormat(String pin) => _pin6Digits.hasMatch(pin);

  /// Indique si le coffre a déjà été initialisé avec un Master PIN.
  Future<bool> isVaultInitialized() async {
    final hash = await _store.read(_kMasterPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Indique si un Decoy PIN (déni plausible) est configuré.
  Future<bool> hasDecoyPin() async {
    final hash = await _store.read(_kDecoyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// SEC-03 : Forge initiale du Master PIN personnel (zéro code par défaut).
  Future<String> initializeMasterPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('Le Master PIN doit contenir exactement 6 chiffres.');
    }
    final hash = CryptoEngine.hashPinForStorage(pin);
    final derivedKey = CryptoEngine.deriveDatabaseKey(pin);

    await _store.write(_kMasterPinHash, hash);
    await _store.write(_kFailedAttempts, '0');
    await _store.delete(_kLockoutUntilMs);
    // Par défaut : Mode Zone Hostile désactivé (false -> biométrie autorisable)
    await _store.write(_kBioUserAllowed, 'false');
    await _store.write(_kScramblePad, 'true');
    await _store.write(_kAutoLockSeconds, '30');
    await _store.write(_kClipboardSeconds, '30');

    return derivedKey;
  }

  /// SEC-05 : Configure ou met à jour le Decoy PIN avec interdiction
  /// mathématique de collision (`Master PIN != Decoy PIN`).
  Future<String> setDecoyPin(String decoyPin) async {
    if (!isValidPinFormat(decoyPin)) {
      throw ArgumentError('Le Decoy PIN doit contenir exactement 6 chiffres.');
    }

    final masterHash = await _store.read(_kMasterPinHash);
    final decoyHash = CryptoEngine.hashPinForStorage(decoyPin);

    if (masterHash != null &&
        CryptoEngine.constantTimeEquals(masterHash, decoyHash)) {
      throw const PinCollisionException(
        'Interdit : le Decoy PIN doit être strictement différent du Master PIN.',
      );
    }

    await _store.write(_kDecoyPinHash, decoyHash);
    return CryptoEngine.deriveDatabaseKey(decoyPin);
  }

  /// Supprime le Decoy PIN du Keystore.
  Future<void> clearDecoyPin() async {
    await _store.delete(_kDecoyPinHash);
  }

  /// SEC-07 : Retourne les secondes restantes de blocage (0 si débloqué).
  /// Assure le réarmement automatique garanti dès l'expiration du délai.
  Future<int> getRemainingLockoutSeconds() async {
    final raw = await _store.read(_kLockoutUntilMs);
    if (raw == null) return 0;

    final lockoutUntilMs = int.tryParse(raw) ?? 0;
    final nowMs = _clock().millisecondsSinceEpoch;
    if (nowMs >= lockoutUntilMs) {
      await _store.delete(_kLockoutUntilMs);
      return 0;
    }

    final remainingMs = lockoutUntilMs - nowMs;
    return (remainingMs / 1000).ceil();
  }

  /// Vérifie un PIN saisi, applique SEC-05 (Master/Decoy) et SEC-07 (Lockout).
  Future<PinAuthResult> verifyPin(String pin) async {
    final remaining = await getRemainingLockoutSeconds();
    if (remaining > 0) {
      final attempts = await getFailedAttempts();
      return PinAuthResult(
        status: PinAuthStatus.lockedOut,
        remainingLockoutSeconds: remaining,
        failedAttempts: attempts,
      );
    }

    if (!isValidPinFormat(pin)) {
      return _registerFailedAttempt();
    }

    final candidateHash = CryptoEngine.hashPinForStorage(pin);
    final masterHash = await _store.read(_kMasterPinHash);
    if (masterHash != null &&
        CryptoEngine.constantTimeEquals(masterHash, candidateHash)) {
      await _resetBruteForceCounter();
      return PinAuthResult(
        status: PinAuthStatus.masterSuccess,
        derivedKey: CryptoEngine.deriveDatabaseKey(pin),
      );
    }

    final decoyHash = await _store.read(_kDecoyPinHash);
    if (decoyHash != null &&
        CryptoEngine.constantTimeEquals(decoyHash, candidateHash)) {
      await _resetBruteForceCounter();
      return PinAuthResult(
        status: PinAuthStatus.decoySuccess,
        derivedKey: CryptoEngine.deriveDatabaseKey(pin),
      );
    }

    return _registerFailedAttempt();
  }

  Future<int> getFailedAttempts() async {
    final raw = await _store.read(_kFailedAttempts);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<PinAuthResult> _registerFailedAttempt() async {
    final nextAttempts = (await getFailedAttempts()) + 1;
    await _store.write(_kFailedAttempts, nextAttempts.toString());

    int lockoutSeconds = 0;
    if (nextAttempts >= 5) {
      lockoutSeconds = 120; // 2 minutes dès 5 échecs (SEC-07)
    } else if (nextAttempts == 3) {
      lockoutSeconds = 30; // 30 secondes au 3e échec (SEC-07)
    }

    if (lockoutSeconds > 0) {
      final untilMs =
          _clock().millisecondsSinceEpoch + (lockoutSeconds * 1000);
      await _store.write(_kLockoutUntilMs, untilMs.toString());
      return PinAuthResult(
        status: PinAuthStatus.lockedOut,
        remainingLockoutSeconds: lockoutSeconds,
        failedAttempts: nextAttempts,
      );
    }

    return PinAuthResult(
      status: PinAuthStatus.invalidPin,
      failedAttempts: nextAttempts,
    );
  }

  Future<void> _resetBruteForceCounter() async {
    await _store.write(_kFailedAttempts, '0');
    await _store.delete(_kLockoutUntilMs);
  }

  /// SEC-11 : Rotation isolée du Master PIN avec anti-collision Decoy & rekey.
  Future<void> changeMasterPin({
    required String currentPin,
    required String newPin,
  }) async {
    if (!isValidPinFormat(newPin)) {
      throw ArgumentError(
        'Le nouveau Master PIN doit contenir exactement 6 chiffres.',
      );
    }

    final masterHash = await _store.read(_kMasterPinHash);
    final currentHash = CryptoEngine.hashPinForStorage(currentPin);
    if (masterHash == null ||
        !CryptoEngine.constantTimeEquals(masterHash, currentHash)) {
      throw StateError('Master PIN actuel incorrect.');
    }

    final newHash = CryptoEngine.hashPinForStorage(newPin);
    final decoyHash = await _store.read(_kDecoyPinHash);
    if (decoyHash != null &&
        CryptoEngine.constantTimeEquals(decoyHash, newHash)) {
      throw const PinCollisionException(
        'Le nouveau Master PIN ne peut pas être identique au Decoy PIN.',
      );
    }

    final oldKey = CryptoEngine.deriveDatabaseKey(currentPin);
    final newKey = CryptoEngine.deriveDatabaseKey(newPin);

    // Rotation isolée SQLCipher (fermeture exclusive -> PRAGMA rekey)
    await DatabaseHelper.instance.rekeyVault(
      oldDerivedKey: oldKey,
      newDerivedKey: newKey,
      isDecoy: false,
    );

    await _store.write(_kMasterPinHash, newHash);

    // Si la biométrie est active, mettre à jour la clé scellée TEE
    if (await isBiometricsUserAllowed()) {
      await _store.write(_kBioMasterKey, newKey);
    }
  }

  // ---------------------------------------------------------------------------
  // SEC-06 : Biométrie TEE & Mode Zone Hostile
  // ---------------------------------------------------------------------------

  Future<bool> isBiometricsUserAllowed() async {
    final raw = await _store.read(_kBioUserAllowed);
    return raw == 'true';
  }

  /// Active ou désactive définitivement la biométrie (Mode Zone Hostile).
  /// Quand désactivé, la clé biométrique est immédiatement purgée du Keystore.
  Future<void> setBiometricsAllowed({
    required bool allowed,
    String? masterDerivedKey,
  }) async {
    if (!allowed) {
      await _store.write(_kBioUserAllowed, 'false');
      await _store.delete(_kBioMasterKey);
      return;
    }

    if (masterDerivedKey == null ||
        !CryptoEngine.isValidDerivedKey(masterDerivedKey)) {
      throw ArgumentError(
        'Clé Master requise pour activer le déverrouillage biométrique.',
      );
    }

    await _store.write(_kBioMasterKey, masterDerivedKey);
    await _store.write(_kBioUserAllowed, 'true');
  }

  Future<bool> isDeviceBiometricsAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Authentifie via TEE matériel. Retourne la clé DB Master si succès.
  Future<String?> authenticateWithBiometrics() async {
    if (!await isBiometricsUserAllowed()) return null;
    if (await getRemainingLockoutSeconds() > 0) return null;

    final sealedKey = await _store.read(_kBioMasterKey);
    if (sealedKey == null || !CryptoEngine.isValidDerivedKey(sealedKey)) {
      return null;
    }

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Déverrouiller Sutura Vault',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!authenticated) return null;
      await _resetBruteForceCounter();
      return sealedKey;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Préférences de sécurité (SEC-04, SEC-09, SEC-10)
  // ---------------------------------------------------------------------------

  Future<bool> isScramblePadEnabled() async {
    final raw = await _store.read(_kScramblePad);
    return raw != 'false';
  }

  Future<void> setScramblePadEnabled(bool enabled) =>
      _store.write(_kScramblePad, enabled.toString());

  Future<int> getAutoLockTimeoutSeconds() async {
    final raw = await _store.read(_kAutoLockSeconds);
    return int.tryParse(raw ?? '30') ?? 30;
  }

  Future<void> setAutoLockTimeoutSeconds(int seconds) =>
      _store.write(_kAutoLockSeconds, seconds.toString());

  Future<int> getClipboardPurgeSeconds() async {
    final raw = await _store.read(_kClipboardSeconds);
    return int.tryParse(raw ?? '30') ?? 30;
  }

  Future<void> setClipboardPurgeSeconds(int seconds) =>
      _store.write(_kClipboardSeconds, seconds.toString());

  /// Purge intégrale du Keystore matériel (utilisé par Panic Wipe — SEC-12).
  Future<void> wipeAllSecureKeys() => _store.deleteAll();
}