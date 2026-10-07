// First-run setup / API key entry screen.
//
// Used twice:
//   * as the gate shown by [HomeShell] while no key is configured,
//   * as an "edit keys" screen pushed from Settings.
//
// The entered key is verified against Binance *before* anything is written to
// the secure storage, so a typo never leaves a broken session behind.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/binance_environment.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/info_banner.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/status_pill.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.isInitialSetup = true});

  /// True when shown as the app gate (no back button, read-only option shown).
  final bool isInitialSetup;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();

  BinanceEnvironment _environment = BinanceEnvironment.testnet;
  bool _obscureSecret = true;
  bool _saving = false;
  bool _initialised = false;
  String? _error;
  String? _errorDetail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) {
      return;
    }
    _initialised = true;
    // Start on the environment the app is currently using.
    _environment = context.read<AppState>().environment;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final bool busy = _saving || app.busy;
    final bool live = _environment.isLive;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.isInitialSetup
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              title: const Text('API credentials'),
              foregroundColor: AppColors.textPrimary,
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
          children: <Widget>[
            if (widget.isInitialSetup) ...<Widget>[
              const _SetupHeader(),
              const SizedBox(height: 22),
            ] else ...<Widget>[
              Text(
                'Update the API key used for trading.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 16),
            ],

            // ---- environment -------------------------------------------
            AppCard(
              title: 'Environment',
              subtitle: 'Credentials are stored separately for each one',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SegmentedToggle<BinanceEnvironment>(
                    values: const <BinanceEnvironment>[
                      BinanceEnvironment.testnet,
                      BinanceEnvironment.live,
                    ],
                    selected: _environment,
                    labelBuilder: (BinanceEnvironment value) => value.shortLabel,
                    activeColor: live ? AppColors.red : AppColors.green,
                    activeTextColor: AppColors.background,
                    onChanged: busy
                        ? (BinanceEnvironment value) {}
                        : (BinanceEnvironment value) {
                            setState(() {
                              _environment = value;
                              _error = null;
                              _errorDetail = null;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(_environment.description, style: AppTextStyles.bodyMuted),
                  if (live) ...<Widget>[
                    const SizedBox(height: 10),
                    const InfoBanner.warning(
                      message:
                          'Live keys can move real money. Follow the checklist '
                          'below and start with a very small order.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ---- where to get keys --------------------------------------
            AppCard(
              title: 'Get an API key',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _environment.isLive
                        ? 'Binance → Profile → API Management → Create API'
                        : 'Testnet: log in with GitHub and click "Generate HMAC_SHA256 Key".',
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 10),
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
                            _environment.keyManagementUrl,
                            style: AppTextStyles.monoSmall.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _copy(
                            _environment.keyManagementUrl,
                            'Link copied. Open it in your browser.',
                          ),
                          icon: const Icon(Icons.copy, size: 18),
                          color: AppColors.textSecondary,
                          tooltip: 'Copy link',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _environment.keyManagementLabel,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ---- credentials --------------------------------------------
            AppCard(
              title: 'Credentials',
              subtitle: 'Stored in the device keystore, never in plain text',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppTextField(
                    controller: _apiKeyController,
                    label: 'API key',
                    hint: 'Paste the API key',
                    monospace: true,
                    enabled: !busy,
                    inputFormatters: secretInputFormatters,
                    onChanged: (String value) => _clearError(),
                    suffix: IconButton(
                      onPressed: () => _pasteInto(_apiKeyController),
                      icon: const Icon(Icons.content_paste, size: 18),
                      color: AppColors.textMuted,
                      tooltip: 'Paste',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _secretController,
                    label: 'API secret',
                    hint: 'Paste the secret key',
                    monospace: true,
                    obscureText: _obscureSecret,
                    enabled: !busy,
                    inputFormatters: secretInputFormatters,
                    onChanged: (String value) => _clearError(),
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscureSecret = !_obscureSecret),
                      icon: Icon(
                        _obscureSecret ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      color: AppColors.textMuted,
                      tooltip: _obscureSecret ? 'Show secret' : 'Hide secret',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The secret is only shown once by Binance. If you lost it, '
                    'delete the key and create a new one.',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ---- security checklist --------------------------------------
            const _SecurityChecklist(),
            const SizedBox(height: 14),

            if (_error != null) ...<Widget>[
              InfoBanner.error(
                message: _error!,
                title: 'Could not save the credentials',
                detail: _errorDetail,
                onDismiss: _clearError,
              ),
              const SizedBox(height: 14),
            ],

            // ---- actions --------------------------------------------------
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  disabledBackgroundColor: AppColors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Text('Verify & save keys', style: AppTextStyles.button),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.isInitialSetup)
              TextButton(
                onPressed: busy ? null : _continueReadOnly,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('Continue without API keys (read-only)'),
              )
            else
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('Cancel'),
              ),
            const SizedBox(height: 18),
            const _DisclaimerText(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- actions ---

  Future<void> _save() async {
    final AppState app = context.read<AppState>();
    final String apiKey = _apiKeyController.text.trim();
    final String secret = _secretController.text.trim();

    if (apiKey.isEmpty || secret.isEmpty) {
      setState(() {
        _error = 'Both the API key and the API secret are required.';
        _errorDetail = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _errorDetail = null;
    });

    try {
      await app.saveCredentials(
        apiKey: apiKey,
        secret: secret,
        environment: _environment,
      );
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Key verified and stored in the device keystore.',
          ),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (!widget.isInitialSetup) {
        Navigator.of(context).maybePop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = describeError(error);
        _errorDetail = describeErrorDetail(error);
      });
    }
  }

  Future<void> _continueReadOnly() async {
    final AppState app = context.read<AppState>();
    await app.continueWithoutCredentials();
  }

  void _clearError() {
    if (_error == null) {
      return;
    }
    setState(() {
      _error = null;
      _errorDetail = null;
    });
  }

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surfaceAlt,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pasteInto(TextEditingController controller) async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    if (!mounted || text == null) {
      return;
    }
    setState(() {
      controller.text = text.trim();
      _error = null;
    });
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '₿',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Binance Trader', style: AppTextStyles.title),
            ),
            const StatusPill.neutral(label: 'SPOT'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Connect your Binance Spot account',
          style: AppTextStyles.title.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(
          'Live prices stream without a key. Trading, balances and order history '
          'need an API key with spot-trading permission.',
          style: AppTextStyles.bodyMuted,
        ),
      ],
    );
  }
}

class _SecurityChecklist extends StatelessWidget {
  const _SecurityChecklist();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Security checklist',
      subtitle: 'Do this before pasting the key into the app',
      child: Column(
        children: const <_ChecklistItem>[
          _ChecklistItem(
            icon: Icons.public,
            title: 'Restrict access to your IP',
            message:
                'Enable "Restrict access to trusted IPs only" and add your '
                'current IP. The key then only works from your network.',
          ),
          _ChecklistItem(
            icon: Icons.block,
            title: 'Never enable withdrawals',
            message:
                'Leave "Enable Withdrawals" off. This app only places spot '
                'orders; a key without withdrawal rights is worthless to thieves.',
          ),
          _ChecklistItem(
            icon: Icons.swap_horiz,
            title: 'Allow spot & margin trading',
            message:
                '"Enable Spot & Margin Trading" must be on, otherwise orders are '
                'rejected with error -2015.',
          ),
          _ChecklistItem(
            icon: Icons.phone_iphone,
            title: 'One dedicated key per device',
            message:
                'Create a separate key for this phone and delete it immediately '
                'if the device is lost or sold.',
          ),
          _ChecklistItem(
            icon: Icons.lock_outline,
            title: 'Secrets stay on the device',
            message:
                'Keys are kept in the Android Keystore / iOS Keychain through '
                'flutter_secure_storage and are never sent anywhere except Binance.',
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message, style: AppTextStyles.caption.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'RISK DISCLAIMER',
          style: AppTextStyles.sectionTitle.copyWith(color: AppColors.red),
        ),
        const SizedBox(height: 6),
        Text(
          'Trading cryptocurrencies involves substantial risk of loss and is not '
          'suitable for every investor. Past performance is not indicative of '
          'future results. You are solely responsible for the orders you place '
          'with this application. This app is not affiliated with or endorsed by '
          'Binance; "Binance" is referenced only because its public API is used.',
          style: AppTextStyles.caption.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
