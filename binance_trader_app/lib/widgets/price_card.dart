// Live price card + trade tape.
//
// The price text listens to `AppState.lastTick` (a ValueNotifier) so a burst of
// trades only rebuilds this small subtree instead of the whole screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/market_tick.dart';
import '../providers/app_state.dart';
import '../services/market_stream_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'app_card.dart';
import 'status_pill.dart';

class LivePriceCard extends StatelessWidget {
  const LivePriceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final TickerStats? stats = app.tickerStats;
    final double changePercent = stats?.priceChangePercent ?? 0;
    final bool isUp = changePercent >= 0;
    final Color trendColor = isUp ? AppColors.green : AppColors.red;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      title: '${app.baseAsset} / ${app.quoteAsset}',
      subtitle: 'Spot market · WebSocket stream',
      trailing: _StreamStatusPill(
        status: app.streamStatus,
        onReconnect: app.streamStatus.isConnected ? null : app.reconnectStream,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- live price -------------------------------------------------
          ValueListenableBuilder<MarketTick?>(
            valueListenable: app.lastTick,
            builder: (BuildContext context, MarketTick? tick, Widget? child) {
              final double price = tick?.price ?? stats?.lastPrice ?? 0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      price > 0 ? formatPrice(price) : '--',
                      style: AppTextStyles.display.copyWith(color: trendColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      app.quoteAsset,
                      style: AppTextStyles.bodyMuted,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              StatusPill(
                label: formatPercentChange(changePercent),
                background: isUp ? AppColors.greenSoft : AppColors.redSoft,
                foreground: trendColor,
                icon: isUp ? Icons.trending_up : Icons.trending_down,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stats == null
                      ? 'Loading 24h statistics…'
                      : '24h ${formatPrice(stats.priceChange)} ${app.quoteAsset}',
                  style: AppTextStyles.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: '24h high',
                  value: stats == null ? '--' : formatPrice(stats.highPrice),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: '24h low',
                  value: stats == null ? '--' : formatPrice(stats.lowPrice),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: '24h volume',
                  value: stats == null ? '--' : formatCompact(stats.volume),
                  suffix: app.baseAsset,
                ),
              ),
            ],
          ),
          if (app.streamError != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(Icons.wifi_off, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    app.streamError!,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.suffix});

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 3),
        Text(
          suffix == null ? value : '$value $suffix',
          style: AppTextStyles.monoSmall.copyWith(color: AppColors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StreamStatusPill extends StatelessWidget {
  const _StreamStatusPill({required this.status, this.onReconnect});

  final MarketStreamStatus status;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final StatusPill pill;
    if (status == MarketStreamStatus.connected) {
      pill = const StatusPill.success(label: 'LIVE', icon: Icons.bolt);
    } else if (status == MarketStreamStatus.connecting) {
      pill = const StatusPill.warning(label: 'CONNECTING');
    } else if (status == MarketStreamStatus.reconnecting) {
      pill = const StatusPill.warning(label: 'RETRYING');
    } else if (status == MarketStreamStatus.error) {
      pill = const StatusPill.danger(label: 'OFFLINE');
    } else {
      pill = const StatusPill.neutral(label: 'IDLE');
    }

    if (onReconnect == null) {
      return pill;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        pill,
        const SizedBox(width: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onReconnect,
          child: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Scrolling list of the most recent trades from the WebSocket stream.
class TradeTape extends StatelessWidget {
  const TradeTape({super.key, this.maxItems = 12});

  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final List<MarketTick> trades = app.recentTrades;
    if (trades.isEmpty) {
      return AppCard(
        title: 'Trade tape',
        child: Text(
          'Waiting for trades on ${app.symbol}…',
          style: AppTextStyles.bodyMuted,
        ),
      );
    }
    final List<MarketTick> visible =
        trades.length > maxItems ? trades.sublist(0, maxItems) : trades;

    return AppCard(
      title: 'Trade tape',
      subtitle: 'Newest first · from the live stream',
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        children: <Widget>[
          for (final MarketTick tick in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                  // Taker side: green when the buyer was the aggressor.
                  Icon(
                    tick.isAggressiveBuy ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: tick.isAggressiveBuy ? AppColors.green : AppColors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatPrice(tick.price),
                      style: AppTextStyles.mono.copyWith(
                        color: tick.isAggressiveBuy ? AppColors.green : AppColors.red,
                      ),
                    ),
                  ),
                  Text(
                    '${formatAmount(tick.quantity)} ${app.baseAsset}',
                    style: AppTextStyles.monoSmall,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 58,
                    child: Text(
                      formatClock(tick.tradeTimeMs),
                      textAlign: TextAlign.right,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
