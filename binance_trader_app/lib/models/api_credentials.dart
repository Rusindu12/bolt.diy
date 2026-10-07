// Value object holding a Binance API key/secret pair for one environment.

import 'binance_environment.dart';

/// An API key + secret belonging to a specific [BinanceEnvironment].
///
/// Credentials are stored per environment so switching Testnet <-> Live never
/// forces the user to retype the other environment's keys.
class ApiCredentials {
  const ApiCredentials({
    required this.apiKey,
    required this.secret,
    required this.environment,
  });

  final String apiKey;
  final String secret;
  final BinanceEnvironment environment;

  /// Both parts present (whitespace is trimmed by the storage layer).
  bool get isValid => apiKey.isNotEmpty && secret.isNotEmpty;

  /// Masked key for display: `A1B2...WXYZ`.
  String get maskedKey {
    if (apiKey.length <= 8) {
      return apiKey;
    }
    return '${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}';
  }

  ApiCredentials copyWith({String? apiKey, String? secret}) => ApiCredentials(
        apiKey: apiKey ?? this.apiKey,
        secret: secret ?? this.secret,
        environment: environment,
      );

  @override
  String toString() => 'ApiCredentials(${environment.name}, $maskedKey)';
}
