// Trade tab: pair selector, live price, order entry and the trade tape.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/order_form.dart';
import '../widgets/price_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/symbol_picker_sheet.dart';
import 'setup_screen.dart';

class TradeScreen extends StatelessWidget {
  const TradeScreen({super.key});

  Future<void> _openSymbolPicker(BuildContext context) async {
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

  Future<void> _openKeySetup(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) =>
            const SetupScreen(isInitialSetup: false),
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final AppState app = context.read<AppState>();
    await Future.wait<void>(<Future<void>>[
      app.refreshTickerStats(),
      app.refreshAccount(silent: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();

    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: <Widget>[
          _SymbolSelector(
            app: app,
            onTap: () => _openSymbolPicker(context),
          ),
          const SizedBox(height: 12),
          const LivePriceCard(),
          const SizedBox(height: 12),
          OrderForm(onOpenSettings: () => _openKeySetup(context)),
          const SizedBox(height: 12),
          const TradeTape(),
        ],
      ),
    );
  }
}

/// Compact "trading pair" card that opens the picker when tapped.
class _SymbolSelector extends StatelessWidget {
  const _SymbolSelector({required this.app, required this.onTap});

  final AppState app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool live = app.environment.isLive;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Trading pair', style: AppTextStyles.caption),
                const SizedBox(height: 3),
                Text(
                  app.symbol,
                  style: AppTextStyles.title.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  '${app.baseAsset} / ${app.quoteAsset} · spot',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              StatusPill(
                label: live ? 'LIVE' : 'TESTNET',
                background: live ? AppColors.redSoft : AppColors.greenSoft,
                foreground: live ? AppColors.red : AppColors.green,
                dense: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Change pair',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.unfold_more, color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}
