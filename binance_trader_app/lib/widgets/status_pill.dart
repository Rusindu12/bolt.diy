// Small coloured pill used for stream status, environment badges and order
// states. Named constructors keep the colour/contrast pairs consistent.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.dense = false,
  });

  const StatusPill.success({super.key, required this.label, this.icon, this.dense = false})
      : background = AppColors.greenSoft,
        foreground = AppColors.green;

  const StatusPill.danger({super.key, required this.label, this.icon, this.dense = false})
      : background = AppColors.redSoft,
        foreground = AppColors.red;

  const StatusPill.warning({super.key, required this.label, this.icon, this.dense = false})
      : background = AppColors.primarySoft,
        foreground = AppColors.primary;

  const StatusPill.info({super.key, required this.label, this.icon, this.dense = false})
      : background = AppColors.blueSoft,
        foreground = AppColors.blue;

  const StatusPill.neutral({super.key, required this.label, this.icon, this.dense = false})
      : background = AppColors.greySoft,
        foreground = AppColors.textSecondary;

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 9,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
