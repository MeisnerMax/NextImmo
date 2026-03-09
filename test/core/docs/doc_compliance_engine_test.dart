import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/docs/doc_compliance_engine.dart';
import 'package:neximmo_app/core/models/documents.dart';

void main() {
  test('detects missing required document and expired metadata', () {
    const engine = DocComplianceEngine();
    final requirements = <RequiredDocumentRecord>[
      RequiredDocumentRecord(
        id: 'r1',
        entityType: 'property',
        propertyType: null,
        typeId: 'type_lease',
        required: true,
        expiresFieldKey: 'valid_until',
        createdAt: 1,
      ),
    ];
    final docs = <DocumentWithMetadata>[
      DocumentWithMetadata(
        document: DocumentRecord(
          id: 'd1',
          entityType: 'property',
          entityId: 'p1',
          typeId: 'type_lease',
          filePath: '/tmp/lease.pdf',
          fileName: 'lease.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 10,
          sha256: null,
          createdAt: 1,
          createdBy: null,
          updatedAt: 1,
        ),
        metadata: <String, String>{
          'valid_until':
              (DateTime.now()
                      .subtract(const Duration(days: 1))
                      .millisecondsSinceEpoch)
                  .toString(),
        },
      ),
    ];

    final issues = engine.checkEntityCompliance(
      entityType: 'property',
      entityId: 'p1',
      requirements: requirements,
      documents: docs,
    );
    expect(issues.where((i) => i.code == 'expired_document'), isNotEmpty);
  });

  test('detects missing required document type', () {
    const engine = DocComplianceEngine();
    final requirements = <RequiredDocumentRecord>[
      RequiredDocumentRecord(
        id: 'r2',
        entityType: 'property',
        propertyType: null,
        typeId: 'type_epc',
        required: true,
        expiresFieldKey: null,
        createdAt: 1,
      ),
    ];
    final issues = engine.checkEntityCompliance(
      entityType: 'property',
      entityId: 'p2',
      requirements: requirements,
      documents: const <DocumentWithMetadata>[],
    );
    expect(
      issues.where((i) => i.code == 'missing_required_document'),
      isNotEmpty,
    );
  });
}
