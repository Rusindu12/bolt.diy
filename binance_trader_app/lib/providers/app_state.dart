// Global application state.
//
// Owns everything that more than one screen needs:
//   * the setup flow (credentials, read-only mode, risk acknowledgement),
//   * the active environment (Testnet / Live) and the active symbol,
//   * the WebSocket price stream (ticks, status, recent trade tape),
//   * the cached account snapshot (balances + key permissions),
//   * the live ticker via a `ValueNotifier` so price ticks only rebuild the
//     price widget instead of the whole tree.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account_balance.dart';
import '../models/api_credentials.dart';
import '../models/binance_environment.dart';
import '../models/market_tick.dart';
import '../models/symbol_info.dart';
import '../services/binance_service.dart';
import '../services/market_stream_service.dart';
import '../services/settings_service.dart';
import '../utils/api_exceptions.dart';

/// Where the app is in its high level flow.
enum AppStatus {
  /// Reading settings / restoring the session.
  initializing,

  /// The user still has to provide API keys (or choose read-only mode).
  setupRequired,

  /// Fully usable (either trading enabled or read-only browsing).
  ready,
}

/// Single source of truth for the trading session.
class AppState extends ChangeNotifier {
  AppState({
    required SettingsService settings,
    required BinanceService binance,
    required MarketStreamService stream,
  })  : _settings = settings,
        _binance = binance,
        _stream = stream;

  /// How many ticks are kept for the "live tape" list.
  static const int _tradeTapeLength = 30;

  /// Tick bursts (BTCUSDT can print dozens per second) are coalesced into at
  /// most two list refreshes per second.
  static const Duration _notifyThrottle = Duration(milliseconds: 500);

  /// How often the 24h statistics are refreshed while the app is open.
  static const Duration _statsRefreshInterval = Duration(seconds: 30);

  final SettingsService _settings;
  final BinanceService _binance;
  final MarketStreamService _stream;

  /// Latest trade tick. Widgets can listen to this directly to update a price
  /// without rebuilding their whole subtree.
  final ValueNotifier<MarketTick?> lastTick = ValueNotifier<MarketTick?>(null);

  final List<MarketTick> _recentTrades = <MarketTick>[];

  AppStatus _status = AppStatus.initializing;
  BinanceEnvironment _environment = BinanceEnvironment.testnet;
  String _symbol = SettingsService.fallbackSymbol;
  String? _startupError;

  List<SymbolInfo> _symbols = <SymbolInfo>[];
  bool _symbolsLoading = false;
  String? _symbolsError;

  AccountSnapshot _account = AccountSnapshot.empty;
  bool _accountLoading = false;
  String? _accountError;
  DateTime? _accountFetchedAt;

  MarketStreamStatus _streamStatus = MarketStreamStatus.idle;
  String? _streamError;
  TickerStats? _tickerStats;
  bool _tickerLoading = false;

  bool _busy = false;
  String? _actionError;
  bool _disposed = false;
  int _revision = 0;

  StreamSubscription<MarketTick>? _tickSubscription;
  StreamSubscription<MarketStreamStatus>? _statusSubscription;
  Timer? _notifyTimer;
  Timer? _statsTimer;
  bool _pendingNotify = false;

  // ------------------------------------------------------------- getters ----

  AppStatus get status => _status;

  bool get isReady => _status == AppStatus.ready;

  bool get isInitializing => _status == AppStatus.initializing;

  /// Fatal-ish startup problem (e.g. unreadable keystore) shown as a banner.
  String? get startupError => _startupError;

  BinanceEnvironment get environment => _environment;

  /// Active trading pair, e.g. `BTCUSDT`.
  String get symbol => _symbol;

  /// Base asset of [symbol] (`BTC`).
  String get baseAsset => _splitSymbol().$1;

  /// Quote asset of [symbol] (`USDT`).
  String get quoteAsset => _splitSymbol().$2;

  /// Exchange filters for [symbol] when `exchangeInfo` has been loaded.
  SymbolInfo? get symbolInfo => SymbolInfo.find(_symbols, _symbol);

  List<SymbolInfo> get symbols => _symbols;

  bool get symbolsLoading => _symbolsLoading;

  String? get symbolsError => _symbolsError;

  AccountSnapshot get account => _account;

  List<AccountBalance> get balances => _account.balances;

  AccountPermissions? get permissions =>
      _account.fetchedAt == null ? null : _account.permissions;

  bool get accountLoading => _accountLoading;

  String? get accountError => _accountError;

  DateTime? get accountFetchedAt => _accountFetchedAt;

  MarketStreamStatus get streamStatus => _streamStatus;

