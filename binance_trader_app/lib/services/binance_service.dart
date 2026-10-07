// Binance Spot REST client.
//
// Responsibilities:
//   * hold the active environment (Testnet / Live) and the API credentials,
//   * sign private requests with HMAC-SHA256 (see `utils/signing.dart`),
//   * translate HTTP/Binance failures into typed, user friendly exceptions,
//   * keep an in-memory cache of `exchangeInfo` filters and a server clock
//     offset so signed requests are not rejected with code -1021.
//
// All private endpoints follow the same shape:
//   GET/POST/DELETE https://<host>/api/v3/<path>?<params>&recvWindow=..&timestamp=..&signature=..
// The parameters are placed in the query string for every verb, which keeps the
// exact bytes used for signing identical to the bytes that are sent.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account_balance.dart';
import '../models/binance_environment.dart';
import '../models/binance_order.dart';
import '../models/market_tick.dart';
import '../models/symbol_info.dart';
import '../utils/api_exceptions.dart';
import '../utils/json_utils.dart';
import '../utils/signing.dart';

/// Thin wrapper around the Binance Spot REST API.
class BinanceService {
  BinanceService({http.Client? client}) : _client = client ?? http.Client();

  /// How long a single request may take before it is considered a network
  /// failure. Trading on mobile networks needs a generous value.
  static const Duration _requestTimeout = Duration(seconds: 20);

  /// Binance allows a maximum receive window of 60 s; 10 s tolerates clock
  /// drift without leaving a large window for replay attacks.
  static const int _recvWindowMs = 10000;

  /// `exchangeInfo` is cached for this long (it changes rarely).
  static const Duration _symbolCacheTtl = Duration(minutes: 15);

  final http.Client _client;

  BinanceEnvironment _environment = BinanceEnvironment.testnet;
  String? _apiKey;
  String? _apiSecret;
  int _timeOffsetMs = 0;
  List<SymbolInfo>? _symbolCache;
  DateTime? _symbolCacheTime;

  // ---------------------------------------------------------------- state ---

  BinanceEnvironment get environment => _environment;

  /// True when both an API key and a secret are available for signing.
  bool get hasCredentials =>
      (_apiKey?.isNotEmpty ?? false) && (_apiSecret?.isNotEmpty ?? false);

  /// Difference between Binance server time and this device, in milliseconds.
  int get serverTimeOffsetMs => _timeOffsetMs;

  /// Applies the environment and credentials selected by the user.
  void configure({
    required BinanceEnvironment environment,
    String? apiKey,
    String? apiSecret,
  }) {
    final bool environmentChanged = environment != _environment;
    _environment = environment;
    _apiKey = apiKey;
    _apiSecret = apiSecret;
    if (environmentChanged) {
      // Cached market data and the clock offset belong to the old environment.
      _symbolCache = null;
      _symbolCacheTime = null;
      _timeOffsetMs = 0;
    }
  }

  /// Releases the underlying HTTP connections.
  void dispose() => _client.close();

  // ------------------------------------------------------- market data ------

  /// `GET /api/v3/time` - used to measure the device clock offset.
  Future<int> fetchServerTime() async {
    final Map<String, dynamic> payload = await _publicGet('/api/v3/time');
    final int serverTime = asInt(payload['serverTime']);
    if (serverTime <= 0) {
      throw const BinanceApiException(
        message: 'Binance returned an unexpected server time response.',
      );
    }
    return serverTime;
  }

  /// Measures (and caches) the offset between Binance and the device clock.
  ///
  /// This is what keeps signed requests from failing with `-1021` when the
  /// phone's clock is a few seconds off.
  Future<int> syncClock() async {
    final int serverTime = await fetchServerTime();
    _timeOffsetMs = serverTime - DateTime.now().millisecondsSinceEpoch;
    return _timeOffsetMs;
  }

  /// `GET /api/v3/ticker/price` - last traded price for one symbol.
  Future<double> fetchLastPrice(String symbol) async {
    final Map<String, dynamic> payload = await _publicGet(
      '/api/v3/ticker/price',
      params: <String, String>{'symbol': symbol.toUpperCase()},
    );
    return asDouble(payload['price']);
  }

  /// `GET /api/v3/ticker/24hr` - rolling 24h statistics for one symbol.
  Future<TickerStats> fetchTickerStats(String symbol) async {
    final Map<String, dynamic> payload = await _publicGet(
      '/api/v3/ticker/24hr',
      params: <String, String>{'symbol': symbol.toUpperCase()},
    );
    return TickerStats.fromJson(payload);
  }

