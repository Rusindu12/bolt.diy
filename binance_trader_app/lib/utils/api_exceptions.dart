// Typed exceptions + Binance error-code translation.
//
// Every failure surfaced to the UI is converted into a [BinanceApiException]
// (or [NetworkException]) carrying a short, user friendly [message] plus the
// raw technical detail for the expandable "technical details" section.

/// Base class so `catch (e)` blocks can distinguish our errors from bugs.
abstract class AppException implements Exception {
  const AppException(this.message, {this.detail});

  /// Short, user friendly description safe to show in a snackbar or banner.
  final String message;

  /// Technical detail (raw response / stack context) shown on demand.
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Any failure reported by Binance (HTTP 4xx/5xx with a JSON body).
class BinanceApiException extends AppException {
  const BinanceApiException({
    required super.message,
    this.code,
    this.httpStatus,
    super.detail,
  });

  /// Binance error code, e.g. `-2015`. Null for non-JSON failures.
  final int? code;

  /// HTTP status code that carried the error.
  final int? httpStatus;

  /// True when the request was rejected because the device clock drifted
  /// outside Binance's `recvWindow` (safe to retry after re-syncing the clock).
  bool get isTimestampError => code == -1021 || code == -1125;

  /// True when the key/secret pair is missing, invalid or unauthorised.
  bool get isAuthError =>
      code == -2015 || code == -2014 || code == -1022 || httpStatus == 401;

  /// True when Binance is rate limiting us.
  bool get isRateLimited => code == -1003 || httpStatus == 429 || httpStatus == 418;

  /// True when the request was rejected because of a filter violation
  /// (quantity/price precision, min notional, ...).
  bool get isFilterError => code == -1013 || code == -1111 || code == -2010;
}

/// Transport level failures: no connectivity, DNS, TLS, timeouts.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.detail});
}

/// Local validation failures (bad input, wrong precision, insufficient funds).
class ValidationException extends AppException {
  const ValidationException(super.message, {super.detail});
}

/// Keys / secret missing for an operation that requires signing.
class MissingCredentialsException extends AppException {
  const MissingCredentialsException()
      : super(
          'No API key configured. Add your Binance API key and secret first.',
        );
}

/// Converts Binance `{ "code": -1100, "msg": "..." }` payloads into something a
/// human can act on. Falls back to the raw message for unknown codes.
BinanceApiException mapBinanceError({
  required int httpStatus,
  required Object? body,
  Map<String, String>? headers,
}) {
  int? code;
  String rawMessage = 'Request failed with HTTP $httpStatus.';

  if (body is Map) {
    final dynamic rawCode = body['code'];
    if (rawCode is num) {
      code = rawCode.toInt();
    } else if (rawCode is String) {
      code = int.tryParse(rawCode);
    }
    final dynamic rawMsg = body['msg'];
    if (rawMsg is String && rawMsg.isNotEmpty) {
      rawMessage = rawMsg;
    }
  } else if (body is String && body.isNotEmpty) {
    // Binance sometimes answers with plain text (WAF / 403 / 5xx pages).
    rawMessage = body.length > 300 ? '${body.substring(0, 300)}...' : body;
  }

  final String friendly = _friendlyMessage(code, httpStatus, rawMessage);
  return BinanceApiException(
    message: friendly,
    code: code,
    httpStatus: httpStatus,
    detail: 'HTTP $httpStatus${code == null ? '' : ' / code $code'}: $rawMessage',
  );
}

String _friendlyMessage(int? code, int httpStatus, String rawMessage) {
  switch (code) {
    case -1003:
      return 'Binance rate limit reached. Wait a few seconds and try again.';
    case -1013:
    case -1111:
      return 'Order rejected: quantity or price does not match the symbol '
          'filters (step size / tick size / minimum notional).';
    case -1021:
      return 'Timestamp rejected by Binance. Your phone clock is out of sync - '
          'enable "Automatic date & time" in Android settings.';
    case -1022:
      return 'Signature mismatch. The API secret is incorrect or truncated.';
    case -1100:
      return 'Binance rejected a parameter. Check the symbol, side and amount.';
    case -1102:
      return 'Missing a mandatory parameter for this request.';
    case -1121:
      return 'Unknown symbol. Pick a symbol from the selector.';
    case -1125:
      return 'Timestamp for this request is outside the allowed window.';
    case -2010:
      return 'Order rejected by Binance. Usually insufficient balance or a '
          'filter violation.';
    case -2011:
      return 'Cancel rejected: the order is already filled or cancelled.';
    case -2013:
      return 'Order does not exist for this symbol.';
    case -2014:
      return 'Malformed API key. Paste the full key without spaces or quotes.';
    case -2015:
      return 'Invalid API key, IP or permissions. Check that the key belongs to '
          'this environment (Testnet vs Live), that "Enable Spot & Margin '
          'Trading" is ticked and that your IP is whitelisted.';
    case -1023:
    case -1024:
      return 'This account is not eligible for the requested operation.';
    case -2008:
      return 'Invalid asset/balance for this order.';
    default:
      break;
  }

  switch (httpStatus) {
    case 401:
      return 'Unauthorised (401). The API key is invalid or deleted.';
    case 403:
      return 'Forbidden (403). Binance blocked this request (WAF or region).';
    case 418:
      return 'Binance temporarily banned this IP after repeated rate limit '
          'violations. Stop trading for a few minutes.';
    case 429:
      return 'Too many requests. Slow down and retry in a moment.';
    case 451:
      return 'Binance is not available from your region (HTTP 451).';
    case 500:
    case 502:
    case 503:
    case 504:
      return 'Binance is having trouble (HTTP $httpStatus). Try again shortly.';
    default:
      break;
  }

  if (rawMessage.trim().isNotEmpty && rawMessage.length <= 180) {
    return rawMessage;
  }
  return 'Binance returned HTTP $httpStatus.';
}
