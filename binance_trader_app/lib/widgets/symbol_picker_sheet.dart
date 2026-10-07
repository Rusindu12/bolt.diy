// Searchable trading-pair picker (modal bottom sheet).
//
// The list comes from `exchangeInfo`, so only symbols that are actually
// tradable in the active environment are offered.

import 'package:flutter/material.dart';

import '../models/symbol_info.dart';
import '../theme/app_theme.dart';
import 'app_text_field.dart';
import 'empty_state.dart';

/// Opens the picker and resolves with the chosen symbol (or null).
Future<String?> showSymbolPicker(
  BuildContext context, {
  required List<SymbolInfo> symbols,
  required String selected,
  bool loading = false,
  String? error,
  Future<void> Function()? onRefresh,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (BuildContext sheetContext) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _SymbolPickerBody(
        symbols: symbols,
        selected: selected,
        loading: loading,
        error: error,
        onRefresh: onRefresh,
      ),
    ),
  );
}

class _SymbolPickerBody extends StatefulWidget {
  const _SymbolPickerBody({
    required this.symbols,
    required this.selected,
    required this.loading,
    this.error,
    this.onRefresh,
  });

  final List<SymbolInfo> symbols;
  final String selected;
  final bool loading;
  final String? error;
  final Future<void> Function()? onRefresh;

  @override
  State<_SymbolPickerBody> createState() => _SymbolPickerBodyState();
}

class _SymbolPickerBodyState extends State<_SymbolPickerBody> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SymbolInfo> get _filtered {
    final String query = _query.trim().toUpperCase();
    if (query.isEmpty) {
      return widget.symbols;
    }
    return widget.symbols
        .where((SymbolInfo info) =>
            info.symbol.contains(query) ||
            info.baseAsset.contains(query) ||
            info.quoteAsset.contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<SymbolInfo> filtered = _filtered;
    return Column(
      children: <Widget>[
        const SizedBox(height: 12),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: <Widget>[
              const Text('Select trading pair', style: AppTextStyles.title),
              const Spacer(),
              Text(
                '${widget.symbols.length} pairs',
                style: AppTextStyles.caption,
              ),
              if (widget.onRefresh != null) ...<Widget>[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: widget.loading ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  color: AppColors.textSecondary,
                  tooltip: 'Reload symbol list',
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppTextField(
            controller: _searchController,
            hint: 'Search BTC, ETH, SOL…',
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
            onChanged: (String value) => setState(() => _query = value),
            suffix: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textMuted,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildList(filtered),
        ),
      ],
    );
  }

  Widget _buildList(List<SymbolInfo> filtered) {
    if (widget.loading && widget.symbols.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (widget.symbols.isEmpty) {
      return EmptyState(
        title: 'No symbols available',
        message: widget.error ??
            'The symbol list could not be loaded. Check your connection and try '
                'again.',
        icon: Icons.cloud_off,
        actionLabel: widget.onRefresh == null ? null : 'Retry',
        onAction: widget.onRefresh,
      );
    }
    if (filtered.isEmpty) {
      return EmptyState(
        title: 'No match',
        message: 'Nothing found for "$_query".',
        icon: Icons.search_off,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: filtered.length,
      itemBuilder: (BuildContext context, int index) {
        final SymbolInfo info = filtered[index];
        final bool isSelected = info.symbol == widget.selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).pop(info.symbol),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            info.symbol,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${info.baseAsset} / ${info.quoteAsset}'
                            '${info.minNotional > 0 ? ' · min ${info.minimumNotionalText}' : ''}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, color: AppColors.primary)
                    else
                      Text(
                        info.formatQuantity(info.minimumQuantity()),
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
