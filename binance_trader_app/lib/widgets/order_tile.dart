// One order row in the Orders tab (open orders and history).

import 'package:flutter/material.dart';

import '../models/binance_order.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'status_pill.dart';

class OrderTile extends StatelessWidget {
  const OrderTile({
    super.key,
    required this.order,
    this.onCancel,
    this.cancelling = false,
    this.showSymbol = true,
  });

  final BinanceOrder order;

  /// Provided only for cancellable (open) orders.
  final VoidCallback? onCancel;

  /// True while this specific order is being cancelled.
  final bool cancelling;

  /// Hidden when the list is filtered to a single symbol.
  final bool showSymbol;

  @override
  Widget build(BuildContext context) {
    final bool isBuy = order.side.isBuy;
    final Color sideColor = isBuy ? AppColors.green : AppColors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              StatusPill(
                label: order.side.apiValue,
                background: isBuy ? AppColors.greenSoft : AppColors.redSoft,
                foreground: sideColor,
              ),
              const SizedBox(width: 8),
              if (showSymbol) ...<Widget>[
                Text(
                  order.symbol,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(order.type.label, style: AppTextStyles.caption),
              const Spacer(),
              _StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _Field(
                  label: 'Quantity',
                  value: formatAmount(order.origQuantity),
                ),
              ),
              Expanded(
                child: _Field(
                  label: order.executedQuantity > 0 ? 'Avg. price' : 'Price',
                  value: order.displayPrice > 0
                      ? formatPrice(order.displayPrice)
                      : 'Market',
                ),
              ),
              Expanded(
                child: _Field(
                  label: 'Filled',
                  value: '${(order.fillRatio * 100).toStringAsFixed(1)}%',
                  valueColor: order.status == OrderStatus.filled
                      ? AppColors.green
                      : null,
                ),
              ),
            ],
          ),
          if (order.executedQuantity > 0 &&
              order.cummulativeQuoteQuantity > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Executed ${formatAmount(order.executedQuantity)} for '
              '${formatAmount(order.cummulativeQuoteQuantity)} '
              '${_quoteOf(order)}',
              style: AppTextStyles.caption,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${formatTimestamp(order.createdAtMs)} · #${order.orderId}',
                  style: AppTextStyles.caption,
                ),
              ),
              if (order.fills.isNotEmpty)
                Text('Fees ${order.feesText}', style: AppTextStyles.caption),
            ],
          ),
          if (onCancel != null) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: cancelling ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(cancelling ? 'Cancelling…' : 'Cancel order'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Best effort quote asset extraction (`BTCUSDT` -> `USDT`).
  String _quoteOf(BinanceOrder order) {
    const List<String> quotes = <String>[
      'USDT',
      'FDUSD',
      'USDC',
      'TUSD',
      'BUSD',
      'BTC',
      'ETH',
      'BNB',
      'EUR',
      'TRY',
      'BRL',
    ];
    for (final String quote in quotes) {
      if (order.symbol.length > quote.length && order.symbol.endsWith(quote)) {
        return quote;
      }
    }
    return '';
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTextStyles.monoSmall.copyWith(
            color: valueColor ?? AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.filled) {
      return StatusPill.success(label: status.label, dense: true);
    }
    if (status == OrderStatus.rejected || status == OrderStatus.expired) {
      return StatusPill.danger(label: status.label, dense: true);
    }
    if (status.isOpen) {
      return StatusPill.info(label: status.label, dense: true);
    }
    return StatusPill.neutral(label: status.label, dense: true);
  }
}
