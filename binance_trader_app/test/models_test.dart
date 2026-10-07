// Unit tests for the Binance response models (JSON parsing must be tolerant:
// Binance mixes strings, ints and doubles across endpoints).

import 'package:binance_trader_app/models/account_balance.dart';
import 'package:binance_trader_app/models/binance_order.dart';
import 'package:binance_trader_app/models/market_tick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarketTick', () {
    test('parses a @trade event', () {
      final MarketTick tick = MarketTick.fromJson(<String, dynamic>{
        'e': 'trade',
        's': 'BTCUSDT',
        'p': '50000.01',
        'q': '0.015',
        'T': 1700000000000,
        'm': true,
      });
      expect(tick.symbol, 'BTCUSDT');
      expect(tick.price, closeTo(50000.01, 1e-9));
      expect(tick.quantity, closeTo(0.015, 1e-9));
      expect(tick.tradeTimeMs, 1700000000000);
      // `m: true` means the buyer was the maker, so the taker sold.
      expect(tick.isAggressiveBuy, isFalse);
      expect(tick.quoteValue, closeTo(750.00015, 1e-6));
    });

    test('unwraps a combined-stream payload', () {
      final MarketTick tick = MarketTick.fromJson(<String, dynamic>{
        'stream': 'btcusdt@trade',
        'data': <String, dynamic>{
          'e': 'trade',
          's': 'BTCUSDT',
          'p': 42000,
          'q': '0.5',
          'T': 1700000000001,
          'm': false,
        },
      });
      expect(tick.price, 42000);
      expect(tick.quantity, 0.5);
      expect(tick.isAggressiveBuy, isTrue);
    });
  });

  group('TickerStats', () {
    test('parses /api/v3/ticker/24hr', () {
      final TickerStats stats = TickerStats.fromJson(<String, dynamic>{
        'symbol': 'BTCUSDT',
        'lastPrice': '50000.00',
        'openPrice': '49000.00',
        'highPrice': '51000.00',
        'lowPrice': '48000.00',
        'priceChange': '1000.00',
        'priceChangePercent': '2.04',
        'volume': '12345.6',
        'quoteVolume': '600000000.5',
        'weightedAvgPrice': '49999.99',
      });
      expect(stats.lastPrice, 50000);
      expect(stats.priceChangePercent, closeTo(2.04, 1e-9));
      expect(stats.isUp, isTrue);
      expect(stats.highPrice, 51000);
      expect(stats.lowPrice, 48000);
    });
  });

  group('BinanceOrder', () {
    test('parses a FULL market order response with fills', () {
      final BinanceOrder order = BinanceOrder.fromJson(<String, dynamic>{
        'symbol': 'BTCUSDT',
        'orderId': 28,
        'clientOrderId': 'abc123',
        'transactTime': 1700000000123,
        'price': '0.00000000',
        'origQty': '0.01000000',
        'executedQty': '0.01000000',
        'cummulativeQuoteQty': '500.00',
        'status': 'FILLED',
        'timeInForce': 'GTC',
        'type': 'MARKET',
        'side': 'BUY',
        'fills': <Map<String, dynamic>>[
          <String, dynamic>{
            'price': '50000.00',
            'qty': '0.00400000',
            'commission': '0.00000400',
            'commissionAsset': 'BTC',
            'tradeId': 1,
          },
          <String, dynamic>{
            'price': '49999.00',
            'qty': '0.00600000',
            'commission': '0.00000600',
            'commissionAsset': 'BTC',
            'tradeId': 2,
          },
        ],
      });

      expect(order.side, OrderSide.buy);
      expect(order.type, OrderType.market);
      expect(order.status, OrderStatus.filled);
      expect(order.status.isFinal, isTrue);
      expect(order.origQuantity, closeTo(0.01, 1e-12));
      expect(order.averageFillPrice, closeTo(50000, 1e-6));
      expect(order.remainingQuantity, 0);
      expect(order.fillRatio, closeTo(1, 1e-12));
      expect(order.feesText, '0.00001 BTC');
      expect(order.createdAtMs, 1700000000123);
    });

    test('parses an open limit order from allOrders', () {
      final BinanceOrder order = BinanceOrder.fromJson(<String, dynamic>{
        'symbol': 'ETHUSDT',
        'orderId': 42,
        'clientOrderId': 'xyz',
        'price': '2000.00',
        'origQty': '1.50000000',
        'executedQty': '0.00000000',
        'cummulativeQuoteQty': '0.00000000',
        'status': 'NEW',
        'timeInForce': 'GTC',
        'type': 'LIMIT',
        'side': 'SELL',
        'time': 1700000000000,
        'updateTime': 1700000000000,
      });

      expect(order.side, OrderSide.sell);
      expect(order.type, OrderType.limit);
      expect(order.status, OrderStatus.newOrder);
      expect(order.isOpen, isTrue);
      expect(order.remainingQuantity, closeTo(1.5, 1e-12));
      expect(order.displayPrice, 2000);
      expect(order.feesText, '--');
      expect(order.fills, isEmpty);
    });

    test('maps unknown statuses to OrderStatus.unknown', () {
      expect(OrderStatus.fromApi('SOMETHING_NEW'), OrderStatus.unknown);
      expect(OrderStatus.fromApi(null), OrderStatus.unknown);
    });
  });

  group('AccountBalance', () {
    final Map<String, dynamic> payload = <String, dynamic>{
      'canTrade': true,
      'canWithdraw': false,
      'canDeposit': true,
      'accountType': 'SPOT',
      'makerCommission': 10,
      'takerCommission': 10,
      'balances': <Map<String, dynamic>>[
        <String, dynamic>{'asset': 'BTC', 'free': '0.50000000', 'locked': '0.10000000'},
        <String, dynamic>{'asset': 'USDT', 'free': '1000.00', 'locked': '0.00000000'},
        <String, dynamic>{'asset': 'DOGE', 'free': '0.00000000', 'locked': '0.00000000'},
        <String, dynamic>{'asset': 'ETH', 'free': 2, 'locked': 0.5},
      ],
    };

    test('hides zero balances and keeps the rest', () {
      final List<AccountBalance> balances =
          AccountBalance.listFromAccountPayload(payload);
      expect(balances.map((AccountBalance b) => b.asset), <String>['USDT', 'BTC', 'ETH']);
    });

    test('can include zero balances', () {
      final List<AccountBalance> balances =
          AccountBalance.listFromAccountPayload(payload, includeZero: true);
      expect(balances.length, 4);
      expect(balances.first.asset, 'BTC');
    });

    test('computes totals', () {
      final List<AccountBalance> balances =
          AccountBalance.listFromAccountPayload(payload);
      final AccountBalance btc =
          balances.firstWhere((AccountBalance b) => b.asset == 'BTC');
      expect(btc.total, closeTo(0.6, 1e-12));
      expect(btc.isZero, isFalse);
    });

    test('reads permissions', () {
      final AccountPermissions permissions =
          AccountPermissions.fromAccountPayload(payload);
      expect(permissions.canTrade, isTrue);
      expect(permissions.canWithdraw, isFalse);
      expect(permissions.hasDangerousWithdrawalPermission, isFalse);
      expect(permissions.takerFeeText, '0.10%');
    });

    test('builds an AccountSnapshot with asset lookups', () {
      final AccountSnapshot snapshot =
          AccountSnapshot.fromPayload(payload, fetchedAt: DateTime(2024));
      expect(snapshot.balances.length, 3);
      expect(snapshot.freeBalanceOf('USDT'), 1000);
      expect(snapshot.totalBalanceOf('btc'), closeTo(0.6, 1e-12));
      expect(snapshot.freeBalanceOf('NOPE'), 0);
      expect(snapshot.fetchedAt, DateTime(2024));
    });
  });
}
