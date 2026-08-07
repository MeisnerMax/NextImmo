import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';

/// The P2-D04 tables reuse the P2-D03 `document_link_entity_type` enum
/// server-side. `PlatformEntityType` mirrors that vocabulary rather than
/// importing `DocumentLinkEntityType`, so that a migrated vertical does not
/// depend on another migrated vertical's domain layer.
///
/// This test is the price of that decision: the duplication is only safe while
/// the two vocabularies stay identical, so drift fails here instead of showing
/// up as a runtime `Unknown entity type` from the server.
void main() {
  test('platform entity types mirror the document link registry', () {
    final platformWireNames = PlatformEntityType.values
        .map((type) => type.wireName)
        .toList(growable: false);
    final documentWireNames = DocumentLinkEntityType.values
        .map((type) => type.wireName)
        .toList(growable: false);

    expect(
      platformWireNames,
      documentWireNames,
      reason:
          'PlatformEntityType and DocumentLinkEntityType both map the SQL enum '
          'public.document_link_entity_type; they must not drift apart.',
    );
  });

  test('every wire name round-trips', () {
    for (final type in PlatformEntityType.values) {
      expect(PlatformEntityType.fromWire(type.wireName), type);
    }
    expect(PlatformEntityType.fromWire('not_a_type'), isNull);
    expect(PlatformEntityType.fromWire(null), isNull);
  });

  test('an entity reference compares by both halves', () {
    const first = PlatformEntityRef(
      type: PlatformEntityType.property,
      id: 'property-1',
    );
    const same = PlatformEntityRef(
      type: PlatformEntityType.property,
      id: 'property-1',
    );
    const otherType = PlatformEntityRef(
      type: PlatformEntityType.unit,
      id: 'property-1',
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(otherType));
  });
}
