import '../models/documents.dart';

class DocComplianceEngine {
  const DocComplianceEngine();

  List<DocumentComplianceIssue> checkEntityCompliance({
    required String entityType,
    required String entityId,
    required List<RequiredDocumentRecord> requirements,
    required List<DocumentWithMetadata> documents,
  }) {
    final issues = <DocumentComplianceIssue>[];
    final docsByType = <String, List<DocumentWithMetadata>>{};
    for (final doc in documents) {
      final typeId = doc.document.typeId;
      if (typeId == null) {
        continue;
      }
      docsByType.putIfAbsent(typeId, () => <DocumentWithMetadata>[]).add(doc);
    }

    for (final requirement in requirements.where((r) => r.required)) {
      final docs =
          docsByType[requirement.typeId] ?? const <DocumentWithMetadata>[];
      if (docs.isEmpty) {
        issues.add(
          DocumentComplianceIssue(
            entityType: entityType,
            entityId: entityId,
            typeId: requirement.typeId,
            code: 'missing_required_document',
            message: 'Missing required document type ${requirement.typeId}.',
          ),
        );
      }
    }

    issues.addAll(
      checkExpiries(
        entityType: entityType,
        entityId: entityId,
        requirements: requirements,
        documents: documents,
      ),
    );
    return issues;
  }

  List<DocumentComplianceIssue> checkExpiries({
    required String entityType,
    required String entityId,
    required List<RequiredDocumentRecord> requirements,
    required List<DocumentWithMetadata> documents,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final issues = <DocumentComplianceIssue>[];
    for (final requirement in requirements) {
      final key = requirement.expiresFieldKey;
      if (key == null || key.trim().isEmpty) {
        continue;
      }
      final matchingDocs = documents.where(
        (entry) => entry.document.typeId == requirement.typeId,
      );
      for (final doc in matchingDocs) {
        final raw = doc.metadata[key];
        if (raw == null || raw.trim().isEmpty) {
          issues.add(
            DocumentComplianceIssue(
              entityType: entityType,
              entityId: entityId,
              typeId: requirement.typeId,
              code: 'missing_expiry_metadata',
              message:
                  'Missing expiry metadata "$key" for document ${doc.document.id}.',
            ),
          );
          continue;
        }
        final expiry =
            int.tryParse(raw.trim()) ??
            DateTime.tryParse(raw.trim())?.millisecondsSinceEpoch;
        if (expiry == null) {
          issues.add(
            DocumentComplianceIssue(
              entityType: entityType,
              entityId: entityId,
              typeId: requirement.typeId,
              code: 'invalid_expiry_metadata',
              message:
                  'Invalid expiry metadata "$key" for document ${doc.document.id}.',
            ),
          );
          continue;
        }
        if (expiry < now) {
          issues.add(
            DocumentComplianceIssue(
              entityType: entityType,
              entityId: entityId,
              typeId: requirement.typeId,
              code: 'expired_document',
              message: 'Document ${doc.document.id} is expired.',
            ),
          );
        }
      }
    }
    return issues;
  }
}
