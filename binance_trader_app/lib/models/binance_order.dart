// Order models shared by "place order" responses and order history.
//
// Binance returns slightly different flavours of the same object:
//   * POST /api/v3/order              -> ACK/RESULT/FULL style response
//   * GET  /api/v3/allOrders          -> historical orders (has `time`)
//   * GET  /api/v3/openOrders         -> working orders (has `updateTime`)
// A single lenient model covers all three.

import '../utils/formatters.dart';
import '../utils/json_utils.dart';

/// Order direction.
enum OrderSide {
  buy('BUY', 'Buy'),
  sell('SELL', 'Sell');

  const OrderSide(this.apiValue, this.label);

  /// Value expected by the Binance API.
  final String apiValue;

  /// Display label.
  final String label;

  bool get isBuy => this == OrderSide.buy;

  static OrderSide fromApi(String? value) =>
      asString(value).toUpperCase() == 'SELL' ? OrderSide.sell : OrderSide.buy;
}

/// Order type supported by the app.
enum OrderType {
  market('MARKET', 'Market'),
  limit('LIMIT', 'Limit');

  const OrderType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static OrderType fromApi(String? value) =>
      asString(value).toUpperCase() == 'LIMIT' ? OrderType.limit : OrderType.market;
}

/// Lifecycle status of an order.
enum OrderStatus {
  newOrder('NEW', 'Open'),
  partiallyFilled('PARTIALLY_FILLED', 'Partially filled'),
  filled('FILLED', 'Filled'),
  canceled('CANCELED', 'Cancelled'),
  pendingCancel('PENDING_CANCEL', 'Cancel pending'),
  rejected('REJECTED', 'Rejected'),
  expired('EXPIRED', 'Expired'),
  expiredInMatch('EXPIRED_IN_MATCH', 'Expired'),
  unknown('UNKNOWN', 'Unknown');

  const OrderStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Still working on the book and therefore cancellable.
  bool get isOpen => this == OrderStatus.newOrder || this == OrderStatus.partiallyFilled;

  /// No further updates will arrive for this order.
  bool get isFinal =>
      this == OrderStatus.filled ||
      this == OrderStatus.canceled ||
      this == OrderStatus.rejected ||
      this == OrderStatus.expired ||
      this == OrderStatus.expiredInMatch;

  static OrderStatus fromApi(String? value) {
    final String raw = asString(value).toUpperCase();
    for (final OrderStatus status in OrderStatus.values) {
      if (status.apiValue == raw) {
        return status;
      }
    }
    return OrderStatus.unknown;
  }
}

/// A single (partial) fill of an order.
class OrderFill {
  const OrderFill({
    required this.price,
    required this.quantity,
    required this.commission,
    required this.commissionAsset,
    required this.tradeId,
  });

  factory OrderFill.fromJson(Map<String, dynamic> json) => OrderFill(
        price: asDouble(json['price']),
        quantity: asDouble(json['qty']),
        commission: asDouble(json['commission']),
        commissionAsset: asString(json['commissionAsset']),
        tradeId: asInt(json['tradeId']),
      );

  final double price;
  final double quantity;
  final double commission;
  final String commissionAsset;
  final int tradeId;
}

/// An order as returned by Binance.
class BinanceOrder {
  const BinanceOrder({
    required this.symbol,
    required this.orderId,
    required this.clientOrderId,
    required this.price,
    required this.origQuantity,
    required this.executedQuantity,
    required this.cummulativeQuoteQuantity,
    required this.status,
    required this.type,
    required this.side,
    required this.timeInForce,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.fills,
  });

  factory BinanceOrder.fromJson(Map<String, dynamic> json) {
    final int created = asInt(json['time'], fallback: asInt(json['transactTime']));
    final int updated = asInt(json['updateTime'], fallback: created);
    return BinanceOrder(
      symbol: asString(json['symbol']),
      orderId: asInt(json['orderId']),
      clientOrderId: asString(json['clientOrderId']),
      price: asDouble(json['price']),
      origQuantity: asDouble(json['origQty']),
      executedQuantity: asDouble(json['executedQty']),
      cummulativeQuoteQuantity: asDouble(json['cummulativeQuoteQty']),
      status: OrderStatus.fromApi(asString(json['status'])),
      type: OrderType.fromApi(asString(json['type'])),
      side: OrderSide.fromApi(asString(json['side'])),
      timeInForce: asString(json['timeInForce'], fallback: 'GTC'),
      createdAtMs: created,
      updatedAtMs: updated,
      fills: asMapList(json['fills']).map(OrderFill.fromJson).toList(growable: false),
    );
  }

  final String symbol;
  final int orderId;
  final String clientOrderId;

  /// Limit price (0 for market orders).
  final double price;

  /// Quantity requested.
  final double origQuantity;

  /// Quantity already executed.
  final double executedQuantity;

  /// Quote amount already spent/received.
  final double cummulativeQuoteQuantity;

  final OrderStatus status;
  final OrderType type;
  final OrderSide side;
  final String timeInForce;
  final int createdAtMs;
  final int updatedAtMs;
  final List<OrderFill> fills;

  /// Remaining quantity to execute.
  double get remainingQuantity {
    final double remaining = origQuantity - executedQuantity;
    return remaining < 0 ? 0 : remaining;
  }

  /// Actual average fill price, when anything has been filled.
  double get averageFillPrice =>
      executedQuantity > 0 ? cummulativeQuoteQuantity / executedQuantity : 0;

  /// Price used for display: average fill for executed orders, limit price
  /// otherwise, plus the total fees paid in the fills.
  double get displayPrice {
    if (executedQuantity > 0 && cummulativeQuoteQuantity > 0) {
      return averageFillPrice;
    }
    return price;
  }

  /// Sum of commissions grouped per asset, e.g. `BNB 0.0001`.
  String get feesText {
    if (fills.isEmpty) {
      return '--';
    }
    final Map<String, double> totals = <String, double>{};
    for (final OrderFill fill in fills) {
      if (fill.commission <= 0) {
        continue;
      }
      totals.update(
        fill.commissionAsset,
        (double value) => value + fill.commission,
        ifAbsent: () => fill.commission,
      );
    }
    if (totals.isEmpty) {
      return '--';
    }
    return totals.entries
        // Formatted through the shared helper so floating point noise never
        // reaches the UI (e.g. 0.000004 + 0.000006 -> "0.00001 BTC").
        .map((MapEntry<String, double> entry) =>
            '${formatAmount(entry.value)} ${entry.key}')
        .join(', ');
  }

  /// Filled percentage (0..1).
  double get fillRatio {
    if (origQuantity <= 0) {
      return 0;
    }
    final double ratio = executedQuantity / origQuantity;
    return ratio > 1 ? 1 : ratio;
  }

  bool get isOpen => status.isOpen;

  @override
  String toString() =>
      '#$orderId ${side.apiValue} ${type.apiValue} $symbol '
      '$origQuantity @ $displayPrice (${status.apiValue})';
}