  String? get streamError => _streamError;

  TickerStats? get tickerStats => _tickerStats;

  bool get tickerLoading => _tickerLoading;

  List<MarketTick> get recentTrades => List<MarketTick>.unmodifiable(_recentTrades);

  /// Last traded price (from the stream, falling back to the 24h ticker).
  double get lastPrice =>
      lastTick.value?.price ?? _tickerStats?.lastPrice ?? 0;

  bool get busy => _busy;

  String? get actionError => _actionError;

  /// True when the user stored a key/secret pair for the active environment.
  bool get hasCredentials => _settings.hasCredentials(_environment);

  /// True when the user chose to browse prices without trading.
  bool get readOnlyMode => _settings.readOnlyMode;

  bool get riskAcknowledged => _settings.riskAcknowledged;

  ApiCredentials? get credentials => _settings.credentialsFor(_environment);

  String? get maskedApiKey => credentials?.maskedKey;

  /// Increments whenever credentials or the environment change. Used by the
  /// feature providers to know when to reload.
  int get revision => _revision;

  BinanceService get binance => _binance;

  MarketStreamService get stream => _stream;

  // ----------------------------------------------------------- lifecycle ----

  /// Restores the persisted session and starts the background services.
  Future<void> bootstrap() async {
    try {
      await _settings.init();

      _environment = _settings.environment;
      _symbol = _settings.defaultSymbol.toUpperCase();
      _startupError = _settings.lastStorageError;
      _settings.clearStorageError();

      _applyServices();

      _tickSubscription ??= _stream.ticks.listen(_handleTick);
      _statusSubscription ??= _stream.statusChanges.listen(_handleStreamStatus);

      _status = _resolveStatus();
      _startStatsTimer();

      if (_status == AppStatus.ready) {
        unawaited(loadSymbols());
        unawaited(refreshTickerStats());
        if (hasCredentials) {
          unawaited(refreshAccount(silent: true));
        }
      }
    } catch (error) {
      _startupError = 'Startup failed: $error';
      _status = AppStatus.setupRequired;
    }
    _safeNotify();
  }

