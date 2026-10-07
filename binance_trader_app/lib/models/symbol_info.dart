// Exchange filters for a trading pair.
//
// Binance rejects orders that violate the LOT_SIZE / PRICE_FILTER / NOTIONAL
// filters (error -1013). Instead of letting the API reject the user, the app
// downloads `exchangeInfo` once and validates every order locally *and* rounds
// quantities/prices to the allowed precision.

import '../utils/json_utils.dart';

/// One tradable symbol with its filter rules.
class SymbolInfo {
  const SymbolInfo({
    required this.symbol,
    required this.baseAsset,
    required this.quoteAsset,
    required this.status,
    required this.baseAssetPrecision,
    required this.quoteAssetPrecision,
    required this.minQuantity,
    required this.maxQuantity,
    required this.stepSize,
    required this.marketMinQuantity,
    required this.marketMaxQuantity,
    required this.marketStepSize,
    required this.tickSize,
    required this.minNotional,
    required this.minNotionalAppliesToMarket,
    required this.isSpotTradingAllowed,
  });

  factory SymbolInfo.fromJson(Map<String, dynamic> json) {
    final List<Map<String, dynamic>> filters = asMapList(json['filters']);

    double lotMin = 0;
    double lotMax = 0;
    double lotStep = 0;
    double marketMin = 0;
    double marketMax = 0;
    double marketStep = 0;
    double tickSize = 0;
    double minNotional = 0;
    bool notionalAppliesToMarket = true;

    for (final Map<String, dynamic> filter in filters) {
      final String type = asString(filter['filterType']).toUpperCase();
      if (type == 'LOT_SIZE') {
        lotMin = asDouble(filter['minQty']);
        lotMax = asDouble(filter['maxQty']);
        lotStep = asDouble(filter['stepSize']);
      } else if (type == 'MARKET_LOT_SIZE') {
        marketMin = asDouble(filter['minQty']);
        marketMax = asDouble(filter['maxQty']);
        marketStep = asDouble(filter['stepSize']);
      } else if (type == 'PRICE_FILTER') {
        tickSize = asDouble(filter['tickSize']);
      } else if (type == 'MIN_NOTIONAL') {
        minNotional = asDouble(filter['minNotional']);
        notionalAppliesToMarket =
            asBool(filter['applyToMarket'], fallback: true);
      } else if (type == 'NOTIONAL') {
        minNotional = asDouble(filter['minNotional']);
        notionalAppliesToMarket =
            asBool(filter['applyMinToMarket'], fallback: true);
      }
    }

    return SymbolInfo(
      symbol: asString(json['symbol']).toUpperCase(),
      baseAsset: asString(json['baseAsset']).toUpperCase(),
      quoteAsset: asString(json['quoteAsset']).toUpperCase(),
      status: asString(json['status'], fallback: 'UNKNOWN').toUpperCase(),
      baseAssetPrecision: asInt(json['baseAssetPrecision'], fallback: 8),
      quoteAssetPrecision: asInt(json['quoteAssetPrecision'], fallback: 8),
      minQuantity: lotMin,
      maxQuantity: lotMax,
      stepSize: lotStep,
      marketMinQuantity: marketMin,
      marketMaxQuantity: marketMax,
      marketStepSize: marketStep,
      tickSize: tickSize,
      minNotional: minNotional,
      minNotionalAppliesToMarket: notionalAppliesToMarket,
      isSpotTradingAllowed: asBool(json['isSpotTradingAllowed'], fallback: true),
    );
  }

  /// Parses the `symbols` array of an `exchangeInfo` payload.
  static List<SymbolInfo> listFromExchangeInfo(Map<String, dynamic> payload) =>
      asMapList(payload['symbols'])
          .map(SymbolInfo.fromJson)
          .where((SymbolInfo info) => info.symbol.isNotEmpty)
          .toList(growable: false);

  final String symbol;
  final String baseAsset;
  final String quoteAsset;
  final String status;
  final int baseAssetPrecision;
  final int quoteAssetPrecision;

