// Balances tab: non-zero assets of the spot wallet.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_balance.dart';
import '../models/symbol_info.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/balance_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_banner.dart';
import 'setup_screen.dart';

class BalancesScreen extends StatefulWidget {
  const BalancesScreen({super.key, this.onOpenTrade});

  /// Switches to the Trade tab after a pair was selected from a balance.
  final VoidCallback? onOpenTrade;

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh once the first frame is on screen (keeps build side-effect free).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final AppState app = context.read<AppState>();
      if (app.hasCredentials && !app.readOnlyMode) {
        app.refreshAccount();
      }
    });
  }

  Future<void> _refresh() async {
    await context.read<AppState>().refreshAccount();
  }

  Future<void> _openKeySetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) =>
            const SetupScreen(isInitialSetup: false),
      ),
    );
  }

  /// Tapping a balance switches the trading pair to `<asset>USDT` (or the best
  /// available quote asset) and jumps to the Trade tab.
  Future<void> _tradeAsset(String asset) async {
    final AppState app = context.read<AppState>();
    final String? pair = _findPair(app, asset);
    if (pair == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No spot pair found for $asset in this environment.'),
          backgroundColor: AppColors.surfaceAlt,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await app.setSymbol(pair);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Trading pair switched to ${app.symbol}'),
        backgroundColor: AppColors.surfaceAlt,
        behavior: SnackBarBehavior.floating,
      ),
    );
    widget.onOpenTrade?.call();
  }

  String? _findPair(AppState app, String asset) {
    if (app.symbols.isEmpty) {
      return null;
    }
    final String direct = '${asset}USDT';
    if (SymbolInfo.find(app.symbols, direct) != null) {
      return direct;
    }
    final String withQuote = '$asset${app.quoteAsset}';
    if (SymbolInfo.find(app.symbols, withQuote) != null) {
      return withQuote;
    }
    for (final SymbolInfo info in app.symbols) {
      if (info.baseAsset == asset) {
        return info.symbol;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final List<AccountBalance> balances = app.balances;
    final AccountPermissions? permissions = app.permissions;
    final bool canLoad = app.hasCredentials && !app.readOnlyMode;

    if (!canLoad) {
      return EmptyState(
        title: 'Balances locked',
        message: app.readOnlyMode
            ? 'You are in read-only mode. Add an API key to read your spot '
                'balances from Binance.'
            : 'Add your API key and secret to load your balances.',
        icon: Icons.account_balance_wallet_outlined,
        actionLabel: 'Add API keys',
        onAction: _openKeySetup,
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
          AppCard(
            title: 'Spot wallet',
            subtitle: app.environment.label,
            trailing: IconButton(
              onPressed: app.accountLoading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 20),
              color: AppColors.textSecondary,
              tooltip: 'Reload balances',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${balances.length}',
                      style: AppTextStyles.display.copyWith(fontSize: 28),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        balances.length == 1 ? 'asset held' : 'assets held',
                        style: AppTextStyles.bodyMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                KeyValueRow(
                  label: 'Last updated',
                  value: app.accountFetchedAt == null
                      ? 'never'
                      : formatClock(app.accountFetchedAt!.millisecondsSinceEpoch),
                  dense: true,
                ),
                if (permissions != null) ...<Widget>[
                  KeyValueRow(
                    label: 'Trading permission',
                    value: permissions.canTrade ? 'enabled' : 'disabled',
                    valueColor:
                        permissions.canTrade ? AppColors.green : AppColors.red,
                    dense: true,
                  ),
                  KeyValueRow(
                    label: 'Maker / taker fee',
                    value: '${permissions.makerFeeText} / ${permissions.takerFeeText}',
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (permissions != null && permissions.canWithdraw)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InfoBanner.error(
                title: 'Dangerous key setting',
                message:
                    'This API key is allowed to withdraw funds. Disable '
                    '"Enable Withdrawals" in the Binance API settings - this app '
                    'never needs it.',
              ),
            ),
          if (app.accountError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoBanner.error(
                message: app.accountError!,
                title: 'Could not load balances',
                actionLabel: 'Retry',
                onAction: _refresh,
              ),
            ),
          if (app.accountLoading && balances.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (balances.isEmpty)
            const EmptyState(
              title: 'No assets yet',
              message:
                  'Every asset with a zero balance is hidden. Deposit funds or '
                  'place a trade to see balances here.',
              icon: Icons.savings_outlined,
            )
          else
            ...balances.map(
              (AccountBalance balance) => BalanceTile(
                balance: balance,
                highlighted: balance.asset == app.baseAsset ||
                    balance.asset == app.quoteAsset,
                onTap: () => _tradeAsset(balance.asset),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Source: GET /api/v3/account · zero balances are hidden',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
