// Display formatting helpers.
//
// All formatting is done manually (no locale package) so the binary stays slim
// and the output is identical on every device: prices use a magnitude aware
// number of decimals and amounts use thin thousands separators.

/// Formats a price with a sensible precision for its magnitude.
String formatPrice(double price) {
  if (!price.isFinite) {
    return '--';
  }
  final double abs = price.abs();
  if (abs == 0) {
    return '0.00';
  }
  if (abs >= 100) {
    return _grouped(price.toStringAsFixed(2));
  }
  if (abs >= 1) {
    return _grouped(price.toStringAsFixed(4));
  }
  if (abs >= 0.01) {
    return _grouped(price.toStringAsFixed(5));
  }
  if (abs >= 0.0001) {
    return _grouped(price.toStringAsFixed(6));
  }
  return _grouped(price.toStringAsFixed(8));
}

/// Formats a quantity/amount, trimming useless trailing zeros.
/// `1.23000000` becomes `1.23`, `0.00001000` becomes `0.00001`.
String formatAmount(double value, {int maxDecimals = 8}) {
  if (!value.isFinite) {
    return '--';
  }
  final int decimals = value == value.roundToDouble() && value.abs() < 1e15
      ? 0
      : maxDecimals;
  String text = value.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return _grouped(text);
}

/// Formats a fixed-precision amount without grouping, ready for API payloads
/// (Binance does not accept thousands separators).
String formatAmountRaw(double value, int decimals) =>
    value.toStringAsFixed(decimals);

/// Formats a number for a text input field: no thousands separators, trailing
/// zeros removed (`0.00001000` -> `0.00001`).
String formatInputValue(double value, {int maxDecimals = 8}) {
  if (!value.isFinite) {
    return '';
  }
  String text = value.toStringAsFixed(maxDecimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// `+2.34%` / `-0.51%` for 24h change badges.
String formatPercentChange(double percent) {
  final String sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(2)}%';
}

/// `1.2K`, `3.4M`, `5.6B` for trading volumes.
String formatCompact(double value) {
  final double abs = value.abs();
  if (abs >= 1e9) {
    return '${(value / 1e9).toStringAsFixed(2)}B';
  }
  if (abs >= 1e6) {
    return '${(value / 1e6).toStringAsFixed(2)}M';
  }
  if (abs >= 1e3) {
    return '${(value / 1e3).toStringAsFixed(2)}K';
  }
  return value.toStringAsFixed(2);
}

/// Formats a Binance millisecond timestamp as `2025-10-07 14:03:22` (device
/// local time).
String formatTimestamp(int milliseconds, {bool withDate = true}) {
  if (milliseconds <= 0) {
    return '--';
  }
  final DateTime date =
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: false).toLocal();
  final String time = '${_pad(date.hour)}:${_pad(date.minute)}:${_pad(date.second)}';
  if (!withDate) {
    return time;
  }
  return '${date.year}-${_pad(date.month)}-${_pad(date.day)} $time';
}

/// `14:03:22` for the live tape.
String formatClock(int milliseconds) => formatTimestamp(milliseconds, withDate: false);

/// Parses what the user typed into a number.
///
/// Accepts `1234.5`, `1234,5` (comma as decimal separator) and `1,234.5`
/// (comma as thousands separator). Returns null when the input is not a number.
double? parseDecimalInput(String raw) {
  String text = raw.trim().replaceAll(' ', '');
  if (text.isEmpty) {
    return null;
  }
  if (text.contains(',') && text.contains('.')) {
    // Both separators present: the comma can only be a grouping separator.
    text = text.replaceAll(',', '');
  } else if (text.contains(',')) {
    text = text.replaceAll(',', '.');
  }
  final double? value = double.tryParse(text);
  if (value == null || !value.isFinite) {
    return null;
  }
  return value;
}

/// Masks a secret for on-screen display: `A1B2C3D4...WXYZ` -> `A1B2...WXYZ`.
String maskSecret(String value) {
  if (value.isEmpty) {
    return '';
  }
  if (value.length <= 8) {
    return '${'*' * value.length}';
  }
  return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// Inserts thin thousands separators into the integer part of [number].
String _grouped(String number) {
  final bool negative = number.startsWith('-');
  final String unsigned = negative ? number.substring(1) : number;
  final int dotIndex = unsigned.indexOf('.');
  final String intPart = dotIndex == -1 ? unsigned : unsigned.substring(0, dotIndex);
  final String rest = dotIndex == -1 ? '' : unsigned.substring(dotIndex);

  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}${buffer.toString()}$rest';
}