  // LOT_SIZE filters (limit orders)
  final double minQuantity;
  final double maxQuantity;
  final double stepSize;

  // MARKET_LOT_SIZE filters (market orders); zero when unsupported.
  final double marketMinQuantity;
  final double marketMaxQuantity;
  final double marketStepSize;

  // PRICE_FILTER
  final double tickSize;

  // MIN_NOTIONAL / NOTIONAL
  final double minNotional;
  final bool minNotionalAppliesToMarket;

  final bool isSpotTradingAllowed;

  /// Symbol can currently be traded.
  bool get isTradable => status == 'TRADING' && isSpotTradingAllowed;

  /// Effective minimum quantity for the given order type.
  double minimumQuantity({bool market = false}) {
    final double value = market && marketMinQuantity > 0 ? marketMinQuantity : minQuantity;
    if (value > 0) {
      return value;
    }
    // Fall back to one step when the exchange omits the filter.
    return effectiveStepSize(market: market);
  }

  /// Effective maximum quantity (0 when unlimited).
  double maximumQuantity({bool market = false}) {
    final double value = market && marketMaxQuantity > 0 ? marketMaxQuantity : maxQuantity;
    return value;
  }

  /// Effective step size (quantity increment).
  double effectiveStepSize({bool market = false}) {
    if (market && marketStepSize > 0) {
      return marketStepSize;
    }
    if (stepSize > 0) {
      return stepSize;
    }
    return 0;
  }

  /// Decimals allowed for quantities (derived from the step size).
  int quantityDecimals({bool market = false}) =>
      _decimalsOf(effectiveStepSize(market: market));

  /// Decimals allowed for prices (derived from the tick size).
  int get priceDecimals => _decimalsOf(tickSize);

  /// Floors [quantity] to the allowed step size and precision.
  double normalizeQuantity(double quantity, {bool market = false}) {
    final double step = effectiveStepSize(market: market);
    if (step <= 0 || quantity <= 0) {
      return quantity;
    }
    final double steps = _floorToStep(quantity / step);
    return _clean(steps * step, quantityDecimals(market: market));
  }

  /// Floors [price] to the allowed tick size and precision.
  double normalizePrice(double price) {
    if (tickSize <= 0 || price <= 0) {
      return price;
    }
    final double ticks = _floorToStep(price / tickSize);
    return _clean(ticks * tickSize, priceDecimals);
  }

  /// `0.00001000` style string ready for the API.
  String formatQuantity(double quantity, {bool market = false}) =>
      quantity.toStringAsFixed(quantityDecimals(market: market));

  /// `1234.56000000` style string ready for the API.
  String formatPriceValue(double price) => price.toStringAsFixed(priceDecimals);

  /// Human readable minimum quantity, e.g. `0.00001 BTC`.
  String minimumQuantityText({bool market = false}) =>
      '${formatQuantity(minimumQuantity(market: market), market: market)} $baseAsset';

  /// Minimum order value, e.g. `5 USDT` (empty when not enforced).
  String get minimumNotionalText =>
      minNotional > 0 ? '${formatAmountShort(minNotional)} $quoteAsset' : '';

  /// Validates a quantity against the exchange filters.
  ///
  /// Returns `null` when the order may be submitted, otherwise a message that is
  /// safe to show directly to the user.
  String? validateQuantity(
    double quantity, {
    bool market = false,
    double? referencePrice,
    bool checkNotional = true,
  }) {
    if (quantity <= 0 || !quantity.isFinite) {
      return 'Enter an amount greater than zero.';
    }

    final double min = minimumQuantity(market: market);
    if (min > 0 && quantity < min * (1 - _epsilon)) {
      return 'Minimum quantity for $symbol is '
          '${formatQuantity(min, market: market)} $baseAsset.';
    }

    final double max = maximumQuantity(market: market);
    if (max > 0 && quantity > max * (1 + _epsilon)) {
      return 'Maximum quantity for $symbol is '
          '${formatQuantity(max, market: market)} $baseAsset.';
    }

    final double step = effectiveStepSize(market: market);
    if (step > 0 && !isAlignedToStep(quantity, step)) {
      return 'Quantity must be a multiple of '
          '${formatQuantity(step, market: market)} $baseAsset.';
    }

    final bool notionalEnforced =
        minNotional > 0 && (!market || minNotionalAppliesToMarket);
    if (checkNotional && notionalEnforced && referencePrice != null && referencePrice > 0) {
      final double notional = quantity * referencePrice;
      if (notional < minNotional * (1 - _epsilon)) {
        return 'Order value is too small. Minimum is '
            '${formatAmountShort(minNotional)} $quoteAsset '
            '(about ${formatQuantity(minNotional / referencePrice, market: market)} $baseAsset).';
      }
    }
    return null;
  }

