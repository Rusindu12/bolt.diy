// Binance WebSocket market stream.
//
// Subscribes to `<symbol>@trade` (e.g.
// `wss://stream.binance.com:9443/ws/btcusdt@trade`) and exposes two broadcast
// streams: the trade ticker and the connection status. The service keeps itself
// alive with exponential-backoff reconnects and an inactivity watchdog, which
// matters on mobile where the socket is dropped whenever the device sleeps or
// switches between Wi-Fi and mobile data.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/binance_environment.dart';
import '../models/market_tick.dart';
import '../utils/json_utils.dart';

/// Connection state of the price stream, rendered as a small status pill.
enum MarketStreamStatus {
  idle('Idle'),
  connecting('Connecting'),
  connected('Live'),
  reconnecting('Reconnecting'),
  error('Offline');

  const MarketStreamStatus(this.label);

  final String label;

  bool get isConnected => this == MarketStreamStatus.connected;
}

/// Live trade ticks for a single symbol.
class MarketStreamService {
  MarketStreamService({WebSocketChannel Function(Uri uri)? connector})
      : _connector = connector ?? _defaultConnector;

  /// Binance is idle between pings; three minutes without a single trade means
  /// the socket is stale and is force-reconnected.
  static const Duration _inactivityTimeout = Duration(minutes: 3);

  static const Duration _maxBackoff = Duration(seconds: 30);

  static WebSocketChannel _defaultConnector(Uri uri) =>
      WebSocketChannel.connect(uri);

  final WebSocketChannel Function(Uri uri) _connector;

  final StreamController<MarketTick> _tickController =
      StreamController<MarketTick>.broadcast();
  final StreamController<MarketStreamStatus> _statusController =
      StreamController<MarketStreamStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;

  String? _symbol;
  BinanceEnvironment _environment = BinanceEnvironment.testnet;
  MarketStreamStatus _status = MarketStreamStatus.idle;
  String? _lastError;
  int _attempt = 0;
  int _generation = 0;
  bool _disposed = false;

  /// Trade stream, broadcast so multiple widgets can listen.
  Stream<MarketTick> get ticks => _tickController.stream;

  /// Connection status changes.
  Stream<MarketStreamStatus> get statusChanges => _statusController.stream;

  MarketStreamStatus get status => _status;

  String? get lastError => _lastError;

  String? get symbol => _symbol;

  /// Points the stream at [symbol] on [environment].
  ///
  /// Calling this with the symbol that is already streaming is a no-op, which
  /// makes it safe to call from `build`/`didChangeDependencies`.
  void subscribe(String symbol, BinanceEnvironment environment) {
    if (_disposed) {
      return;
    }
    final String normalized = symbol.toUpperCase().trim();
    if (normalized.isEmpty) {
      return;
    }
    final bool sameTarget =
        _symbol == normalized && _environment == environment;
    if (sameTarget &&
        (_status == MarketStreamStatus.connected ||
            _status == MarketStreamStatus.connecting)) {
      return;
    }
    _symbol = normalized;
    _environment = environment;
    _attempt = 0;
    unawaited(_connect());
  }

  /// Tears the socket down (used when the app goes to the background and the
  /// user comes back, or when the credentials/environment change).
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _closeChannel();
    _setStatus(MarketStreamStatus.idle);
  }

  /// Reconnects immediately (manual "retry" button).
  void reconnect() {
    if (_disposed) {
      return;
    }
    _attempt = 0;
    unawaited(_connect());
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _tickController.close();
    await _statusController.close();
  }

  // ------------------------------------------------------- internals --------

  Future<void> _connect() async {
    if (_disposed || _symbol == null) {
      return;
    }
    final int generation = ++_generation;
    await _closeChannel();
    if (_disposed || generation != _generation) {
      return;
    }

    _setStatus(MarketStreamStatus.connecting);
    final Uri uri = Uri.parse(_environment.tradeStreamUrl(_symbol!));

    try {
      final WebSocketChannel channel = _connector(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stackTrace) =>
            _handleStreamError(error, generation),
        onDone: () => _handleStreamDone(generation),
        cancelOnError: false,
      );

      // `ready` completes once the handshake finished, which also surfaces
      // DNS/TLS/proxy failures as an exception.
      await channel.ready;
      if (_disposed || generation != _generation) {
        return;
      }
      _attempt = 0;
      _lastError = null;
      _setStatus(MarketStreamStatus.connected);
      _resetWatchdog(generation);
    } catch (error) {
      _lastError = _describeError(error);
      _setStatus(MarketStreamStatus.error);
      _scheduleReconnect();
    }
  }

  Future<void> _closeChannel() async {
    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    final WebSocketChannel? channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink.close();
      } catch (_) {
        // Closing an already broken socket is not an error worth reporting.
      }
    }
  }

  void _handleMessage(dynamic message) {
    _resetWatchdog(_generation);
    if (message is! String || message.isEmpty) {
      return;
    }
    Map<String, dynamic> payload;
    try {
      final Object? decoded = jsonDecode(message);
      if (decoded is! Map) {
        return;
      }
      payload = asMap(decoded);
    } on FormatException {
      return; // Malformed frame: ignore instead of killing the stream.
    }

    // Binance reports stream errors inline, e.g.
    // `{"e":"error","code":-1121,"msg":"Invalid symbol"}`.
    final String eventType = asString(payload['e']);
    if (eventType == 'error') {
      _lastError = asString(payload['msg'], fallback: 'Stream error');
      _setStatus(MarketStreamStatus.error);
      return;
    }

    // Ignore subscribe/unsubscribe confirmations (`{"result":null,"id":1}`).
    if (eventType == 'trade' || eventType == 'aggTrade') {
      final MarketTick tick = MarketTick.fromJson(payload);
      if (tick.price > 0 && !_tickController.isClosed) {
        _tickController.add(tick);
      }
    }
  }

  void _handleStreamError(Object error, int generation) {
    if (_disposed || generation != _generation) {
      return;
    }
    _lastError = _describeError(error);
    _setStatus(MarketStreamStatus.error);
    _scheduleReconnect();
  }

  void _handleStreamDone(int generation) {
    if (_disposed || generation != _generation) {
      return;
    }
    // The server closed the socket (network handover, idle timeout, ...).
    _setStatus(MarketStreamStatus.reconnecting);
    _scheduleReconnect();
  }

  /// Reconnects with exponential backoff: 1s, 2s, 4s, 8s, 16s, then 30s.
  void _scheduleReconnect() {
    if (_disposed || _symbol == null || _reconnectTimer != null) {
      return;
    }
    _attempt = math.min(_attempt + 1, 6);
    final int seconds = math.min(_maxBackoff.inSeconds, 1 << (_attempt - 1));
    _setStatus(MarketStreamStatus.reconnecting);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  /// Drops the socket when no trade arrived for [_inactivityTimeout].
  void _resetWatchdog(int generation) {
    _watchdogTimer?.cancel();
    if (_disposed || generation != _generation) {
      return;
    }
    _watchdogTimer = Timer(_inactivityTimeout, () {
      if (_disposed || generation != _generation) {
        return;
      }
      _lastError = 'No data received for ${_inactivityTimeout.inMinutes} minutes.';
      unawaited(_connect());
    });
  }

  void _setStatus(MarketStreamStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  String _describeError(Object error) {
    final String text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return 'No connection to the Binance stream. Check your internet '
          'connection (VPNs and some carriers block WebSockets).';
    }
    if (text.contains('HandshakeException')) {
      return 'Secure connection to the Binance stream failed.';
    }
    if (text.length > 200) {
      return '${text.substring(0, 200)}...';
    }
    return text;
  }
}
