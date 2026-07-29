import 'package:flutter/material.dart';

import '../../../../../features/valuation/domain/valuation_method.dart';
import '../../../../components/nx_data_table_shell.dart';
import 'valuation_badges.dart';
import 'valuation_formatting.dart';

/// The assumption ledger: every factor a method actually used, with its
/// provenance and source. This is the audit/PDF trail made visible — the answer
/// to "where does this number come from" without leaving the screen.
class AssumptionLedgerTable extends StatelessWidget {
  const AssumptionLedgerTable({super.key, required this.assumptions});

  final List<ValuationAssumption> assumptions;

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      isEmpty: assumptions.isEmpty,
      emptyTitle: 'Noch keine Annahmen',
      emptyDescription:
          'Sobald ein Verfahren rechnet, stehen hier alle verwendeten Faktoren '
          'mit ihrer Herkunft.',
      emptyIcon: Icons.fact_check_outlined,
      minTableWidth: 720,
      child: DataTable(
        columns: const <DataColumn>[
          DataColumn(label: Text('Faktor')),
          DataColumn(label: Text('Wert')),
          DataColumn(label: Text('Herkunft')),
          DataColumn(label: Text('Quelle')),
        ],
        rows: <DataRow>[
          for (final assumption in assumptions)
            DataRow(
              cells: <DataCell>[
                DataCell(Text(assumption.label)),
                DataCell(
                  Text(formatFactorValue(assumption.value, assumption.unit)),
                ),
                DataCell(
                  FactorProvenanceBadge(provenance: assumption.provenance),
                ),
                DataCell(Text(assumption.source ?? '—')),
              ],
            ),
        ],
      ),
    );
  }
}
