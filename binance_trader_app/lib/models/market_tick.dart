// Market data models: the live trade tape and 24h rolling statistics.

import '../utils/json_utils.dart';

/// One executed trade pushed by the `<symbol>@trade` WebSocket stream.
class MarketTick {
  const MarketTick({
    required this.symbol,
    required this.price,
    required this.quantity,
    required this.tradeTimeMs,
    required this.buyerIsMaker,
  });

  /// Parses the payload of a `@trade` event.
  ///
  /// Raw stream payload: `{ "e":"trade", "s":"BTCUSDT", "p":"50000.01",
  /// "q":"0.01", "T":1699999999999, "m":true }`. Combined streams wrap the same
  /// object inside a `data` field, which is handled as well.
  factory MarketTick.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> payload =
        json.containsKey('data') ? asMap(json['data']) : json;
    return MarketTick(
      symbol: asString(payload['s']).toUpperCase(),
      price: asDouble(payload['p']),
      quantity: asDouble(payload['q']),
      tradeTimeMs: asInt(payload['T'], fallback: DateTime.now().millisecondsSinceEpoch),
      // `m` == true means the buyer was the maker, i.e. the taker sold:
      // the trade is a "sell" from the market's point of view.
      buyerIsMaker: asBool(payload['m']),
    );
  }

  final String symbol;
  final double price;
  final double quantity;
  final int tradeTimeMs;
  final bool buyerIsMaker;

  /// True when the aggressive side was a buyer (price pushed up).
  bool get isAggressiveBuy => !buyerIsMaker;

  /// Quote value of the trade.
  double get quoteValue => price * quantity;

  @override
  String toString() => '$symbol ${price.toStringAsFixed(2)} x $quantity';
}

/// 24h rolling statistics from `GET /api/v3/ticker/24hr`.
class TickerStats {
  const TickerStats({
    required this.symbol,
    required this.lastPrice,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.priceChange,
    required this.priceChangePercent,
    required this.volume,
    required this.quoteVolume,
    required this.weightedAveragePrice,
  });

  factory TickerStats.fromJson(Map<String, dynamic> json) => TickerStats(
        symbol: asString(json['symbol']).toUpperCase(),
        lastPrice: asDouble(json['lastPrice']),
        openPrice: asDouble(json['openPrice']),
        highPrice: asDouble(json['highPrice']),
        lowPrice: asDouble(json['lowPrice']),
        priceChange: asDouble(json['priceChange']),
        priceChangePercent: asDouble(json['priceChangePercent']),
        volume: asDouble(json['volume']),
        quoteVolume: asDouble(json['quoteVolume']),
        weightedAveragePrice: asDouble(json['weightedAvgPrice']),
      );

  final String symbol;
  final double lastPrice;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final double priceChange;
  final double priceChangePercent;

  /// Base asset volume traded in the last 24 hours.
  final double volume;

  /// Quote asset volume traded in the last 24 hours.
  final double quoteVolume;

  final double weightedAveragePrice;

  bool get isUp => priceChangePercent >= 0;
}
