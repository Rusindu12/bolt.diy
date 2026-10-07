// Account balance + permission models.
//
// `/api/v3/account` returns one entry per asset (including zero balances) plus a
// set of boolean permissions. Both are modelled here.

import '../utils/json_utils.dart';

/// A single asset entry of the spot wallet.
class AccountBalance {
  const AccountBalance({
    required this.asset,
    required this.free,
    required this.locked,
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
        asset: asString(json['asset']),
        free: asDouble(json['free']),
        locked: asDouble(json['locked']),
      );

  /// Ticker of the asset, e.g. `BTC`, `USDT`.
  final String asset;

  /// Amount available to trade.
  final double free;

  /// Amount locked in open orders.
  final double locked;

  /// Total holding.
  double get total => free + locked;

  /// True when the wallet holds nothing of this asset.
  bool get isZero => total <= 0;

  /// Parses the `balances` array of an account payload.
  ///
  /// [includeZero] keeps assets with a zero balance (hidden by default).
  static List<AccountBalance> listFromAccountPayload(
    Map<String, dynamic> payload, {
    bool includeZero = false,
  }) {
    final List<AccountBalance> all = asMapList(payload['balances'])
        .map(AccountBalance.fromJson)
        .toList();
    if (includeZero) {
      all.sort((a, b) => a.asset.compareTo(b.asset));
      return all;
    }
    final List<AccountBalance> nonZero =
        all.where((balance) => !balance.isZero).toList();
    nonZero.sort((a, b) {
      // Stable, predictable order: stablecoins/fiat first, then by value.
      final int byStable = _stableRank(a.asset).compareTo(_stableRank(b.asset));
      if (byStable != 0) {
        return byStable;
      }
      return a.asset.compareTo(b.asset);
    });
    return nonZero;
  }

  static int _stableRank(String asset) {
    const List<String> preferred = <String>['USDT', 'USDC', 'FDUSD', 'BUSD', 'BTC', 'ETH'];
    final int index = preferred.indexOf(asset);
    return index == -1 ? preferred.length : index;
  }

  @override
  String toString() => '$asset: free=$free locked=$locked';
}

/// Everything the app needs from a `/api/v3/account` response.
class AccountSnapshot {
  const AccountSnapshot({
    required this.balances,
    required this.permissions,
    required this.fetchedAt,
  });

  factory AccountSnapshot.fromPayload(
    Map<String, dynamic> payload, {
    bool includeZeroBalances = false,
    DateTime? fetchedAt,
  }) =>
      AccountSnapshot(
        balances: AccountBalance.listFromAccountPayload(
          payload,
          includeZero: includeZeroBalances,
        ),
        permissions: AccountPermissions.fromAccountPayload(payload),
        fetchedAt: fetchedAt ?? DateTime.now(),
      );

  static const AccountSnapshot empty = AccountSnapshot(
    balances: <AccountBalance>[],
    permissions: AccountPermissions(
      canTrade: false,
      canWithdraw: false,
      canDeposit: false,
      accountType: 'UNKNOWN',
      makerCommission: 0,
      takerCommission: 0,
    ),
    fetchedAt: null,
  );

  final List<AccountBalance> balances;
  final AccountPermissions permissions;
  final DateTime? fetchedAt;

  /// Free balance of [asset] (0 when the asset is not held).
  double freeBalanceOf(String asset) {
    final String needle = asset.toUpperCase();
    for (final AccountBalance balance in balances) {
      if (balance.asset == needle) {
        return balance.free;
      }
    }
    return 0;
  }

  /// Total balance (free + locked) of [asset].
  double totalBalanceOf(String asset) {
    final String needle = asset.toUpperCase();
    for (final AccountBalance balance in balances) {
      if (balance.asset == needle) {
        return balance.total;
      }
    }
    return 0;
  }
}

/// Permission flags returned by `/api/v3/account`.
///
/// Used by the Security panel to warn about dangerous key settings.
class AccountPermissions {
  const AccountPermissions({
    required this.canTrade,
    required this.canWithdraw,
    required this.canDeposit,
    required this.accountType,
    required this.makerCommission,
    required this.takerCommission,
  });

  factory AccountPermissions.fromAccountPayload(Map<String, dynamic> payload) =>
      AccountPermissions(
        canTrade: asBool(payload['canTrade']),
        canWithdraw: asBool(payload['canWithdraw']),
        canDeposit: asBool(payload['canDeposit']),
        accountType: asString(payload['accountType'], fallback: 'SPOT'),
        makerCommission: asInt(payload['makerCommission']),
        takerCommission: asInt(payload['takerCommission']),
      );

  final bool canTrade;
  final bool canWithdraw;
  final bool canDeposit;
  final String accountType;

  /// Commission in basis points (10 == 0.10 %).
  final int makerCommission;
  final int takerCommission;

  /// 0.1 % fee shown as `0.10%`.
  static String formatCommission(int basisPoints) =>
      '${(basisPoints / 100).toStringAsFixed(2)}%';

  String get makerFeeText => formatCommission(makerCommission);
  String get takerFeeText => formatCommission(takerCommission);

  /// True when the key can move funds out of the account: a configuration the
  /// app actively warns about.
  bool get hasDangerousWithdrawalPermission => canWithdraw;
}
