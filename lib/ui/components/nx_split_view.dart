import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The unified master-detail split (Foundation §4/§8/§18).
///
/// Split when the available width exceeds [AppBreakpoints.tabletMax]
/// (measured against [AppLayout.splitViewMinWidth]), desktop ratio
/// list : detail = 3 : 2. Narrow mode follows the Wave-2 pattern: the detail
/// *replaces* the list and a back affordance returns to it — never the
/// stacked table-plus-detail column. Replaces the per-file
/// `_splitViewBreakpoint = 1200` constants as screens are rebuilt.
class NxSplitView extends StatelessWidget {
  const NxSplitView({
    super.key,
    required this.list,
    required this.detail,
    required this.showDetail,
    this.onBackToList,
    this.backLabel = 'Zur Liste',
    this.listFlex = 3,
    this.detailFlex = 2,
  });

  final Widget list;
  final Widget detail;

  /// Whether a selection exists. In split mode the detail pane renders either
  /// way (screens show their own idle state); in narrow mode this decides
  /// between list and detail.
  final bool showDetail;

  /// Returns from the narrow detail to the list. Screens that cannot clear
  /// their selection may omit it, but the Foundation expects the affordance.
  final VoidCallback? onBackToList;
  final String backLabel;
  final int listFlex;
  final int detailFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= AppLayout.splitViewMinWidth;
        if (split) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: listFlex, child: list),
              const SizedBox(width: AppSpacing.component),
              Expanded(flex: detailFlex, child: detail),
            ],
          );
        }
        if (!showDetail) {
          return list;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onBackToList != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBackToList,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(backLabel),
                ),
              ),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}
