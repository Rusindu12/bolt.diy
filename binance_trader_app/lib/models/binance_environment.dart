// Binance Spot environment definitions (REST + WebSocket endpoints).
//
// Testnet and Live share the same REST/WS API surface, they only differ by host
// name and by the fact that Testnet uses play money. Everything in the app is
// written against this enum so a single switch flips the whole app.

enum BinanceEnvironment {
  testnet(
    label: 'Binance Testnet',
    shortLabel: 'Testnet',
    description: 'Paper trading with virtual funds. Perfect for testing.',
    restBaseUrl: 'https://testnet.binance.vision',
    webSocketBaseUrl: 'wss://stream.testnet.binance.vision',
    keyManagementUrl: 'https://testnet.binance.vision/',
    keyManagementLabel: 'testnet.binance.vision',
    isLive: false,
  ),
  live(
    label: 'Binance Live',
    shortLabel: 'Live',
    description: 'Real money. Every order moves real funds.',
    restBaseUrl: 'https://api.binance.com',
    webSocketBaseUrl: 'wss://stream.binance.com:9443',
    keyManagementUrl: 'https://www.binance.com/en/my/settings/api-management',
    keyManagementLabel: 'Binance API Management',
    isLive: true,
  );

  const BinanceEnvironment({
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.restBaseUrl,
    required this.webSocketBaseUrl,
    required this.keyManagementUrl,
    required this.keyManagementLabel,
    required this.isLive,
  });

  /// Human readable name shown in the UI.
  final String label;

  /// Compact name used in badges and chips.
  final String shortLabel;

  /// One line explanation of what trading here means.
  final String description;

  /// REST root, e.g. `https://api.binance.com`.
  final String restBaseUrl;

  /// WebSocket root, e.g. `wss://stream.binance.com:9443`.
  final String webSocketBaseUrl;

  /// Where the user creates API keys for this environment.
  final String keyManagementUrl;

  /// Display text for [keyManagementUrl].
  final String keyManagementLabel;

  /// True for the production environment with real funds.
  final bool isLive;

  /// Single trade stream for one symbol, e.g.
  /// `wss://stream.binance.com:9443/ws/btcusdt@trade`.
  String tradeStreamUrl(String symbol) =>
      '$webSocketBaseUrl/ws/${symbol.toLowerCase()}@trade';

  /// Combined stream URL, e.g.
  /// `wss://stream.binance.com:9443/stream?streams=btcusdt@trade/btcusdt@ticker`.
  /// Kept for future multi-stream use (depth, klines, user data stream).
  String combinedStreamUrl(List<String> streamNames) =>
      '$webSocketBaseUrl/stream?streams=${streamNames.join('/')}';

  /// Parses a persisted value. Unknown values fall back to [testnet] so the app
  /// never accidentally starts in live mode because of corrupted storage.
  static BinanceEnvironment fromStorage(String? value) {
    if (value == null) {
      return BinanceEnvironment.testnet;
    }
    for (final environment in BinanceEnvironment.values) {
      if (environment.name == value) {
        return environment;
      }
    }
    return BinanceEnvironment.testnet;
  }
}
