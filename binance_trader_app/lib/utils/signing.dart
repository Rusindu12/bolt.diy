// Request signing helpers for Binance's SIGNED (private) endpoints.
//
// Binance requires every private request to carry:
//   1. a `timestamp` (and optionally `recvWindow`) parameter,
//   2. a `signature` = HMAC-SHA256(secret, queryString) rendered as lowercase hex.
// The signature is computed over the *exact* query string that is sent, so the
// query is built once and reused for both signing and the request URL.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// HMAC-SHA256 of [payload] using [secret], returned as lowercase hex.
///
/// Exposed as a top level function (instead of being buried in the HTTP
/// service) so it can be unit tested against published test vectors.
String hmacSha256Hex({required String secret, required String payload}) {
  final Hmac hmac = Hmac(sha256, utf8.encode(secret));
  return hmac.convert(utf8.encode(payload)).toString();
}

/// Builds a canonical, percent-encoded query string from [parameters].
///
/// Insertion order of the map is preserved, which keeps requests reproducible
/// and makes logging/signing deterministic.
String buildQueryString(Map<String, String> parameters) {
  final StringBuffer buffer = StringBuffer();
  bool first = true;
  parameters.forEach((key, value) {
    if (!first) {
      buffer.write('&');
    }
    first = false;
    // `Uri.encodeComponent` (RFC 3986) rather than `encodeQueryComponent`:
    // the latter applies HTML form rules and would turn a space into '+'.
    buffer
      ..write(Uri.encodeComponent(key))
      ..write('=')
      ..write(Uri.encodeComponent(value));
  });
  return buffer.toString();
}

/// Convenience wrapper: signs a query string built from [parameters].
String signQuery({
  required String secret,
  required Map<String, String> parameters,
}) {
  final String query = buildQueryString(parameters);
  return buildSignature(secret: secret, query: query);
}

/// Signs an already built [query] string.
String buildSignature({required String secret, required String query}) =>
    hmacSha256Hex(secret: secret, payload: query);
