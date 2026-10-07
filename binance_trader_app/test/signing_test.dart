// Unit tests for HMAC-SHA256 request signing.
//
// These matter: a wrong signature is the difference between a working order and
// a confusing `-1022` error from Binance.

import 'package:binance_trader_app/utils/signing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hmacSha256Hex', () {
    test('matches the published HMAC-SHA256 test vector', () {
      // Well known vector: HMAC_SHA256(key="key", msg="The quick brown fox ...").
      final String digest = hmacSha256Hex(
        secret: 'key',
        payload: 'The quick brown fox jumps over the lazy dog',
      );
      expect(
        digest,
        'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
      );
    });

    test('is deterministic and 64 lowercase hex characters long', () {
      final String a = hmacSha256Hex(secret: 'secret', payload: 'symbol=BTCUSDT');
      final String b = hmacSha256Hex(secret: 'secret', payload: 'symbol=BTCUSDT');
      expect(a, b);
      expect(a.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    });

    test('changes when any parameter changes', () {
      final String base = hmacSha256Hex(secret: 's', payload: 'side=BUY');
      final String other = hmacSha256Hex(secret: 's', payload: 'side=SELL');
      expect(base, isNot(other));
    });
  });

  group('buildQueryString', () {
    test('keeps insertion order', () {
      final String query = buildQueryString(<String, String>{
        'symbol': 'BTCUSDT',
        'side': 'BUY',
        'type': 'MARKET',
        'timestamp': '1700000000000',
      });
      expect(query, 'symbol=BTCUSDT&side=BUY&type=MARKET&timestamp=1700000000000');
    });

    test('percent-encodes keys and values', () {
      final String query = buildQueryString(<String, String>{
        'symbol': 'BTC/USDT',
        'note': 'a b',
      });
      expect(query, 'symbol=BTC%2FUSDT&note=a%20b');
    });

    test('signQuery signs exactly the query that is built', () {
      const Map<String, String> params = <String, String>{'a': '1', 'b': '2'};
      final String query = buildQueryString(params);
      expect(
        signQuery(secret: 'topsecret', parameters: params),
        buildSignature(secret: 'topsecret', query: query),
      );
    });
  });
}
