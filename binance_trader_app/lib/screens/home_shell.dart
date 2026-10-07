// Root scaffold: splash -> setup -> the four tabbed screens.
//
// Also the place where the app lifecycle is observed so the WebSocket is paused
// while the app is in the background and resumed on return.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_banner.dart';
import 'balances_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'trade_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tabIndex = 0;
  bool _riskDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppState app = context.read<AppState>();
    if (state == AppLifecycleState.resumed) {
      app.handleLifecycleChange(resumed: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      app.handleLifecycleChange(resumed: false);
    }
  }

  void selectTab(int index) {
    if (_tabIndex == index) {
      return;
    }
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();

    if (app.isInitializing) {
      return const _SplashScreen();
    }
    if (app.status == AppStatus.setupRequired) {
      return const SetupScreen();
    }

    _scheduleRiskDisclaimer(app);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _EnvironmentStrip(app: app),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: <Widget>[
                  const TradeScreen(),
                  BalancesScreen(onOpenTrade: () => selectTab(0)),
                  // `isActive` lets the orders list stop polling while hidden.
                  OrdersScreen(isActive: _tabIndex == 2),
                  const SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _tabIndex,
        onSelected: selectTab,
      ),
    );
  }

  /// Shows the risk disclaimer once per install (before the first trade).
  void _scheduleRiskDisclaimer(AppState app) {
    if (_riskDialogShown || app.riskAcknowledged) {
      return;
    }
    _riskDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _showRiskDisclaimer();
    });
  }

  Future<void> _showRiskDisclaimer() async {
    final AppState app = context.read<AppState>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Before you trade',
                style: AppTextStyles.title.copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const <Widget>[
              Text(
                'Trading cryptocurrency is risky. Prices can move sharply and you '
                'can lose money, including your entire deposit. Nothing in this '
                'app is financial advice.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Safety checklist',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '• Start on the Testnet environment.\n'
                '• Restrict your API key to your own IP address.\n'
                '• Never enable "Enable Withdrawals" on an API key.\n'
                '• Keep the secret only on this device.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
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
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    await app.acknowledgeRisk();
  }
}

/// Thin strip above the tab content: environment badge + read-only notice.
class _EnvironmentStrip extends StatelessWidget {
  const _EnvironmentStrip({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final bool live = app.environment.isLive;
    final Color color = live ? AppColors.red : AppColors.primary;
    final Color background = live ? AppColors.redSoft : AppColors.primarySoft;

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: background,
          child: Row(
            children: <Widget>[
              Icon(
                live ? Icons.warning_amber_rounded : Icons.science_outlined,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  live
                      ? 'LIVE TRADING · real funds at risk'
                      : 'TESTNET · paper trading with virtual funds',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: color,
                  ),
                ),
              ),
              if (app.readOnlyMode)
                const Text(
                  'READ-ONLY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        if (app.startupError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: InfoBanner.warning(
              message: app.startupError!,
              title: 'Storage notice',
              onDismiss: () {
                // The notice is one-shot: clearing the field hides it.
                context.read<AppState>().clearStartupError();
              },
            ),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelected,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: 'Trade',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Balances',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '₿',
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 14),
            Text('Binance Trader', style: AppTextStyles.title),
            SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 14),
            Text('Restoring your session…', style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
