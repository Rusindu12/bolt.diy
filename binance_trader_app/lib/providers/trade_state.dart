// State for the Trade tab: the side/type toggles and order submission.
//
// The text currently typed in the quantity/price fields intentionally stays in
// the widget (TextEditingController) - only what must survive a rebuild or be
// shared between widgets (side, order type, submission status, last order) is
// kept here.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/binance_environment.dart';
import '../models/binance_order.dart';
import '../models/symbol_info.dart';
import 'app_state.dart';

/// Order entry state machine.
class TradeState extends ChangeNotifier {
  TradeState({required AppState app}) : _app = app {
    _app.addListener(_handleAppChange);
    _lastSymbol = _app.symbol;
    _lastEnvironment = _app.environment;
  }

  final AppState _app;

  OrderSide _side = OrderSide.buy;
  OrderType _orderType = OrderType.market;
  bool _submitting = false;
  BinanceOrder? _lastOrder;
  String? _error;
  String? _lastSymbol;
  BinanceEnvironment? _lastEnvironment;

  // ------------------------------------------------------------- getters ----

  OrderSide get side => _side;

  OrderType get orderType => _orderType;

  bool get submitting => _submitting;

  /// The most recent successfully placed (or validated) order.
  BinanceOrder? get lastOrder => _lastOrder;

  String? get error => _error;

  bool get isBuy => _side == OrderSide.buy;

  bool get isMarket => _orderType == OrderType.market;

  /// The pair currently selected in [AppState].
  String get symbol => _app.symbol;

  /// Exchange filters for the active pair (null until `exchangeInfo` loaded).
  SymbolInfo? get symbolInfo => _app.symbolInfo;

  /// Live price used for market orders and for the "notional" preview.
  double get referencePrice => _app.lastPrice;

  /// Free quote balance (what a buy can spend).
  double get availableQuote => _app.account.freeBalanceOf(_app.quoteAsset);

  /// Free base balance (what a sell can sell).
  double get availableBase => _app.account.freeBalanceOf(_app.baseAsset);

  /// Balance that limits the current order.
  double get availableForSide => isBuy ? availableQuote : availableBase;

  String get availableForSideText =>
      '${formatBalance(availableForSide)} ${isBuy ? _app.quoteAsset : _app.baseAsset}';

  /// True when the user can submit orders at all.
  bool get canTrade => _app.hasCredentials && !_app.readOnlyMode;

  // ------------------------------------------------------------ mutators ----

  void setSide(OrderSide value) {
    if (_side == value) {
      return;
    }
    _side = value;
    _error = null;
    notifyListeners();
  }

  void setOrderType(OrderType value) {
    if (_orderType == value) {
      return;
    }
    _orderType = value;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    notifyListeners();
  }

  void clearLastOrder() {
    if (_lastOrder == null) {
      return;
    }
    _lastOrder = null;
    notifyListeners();
  }

  // --------------------------------------------------------- order entry ----

  /// Local (pre-flight) validation of a market order.
  ///
  /// Catches the mistakes Binance would reject with `-1013`, so the user gets
  /// immediate feedback instead of a round trip.
  String? validateMarketAmount({
    double? quantity,
    double? quoteAmount,
  }) {
    if (!canTrade) {
      return 'Add API keys with trading permission to place orders.';
    }
    final SymbolInfo? info = symbolInfo;
    if (info == null) {
      return 'Still loading symbol rules. Try again in a moment.';
    }
    if (quoteAmount != null) {
      if (quoteAmount <= 0) {
        return 'Enter an amount greater than zero.';
      }
      final double price = referencePrice;
      if (info.minNotional > 0 && quoteAmount < info.minNotional) {
        return 'Minimum order value is ${info.minimumNotionalText}.';
      }
      if (price > 0) {
        // Round-trip check: the API converts the quote amount to base quantity.
        final double impliedQuantity = quoteAmount / price;
        if (impliedQuantity < info.minimumQuantity(market: true)) {
          return 'Amount too small: it buys less than '
              '${info.minimumQuantityText(market: true)}.';
        }
      }
      if (quoteAmount > availableQuote && availableQuote > 0) {
        return 'Not enough ${_app.quoteAsset}. Available: '
            '${formatBalance(availableQuote)} ${_app.quoteAsset}.';
      }
      return null;
    }

    if (quantity == null || quantity <= 0) {
      return 'Enter the amount you want to trade.';
    }
    final String? filterError = info.validateQuantity(
      quantity,
      market: true,
      // Without a reference price the notional check cannot be evaluated, so it
      // is skipped instead of guessed.
      referencePrice: referencePrice > 0 ? referencePrice : null,
      checkNotional: referencePrice > 0,
    );
    if (filterError != null) {
      return filterError;
    }
    if (quantity > availableBase && availableBase > 0) {
      return 'Not enough ${_app.baseAsset}. Available: '
          '${formatBalance(availableBase)} ${_app.baseAsset}.';
    }
    return null;
  }

