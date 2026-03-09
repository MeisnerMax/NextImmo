import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'info_tooltip.dart';

class DataTableWidget extends StatelessWidget {
  const DataTableWidget({
    super.key,
    required this.columns,
    required this.rows,
    this.metricKeysByColumn = const <String, String>{},
  });

  final List<String> columns;
  final List<List<String>> rows;
  final Map<String, String> metricKeysByColumn;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.hovered)) {
              return semantic.surfaceAlt;
            }
            return null;
          }),
          columns:
              columns
                  .map(
                    (column) => DataColumn(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(column),
                          if (metricKeysByColumn[column] != null) ...[
                            const SizedBox(width: 6),
                            InfoTooltip(
                              metricKey: metricKeysByColumn[column]!,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(),
          rows:
              rows
                  .map(
                    (row) => DataRow(
                      cells:
                          row
                              .map(
                                (cell) => DataCell(
                                  Text(
                                    cell,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}
