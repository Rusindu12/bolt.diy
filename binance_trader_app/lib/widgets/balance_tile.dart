// One wallet row in the Balances tab.

import 'package:flutter/material.dart';

import '../models/account_balance.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class BalanceTile extends StatelessWidget {
  const BalanceTile({
    super.key,
    required this.balance,
    this.onTap,
    this.highlighted = false,
  });

  final AccountBalance balance;

  /// Called with the asset ticker when the row is tapped (used to trade it).
  final VoidCallback? onTap;

  /// Highlights the assets of the active pair.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: highlighted ? AppColors.primarySoft : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                // Asset avatar with the first letter of the ticker.
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    balance.asset.isEmpty ? '?' : balance.asset.substring(0, 1),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        balance.asset,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Free ${formatAmount(balance.free)}  ·  '
                        'Locked ${formatAmount(balance.locked)}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      formatAmount(balance.total),
                      style: AppTextStyles.mono.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (onTap != null)
                      const Text(
                        'tap to trade',
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
