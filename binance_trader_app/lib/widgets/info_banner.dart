// Banner used for warnings, errors and security notices.
//
// Technical details (raw Binance responses) are hidden behind a "Details"
// toggle so the main message stays readable on a phone screen.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class InfoBanner extends StatefulWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.title,
    this.detail,
    this.icon = Icons.info_outline,
    this.background = AppColors.blueSoft,
    this.foreground = AppColors.blue,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  const InfoBanner.error({
    super.key,
    required this.message,
    this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.icon = Icons.error_outline,
    this.background = AppColors.redSoft,
    this.foreground = AppColors.red,
  });

  const InfoBanner.warning({
    super.key,
    required this.message,
    this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.icon = Icons.warning_amber_rounded,
    this.background = AppColors.primarySoft,
    this.foreground = AppColors.primary,
  });

  const InfoBanner.success({
    super.key,
    required this.message,
    this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.icon = Icons.check_circle_outline,
    this.background = AppColors.greenSoft,
    this.foreground = AppColors.green,
  });

  final String message;
  final String? title;

  /// Optional technical detail revealed on demand.
  final String? detail;

  final IconData icon;
  final Color background;
  final Color foreground;

  /// Optional inline action, e.g. "Retry" or "Add API keys".
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows a close button when provided.
  final VoidCallback? onDismiss;

  @override
  State<InfoBanner> createState() => _InfoBannerState();
}

class _InfoBannerState extends State<InfoBanner> {
  bool _detailsVisible = false;

  @override
  Widget build(BuildContext context) {
    final bool hasDetail = widget.detail != null && widget.detail!.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(widget.icon, size: 18, color: widget.foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (widget.title != null) ...<Widget>[
                      Text(
                        widget.title!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: widget.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      widget.message,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onDismiss != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
          if (widget.actionLabel != null && widget.onAction != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 28),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onAction,
                child: Text(
                  widget.actionLabel!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: widget.foreground,
                  ),
                ),
              ),
            ),
          if (hasDetail)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _detailsVisible = !_detailsVisible),
                    child: Text(
                      _detailsVisible ? 'Hide details' : 'Details',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (_detailsVisible) ...<Widget>[
                    const SizedBox(height: 6),
                    SelectableText(
                      widget.detail!,
                      style: AppTextStyles.monoSmall,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