  /// Pauses/resumes the socket when the app moves between background and
  /// foreground (mobile radios drop idle WebSockets).
  void handleLifecycleChange({required bool resumed}) {
    if (_disposed) {
      return;
    }
    if (resumed) {
      _stream.reconnect();
      _startStatsTimer();
      if (hasCredentials) {
        unawaited(refreshAccount(silent: true));
      }
    } else {
      _statsTimer?.cancel();
      _statsTimer = null;
      unawaited(_stream.disconnect());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_tickSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    _notifyTimer?.cancel();
    _statsTimer?.cancel();
    lastTick.dispose();
    unawaited(_stream.dispose());
    _binance.dispose();
    super.dispose();
  }

  // --------------------------------------------------------- credentials ----

  /// Validates the credentials against Binance, then persists them securely.
  ///
  /// The order matters: nothing is written to the keystore until Binance has
  /// accepted the key, so a typo never leaves a broken session behind.
  Future<void> saveCredentials({
    required String apiKey,
    required String secret,
    BinanceEnvironment? environment,
  }) async {
    final String trimmedKey = apiKey.trim();
    final String trimmedSecret = secret.trim();
    if (trimmedKey.isEmpty || trimmedSecret.isEmpty) {
      throw const ValidationException(
        'Both the API key and the API secret are required.',
      );
    }

    final BinanceEnvironment target = environment ?? _environment;
    _busy = true;
    _actionError = null;
    _safeNotify();

    // Remember the previous configuration so a failed verification can be
    // rolled back without logging the user out.
    final ApiCredentials? previousCredentials = _settings.credentialsFor(target);
    final BinanceEnvironment previousEnvironment = _environment;

    try {
      _environment = target;
      _binance.configure(
        environment: target,
        apiKey: trimmedKey,
        apiSecret: trimmedSecret,
      );

      // Throws BinanceApiException / NetworkException when the key is bad.
      final AccountSnapshot snapshot = await _binance.verifyCredentials();

      await _settings.saveCredentials(
        ApiCredentials(
          apiKey: trimmedKey,
          secret: trimmedSecret,
          environment: target,
        ),
      );
      await _settings.setEnvironment(target);
      await _settings.setReadOnlyMode(false);

      _account = snapshot;
      _accountFetchedAt = DateTime.now();
      _accountError = null;
      _revision++;
      _status = _resolveStatus();
      _applyServices();
      unawaited(loadSymbols(forceRefresh: true));
      unawaited(refreshTickerStats());
    } catch (error) {
      // Roll back to the previous (working) configuration.
      _environment = previousEnvironment;
      _binance.configure(
        environment: previousEnvironment,
        apiKey: previousCredentials?.apiKey,
        apiSecret: previousCredentials?.secret,
      );
      _actionError = describeError(error);
      rethrow;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// "Continue without keys" - prices remain available, trading is disabled.
  Future<void> continueWithoutCredentials() async {
    await _settings.setReadOnlyMode(true);
    _status = _resolveStatus();
    unawaited(loadSymbols());
    unawaited(refreshTickerStats());
    _safeNotify();
  }

  /// Removes stored credentials and returns to the setup screen.
  ///
  /// When [environment] is null every environment is cleared.
  Future<void> clearCredentials({BinanceEnvironment? environment}) async {
    if (environment == null) {
      await _settings.clearAllCredentials();
    } else {
      await _settings.clearCredentials(environment);
    }
    await _settings.setReadOnlyMode(false);

    _account = AccountSnapshot.empty;
    _accountFetchedAt = null;
    _accountError = null;
    _revision++;
    _applyServices();
    _status = _resolveStatus();
    _safeNotify();
  }

  /// Records the live-trading disclaimer acknowledgement.
  Future<void> acknowledgeRisk() async {
    await _settings.setRiskAcknowledged(true);
    _safeNotify();
  }

  // ------------------------------------------------------------ symbols -----

  /// Loads `exchangeInfo` (cached for 15 minutes inside [BinanceService]).
  Future<void> loadSymbols({bool forceRefresh = false}) async {
    if (_symbolsLoading) {
      return;
    }
    _symbolsLoading = true;
    _symbolsError = null;
    _safeNotify();
    try {
      final List<SymbolInfo> loaded =
          await _binance.loadTradableSymbols(forceRefresh: forceRefresh);
      _symbols = loaded;
      _ensureSymbolIsSupported();
    } catch (error) {
      _symbolsError = describeError(error);
    } finally {
      _symbolsLoading = false;
      _safeNotify();
    }
  }

  /// Switches the active symbol (persisted as the default).
  Future<void> setSymbol(String symbol) async {
    final String normalized = symbol.toUpperCase().trim();
    if (normalized.isEmpty || normalized == _symbol) {
      return;
    }
    _symbol = normalized;
    _recentTrades.clear();
    lastTick.value = null;
    _tickerStats = null;
    await _settings.setDefaultSymbol(normalized);
    _applyServices();
    _safeNotify();
    unawaited(refreshTickerStats());
  }

  // -------------------------------------------------       environment  -----

  /// Switches between Testnet and Live.
  ///
  /// Cached market data, prices and balances belong to the previous
  /// environment and are therefore dropped.
  Future<void> setEnvironment(BinanceEnvironment environment) async {
    if (environment == _environment) {
      return;
    }
    _environment = environment;
    await _settings.setEnvironment(environment);

    _recentTrades.clear();
    lastTick.value = null;
    _tickerStats = null;
    _account = AccountSnapshot.empty;
    _accountFetchedAt = null;
    _accountError = null;
    _streamError = null;
    _symbols = <SymbolInfo>[];
    _revision++;

    _applyServices();
    _status = _resolveStatus();
    _safeNotify();

    unawaited(loadSymbols(forceRefresh: true));
    unawaited(refreshTickerStats());
    if (hasCredentials) {
      unawaited(refreshAccount(silent: true));
    }
  }

  // ------------------------------------------------------------ account -----

  /// Refreshes balances and key permissions via `GET /api/v3/account`.
  Future<void> refreshAccount({bool silent = false}) async {
    if (!hasCredentials) {
      _accountError = 'Add your Binance API key to see balances.';
      _safeNotify();
      return;
    }
    if (_accountLoading) {
      return;
    }
    _accountLoading = true;
    if (!silent) {
      _safeNotify();
    }
    try {
      _account = await _binance.fetchAccountSnapshot();
      _accountFetchedAt = DateTime.now();
      _accountError = null;
    } catch (error) {
      _accountError = describeError(error);
    } finally {
      _accountLoading = false;
      _safeNotify();
    }
  }

  // ------------------------------------------------------------- market -----

  /// Refreshes the 24h statistics for the active symbol.
  Future<void> refreshTickerStats() async {
    if (_tickerLoading) {
      return;
    }
    _tickerLoading = true;
    try {
      _tickerStats = await _binance.fetchTickerStats(_symbol);
    } catch (error) {
      // A failing REST poll is not fatal: the WebSocket price keeps working.
      if (lastTick.value == null) {
        _streamError = describeError(error);
      }
    } finally {
      _tickerLoading = false;
      _safeNotify();
    }
  }

  /// Manual "reconnect" from the price card.
  void reconnectStream() {
    _streamError = null;
    _stream.reconnect();
    _safeNotify();
  }

  /// Hides the one-shot storage notice shown at startup.
  void clearStartupError() {
    if (_startupError == null) {
      return;
    }
    _startupError = null;
    _safeNotify();
  }

  /// Clears a one-shot error message that was already shown.
  void clearActionError() {
    if (_actionError == null) {
      return;
    }
    _actionError = null;
    _safeNotify();
  }

  /// Clears the account/stream error banners.
  void clearStreamError() {
    if (_streamError == null) {
      return;
    }
    _streamError = null;
    _safeNotify();
  }

  // --------------------------------------------------------- internals ------

  void _applyServices() {
    final ApiCredentials? credentials = _settings.credentialsFor(_environment);
    _binance.configure(
      environment: _environment,
      apiKey: credentials?.apiKey,
      apiSecret: credentials?.secret,
    );
    if (_status == AppStatus.ready || _status == AppStatus.initializing) {
      _stream.subscribe(_symbol, _environment);
    }
  }

  AppStatus _resolveStatus() {
    if (_settings.hasCredentials(_environment) || _settings.readOnlyMode) {
      return AppStatus.ready;
    }
    return AppStatus.setupRequired;
  }

  void _handleTick(MarketTick tick) {
    if (_disposed || tick.symbol != _symbol) {
      return;
    }
    lastTick.value = tick;
    _recentTrades.insert(0, tick);
    if (_recentTrades.length > _tradeTapeLength) {
      _recentTrades.removeRange(_tradeTapeLength, _recentTrades.length);
    }
    _scheduleNotify();
  }

  void _handleStreamStatus(MarketStreamStatus status) {
    if (_disposed) {
      return;
    }
    _streamStatus = status;
    if (status == MarketStreamStatus.connected) {
      _streamError = null;
    } else if (status == MarketStreamStatus.error) {
      _streamError = _stream.lastError;
    }
    _safeNotify();
  }

  /// Coalesces high frequency tick updates into one rebuild every 500 ms.
  void _scheduleNotify() {
    if (_pendingNotify) {
      return;
    }
    _pendingNotify = true;
    _notifyTimer ??= Timer(_notifyThrottle, () {
      _notifyTimer = null;
      _pendingNotify = false;
      _safeNotify();
    });
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsRefreshInterval, (_) {
      if (!_disposed) {
        unawaited(refreshTickerStats());
      }
    });
  }

  /// Falls back to a supported symbol when the current one is not tradable in
  /// the active environment (Testnet lists a much smaller set of pairs).
  void _ensureSymbolIsSupported() {
    if (_symbols.isEmpty || symbolInfo != null) {
      return;
    }
    String replacement = SettingsService.fallbackSymbol;
    if (SymbolInfo.find(_symbols, replacement) == null) {
      final SymbolInfo preferred = _symbols.firstWhere(
        (SymbolInfo info) => info.quoteAsset == 'USDT',
        orElse: () => _symbols.first,
      );
      replacement = preferred.symbol;
    }
    if (replacement != _symbol) {
      _symbol = replacement;
      lastTick.value = null;
      _recentTrades.clear();
      unawaited(_settings.setDefaultSymbol(replacement));
      _applyServices();
    }
  }

  /// Splits `BTCUSDT` into `(BTC, USDT)` using the loaded exchange info, with a
  /// string based fallback for the moment before `exchangeInfo` arrives.
  (String, String) _splitSymbol() {
    final SymbolInfo? info = symbolInfo;
    if (info != null) {
      return (info.baseAsset, info.quoteAsset);
    }
    const List<String> knownQuotes = <String>[
      'USDT',
      'FDUSD',
      'USDC',
      'TUSD',
      'BUSD',
      'BTC',
      'ETH',
      'BNB',
      'EUR',
      'TRY',
      'BRL',
      'DAI',
      'XRP',
      'SOL',
      'DOGE',
    ];
    for (final String quote in knownQuotes) {
      if (_symbol.length > quote.length && _symbol.endsWith(quote)) {
        return (_symbol.substring(0, _symbol.length - quote.length), quote);
      }
    }
    return (_symbol, '');
  }

  void _safeNotify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }
}

/// Converts any thrown object into a message that can be shown to the user.
String describeError(Object error) {
  if (error is AppException) {
    return error.message;
  }
  return 'Unexpected error: $error';
}

/// Technical detail of an error, when available (shown behind "details").
String describeErrorDetail(Object error) {
  if (error is AppException) {
    return error.detail ?? '';
  }
  return error.toString();
}
