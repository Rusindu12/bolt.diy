// Persistence layer.
//
// * API keys/secrets  -> flutter_secure_storage (Android Keystore / iOS Keychain)
//   Keys are stored *per environment* so switching Testnet <-> Live keeps both
//   credential sets available.
// * UI preferences    -> shared_preferences (never anything sensitive).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_credentials.dart';
import '../models/binance_environment.dart';

class SettingsService {
  SettingsService({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ??
            FlutterSecureStorage(
              // EncryptedSharedPreferences stores an AES key inside the Android
              // Keystore, so the raw secret never lands in plain text.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _apiKeyPrefix = 'binance_api_key_';
  static const String _apiSecretPrefix = 'binance_api_secret_';

  static const String _prefEnvironment = 'binance.environment';
  static const String _prefDefaultSymbol = 'binance.default_symbol';
  static const String _prefReadOnlyMode = 'binance.read_only_mode';
  static const String _prefRiskAcknowledged = 'binance.risk.acknowledged';

  /// Used before the user picks a symbol.
  static const String fallbackSymbol = 'BTCUSDT';

  final FlutterSecureStorage _storage;

  SharedPreferences? _preferences;
  final Map<BinanceEnvironment, ApiCredentials?> _credentials =
      <BinanceEnvironment, ApiCredentials?>{};
  String? _lastStorageError;

  /// Loads preferences and warms the credential cache. Called once at startup.
  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    for (final BinanceEnvironment environment in BinanceEnvironment.values) {
      _credentials[environment] = await _readCredentials(environment);
    }
  }

  /// Non-fatal problem with the secure storage (e.g. a corrupted keystore entry
  /// that was wiped automatically). Surface it once in the UI.
  String? get lastStorageError => _lastStorageError;

  void clearStorageError() => _lastStorageError = null;

  // ------------------------------------------------------- credentials ------

  /// Cached credentials for [environment] (null when not configured).
  ApiCredentials? credentialsFor(BinanceEnvironment environment) =>
      _credentials[environment];

  bool hasCredentials(BinanceEnvironment environment) =>
      _credentials[environment]?.isValid ?? false;

  bool get hasAnyCredentials =>
      _credentials.values.any((ApiCredentials? value) => value?.isValid ?? false);

  /// Stores the key/secret pair in the platform keystore.
  Future<void> saveCredentials(ApiCredentials credentials) async {
    final String apiKey = credentials.apiKey.trim();
    final String secret = credentials.secret.trim();
    if (apiKey.isEmpty || secret.isEmpty) {
      throw ArgumentError('Both the API key and the secret are required.');
    }
    try {
      await _storage.write(
        key: '$_apiKeyPrefix${credentials.environment.name}',
        value: apiKey,
      );
      await _storage.write(
        key: '$_apiSecretPrefix${credentials.environment.name}',
        value: secret,
      );
      _credentials[credentials.environment] = credentials.copyWith(
        apiKey: apiKey,
        secret: secret,
      );
    } catch (error) {
      _lastStorageError = 'Could not save the credentials securely: $error';
      rethrow;
    }
  }

  /// Removes the credentials of a single environment.
  Future<void> clearCredentials(BinanceEnvironment environment) async {
    try {
      await _storage.delete(key: '$_apiKeyPrefix${environment.name}');
      await _storage.delete(key: '$_apiSecretPrefix${environment.name}');
    } catch (error) {
      _lastStorageError = 'Could not delete the stored credentials: $error';
    }
    _credentials[environment] = null;
  }

  /// Removes every stored credential (both environments).
  Future<void> clearAllCredentials() async {
    for (final BinanceEnvironment environment in BinanceEnvironment.values) {
      await clearCredentials(environment);
    }
  }

  Future<ApiCredentials?> _readCredentials(BinanceEnvironment environment) async {
    try {
      final String? key =
          await _storage.read(key: '$_apiKeyPrefix${environment.name}');
      final String? secret =
          await _storage.read(key: '$_apiSecretPrefix${environment.name}');
      final String apiKey = (key ?? '').trim();
      final String apiSecret = (secret ?? '').trim();
      if (apiKey.isEmpty || apiSecret.isEmpty) {
        return null;
      }
      return ApiCredentials(
        apiKey: apiKey,
        secret: apiSecret,
        environment: environment,
      );
    } catch (error) {
      // A decryption failure would otherwise break the whole app start, so the
      // unreadable entry is wiped and the user is asked to paste the keys again.
      _lastStorageError =
          'Stored API keys could not be read and were cleared. Please add them '
          'again. ($error)';
      try {
        await _storage.delete(key: '$_apiKeyPrefix${environment.name}');
        await _storage.delete(key: '$_apiSecretPrefix${environment.name}');
      } catch (_) {
        // Ignore: the important part is that the app keeps starting.
      }
      return null;
    }
  }

  // ------------------------------------------------------ preferences -------

  /// Active environment; defaults to Testnet so the app never starts live.
  BinanceEnvironment get environment => BinanceEnvironment.fromStorage(
        _preferences?.getString(_prefEnvironment),
      );

  Future<void> setEnvironment(BinanceEnvironment environment) async {
    await _preferences?.setString(_prefEnvironment, environment.name);
  }

  /// Symbol selected by the user, e.g. `BTCUSDT`.
  String get defaultSymbol =>
      _preferences?.getString(_prefDefaultSymbol) ?? fallbackSymbol;

  Future<void> setDefaultSymbol(String symbol) async {
    final String normalized = symbol.toUpperCase().trim();
    if (normalized.isEmpty) {
      return;
    }
    await _preferences?.setString(_prefDefaultSymbol, normalized);
  }

  /// Read-only mode: the user skipped the API key step and only browses prices.
  bool get readOnlyMode => _preferences?.getBool(_prefReadOnlyMode) ?? false;

  Future<void> setReadOnlyMode(bool value) async {
    await _preferences?.setBool(_prefReadOnlyMode, value);
  }

  /// The user confirmed the live-trading risk disclaimer.
  bool get riskAcknowledged =>
      _preferences?.getBool(_prefRiskAcknowledged) ?? false;

  Future<void> setRiskAcknowledged(bool value) async {
    await _preferences?.setBool(_prefRiskAcknowledged, value);
  }
}
