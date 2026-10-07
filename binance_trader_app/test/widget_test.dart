// Widget tests for the reusable UI building blocks.
//
// They intentionally avoid `AppState` (which needs the platform keystore) and
// only exercise the pure presentation widgets.

import 'package:binance_trader_app/theme/app_theme.dart';
import 'package:binance_trader_app/widgets/app_card.dart';
import 'package:binance_trader_app/widgets/empty_state.dart';
import 'package:binance_trader_app/widgets/info_banner.dart';
import 'package:binance_trader_app/widgets/segmented_toggle.dart';
import 'package:binance_trader_app/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('SegmentedToggle reports the tapped value', (WidgetTester tester) async {
    String? tapped;
    await tester.pumpWidget(
      _wrap(
        SegmentedToggle<String>(
          values: const <String>['market', 'limit'],
          selected: 'market',
          labelBuilder: (String value) => value,
          onChanged: (String value) => tapped = value,
        ),
      ),
    );

    expect(find.text('market'), findsOneWidget);
    expect(find.text('limit'), findsOneWidget);

    await tester.tap(find.text('limit'));
    await tester.pump();
    expect(tapped, 'limit');
  });

  testWidgets('SegmentedToggle ignores taps while disabled',
      (WidgetTester tester) async {
    String? tapped;
    await tester.pumpWidget(
      _wrap(
        SegmentedToggle<String>(
          values: const <String>['a', 'b'],
          selected: 'a',
          enabled: false,
          labelBuilder: (String value) => value,
          onChanged: (String value) => tapped = value,
        ),
      ),
    );

    await tester.tap(find.text('b'));
    await tester.pump();
    expect(tapped, isNull);
  });

  testWidgets('StatusPill renders its label', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(const StatusPill.success(label: 'LIVE', icon: Icons.bolt)),
    );
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('InfoBanner reveals technical details on demand',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const InfoBanner.error(
          message: 'Invalid API key.',
          detail: 'HTTP 401 / code -2015',
        ),
      ),
    );

    expect(find.text('Invalid API key.'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('HTTP 401 / code -2015'), findsNothing);

    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(find.text('HTTP 401 / code -2015'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
  });

  testWidgets('InfoBanner dismiss button fires its callback',
      (WidgetTester tester) async {
    bool dismissed = false;
    await tester.pumpWidget(
      _wrap(
        InfoBanner.warning(
          message: 'Clock drift detected.',
          onDismiss: () => dismissed = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('AppCard upper-cases its title and shows a trailing widget',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppCard(
          title: 'order entry',
          subtitle: 'market order',
          trailing: StatusPill.neutral(label: 'SPOT'),
          child: Text('body'),
        ),
      ),
    );

    expect(find.text('ORDER ENTRY'), findsOneWidget);
    expect(find.text('market order'), findsOneWidget);
    expect(find.text('SPOT'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('KeyValueRow renders label and value', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(const KeyValueRow(label: 'Available', value: '1000 USDT')),
    );
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('1000 USDT'), findsOneWidget);
  });

  testWidgets('EmptyState runs its action', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      _wrap(
        EmptyState(
          title: 'No open orders',
          message: 'Limit orders appear here.',
          actionLabel: 'Refresh',
          onAction: () => tapped = true,
        ),
      ),
    );

    expect(find.text('No open orders'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
