// Application entry point.
//
// The object graph is created once here and injected with `provider`:
//
//   SettingsService      -> secure storage + preferences
//   BinanceService       -> signed REST client
//   MarketStreamService  -> WebSocket trade stream
//   AppState             -> session (setup, environment, symbol, account, stream)
//   TradeState           -> order entry (depends on AppState)
//   OrdersState          -> open orders / history (depends on AppState)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'providers/orders_state.dart';
import 'providers/trade_state.dart';
import 'screens/home_shell.dart';
import 'services/binance_service.dart';
import 'services/market_stream_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BinanceTraderApp());
}

class BinanceTraderApp extends StatefulWidget {
  const BinanceTraderApp({super.key});

  @override
  State<BinanceTraderApp> createState() => _BinanceTraderAppState();
}

class _BinanceTraderAppState extends State<BinanceTraderApp> {
  late final SettingsService _settingsService;
  late final BinanceService _binanceService;
  late final MarketStreamService _streamService;
  late final AppState _appState;
  late final TradeState _tradeState;
  late final OrdersState _ordersState;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService();
    _binanceService = BinanceService();
    _streamService = MarketStreamService();
    _appState = AppState(
      settings: _settingsService,
      binance: _binanceService,
      stream: _streamService,
    );
    _tradeState = TradeState(app: _appState);
    _ordersState = OrdersState(app: _appState);

    // Restores the saved session (environment, symbol, credentials).
    unawaited(_appState.bootstrap());
  }

  @override
  void dispose() {
    _ordersState.dispose();
    _tradeState.dispose();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<TradeState>.value(value: _tradeState),
        ChangeNotifierProvider<OrdersState>.value(value: _ordersState),
      ],
      child: MaterialApp(
        title: 'Binance Trader',
        debugShowCheckedModeBanner: false,
        // The trading UI is dark by design; both themes point at the same data
        // so a device in light mode still gets the dark trading view.
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: const HomeShell(),
      ),
    );
  }
}