  /// True when [value] is a whole multiple of [step] (within FP tolerance).
  static bool isAlignedToStep(double value, double step) {
    if (step <= 0) {
      return true;
    }
    final double ratio = value / step;
    final double nearest = ratio.roundToDouble();
    return (ratio - nearest).abs() < 1e-6;
  }

  /// Maximum quantity affordable with [quoteAmount], clamped to the filters.
  double maxAffordableQuantity(double quoteAmount, double price, {bool market = false}) {
    if (price <= 0 || quoteAmount <= 0) {
      return 0;
    }
    final double raw = quoteAmount / price;
    final double normalized = normalizeQuantity(raw, market: market);
    final double max = maximumQuantity(market: market);
    if (max > 0 && normalized > max) {
      return normalizeQuantity(max, market: market);
    }
    return normalized;
  }

  /// Compact number for inline messages (`5`, `10.5`).
  static String formatAmountShort(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  /// Finds a symbol inside [list], case insensitive.
  static SymbolInfo? find(List<SymbolInfo> list, String symbol) {
    final String needle = symbol.toUpperCase();
    for (final SymbolInfo info in list) {
      if (info.symbol == needle) {
        return info;
      }
    }
    return null;
  }

  /// Default picker ordering: USDT pairs first, then alphabetical.
  static int compareForPicker(SymbolInfo a, SymbolInfo b) {
    final int rankA = _quoteRank(a.quoteAsset);
    final int rankB = _quoteRank(b.quoteAsset);
    if (rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    return a.symbol.compareTo(b.symbol);
  }

  static int _quoteRank(String quoteAsset) {
    const List<String> preferred = <String>['USDT', 'USDC', 'FDUSD', 'BTC', 'ETH', 'BNB'];
    final int index = preferred.indexOf(quoteAsset);
    return index == -1 ? preferred.length : index;
  }

  @override
  String toString() => '$symbol ($baseAsset/$quoteAsset)';
}

const double _epsilon = 1e-9;

/// Number of decimals encoded in a step/tick string, ignoring trailing zeros:
/// `0.00001000` -> 5, `0.01000000` -> 2, `1.00000000` -> 0.
int _decimalsOf(double step) {
  if (step <= 0) {
    return 8;
  }
  String text = step.toString();
  if (text.contains('e') || text.contains('E')) {
    // Normalise exponential notation produced by very small doubles.
    text = step.toStringAsFixed(12);
  }
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    final int dot = text.indexOf('.');
    return (text.length - dot - 1).clamp(0, 8);
  }
  return 0;
}

/// Floors a step/tick ratio, treating anything within floating point noise of
/// an integer as that integer.
///
/// Without this, `0.5 / 0.00001` (49999.99999999999) floors to 49999 steps and
/// silently shortens a perfectly valid order by one step size.
double _floorToStep(double ratio) {
  final double nearest = ratio.roundToDouble();
  final double tolerance = 1e-9 * (1 + ratio.abs());
  if ((ratio - nearest).abs() <= tolerance) {
    return nearest;
  }
  return ratio.floorToDouble();
}

/// Removes floating point noise: `0.30000000000000004` -> `0.3`.
double _clean(double value, int decimals) {
  final int clamped = decimals.clamp(0, 8);
  return double.parse(value.toStringAsFixed(clamped));
}
