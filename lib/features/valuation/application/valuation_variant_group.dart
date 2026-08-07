/// The variants of one case, with the value each of them concluded
/// (Welle 5, AP6).
///
/// Reads are bounded by the group, not by the workspace: the siblings come from
/// one property-scoped list read, and only those are opened to read their
/// published opinion. A group holds a handful of variants — [maxVariantsRead]
/// caps it explicitly, and a group that exceeds the cap reads short rather than
/// silently fanning out.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/valuation_case_dto.dart';
import 'valuation_case_controller.dart' show ValuationPermissions;
import 'valuation_providers.dart';
import 'valuation_repository.dart';

/// One variant with its published result — `marketValue` is null when nothing
/// has been published yet, which the comparison shows as "nicht ermittelbar"
/// rather than as a zero.
class ValuationVariantEntry {
  const ValuationVariantEntry({
    required this.valuationCase,
    this.marketValue,
    this.isStale = false,
  });

  final ValuationCaseDto valuationCase;
  final double? marketValue;

  /// The published report predates the current factor set.
  final bool isStale;

  String get label => valuationCase.variantLabel ?? valuationCase.title;
}

typedef ValuationVariantGroupRef = ({String propertyId, String groupId});

/// How many variants of one group are opened for their value. Beyond this the
/// list still shows every sibling, but without its published number.
const int maxVariantsRead = 8;

final valuationVariantGroupProvider = FutureProvider.autoDispose
    .family<List<ValuationVariantEntry>, ValuationVariantGroupRef>((
      ref,
      group,
    ) async {
      final scope = ref.watch(workspaceSessionScopeProvider);
      final workspaceId = scope.workspaceId;
      if (workspaceId == null ||
          !scope.permissions.contains(ValuationPermissions.read)) {
        return const <ValuationVariantEntry>[];
      }

      final repository = ref.watch(valuationCaseRepositoryProvider);
      final list = await repository.searchValuationCases(
        ValuationCaseListQuery(
          workspaceId: workspaceId,
          propertyId: group.propertyId,
          includeArchived: true,
          page: const ValuationPageRequest(limit: 100),
        ),
      );
      if (list is! ValuationRepositorySuccess<
        ValuationPageResult<ValuationCaseDto>
      >) {
        return const <ValuationVariantEntry>[];
      }

      final siblings = list.value.items
          .where((entry) => entry.variantGroupId == group.groupId)
          .toList()
        ..sort((a, b) => (a.variantLabel ?? '').compareTo(b.variantLabel ?? ''));

      final entries = <ValuationVariantEntry>[];
      for (final sibling in siblings) {
        if (entries.length >= maxVariantsRead) {
          entries.add(ValuationVariantEntry(valuationCase: sibling));
          continue;
        }
        final detail = await repository.getValuationCaseById(
          workspaceId: workspaceId,
          valuationCaseId: sibling.id,
        );
        entries.add(
          switch (detail) {
            ValuationRepositorySuccess(:final value) => ValuationVariantEntry(
              valuationCase: sibling,
              marketValue: value.report?.opinion?.amount,
              isStale: value.hasStaleReport,
            ),
            _ => ValuationVariantEntry(valuationCase: sibling),
          },
        );
      }
      return List<ValuationVariantEntry>.unmodifiable(entries);
    });