  /// Local (pre-flight) validation of a limit order.
  String? validateLimitOrder({double? quantity, double? price}) {
    if (!canTrade) {
      return 'Add API keys with trading permission to place orders.';
    }
    final SymbolInfo? info = symbolInfo;
    if (info == null) {
      return 'Still loading symbol rules. Try again in a moment.';
    }
    if (price == null || price <= 0) {
      return 'Enter a limit price greater than zero.';
    }
    if (info.tickSize > 0 && !SymbolInfo.isAlignedToStep(price, info.tickSize)) {
      return 'Price must be a multiple of ${info.formatPriceValue(info.tickSize)}.';
    }
    if (quantity != null) {
      final String? filterError =
          info.validateQuantity(quantity, market: false, referencePrice: price);
      if (filterError != null) {
        return filterError;
      }
    }
    if (isBuy) {
      final double required = (quantity ?? 0) * price;
      if (required > availableQuote && availableQuote > 0) {
        return 'Not enough ${_app.quoteAsset}. Order needs '
            '${formatBalance(required)} ${_app.quoteAsset}.';
      }
    } else if (quantity != null && quantity > availableBase && availableBase > 0) {
      return 'Not enough ${_app.baseAsset}. Available: '
          '${formatBalance(availableBase)} ${_app.baseAsset}.';
    }
    return null;
  }

  /// Places a market order.
  ///
  /// Pass either [quantity] (base amount) or [quoteAmount] (e.g. "spend 50
  /// USDT"), never both.
  Future<BinanceOrder?> placeMarketOrder({
    double? quantity,
    double? quoteAmount,
    bool validateOnly = false,
  }) async {
    final String? validationError = validateMarketAmount(
      quantity: quantity,
      quoteAmount: quoteAmount,
    );
    if (validationError != null) {
      _error = validationError;
      notifyListeners();
      return null;
    }
    return _submit(
      validateOnly: validateOnly,
      action: () => _app.binance.placeMarketOrder(
        symbol: _app.symbol,
        side: _side,
        quantity: quantity,
        quoteOrderQuantity: quoteAmount,
        symbolInfo: symbolInfo,
        validateOnly: validateOnly,
      ),
    );
  }

  /// Places a limit order.
  Future<BinanceOrder?> placeLimitOrder({
    required double quantity,
    required double price,
    bool validateOnly = false,
  }) async {
    final String? validationError =
        validateLimitOrder(quantity: quantity, price: price);
    if (validationError != null) {
      _error = validationError;
      notifyListeners();
      return null;
    }
    return _submit(
      validateOnly: validateOnly,
      action: () => _app.binance.placeLimitOrder(
        symbol: _app.symbol,
        side: _side,
        quantity: quantity,
        price: price,
        symbolInfo: symbolInfo,
        validateOnly: validateOnly,
      ),
    );
  }

  Future<BinanceOrder?> _submit({
    required Future<BinanceOrder> Function() action,
    required bool validateOnly,
  }) async {
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final BinanceOrder order = await action();
      _lastOrder = order;
      if (!validateOnly) {
        // Refresh balances so the "available" figures match reality.
        unawaited(_app.refreshAccount(silent: true));
      }
      return order;
    } catch (error) {
      _error = describeError(error);
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------- housekeeping ----

  void _handleAppChange() {
    // Reset the form feedback when the pair or the environment changes so a
    // message never references the wrong symbol.
    if (_lastSymbol != _app.symbol || _lastEnvironment != _app.environment) {
      _lastSymbol = _app.symbol;
      _lastEnvironment = _app.environment;
      _error = null;
      _lastOrder = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _app.removeListener(_handleAppChange);
    super.dispose();
  }
}

/// Compact balance formatting shared by the trade widgets (`1.2345`).
String formatBalance(double value) {
  if (value == 0) {
    return '0';
  }
  if (value >= 1000) {
    return value.toStringAsFixed(2);
  }
  if (value >= 1) {
    return value.toStringAsFixed(4);
  }
  String text = value.toStringAsFixed(8);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  text = text.replaceFirst(RegExp(r'\.$'), '');
  return text;
}
