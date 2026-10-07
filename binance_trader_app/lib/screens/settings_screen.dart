// Settings tab: environment, credentials, default pair, security and about.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/api_credentials.dart';
import '../models/binance_environment.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/info_banner.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/status_pill.dart';
import '../widgets/symbol_picker_sheet.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openKeySetup(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) =>
            const SetupScreen(isInitialSetup: false),
      ),
    );
  }

  Future<void> _pickSymbol(BuildContext context) async {
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

  Future<void> _changeEnvironment(
    BuildContext context,
    BinanceEnvironment target,
  ) async {
    final AppState app = context.read<AppState>();
    if (target == app.environment) {
      return;
    }
    if (target.isLive) {
      // Extra confirmation: this is the switch that puts real money on the line.
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Switch to Live trading?', style: AppTextStyles.title),
          content: const Text(
            'Live mode sends orders to the real Binance exchange with real '
            'funds. Make sure your API key has IP restrictions and that '
            'withdrawals are disabled before you continue.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: const Text('Stay on testnet'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: AppColors.background,
              ),
              child: const Text('Go live'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    await app.setEnvironment(target);
  }

  Future<void> _removeKeys(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove API keys?', style: AppTextStyles.title),
        content: Text(
          'The ${app.environment.label} key and secret are deleted from the '
          'keystore. You will be asked for keys again before trading.',
          style: AppTextStyles.bodyMuted,
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
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await app.clearCredentials(environment: app.environment);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final ApiCredentials? credentials = app.credentials;
    final bool live = app.environment.isLive;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: <Widget>[
        // ---- environment -------------------------------------------------
        AppCard(
          title: 'Trading environment',
          subtitle: app.environment.label,
          trailing: StatusPill(
            label: live ? 'REAL FUNDS' : 'PAPER',
            background: live ? AppColors.redSoft : AppColors.greenSoft,
            foreground: live ? AppColors.red : AppColors.green,
            dense: true,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SegmentedToggle<BinanceEnvironment>(
                values: const <BinanceEnvironment>[
                  BinanceEnvironment.testnet,
                  BinanceEnvironment.live,
                ],
                selected: app.environment,
                labelBuilder: (BinanceEnvironment value) => value.shortLabel,
                activeColor: live ? AppColors.red : AppColors.green,
                activeTextColor: AppColors.background,
                onChanged: (BinanceEnvironment value) =>
                    _changeEnvironment(context, value),
              ),
              const SizedBox(height: 12),
              Text(app.environment.description, style: AppTextStyles.bodyMuted),
              const SizedBox(height: 8),
              KeyValueRow(
                label: 'REST',
                value: app.environment.restBaseUrl,
                valueStyle: AppTextStyles.monoSmall,
                dense: true,
              ),
              KeyValueRow(
                label: 'WebSocket',
                value: app.environment.webSocketBaseUrl,
                valueStyle: AppTextStyles.monoSmall,
                dense: true,
              ),
              KeyValueRow(
                label: 'Clock offset',
                value: '${app.binance.serverTimeOffsetMs} ms',
                valueStyle: AppTextStyles.monoSmall,
                dense: true,
                tooltip: 'Device clock minus Binance server time; corrected '
                    'automatically for signed requests.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- credentials -------------------------------------------------
        AppCard(
          title: 'API credentials',
          subtitle: credentials == null
              ? 'Not configured for ${app.environment.shortLabel}'
              : 'Stored in the device keystore',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (credentials == null)
                const InfoBanner.warning(
                  message:
                      'No key stored for this environment. Add one to trade, see '
                      'balances and read order history.',
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    KeyValueRow(
                      label: 'API key',
                      value: credentials.maskedKey,
                      valueStyle: AppTextStyles.monoSmall,
                      dense: true,
                    ),
                    if (app.permissions != null)
                      KeyValueRow(
                        label: 'Can trade',
                        value: app.permissions!.canTrade ? 'yes' : 'no',
                        valueColor: app.permissions!.canTrade
                            ? AppColors.green
                            : AppColors.red,
                        dense: true,
                      ),
                    if (app.permissions != null)
                      KeyValueRow(
                        label: 'Can withdraw',
                        value: app.permissions!.canWithdraw ? 'YES - unsafe' : 'no',
                        valueColor: app.permissions!.canWithdraw
                            ? AppColors.red
                            : AppColors.green,
                        dense: true,
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _openKeySetup(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        credentials == null ? 'Add keys' : 'Replace keys',
                      ),
                    ),
                  ),
                  if (credentials != null) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _removeKeys(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Remove keys'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- default symbol ----------------------------------------------
        AppCard(
          title: 'Default trading pair',
          subtitle: 'Used when the app starts',
          onTap: () => _pickSymbol(context),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  app.symbol,
                  style: AppTextStyles.title.copyWith(fontSize: 18),
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
        const SizedBox(height: 14),

        // ---- security ----------------------------------------------------
        AppCard(
          title: 'Security',
          subtitle: 'Protect the key that lives on this phone',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Bullet('Restrict the API key to your own IP address.'),
              const _Bullet('Keep "Enable Withdrawals" switched off.'),
              const _Bullet(
                'Use a dedicated key for this app and revoke it when the phone '
                'is lost or replaced.',
              ),
              const _Bullet(
                'The secret is stored with flutter_secure_storage (Android '
                'Keystore / iOS Keychain) and is never logged.',
              ),
              const SizedBox(height: 12),
              Text('Manage keys at', style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SelectableText(
                        app.environment.keyManagementUrl,
                        style: AppTextStyles.monoSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: app.environment.keyManagementUrl),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to the clipboard.'),
                            backgroundColor: AppColors.surfaceAlt,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      color: AppColors.textSecondary,
                      tooltip: 'Copy link',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- disclaimer --------------------------------------------------
        AppCard(
          title: 'Disclaimer',
          trailing: app.riskAcknowledged
              ? const StatusPill.success(label: 'ACKNOWLEDGED', dense: true)
              : const StatusPill.warning(label: 'PENDING', dense: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Cryptocurrency trading is highly volatile. You can lose all of '
                'your funds. This application is an unofficial client of the '
                'public Binance API and is provided as-is, without any warranty '
                'and without any liability for trading losses.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
              if (!app.riskAcknowledged) ...<Widget>[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: app.acknowledgeRisk,
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  child: const Text('I understand the risk'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- danger zone -------------------------------------------------
        AppCard(
          title: 'Reset',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Removes every stored API key (testnet and live), signs you out '
                'and returns to the setup screen.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _resetApp(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Sign out & clear all data'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Binance Trader 1.0.0 · unofficial client of the Binance public API',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _resetApp(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out?', style: AppTextStyles.title),
        content: const Text(
          'All API keys stored by this app are deleted from the device keystore. '
          'Nothing on your Binance account is changed.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textMuted,
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
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Delete & sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await app.clearCredentials();
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check, size: 14, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