  /// `GET /api/v3/exchangeInfo` - every symbol and its filters (cached).
  ///
  /// The result powers the symbol picker and the local order validation that
  /// prevents `-1013` (filter violation) rejections.
  Future<List<SymbolInfo>> loadExchangeInfo({bool forceRefresh = false}) async {
    final List<SymbolInfo>? cached = _symbolCache;
    final DateTime? cachedAt = _symbolCacheTime;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _symbolCacheTtl) {
      return cached;
    }

    final Map<String, dynamic> payload = await _publicGet('/api/v3/exchangeInfo');
    final List<SymbolInfo> symbols = SymbolInfo.listFromExchangeInfo(payload);
    if (symbols.isEmpty) {
      throw const BinanceApiException(
        message: 'Binance returned an empty symbol list. Try again in a moment.',
      );
    }
    _symbolCache = symbols;
    _symbolCacheTime = DateTime.now();
    return symbols;
  }

  /// Symbols that can be traded right now, ordered for the picker.
  Future<List<SymbolInfo>> loadTradableSymbols({bool forceRefresh = false}) async {
    final List<SymbolInfo> symbols =
        await loadExchangeInfo(forceRefresh: forceRefresh);
    final List<SymbolInfo> tradable =
        symbols.where((SymbolInfo info) => info.isTradable).toList()
          ..sort(SymbolInfo.compareForPicker);
    return tradable;
  }

  // ---------------------------------------------------------- account -------

  /// `GET /api/v3/account` (SIGNED) - balances plus permission flags.
  ///
  /// Also used by [verifyCredentials] because it is the cheapest endpoint that
  /// proves the key/secret pair works and has trading permissions.
  Future<AccountSnapshot> fetchAccountSnapshot({bool includeZeroBalances = false}) async {
    final Map<String, dynamic> payload = await _signedRequest('GET', '/api/v3/account');
    return AccountSnapshot.fromPayload(
      payload,
      includeZeroBalances: includeZeroBalances,
    );
  }

  /// Validates the stored credentials by performing one authenticated call.
  ///
  /// Throws a [BinanceApiException] with a friendly message when the key is
  /// invalid, restricted or IP locked.
  Future<AccountSnapshot> verifyCredentials() async {
    if (!hasCredentials) {
      throw const MissingCredentialsException();
    }
    // A fresh clock offset avoids false negatives caused by `-1021`.
    await syncClock();
    return fetchAccountSnapshot();
  }

  // ------------------------------------------------------------ orders ------

  /// `POST /api/v3/order` with `type=MARKET`.
  ///
  /// Provide either [quantity] (base asset amount) or [quoteOrderQuantity]
  /// (quote asset amount, e.g. "buy 50 USDT worth of BTC"). The latter is often
  /// the friendlier option because it is not affected by the base step size.
  Future<BinanceOrder> placeMarketOrder({
    required String symbol,
    required OrderSide side,
    double? quantity,
    double? quoteOrderQuantity,
    SymbolInfo? symbolInfo,
    bool validateOnly = false,
  }) async {
    final bool useQuoteAmount = quoteOrderQuantity != null && quoteOrderQuantity > 0;
    if (!useQuoteAmount && (quantity == null || quantity <= 0)) {
      throw const ValidationException('Enter the amount you want to trade.');
    }

    final Map<String, String> params = <String, String>{
      'symbol': symbol.toUpperCase(),
      'side': side.apiValue,
      'type': OrderType.market.apiValue,
      'newOrderRespType': 'FULL',
    };

    if (useQuoteAmount) {
      // Quote amounts follow the quote asset precision, not the base step size.
      params['quoteOrderQty'] = _formatQuoteAmount(quoteOrderQuantity);
    } else {
      params['quantity'] = _formatNumber(quantity, symbolInfo, isPrice: false);
    }

    final Map<String, dynamic> payload = await _signedRequest(
      'POST',
      validateOnly ? '/api/v3/order/test' : '/api/v3/order',
      params: params,
    );
    if (validateOnly) {
      return _dryRunOrder(
        symbol: symbol,
        side: side,
        type: OrderType.market,
        quantity: quantity ?? 0,
        quoteQuantity: quoteOrderQuantity ?? 0,
      );
    }
    return BinanceOrder.fromJson(payload);
  }

  /// `POST /api/v3/order` with `type=LIMIT`.
  Future<BinanceOrder> placeLimitOrder({
    required String symbol,
    required OrderSide side,
    required double quantity,
    required double price,
    SymbolInfo? symbolInfo,
    String timeInForce = 'GTC',
    bool validateOnly = false,
  }) async {
    if (quantity <= 0) {
      throw const ValidationException('Enter the amount you want to trade.');
    }
    if (price <= 0) {
      throw const ValidationException('Enter a limit price greater than zero.');
    }

    final Map<String, String> params = <String, String>{
      'symbol': symbol.toUpperCase(),
      'side': side.apiValue,
      'type': OrderType.limit.apiValue,
      'timeInForce': timeInForce,
      'quantity': _formatNumber(quantity, symbolInfo, isPrice: false),
      'price': _formatNumber(price, symbolInfo, isPrice: true),
      'newOrderRespType': 'FULL',
    };

    final Map<String, dynamic> payload = await _signedRequest(
      'POST',
      validateOnly ? '/api/v3/order/test' : '/api/v3/order',
      params: params,
    );
    if (validateOnly) {
      return _dryRunOrder(
        symbol: symbol,
        side: side,
        type: OrderType.limit,
        quantity: quantity,
        price: price,
      );
    }
    return BinanceOrder.fromJson(payload);
  }

  /// `GET /api/v3/allOrders` (SIGNED) - order history for one symbol.
  Future<List<BinanceOrder>> fetchOrderHistory({
    required String symbol,
    int limit = 50,
  }) async {
    final List<Object?> orders = await _signedRequestList(
      'GET',
      '/api/v3/allOrders',
      params: <String, String>{
        'symbol': symbol.toUpperCase(),
        // Asking for exactly `limit` keeps the response small; Binance caps it
        // at 1000 and needs a time window when more than 1000 are requested.
        'limit': '${limit.clamp(1, 1000)}',
      },
    );
    return orders.map(asMap).map(BinanceOrder.fromJson).toList(growable: false);
  }

  /// `GET /api/v3/openOrders` (SIGNED) - orders that are still working.
  ///
  /// Passing [symbol] is strongly recommended: the request weighs 3 instead of
  /// 40 without it.
  Future<List<BinanceOrder>> fetchOpenOrders({String? symbol}) async {
    final Map<String, String> params = <String, String>{};
    if (symbol != null && symbol.isNotEmpty) {
      params['symbol'] = symbol.toUpperCase();
    }
    final List<Object?> orders = await _signedRequestList(
      'GET',
      '/api/v3/openOrders',
      params: params,
    );
    return orders.map(asMap).map(BinanceOrder.fromJson).toList(growable: false);
  }

  /// `DELETE /api/v3/order` (SIGNED) - cancel a working order.
  Future<BinanceOrder> cancelOrder({
    required String symbol,
    required int orderId,
  }) async {
    final Map<String, dynamic> payload = await _signedRequest(
      'DELETE',
      '/api/v3/order',
      params: <String, String>{
        'symbol': symbol.toUpperCase(),
        'orderId': '$orderId',
      },
    );
    return BinanceOrder.fromJson(payload);
  }

  // ------------------------------------------------------- internals --------

  /// Formats a number for the API. When [symbolInfo] is available the value is
  /// aligned to the symbol's step/tick size, otherwise a safe 8-decimal
  /// representation is used.
  String _formatNumber(double? value, SymbolInfo? symbolInfo, {required bool isPrice}) {
    final double number = value ?? 0;
    if (symbolInfo != null) {
      if (isPrice) {
        return symbolInfo.formatPriceValue(number);
      }
      return symbolInfo.formatQuantity(number);
    }
    return number.toStringAsFixed(8);
  }

  /// Formats a quote-asset amount (`quoteOrderQty`) with up to 8 decimals and
  /// without trailing zeros, e.g. `50.5`.
  String _formatQuoteAmount(double? value) {
    final double number = value ?? 0;
    String text = number.toStringAsFixed(8);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  /// Builds a read-only [BinanceOrder] so the UI can show a "dry run" receipt
  /// after a successful `POST /api/v3/order/test`.
  BinanceOrder _dryRunOrder({
    required String symbol,
    required OrderSide side,
    required OrderType type,
    required double quantity,
    double price = 0,
    double quoteQuantity = 0,
  }) =>
      BinanceOrder(
        symbol: symbol.toUpperCase(),
        orderId: 0,
        clientOrderId: 'VALIDATED-ONLY',
        price: price,
        origQuantity: quantity,
        executedQuantity: 0,
        cummulativeQuoteQuantity: quoteQuantity,
        // The test endpoint proves the order *would* be accepted.
        status: OrderStatus.newOrder,
        type: type,
        side: side,
        timeInForce: 'GTC',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        fills: const <OrderFill>[],
      );

  Uri _uri(String path, Map<String, String>? params) {
    final Uri base = Uri.parse('${_environment.restBaseUrl}$path');
    if (params == null || params.isEmpty) {
      return base;
    }
    return base.replace(queryParameters: params);
  }

  /// Performs an unsigned request (public market data).
  Future<Map<String, dynamic>> _publicGet(
    String path, {
    Map<String, String>? params,
  }) async {
    final http.Response response = await _send(
      () => _client.get(_uri(path, params), headers: _publicHeaders()),
      '$path',
    );
    return _decode(response);
  }

  /// Performs a SIGNED request (private account/trading endpoints).
  Future<Map<String, dynamic>> _signedRequest(
    String method,
    String path, {
    Map<String, String>? params,
    bool allowClockRetry = true,
  }) async {
    try {
      return await _signedRequestInternal(method, path, params: params);
    } on BinanceApiException catch (error) {
      // Retry once with a corrected clock offset: `-1021` means the request
      // never reached the matching engine, so retrying is safe even for orders.
      if (allowClockRetry && error.isTimestampError) {
        await syncClock();
        return _signedRequest(method, path, params: params, allowClockRetry: false);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _signedRequestInternal(
    String method,
    String path, {
    Map<String, String>? params,
  }) async {
    final String? apiKey = _apiKey;
    final String? apiSecret = _apiSecret;
    if (apiKey == null || apiSecret == null || apiKey.isEmpty || apiSecret.isEmpty) {
      throw const MissingCredentialsException();
    }

    // 1. Build the parameter set that will be signed.
    final Map<String, String> signedParams = <String, String>{
      ...?params,
      'recvWindow': '$_recvWindowMs',
      'timestamp': '${DateTime.now().millisecondsSinceEpoch + _timeOffsetMs}',
    };

    // 2. Sign the canonical query string.
    final String query = buildQueryString(signedParams);
    final String signature = buildSignature(secret: apiSecret, query: query);

    // 3. Send exactly the bytes that were signed, plus the signature.
    final Uri uri = Uri.parse('${_environment.restBaseUrl}$path?$query&signature=$signature');
    final Map<String, String> headers = _signedHeaders(apiKey);

    final http.Response response = await _send(
      () {
        switch (method) {
          case 'POST':
            return _client.post(uri, headers: headers);
          case 'DELETE':
            return _client.delete(uri, headers: headers);
          default:
            return _client.get(uri, headers: headers);
        }
      },
      '$method $path',
    );

    return _decode(response);
  }

  /// Signed request returning a JSON *array* (order lists).
  Future<List<Object?>> _signedRequestList(
    String method,
    String path, {
    Map<String, String>? params,
  }) async {
    final String? apiKey = _apiKey;
    final String? apiSecret = _apiSecret;
    if (apiKey == null || apiSecret == null || apiKey.isEmpty || apiSecret.isEmpty) {
      throw const MissingCredentialsException();
    }

    final Map<String, String> signedParams = <String, String>{
      ...?params,
      'recvWindow': '$_recvWindowMs',
      'timestamp': '${DateTime.now().millisecondsSinceEpoch + _timeOffsetMs}',
    };
    final String query = buildQueryString(signedParams);
    final String signature = buildSignature(secret: apiSecret, query: query);
    final Uri uri = Uri.parse('${_environment.restBaseUrl}$path?$query&signature=$signature');

    final http.Response response = await _send(
      () => _client.get(uri, headers: _signedHeaders(apiKey)),
      '$method $path',
    );
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final List<Object?> decoded = decodeJsonArray(body);
      return decoded;
    }
    throw mapBinanceError(
      httpStatus: response.statusCode,
      body: _parseErrorBody(body),
    );
  }

  Map<String, String> _publicHeaders() => const <String, String>{
        'Accept': 'application/json',
      };

  Map<String, String> _signedHeaders(String apiKey) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-MBX-APIKEY': apiKey,
      };

  /// Executes [request] with a timeout and converts transport problems.
  Future<http.Response> _send(
    Future<http.Response> Function() request,
    String description,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw NetworkException(
        'Binance did not answer within ${_requestTimeout.inSeconds}s. '
        'Check your connection and try again.',
        detail: 'Timeout on $description',
      );
    } on http.ClientException catch (error) {
      throw NetworkException(
        'Network error while contacting Binance. Check your internet '
        'connection and try again.',
        detail: '$description: ${error.message}',
      );
    } catch (error) {
      // TLS failures, DNS problems and anything else thrown by the socket
      // layer. Kept generic so the app also compiles for Flutter Web.
      throw NetworkException(
        'Could not reach Binance. Check your connection, VPN and region '
        'restrictions.',
        detail: '$description: $error',
      );
    }
  }

  /// Decodes a response, throwing a typed exception for non-2xx status codes.
  Map<String, dynamic> _decode(http.Response response) {
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeJsonObject(body);
    }
    throw mapBinanceError(
      httpStatus: response.statusCode,
      body: _parseErrorBody(body),
    );
  }

  /// Binance error bodies are JSON, but proxies/WAFs may return HTML.
  Object? _parseErrorBody(String body) {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }
}
