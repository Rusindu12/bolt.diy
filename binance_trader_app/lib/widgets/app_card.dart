// Surface container used by every screen.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A bordered dark surface with an optional title/trailing header.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.accent,
  });

  final Widget child;

  /// Small header label, e.g. `ORDER ENTRY`.
  final String? title;

  /// Optional second header line.
  final String? subtitle;

  /// Widget rendered on the right of the header.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// Makes the whole card tappable.
  final VoidCallback? onTap;

  /// Optional left accent border colour (buy/sell cards).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title!.toUpperCase(), style: AppTextStyles.sectionTitle),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          if (title != null) const SizedBox(height: 14),
          child,
        ],
      ),
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent ?? AppColors.border,
          width: accent == null ? 1 : 1.4,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// A compact label/value row used inside cards.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
    this.dense = false,
    this.tooltip,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;
  final bool dense;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(
      value,
      textAlign: TextAlign.right,
      style: (valueStyle ?? AppTextStyles.mono)
          .copyWith(color: valueColor ?? AppColors.textPrimary),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: dense ? AppTextStyles.caption : AppTextStyles.bodyMuted,
            ),
          ),
          const SizedBox(width: 12),
          if (tooltip != null)
            Tooltip(message: tooltip!, child: text)
          else
            Flexible(child: text),
        ],
      ),
    );
  }
}
