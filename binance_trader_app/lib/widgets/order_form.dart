// Order entry: market + limit orders with full local validation.
//
// Flow: type an amount -> local filter check (min qty, step size, min notional,
// available balance) -> confirmation dialog -> signed REST call -> receipt.
// The confirmation dialog is always shown, and it is impossible to place an
// order without passing the local checks first.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/binance_order.dart';
import '../models/symbol_info.dart';
import '../providers/app_state.dart';
import '../providers/orders_state.dart';
import '../providers/trade_state.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'app_card.dart';
import 'app_text_field.dart';
import 'info_banner.dart';
import 'segmented_toggle.dart';
import 'status_pill.dart';

/// Denomination of the amount field for market orders.
enum AmountDenomination {
  base('Base asset'),
  quote('Quote asset');

  const AmountDenomination(this.label);

  final String label;
}

class OrderForm extends StatefulWidget {
  const OrderForm({super.key, this.onOpenSettings});

  /// Invoked by the "Add API keys" action in read-only mode.
  final VoidCallback? onOpenSettings;

  @override
  State<OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<OrderForm> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  AmountDenomination _denomination = AmountDenomination.base;
  String? _localError;

  @override
  void dispose() {
    _amountController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final TradeState trade = context.watch<TradeState>();
    final SymbolInfo? info = app.symbolInfo;

    // ---- trading disabled (read-only mode or no keys) --------------------
    if (!trade.canTrade) {
      return AppCard(
        title: 'Order entry',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              app.readOnlyMode ? 'Read-only mode' : 'API keys required',
              style: AppTextStyles.title.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              app.readOnlyMode
                  ? 'You are browsing market data without trading. Add a Binance '
                      'API key (with trading permission) to place orders.'
                  : 'Add your Binance API key and secret to trade '
                      '${app.symbol}.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 14),
            if (widget.onOpenSettings != null)
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: widget.onOpenSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Add API keys', style: AppTextStyles.button),
                ),
              ),
          ],
        ),
      );
    }

    if (info == null) {
      return AppCard(
        title: 'Order entry',
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                app.symbolsError ??
                    'Loading trading rules for ${app.symbol} from Binance…',
                style: AppTextStyles.bodyMuted,
              ),
            ),
          ],
        ),
      );
    }

    final Color sideColor = trade.isBuy ? AppColors.green : AppColors.red;
    final double referencePrice = trade.referencePrice;
    final double? typedAmount = parseDecimalInput(_amountController.text);
    final double? typedPrice = parseDecimalInput(_priceController.text);
    final double notional = _estimateNotional(
      trade: trade,
      typedAmount: typedAmount,
      typedPrice: typedPrice,
      referencePrice: referencePrice,
    );

    return AppCard(
      accent: sideColor,
      title: 'Order entry',
      subtitle: 'Min ${info.minimumQuantityText(market: trade.isMarket)}'
          '${info.minNotional > 0 ? ' · min value ${info.minimumNotionalText}' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- buy / sell ------------------------------------------------
          SegmentedToggle<OrderSide>(
            values: const <OrderSide>[OrderSide.buy, OrderSide.sell],
            selected: trade.side,
            labelBuilder: (OrderSide side) => side.label,
            activeColor: sideColor,
            activeTextColor: AppColors.background,
            onChanged: (OrderSide side) {
              trade.setSide(side);
              _clearLocalError();
            },
          ),
          const SizedBox(height: 8),
          // ---- market / limit --------------------------------------------
          SegmentedToggle<OrderType>(
            values: const <OrderType>[OrderType.market, OrderType.limit],
            selected: trade.orderType,
            labelBuilder: (OrderType type) => type.label,
            background: AppColors.background,
            activeColor: AppColors.surfaceAlt,
            activeTextColor: AppColors.primary,
            onChanged: (OrderType type) {
              trade.setOrderType(type);
              _clearLocalError();
              if (type == OrderType.limit && _priceController.text.trim().isEmpty) {
                final double price = referencePrice;
                if (price > 0) {
                  _priceController.text = info.formatPriceValue(
                    info.normalizePrice(price),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 14),

          // ---- amount denomination (market orders only) -------------------
          if (trade.isMarket) ...<Widget>[
            Text(
              _denomination == AmountDenomination.base
                  ? 'Amount in ${info.baseAsset}'
                  : 'Amount in ${info.quoteAsset}',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 6),
            SegmentedToggle<AmountDenomination>(
              values: const <AmountDenomination>[
                AmountDenomination.base,
                AmountDenomination.quote,
              ],
              selected: _denomination,
              labelBuilder: (AmountDenomination value) =>
                  value == AmountDenomination.base ? info.baseAsset : info.quoteAsset,
              background: AppColors.background,
              activeColor: AppColors.surfaceAlt,
              activeTextColor: AppColors.primary,
              verticalPadding: 8,
              onChanged: (AmountDenomination value) {
                setState(() {
                  _denomination = value;
                  _localError = null;
                });
              },
            ),
            const SizedBox(height: 14),
          ],

          // ---- amount ----------------------------------------------------
          AppTextField(
            controller: _amountController,
            label: 'Amount',
            hint: _amountHint(trade),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalInputFormatters,
            monospace: true,
            onChanged: (String value) => _clearLocalError(),
            suffix: _denominationSuffix(info, trade),
          ),

          // ---- price (limit orders only) ---------------------------------
          if (!trade.isMarket) ...<Widget>[
            const SizedBox(height: 12),
            AppTextField(
              controller: _priceController,
              label: 'Limit price (${info.quoteAsset})',
              hint: 'Tick size ${info.formatPriceValue(info.tickSize)}',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalInputFormatters,
              monospace: true,
              onChanged: (String value) => _clearLocalError(),
              suffix: TextButton(
                onPressed: referencePrice > 0
                    ? () {
                        _priceController.text = info.formatPriceValue(
                          info.normalizePrice(referencePrice),
                        );
                        _clearLocalError();
                      }
                    : null,
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('Market', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],

          const SizedBox(height: 12),
          _PercentRow(
            onSelected: (double fraction) =>
                _applyPercent(fraction, app, trade, info),
          ),
          const SizedBox(height: 14),

          // ---- summary ---------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: <Widget>[
                KeyValueRow(
                  label: 'Available',
                  value: trade.availableForSideText,
                  dense: true,
                ),
                KeyValueRow(
                  label: trade.isMarket ? 'Market price' : 'Limit price',
                  value: trade.isMarket
                      ? (referencePrice > 0
                          ? '~${formatPrice(referencePrice)} ${info.quoteAsset}'
                          : 'waiting for tick…')
                      : (typedPrice == null || typedPrice <= 0
                          ? '--'
                          : '${formatPrice(typedPrice)} ${info.quoteAsset}'),
                  dense: true,
                ),
                KeyValueRow(
                  label: trade.isMarket ? 'Estimated value' : 'Total',
                  value: notional > 0
                      ? '${formatAmount(notional)} ${info.quoteAsset}'
                      : '--',
                  dense: true,
                ),
              ],
            ),
          ),

          if (_localError != null || trade.error != null) ...<Widget>[
            const SizedBox(height: 12),
            InfoBanner.error(
              message: _localError ?? trade.error!,
              onDismiss: () {
                _clearLocalError();
                trade.clearError();
              },
            ),
          ],

          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: trade.submitting ? null : () => _submit(validateOnly: false),
              style: FilledButton.styleFrom(
                backgroundColor: sideColor,
                foregroundColor: AppColors.background,
                disabledBackgroundColor: AppColors.surfaceAlt,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: trade.submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background,
                      ),
                    )
                  : Text(
                      '${trade.side.label} ${info.baseAsset}',
                      style: AppTextStyles.button,
                    ),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: trade.submitting ? null : () => _submit(validateOnly: true),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text(
              'Dry run (validate without placing)',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- helpers ----

  String _amountHint(TradeState trade) {
    if (trade.isMarket && _denomination == AmountDenomination.quote) {
      return trade.isBuy
          ? 'Quote amount to spend'
          : 'Quote value to receive';
    }
    return trade.isMarket ? 'Base amount to ${trade.side.label.toLowerCase()}' : 'Base amount';
  }

  Widget? _denominationSuffix(SymbolInfo info, TradeState trade) {
    final bool isQuoteAmount =
        trade.isMarket && _denomination == AmountDenomination.quote;
    final String asset = isQuoteAmount ? info.quoteAsset : info.baseAsset;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        widthFactor: 1,
        child: Text(
          asset,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  double _estimateNotional({
    required TradeState trade,
    required double? typedAmount,
    required double? typedPrice,
    required double referencePrice,
  }) {
    if (typedAmount == null || typedAmount <= 0) {
      return 0;
    }
    if (trade.isMarket) {
      if (_denomination == AmountDenomination.quote) {
        return typedAmount;
      }
      return referencePrice > 0 ? typedAmount * referencePrice : 0;
    }
    if (typedPrice == null || typedPrice <= 0) {
      return 0;
    }
    return typedAmount * typedPrice;
  }

  void _clearLocalError() {
    if (_localError != null) {
      setState(() => _localError = null);
    }
  }

  /// Fills the amount field for the 25/50/75/100 % buttons.
  void _applyPercent(
    double fraction,
    AppState app,
    TradeState trade,
    SymbolInfo info,
  ) {
    final double price = trade.isMarket
        ? trade.referencePrice
        : (parseDecimalInput(_priceController.text) ?? trade.referencePrice);
    if (price <= 0) {
      setState(() => _localError =
          'No price available yet. Enter the amount manually.');
      return;
    }

    // Leave a hair of headroom on "100 %" so rounding never overshoots the
    // available balance (Binance rejects the order if it does).
    final double used = fraction >= 1 ? 0.999 : fraction;
    final String text;

    if (trade.isMarket && _denomination == AmountDenomination.quote) {
      final double quoteValue = trade.isBuy
          ? trade.availableQuote * used
          : trade.availableBase * price * used;
      text = formatInputValue(quoteValue, maxDecimals: 8);
    } else if (trade.isBuy) {
      final double quantity = info.maxAffordableQuantity(
        trade.availableQuote * used,
        price,
        market: trade.isMarket,
      );
      text = info.formatQuantity(quantity, market: trade.isMarket);
    } else {
      final double quantity = info.normalizeQuantity(
        trade.availableBase * used,
        market: trade.isMarket,
      );
      text = info.formatQuantity(quantity, market: trade.isMarket);
    }

    setState(() {
      _localError = null;
      _amountController.text = text;
      _amountController.selection =
          TextSelection.collapsed(offset: text.length);
    });
  }

  // ------------------------------------------------------------- placing ----

  Future<void> _submit({required bool validateOnly}) async {
    final AppState app = context.read<AppState>();
    final TradeState trade = context.read<TradeState>();
    final OrdersState orders = context.read<OrdersState>();
    final SymbolInfo? info = app.symbolInfo;

    if (info == null) {
      setState(() => _localError = 'Trading rules are still loading.');
      return;
    }
    FocusScope.of(context).unfocus();

    final double? typedAmount = parseDecimalInput(_amountController.text);
    if (typedAmount == null || typedAmount <= 0) {
      setState(() => _localError = 'Enter an amount greater than zero.');
      return;
    }

    double? quantity;
    double? quoteAmount;
    double? limitPrice;

    if (trade.isMarket) {
      if (_denomination == AmountDenomination.quote) {
        quoteAmount = typedAmount;
      } else {
        quantity = info.normalizeQuantity(typedAmount, market: true);
      }
    } else {
      final double? typedPrice = parseDecimalInput(_priceController.text);
      if (typedPrice == null || typedPrice <= 0) {
        setState(() => _localError = 'Enter a limit price greater than zero.');
        return;
      }
      quantity = info.normalizeQuantity(typedAmount);
      limitPrice = info.normalizePrice(typedPrice);
    }

    // Pre-flight validation with the exact values that will be signed.
    final String? validationError = trade.isMarket
        ? trade.validateMarketAmount(quantity: quantity, quoteAmount: quoteAmount)
        : trade.validateLimitOrder(quantity: quantity, price: limitPrice);
    if (validationError != null) {
      setState(() => _localError = validationError);
      return;
    }
    setState(() => _localError = null);

    final bool confirmed = await _confirm(
      app: app,
      trade: trade,
      info: info,
      quantity: quantity,
      quoteAmount: quoteAmount,
      price: limitPrice,
      validateOnly: validateOnly,
    );
    if (!confirmed || !mounted) {
      return;
    }

    final BinanceOrder? order = trade.isMarket
        ? await trade.placeMarketOrder(
            quantity: quantity,
            quoteAmount: quoteAmount,
            validateOnly: validateOnly,
          )
        : await trade.placeLimitOrder(
            quantity: quantity ?? 0,
            price: limitPrice ?? 0,
            validateOnly: validateOnly,
          );

    if (!mounted) {
      return;
    }
    if (order == null) {
      _showSnack(trade.error ?? 'The order could not be placed.', isError: true);
      return;
    }

    _showReceipt(app: app, trade: trade, order: order, validateOnly: validateOnly);
    if (!validateOnly) {
      unawaited(orders.refreshAll(silent: true));
      unawaited(app.refreshAccount(silent: true));
    }
  }

  Future<bool> _confirm({
    required AppState app,
    required TradeState trade,
    required SymbolInfo info,
    required double? quantity,
    required double? quoteAmount,
    required double? price,
    required bool validateOnly,
  }) async {
    final double marketPrice = trade.referencePrice;
    final double estimatedValue =
        quoteAmount ?? ((quantity ?? 0) * (price ?? marketPrice));

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            validateOnly ? 'Validate order' : 'Confirm order',
            style: AppTextStyles.title.copyWith(fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StatusPill(
                      label: app.environment.shortLabel.toUpperCase(),
                      background: app.environment.isLive
                          ? AppColors.redSoft
                          : AppColors.greenSoft,
                      foreground: app.environment.isLive
                          ? AppColors.red
                          : AppColors.green,
                    ),
                    const SizedBox(width: 6),
                    StatusPill(
                      label: trade.side.label.toUpperCase(),
                      background: trade.isBuy
                          ? AppColors.greenSoft
                          : AppColors.redSoft,
                      foreground: trade.isBuy ? AppColors.green : AppColors.red,
                    ),
                    const SizedBox(width: 6),
                    StatusPill.neutral(label: trade.orderType.label.toUpperCase()),
                  ],
                ),
                const SizedBox(height: 12),
                KeyValueRow(label: 'Pair', value: info.symbol),
                if (quoteAmount != null)
                  KeyValueRow(
                    label: 'Spend',
                    value:
                        '${formatAmount(quoteAmount)} ${info.quoteAsset}',
                  )
                else
                  KeyValueRow(
                    label: 'Quantity',
                    value: '${formatAmount(quantity ?? 0)} ${info.baseAsset}',
                  ),
                if (price != null)
                  KeyValueRow(
                    label: 'Limit price',
                    value: '${formatPrice(price)} ${info.quoteAsset}',
                  )
                else
                  KeyValueRow(
                    label: 'Market price',
                    value: marketPrice > 0
                        ? '~${formatPrice(marketPrice)} ${info.quoteAsset}'
                        : 'unknown',
                  ),
                KeyValueRow(
                  label: 'Estimated value',
                  value: '~${formatAmount(estimatedValue)} ${info.quoteAsset}',
                ),
                const SizedBox(height: 10),
                if (validateOnly)
                  const Text(
                    'Dry run: the order is validated by Binance but never '
                    'placed on the book.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  )
                else if (app.environment.isLive)
                  const Text(
                    'LIVE trading: this uses real funds. Market orders execute '
                    'immediately at the best available price.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.red,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor:
                    trade.isBuy ? AppColors.green : AppColors.red,
                foregroundColor: AppColors.background,
              ),
              child: Text(validateOnly ? 'Validate' : 'Confirm'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _showReceipt({
    required AppState app,
    required TradeState trade,
    required BinanceOrder order,
    required bool validateOnly,
  }) {
    final String statusLine = validateOnly
        ? 'Order validated - Binance would accept it.'
        : 'Order ${order.status.label.toLowerCase()} on ${app.environment.shortLabel}.';

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: <Widget>[
            Icon(
              validateOnly ? Icons.verified_outlined : Icons.check_circle_outline,
              color: validateOnly ? AppColors.blue : AppColors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                validateOnly ? 'Validated' : 'Order placed',
                style: AppTextStyles.title.copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(statusLine, style: AppTextStyles.bodyMuted),
              const SizedBox(height: 12),
              KeyValueRow(label: 'Pair', value: order.symbol),
              KeyValueRow(
                label: 'Order id',
                value: validateOnly ? 'dry run' : '#${order.orderId}',
              ),
              KeyValueRow(
                label: 'Side / type',
                value: '${order.side.label} · ${order.type.label}',
              ),
              KeyValueRow(
                label: 'Quantity',
                value: formatAmount(order.origQuantity),
              ),
              KeyValueRow(
                label: 'Executed',
                value: formatAmount(order.executedQuantity),
              ),
              if (order.displayPrice > 0)
                KeyValueRow(
                  label: 'Avg. price',
                  value: formatPrice(order.displayPrice),
                ),
              if (order.cummulativeQuoteQuantity > 0)
                KeyValueRow(
                  label: 'Value',
                  value: formatAmount(order.cummulativeQuoteQuantity),
                ),
              if (order.fills.isNotEmpty)
                KeyValueRow(label: 'Fees', value: order.feesText),
              const SizedBox(height: 6),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

/// 25 / 50 / 75 / 100 % quick-fill buttons.
class _PercentRow extends StatelessWidget {
  const _PercentRow({required this.onSelected});

  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    const List<double> fractions = <double>[0.25, 0.5, 0.75, 1];
    return Row(
      children: <Widget>[
        for (final double fraction in fractions)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(fraction),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(fraction * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
