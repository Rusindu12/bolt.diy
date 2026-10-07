// Orders tab: working orders (cancellable) and order history.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/binance_order.dart';
import '../providers/app_state.dart';
import '../providers/orders_state.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_banner.dart';
import '../widgets/order_tile.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/symbol_picker_sheet.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.isActive = true});

  /// True while this tab is the visible one (stops the auto-refresh timer when
  /// the user is looking at another tab).
  final bool isActive;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const List<int> _historyLimits = <int>[25, 50, 100];

  /// 0 = open orders, 1 = history.
  int _tab = 0;
  late OrdersState _orders;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Captured here (not in dispose) so the timer can always be stopped safely.
    _orders = context.read<OrdersState>();
    if (widget.isActive) {
      _startAutoRefresh();
    }
  }

  @override
  void didUpdateWidget(OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _startAutoRefresh();
    } else if (!widget.isActive && oldWidget.isActive) {
      _orders.stopAutoRefresh();
    }
  }

  @override
  void dispose() {
    _orders.stopAutoRefresh();
    super.dispose();
  }

  void _startAutoRefresh() {
    final AppState app = context.read<AppState>();
    final OrdersState orders = context.read<OrdersState>();
    orders.startAutoRefresh();
    if (app.hasCredentials && !app.readOnlyMode) {
      orders.refreshAll(silent: true);
    }
  }

  Future<void> _refresh() async {
    await _orders.refreshAll();
  }

  Future<void> _pickSymbol() async {
    final AppState app = context.read<AppState>();
    final String? selected = await showSymbolPicker(
      context,
      symbols: app.symbols,
      selected: app.symbol,
      loading: app.symbolsLoading,
      error: app.symbolsError,
      onRefresh: () => app.loadSymbols(forceRefresh: true),
    );
    if (selected == null) {
      return;
    }
    await app.setSymbol(selected);
  }

  Future<void> _confirmCancel(BinanceOrder order) async {
    final OrdersState orders = context.read<OrdersState>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel order?', style: AppTextStyles.title),
        content: Text(
          'Cancel ${order.side.label} ${order.type.label} '
          '#${order.orderId} for ${order.symbol}?\n\n'
          'Remaining quantity: ${formatAmount(order.remainingQuantity)}',
          style: AppTextStyles.bodyMuted,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final bool success = await orders.cancelOrder(order);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Order #${order.orderId} cancelled.'
              : (orders.openError ?? 'The order could not be cancelled.'),
        ),
        backgroundColor: success ? AppColors.green : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final OrdersState orders = context.watch<OrdersState>();
    final bool canLoad = app.hasCredentials && !app.readOnlyMode;

    if (!canLoad) {
      return const EmptyState(
        title: 'Order history locked',
        message:
            'API keys with trading permission are required to read open orders '
            'and order history.',
        icon: Icons.receipt_long_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: <Widget>[
          // ---- filters ---------------------------------------------------
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            onTap: _pickSymbol,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Symbol filter', style: AppTextStyles.caption),
                      const SizedBox(height: 3),
                      Text(
                        _tab == 0 && orders.allSymbols
                            ? 'All symbols'
                            : app.symbol,
                        style: AppTextStyles.title.copyWith(fontSize: 17),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.unfold_more,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SegmentedToggle<int>(
            values: const <int>[0, 1],
            selected: _tab,
            labelBuilder: (int value) => value == 0
                ? 'Open (${orders.openOrders.length})'
                : 'History (${orders.history.length})',
            background: AppColors.background,
            activeColor: AppColors.surfaceAlt,
            activeTextColor: AppColors.primary,
            onChanged: (int value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 12),
          if (_tab == 0)
            ..._buildOpenOrders(orders)
          else
            ..._buildHistory(app, orders),
        ],
      ),
    );
  }

  List<Widget> _buildOpenOrders(OrdersState orders) {
    return <Widget>[
      _ToggleRow(
        label: 'Show open orders of every symbol',
        description: 'Slower: reads the whole account',
        value: orders.allSymbols,
        onChanged: orders.setAllSymbols,
      ),
      const SizedBox(height: 10),
      if (orders.openError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InfoBanner.error(
            message: orders.openError!,
            title: 'Could not load open orders',
            actionLabel: 'Retry',
            onAction: () => orders.refreshOpenOrders(),
          ),
        ),
      if (orders.loadingOpen && orders.openOrders.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        )
      else if (orders.openOrders.isEmpty)
        const EmptyState(
          title: 'No open orders',
          message:
              'Limit orders that have not filled yet appear here and can be '
              'cancelled at any time.',
          icon: Icons.pending_actions_outlined,
        )
      else
        ...orders.openOrders.map(
          (BinanceOrder order) => OrderTile(
            order: order,
            showSymbol: orders.allSymbols,
            cancelling: orders.cancellingOrderId == '${order.orderId}',
            onCancel: () => _confirmCancel(order),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'Auto-refreshes every 20 s · GET /api/v3/openOrders',
        style: AppTextStyles.caption,
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _buildHistory(AppState app, OrdersState orders) {
    return <Widget>[
      Row(
        children: <Widget>[
          Text('Last', style: AppTextStyles.bodyMuted),
          const SizedBox(width: 10),
          for (final int limit in _historyLimits)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => orders.setHistoryLimit(limit),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: orders.historyLimit == limit
                        ? AppColors.primarySoft
                        : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$limit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: orders.historyLimit == limit
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Text('orders', style: AppTextStyles.caption),
        ],
      ),
      const SizedBox(height: 10),
      if (orders.historyError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InfoBanner.error(
            message: orders.historyError!,
            title: 'Could not load order history',
            actionLabel: 'Retry',
            onAction: () => orders.refreshHistory(),
          ),
        ),
      if (orders.loadingHistory && orders.history.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        )
      else if (orders.history.isEmpty)
        EmptyState(
          title: 'No orders yet',
          message:
              'Orders placed on ${app.symbol} (market and limit) are listed here '
              'with their fill status and fees.',
          icon: Icons.history,
        )
      else
        ...orders.history.map(
          (BinanceOrder order) => OrderTile(order: order, showSymbol: false),
        ),
      const SizedBox(height: 8),
      Text(
        'Newest first · GET /api/v3/allOrders',
        style: AppTextStyles.caption,
        textAlign: TextAlign.center,
      ),
    ];
  }
}

/// Checkbox style row without depending on platform styled checkboxes.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: value ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(description, style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
