// Unit tests for exchange filters, order validation and precision rounding.
//
// These rules are what keep Binance from rejecting an order with `-1013`, so
// they are tested against a realistic `exchangeInfo` payload.

import 'package:binance_trader_app/models/symbol_info.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _btcUsdtJson() => <String, dynamic>{
      'symbol': 'BTCUSDT',
      'status': 'TRADING',
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'baseAssetPrecision': 8,
      'quoteAssetPrecision': 8,
      'isSpotTradingAllowed': true,
      'filters': <Map<String, dynamic>>[
        <String, dynamic>{
          'filterType': 'PRICE_FILTER',
          'minPrice': '0.01000000',
          'maxPrice': '1000000.00000000',
          'tickSize': '0.01000000',
        },
        <String, dynamic>{
          'filterType': 'LOT_SIZE',
          'minQty': '0.00001000',
          'maxQty': '9000.00000000',
          'stepSize': '0.00001000',
        },
        <String, dynamic>{
          'filterType': 'MARKET_LOT_SIZE',
          'minQty': '0.00000000',
          'maxQty': '100.00000000',
          'stepSize': '0.00000000',
        },
        <String, dynamic>{
          'filterType': 'MIN_NOTIONAL',
          'minNotional': '5.00000000',
          'applyToMarket': true,
        },
      ],
    };

void main() {
  group('SymbolInfo.fromJson', () {
    final SymbolInfo info = SymbolInfo.fromJson(_btcUsdtJson());

    test('reads the identifying fields', () {
      expect(info.symbol, 'BTCUSDT');
      expect(info.baseAsset, 'BTC');
      expect(info.quoteAsset, 'USDT');
      expect(info.isTradable, isTrue);
    });

    test('parses every filter', () {
      expect(info.tickSize, closeTo(0.01, 1e-12));
      expect(info.stepSize, closeTo(0.00001, 1e-12));
      expect(info.minQuantity, closeTo(0.00001, 1e-12));
      expect(info.maxQuantity, closeTo(9000, 1e-9));
      expect(info.minNotional, closeTo(5, 1e-9));
      expect(info.minNotionalAppliesToMarket, isTrue);
    });

    test('derives decimals from the step/tick sizes', () {
      expect(info.quantityDecimals(), 5);
      expect(info.priceDecimals, 2);
      expect(info.formatQuantity(0.0001), '0.00010');
      expect(info.formatPriceValue(50000.01), '50000.01');
    });

    test('falls back to the LOT_SIZE step when MARKET_LOT_SIZE is empty', () {
      expect(info.effectiveStepSize(market: true), closeTo(0.00001, 1e-12));
      expect(info.minimumQuantity(market: true), closeTo(0.00001, 1e-12));
    });
  });

  group('normalisation', () {
    final SymbolInfo info = SymbolInfo.fromJson(_btcUsdtJson());

    test('floors quantities to the step size', () {
      expect(info.normalizeQuantity(0.000123456), closeTo(0.00012, 1e-12));
      expect(info.normalizeQuantity(1.999999), closeTo(1.99999, 1e-12));
      expect(info.normalizeQuantity(0.5), closeTo(0.5, 1e-12));
    });

    test('floors prices to the tick size', () {
      expect(info.normalizePrice(50000.019), closeTo(50000.01, 1e-9));
      expect(info.normalizePrice(50000.0199), closeTo(50000.01, 1e-9));
      expect(info.normalizePrice(0.019), closeTo(0.01, 1e-9));
    });

    test('leaves zero/negative values untouched', () {
      expect(info.normalizeQuantity(0), 0);
      expect(info.normalizePrice(-1), -1);
    });

    test('isAlignedToStep tolerates floating point noise', () {
      expect(SymbolInfo.isAlignedToStep(0.00012, 0.00001), isTrue);
      expect(SymbolInfo.isAlignedToStep(0.000123, 0.00001), isFalse);
    });
  });

  group('validateQuantity', () {
    final SymbolInfo info = SymbolInfo.fromJson(_btcUsdtJson());

    test('rejects zero and negative amounts', () {
      expect(info.validateQuantity(0), contains('greater than zero'));
      expect(info.validateQuantity(-1), contains('greater than zero'));
    });

    test('rejects amounts below the minimum', () {
      expect(
        info.validateQuantity(0.000001),
        contains('Minimum quantity'),
      );
    });

    test('rejects amounts above the maximum', () {
      expect(info.validateQuantity(100000), contains('Maximum quantity'));
    });

    test('rejects amounts that are not a multiple of the step', () {
      expect(info.validateQuantity(0.000015), contains('multiple of'));
    });

    test('rejects orders below the minimum notional', () {
      // 0.00001 BTC at 50,000 USDT is 0.5 USDT, far below the 5 USDT minimum.
      expect(
        info.validateQuantity(0.00001, referencePrice: 50000),
        contains('too small'),
      );
      expect(
        info.validateQuantity(0.001, referencePrice: 50000),
        isNull,
      );
    });

    test('accepts a valid limit order quantity', () {
      expect(info.validateQuantity(0.00012, referencePrice: 50000), isNull);
    });
  });

  group('maxAffordableQuantity', () {
    final SymbolInfo info = SymbolInfo.fromJson(_btcUsdtJson());

    test('divides the quote balance by the price and floors to the step', () {
      // 100 USDT / 50,000 = 0.002 BTC.
      expect(
        info.maxAffordableQuantity(100, 50000),
        closeTo(0.002, 1e-9),
      );
    });

    test('respects the maximum quantity', () {
      final SymbolInfo small = SymbolInfo.fromJson(<String, dynamic>{
        ..._btcUsdtJson(),
        'filters': <Map<String, dynamic>>[
          <String, dynamic>{
            'filterType': 'LOT_SIZE',
            'minQty': '0.00001000',
            'maxQty': '0.01000000',
            'stepSize': '0.00001000',
          },
        ],
      });
      expect(small.maxAffordableQuantity(100000, 50000), closeTo(0.01, 1e-9));
    });

    test('returns zero for unusable inputs', () {
      expect(info.maxAffordableQuantity(0, 50000), 0);
      expect(info.maxAffordableQuantity(100, 0), 0);
    });
  });

  group('listFromExchangeInfo + find', () {
    test('parses the symbols array and finds a symbol case insensitively', () {
      final List<SymbolInfo> symbols = SymbolInfo.listFromExchangeInfo(
        <String, dynamic>{
          'symbols': <Map<String, dynamic>>[
            _btcUsdtJson(),
            <String, dynamic>{
              ..._btcUsdtJson(),
              'symbol': 'ETHUSDT',
              'baseAsset': 'ETH',
            },
          ],
        },
      );
      expect(symbols.length, 2);
      expect(SymbolInfo.find(symbols, 'ethusdt')?.baseAsset, 'ETH');
      expect(SymbolInfo.find(symbols, 'DOGEUSDT'), isNull);
    });
  });
}
