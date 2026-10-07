// Generic segmented control (Buy/Sell, Market/Limit, Testnet/Live, tabs).
//
// Built from scratch instead of `SegmentedButton`/`ToggleButtons` so the styling
// is independent of Material version changes and identical on every screen.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
    this.activeColor,
    this.activeTextColor,
    this.inactiveTextColor,
    this.background = AppColors.surfaceAlt,
    this.verticalPadding = 11,
    this.enabled = true,
  });

  /// Selectable values, rendered in order.
  final List<T> values;

  /// Currently selected value.
  final T selected;

  final ValueChanged<T> onChanged;

  /// Label for a value (avoids index/label drift).
  final String Function(T value) labelBuilder;

  /// Fill colour of the selected segment.
  final Color? activeColor;

  final Color? activeTextColor;
  final Color? inactiveTextColor;
  final Color background;
  final double verticalPadding;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            for (final T value in values)
              Expanded(child: _segment(value)),
          ],
        ),
      ),
    );
  }

  Widget _segment(T value) {
    final bool isSelected = value == selected;
    final Color background = isSelected
        ? (activeColor ?? AppColors.primary)
        : Colors.transparent;
    final Color textColor = isSelected
        ? (activeTextColor ?? AppColors.background)
        : (inactiveTextColor ?? AppColors.textSecondary);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          labelBuilder(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
