// Unit tests for the display/input formatting helpers.

import 'package:binance_trader_app/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPrice', () {
    test('uses two decimals for large prices', () {
      // Deliberately unambiguous values: Dart's toStringAsFixed uses
      // ECMAScript rounding, where an exact .xx5 tie rounds away from zero.
      expect(formatPrice(50000.126), '50,000.13');
      expect(formatPrice(50000.124), '50,000.12');
      expect(formatPrice(1234.5), '1,234.50');
    });

    test('adds decimals for small prices', () {
      expect(formatPrice(1.2345), '1.2345');
      expect(formatPrice(0.5), '0.50000');
      // Below 0.0001 the full 8-decimal precision is kept so that meme-coin
      // prices stay readable.
      expect(formatPrice(0.00001234), '0.00001234');
      expect(formatPrice(0.00012345), '0.000123');
    });

    test('handles zero and non finite values', () {
      expect(formatPrice(0), '0.00');
      expect(formatPrice(double.nan), '--');
      expect(formatPrice(double.infinity), '--');
    });
  });

  group('formatAmount', () {
    test('drops trailing zeros', () {
      expect(formatAmount(1.23000000), '1.23');
      expect(formatAmount(0.00001000), '0.00001');
      expect(formatAmount(0), '0');
    });

    test('groups thousands', () {
      expect(formatAmount(1234567.0), '1,234,567');
      expect(formatAmount(-2500.5), '-2,500.5');
    });
  });

  group('formatInputValue', () {
    test('produces text suitable for a text field', () {
      expect(formatInputValue(0.00001), '0.00001');
      expect(formatInputValue(1234.5), '1234.5');
      expect(formatInputValue(2.0), '2');
      expect(formatInputValue(double.nan), '');
    });
  });

  group('parseDecimalInput', () {
    test('accepts plain and grouped numbers', () {
      expect(parseDecimalInput('1234.5'), 1234.5);
      expect(parseDecimalInput('1,234.5'), 1234.5);
      expect(parseDecimalInput('1,5'), 1.5);
      expect(parseDecimalInput(' 42 '), 42);
    });

    test('returns null for invalid input', () {
      expect(parseDecimalInput(''), isNull);
      expect(parseDecimalInput('abc'), isNull);
      expect(parseDecimalInput('1.2.3'), isNull);
    });
  });

  group('formatPercentChange', () {
    test('always carries a sign', () {
      expect(formatPercentChange(2.3456), '+2.35%');
      expect(formatPercentChange(-0.5), '-0.50%');
      expect(formatPercentChange(0), '0.00%');
    });
  });

  group('formatCompact', () {
    test('abbreviates large volumes', () {
      expect(formatCompact(950), '950.00');
      expect(formatCompact(1500), '1.50K');
      expect(formatCompact(2500000), '2.50M');
      expect(formatCompact(3000000000), '3.00B');
    });
  });

  group('formatTimestamp', () {
    test('formats epoch milliseconds', () {
      // 2024-01-01T00:00:00Z; local time depends on the test machine, so only
      // the shape is asserted.
      final String formatted = formatTimestamp(1704067200000);
      expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(formatted), isTrue);
    });

    test('falls back for missing timestamps', () {
      expect(formatTimestamp(0), '--');
    });
  });

  group('maskSecret', () {
    test('keeps the ends of long values', () {
      expect(maskSecret('ABCD1234EFGH5678'), 'ABCD...5678');
      expect(maskSecret('short'), '*****');
      expect(maskSecret(''), '');
    });
  });
}
