import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/docs/doc_compliance_engine.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/document_types_repo.dart';
import 'package:neximmo_app/data/repositories/documents_repo.dart';
import 'package:neximmo_app/data/repositories/required_documents_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late DocumentTypesRepo typesRepo;
  late RequiredDocumentsRepo requiredRepo;
  late DocumentsRepo docsRepo;
  late AuditLogRepo auditRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    auditRepo = AuditLogRepo(db);
    typesRepo = DocumentTypesRepo(db);
    requiredRepo = RequiredDocumentsRepo(db);
    docsRepo = DocumentsRepo(
      db,
      requiredRepo,
      const DocComplianceEngine(),
      auditLogRepo: auditRepo,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('document type name unique constraint is enforced', () async {
    await typesRepo.create(name: 'Lease Contract', entityType: 'property');
    expect(
      () => typesRepo.create(name: 'Lease Contract', entityType: 'property'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('metadata unique key per document is replaceable', () async {
    final type = await typesRepo.create(name: 'EPC', entityType: 'property');
    final doc = await docsRepo.createDocument(
      entityType: 'property',
      entityId: 'p1',
      typeId: type.id,
      filePath: '/tmp/epc.pdf',
      fileName: 'epc.pdf',
      metadata: const <String, String>{'epc_valid_until': '100'},
    );
    await docsRepo.upsertMetadata(
      documentId: doc.id,
      key: 'epc_valid_until',
      value: '200',
    );
    final meta = await docsRepo.listMetadata(doc.id);
    expect(meta.length, 1);
    expect(meta.first.value, '200');

    final audits = await auditRepo.list(entityType: 'document', entityId: doc.id);
    expect(audits.where((event) => event.action == 'create'), isNotEmpty);
  });

  test('compliance detects missing required document', () async {
    final type = await typesRepo.create(
      name: 'Insurance',
      entityType: 'property',
    );
    await requiredRepo.upsert(
      entityType: 'property',
      typeId: type.id,
      requiredFlag: true,
    );

    final issues = await docsRepo.checkComplianceForEntity(
      entityType: 'property',
      entityId: 'p99',
    );
    expect(
      issues.where((i) => i.code == 'missing_required_document'),
      isNotEmpty,
    );
  });
}
