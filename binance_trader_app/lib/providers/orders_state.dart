// State for the Orders tab: working orders, order history and cancellations.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/binance_environment.dart';
import '../models/binance_order.dart';
import 'app_state.dart';

/// Loads and mutates the order lists of the active account.
class OrdersState extends ChangeNotifier {
  OrdersState({required AppState app}) : _app = app {
    _app.addListener(_handleAppChange);
    _lastSymbol = _app.symbol;
    _lastEnvironment = _app.environment;
    _lastRevision = _app.revision;
  }

  /// Auto-refresh cadence while the Orders tab is visible.
  static const Duration _autoRefreshInterval = Duration(seconds: 20);

  final AppState _app;

  List<BinanceOrder> _openOrders = <BinanceOrder>[];
  List<BinanceOrder> _history = <BinanceOrder>[];
  bool _loadingOpen = false;
  bool _loadingHistory = false;
  String? _openError;
  String? _historyError;
  DateTime? _openFetchedAt;
  DateTime? _historyFetchedAt;
  int _historyLimit = 50;
  bool _allSymbols = false;
  String? _cancellingOrderId;
  String? _lastSymbol;
  BinanceEnvironment? _lastEnvironment;
  int _lastRevision = 0;
  Timer? _autoRefreshTimer;
  bool _disposed = false;

  // ------------------------------------------------------------- getters ----

  List<BinanceOrder> get openOrders => List<BinanceOrder>.unmodifiable(_openOrders);

  List<BinanceOrder> get history => List<BinanceOrder>.unmodifiable(_history);

  bool get loadingOpen => _loadingOpen;

  bool get loadingHistory => _loadingHistory;

  String? get openError => _openError;

  String? get historyError => _historyError;

  DateTime? get openFetchedAt => _openFetchedAt;

  DateTime? get historyFetchedAt => _historyFetchedAt;

  /// Order history window size (Binance caps a single page at 1000).
  int get historyLimit => _historyLimit;

  /// List open orders of the whole account (slower: weight 40 instead of 3).
  bool get allSymbols => _allSymbols;

  /// True when the account can read private endpoints.
  bool get canQuery => _app.hasCredentials && !_app.readOnlyMode;

  /// `#123456` while an order cancellation is in flight.
  String? get cancellingOrderId => _cancellingOrderId;

  bool get isRefreshing => _loadingOpen || _loadingHistory;

  // ------------------------------------------------------------ mutators ----

  void setAllSymbols(bool value) {
    if (_allSymbols == value) {
      return;
    }
    _allSymbols = value;
    _openOrders = <BinanceOrder>[];
    _openFetchedAt = null;
    notifyListeners();
    unawaited(refreshOpenOrders());
  }

  void setHistoryLimit(int value) {
    final int clamped = value.clamp(10, 1000);
    if (_historyLimit == clamped) {
      return;
    }
    _historyLimit = clamped;
    notifyListeners();
    unawaited(refreshHistory());
  }

  /// Starts the periodic refresh used while the Orders tab is on screen.
  void startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!_disposed && canQuery) {
        unawaited(refreshOpenOrders(silent: true));
      }
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  // ------------------------------------------------------------ loaders -----

  /// `GET /api/v3/openOrders` for the active symbol (or the whole account).
  Future<void> refreshOpenOrders({bool silent = false}) async {
    if (_loadingOpen) {
      return;
    }
    if (!canQuery) {
      _openOrders = <BinanceOrder>[];
      _openError = 'Add API keys with trading permission to see your orders.';
      notifyListeners();
      return;
    }
    _loadingOpen = true;
    if (!silent) {
      _openError = null;
      notifyListeners();
    }
    try {
      final List<BinanceOrder> orders = await _app.binance.fetchOpenOrders(
        symbol: _allSymbols ? null : _app.symbol,
      );
      _openOrders = _sortByRecency(orders);
      _openError = null;
      _openFetchedAt = DateTime.now();
    } catch (error) {
      _openError = describeError(error);
    } finally {
      _loadingOpen = false;
      _notify();
    }
  }

  /// `GET /api/v3/allOrders` for the active symbol.
  Future<void> refreshHistory({bool silent = false}) async {
    if (_loadingHistory) {
      return;
    }
    if (!canQuery) {
      _history = <BinanceOrder>[];
      _historyError = 'Add API keys with trading permission to see your orders.';
      notifyListeners();
      return;
    }
    _loadingHistory = true;
    if (!silent) {
      _historyError = null;
      notifyListeners();
    }
    try {
      final List<BinanceOrder> orders = await _app.binance.fetchOrderHistory(
        symbol: _app.symbol,
        limit: _historyLimit,
      );
      _history = _sortByRecency(orders);
      _historyError = null;
      _historyFetchedAt = DateTime.now();
    } catch (error) {
      _historyError = describeError(error);
    } finally {
      _loadingHistory = false;
      _notify();
    }
  }

  /// Refreshes both lists in parallel.
  Future<void> refreshAll({bool silent = false}) async {
    await Future.wait<void>(<Future<void>>[
      refreshOpenOrders(silent: silent),
      refreshHistory(silent: silent),
    ]);
  }

  /// `DELETE /api/v3/order`. Returns true when the order was cancelled.
  Future<bool> cancelOrder(BinanceOrder order) async {
    if (_cancellingOrderId != null) {
      return false;
    }
    _cancellingOrderId = '${order.orderId}';
    _openError = null;
    notifyListeners();
    try {
      await _app.binance.cancelOrder(
        symbol: order.symbol,
        orderId: order.orderId,
      );
      _openOrders = _openOrders
          .where((BinanceOrder item) => item.orderId != order.orderId)
          .toList(growable: false);
      unawaited(refreshAccountQuietly());
      return true;
    } catch (error) {
      _openError = describeError(error);
      return false;
    } finally {
      _cancellingOrderId = null;
      _notify();
      unawaited(refreshOpenOrders(silent: true));
    }
  }

  Future<void> refreshAccountQuietly() => _app.refreshAccount(silent: true);

  // -------------------------------------------------------- housekeeping ----

  List<BinanceOrder> _sortByRecency(List<BinanceOrder> orders) {
    final List<BinanceOrder> sorted = List<BinanceOrder>.of(orders);
    sorted.sort((BinanceOrder a, BinanceOrder b) {
      final int byTime = b.createdAtMs.compareTo(a.createdAtMs);
      if (byTime != 0) {
        return byTime;
      }
      return b.orderId.compareTo(a.orderId);
    });
    return sorted;
  }

  void _handleAppChange() {
    final bool changed = _lastSymbol != _app.symbol ||
        _lastEnvironment != _app.environment ||
        _lastRevision != _app.revision;
    if (!changed) {
      return;
    }
    _lastSymbol = _app.symbol;
    _lastEnvironment = _app.environment;
    _lastRevision = _app.revision;
    _openOrders = <BinanceOrder>[];
    _history = <BinanceOrder>[];
    _openFetchedAt = null;
    _historyFetchedAt = null;
    _openError = null;
    _historyError = null;
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopAutoRefresh();
    _app.removeListener(_handleAppChange);
    super.dispose();
  }
}
