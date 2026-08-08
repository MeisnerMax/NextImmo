import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/inputs.dart';
import '../../core/models/property.dart';
import '../../core/models/property_creation.dart';
import '../../core/models/scenario.dart';
import '../../core/models/security.dart';
import '../../core/models/settings.dart';
import '../../core/security/rbac.dart';
import 'audit_log_repo.dart';
import 'permission_guard.dart';
import 'search_repo.dart';

class PropertyCreateResult {
  const PropertyCreateResult({required this.property, required this.scenario});

  final PropertyRecord property;
  final ScenarioRecord scenario;
}

class PropertyOnboardingCreateResult {
  const PropertyOnboardingCreateResult({
    required this.property,
    required this.scenario,
  });

  final PropertyRecord property;
  final ScenarioRecord? scenario;
}

class PropertyRepository {
  PropertyRepository(
    this._db, {
    AuditLogRepo? auditLogRepo,
    SearchRepo? searchRepo,
    AuditWriter? auditWriter,
    PermissionGuard? permissionGuard,
    Future<SecurityContextRecord> Function()? securityContextResolver,
  }) : _auditLogRepo = auditLogRepo,
       _searchRepo = searchRepo,
       _auditWriter = auditWriter,
       _permissionGuard = permissionGuard,
       _securityContextResolver = securityContextResolver;

  final Database _db;
  final AuditLogRepo? _auditLogRepo;
  final SearchRepo? _searchRepo;
  final AuditWriter? _auditWriter;
  final PermissionGuard? _permissionGuard;
  final Future<SecurityContextRecord> Function()? _securityContextResolver;
  static const AuditService _auditService = AuditService();

  Future<List<PropertyRecord>> list({bool includeArchived = false}) async {
    final rows = await _db.query(
      'properties',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'updated_at DESC',
    );

    return rows.map(PropertyRecord.fromMap).toList();
  }

  Future<PropertyRecord?> getById(String id) async {
    final rows = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PropertyRecord.fromMap(rows.first);
  }

  Future<PropertyRecord> create({
    required String name,
    required String addressLine1,
    String? addressLine2,
    required String zip,
    required String city,
    required String country,
    required String propertyType,
    required int units,
    double? sqft,
    int? yearBuilt,
    String? notes,
  }) async {
    await _ensurePermission(
      permission: Permission.propertyCreate,
      message: 'You do not have permission to create properties.',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = PropertyRecord(
      id: const Uuid().v4(),
      name: name,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      zip: zip,
      city: city,
      country: country,
      propertyType: propertyType,
      units: units,
      sqft: sqft,
      yearBuilt: yearBuilt,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insert(
      'properties',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(record));
    }
    await _recordAudit(
      entityType: 'property',
      entityId: record.id,
      action: 'create',
      summary: 'Property created: ${record.name}',
      newValues: record.toMap(),
    );
    return record;
  }

  Future<PropertyCreateResult> createWithBaseScenario({
    required String name,
    required String addressLine1,
    String? addressLine2,
    required String zip,
    required String city,
    required String country,
    required String propertyType,
    required int units,
    double? sqft,
    int? yearBuilt,
    String? notes,
    required String strategyType,
    required AppSettingsRecord settings,
    required double purchasePrice,
    required double rentMonthly,
    required double rehabBudget,
    required String financingMode,
  }) async {
    await _ensurePermission(
      permission: Permission.propertyCreate,
      message: 'You do not have permission to create properties.',
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    final property = PropertyRecord(
      id: const Uuid().v4(),
      name: name,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      zip: zip,
      city: city,
      country: country,
      propertyType: propertyType,
      units: units,
      sqft: sqft,
      yearBuilt: yearBuilt,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    final scenario = ScenarioRecord(
      id: const Uuid().v4(),
      propertyId: property.id,
      name: 'Base',
      strategyType: strategyType,
      isBase: true,
      workflowStatus: ScenarioWorkflowStatus.draft,
      approvedBy: null,
      approvedAt: null,
      rejectedBy: null,
      rejectedAt: null,
      reviewComment: null,
      changedSinceApproval: false,
      createdAt: now,
      updatedAt: now,
    );

    final inputs = ScenarioInputs.defaults(
      scenarioId: scenario.id,
      settings: settings,
    ).copyWith(
      purchasePrice: purchasePrice,
      rentMonthlyTotal: rentMonthly,
      rehabBudget: rehabBudget,
      financingMode: financingMode,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      await txn.insert(
        'properties',
        property.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'scenarios',
        scenario.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'scenario_inputs',
        inputs.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(property));
      await searchRepo.upsertIndexEntry(searchRepo.buildScenarioRecord(scenario));
    }
    await _recordAudit(
      entityType: 'property',
      entityId: property.id,
      action: 'create',
      summary: 'Property with base scenario created',
      newValues: property.toMap(),
    );

    return PropertyCreateResult(property: property, scenario: scenario);
  }

  Future<PropertyOnboardingCreateResult> createFromOnboardingDraft({
    required PropertyCreationDraft draft,
    required PropertyCreationAssessment assessment,
    required AppSettingsRecord settings,
  }) async {
    await _ensurePermission(
      permission: Permission.propertyCreate,
      message: 'You do not have permission to create properties.',
    );
    if (!assessment.canSave) {
      throw StateError('Property draft is not valid for saving.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final propertyId = _normalizeInternalId(draft.internalId);
    final property = PropertyRecord(
      id: propertyId,
      name: draft.objectName.trim(),
      addressLine1: draft.addressLine1.trim(),
      addressLine2: _clean(draft.federalState),
      zip: draft.zip.trim(),
      city: draft.city.trim(),
      country: draft.country.trim(),
      propertyType: draft.propertyType,
      units: draft.effectiveUnitCount,
      sqft: draft.totalArea,
      yearBuilt: draft.yearBuilt,
      notes: _joinNotes(<String>[
        draft.shortDescription,
        draft.environmentNotes,
        draft.locationRisks,
        draft.locationPotentials,
        draft.technicalNotes,
        draft.organisationalNotes,
      ]),
      createdAt: now,
      updatedAt: now,
      landArea: draft.landArea,
      residentialArea: draft.residentialArea,
      commercialArea: draft.commercialArea,
      parkingSpots: draft.parkingSpots,
      ownerCompany: _clean(draft.ownerCompany),
      purchaseDate: draft.purchaseDate ?? draft.originalPurchaseDate,
      purchasePrice: draft.purchasePrice ?? draft.originalPurchasePrice,
      notary: draft.notaryDate == null ? null : _formatEpochDate(draft.notaryDate!),
      seller: _clean(draft.seller),
      landRegistryDetails: draft.landRegisterAvailable ? 'vorhanden' : null,
      parcel: _clean(draft.parcel),
      energyCertificate: draft.energyCertificateAvailable ? 'vorhanden' : null,
      insuranceDetails: _clean(draft.insurances),
      taxAssignment: _clean(draft.taxNotes),
    );

    ScenarioRecord? scenario;
    final shouldCreateScenario = _shouldCreateScenario(draft);
    if (shouldCreateScenario) {
      scenario = ScenarioRecord(
        id: const Uuid().v4(),
        propertyId: property.id,
        name: 'Base',
        strategyType: 'rental',
        isBase: true,
        workflowStatus: ScenarioWorkflowStatus.draft,
        approvedBy: null,
        approvedAt: null,
        rejectedBy: null,
        rejectedAt: null,
        reviewComment: null,
        changedSinceApproval: false,
        createdAt: now,
        updatedAt: now,
      );
    }

    await _db.transaction((txn) async {
      await txn.insert(
        'properties',
        property.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (scenario != null) {
        final inputs = ScenarioInputs.defaults(
          scenarioId: scenario.id,
          settings: settings,
        ).copyWith(
          purchasePrice:
              draft.purchasePrice ?? draft.offerPrice ?? draft.originalPurchasePrice ?? 0,
          rentMonthlyTotal:
              draft.monthlyActualRent ?? _monthlyFromAnnual(draft.annualColdRent) ?? 0,
          rehabBudget: draft.renovationBudget ?? 0,
          financingMode: draft.hasLoan ? 'debt' : 'cash',
          grossAreaSqm: draft.totalArea,
          lettableAreaSqm: draft.leasedArea,
          residentialAreaSqm: draft.residentialArea,
          commercialAreaSqm: draft.commercialArea,
          vacancyPercent: draft.vacancyPercent == null
              ? 0
              : draft.vacancyPercent! / 100,
          loanAmount: draft.loanAmount ?? 0,
          interestRatePercent: draft.interestRate == null
              ? settings.defaultInterestRatePercent
              : draft.interestRate! / 100,
          termYears: draft.termYears ?? settings.defaultTermYears,
          updatedAt: now,
        );
        await txn.insert(
          'scenarios',
          scenario.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await txn.insert(
          'scenario_inputs',
          inputs.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final unitIdsByCode = <String, String>{};
      for (final unit in draft.units) {
        final unitCode = unit.unitCode.trim();
        if (unitCode.isEmpty) {
          continue;
        }
        final unitId = const Uuid().v4();
        unitIdsByCode[unitCode] = unitId;
        await txn.insert(
          'units',
          <String, Object?>{
            'id': unitId,
            'asset_property_id': property.id,
            'unit_code': unitCode,
            'unit_type': _clean(unit.useType),
            'beds': unit.rooms,
            'baths': null,
            'sqft': unit.area,
            'floor': _clean(unit.floor),
            'status': unit.status,
            'target_rent_monthly': unit.coldRent,
            'market_rent_monthly': null,
            'offline_reason': null,
            'vacancy_since': null,
            'vacancy_reason': null,
            'marketing_status': null,
            'renovation_status': unit.status == 'renovation' ? 'in_sanierung' : null,
            'expected_ready_date': null,
            'next_action': null,
            'notes': _joinNotes(<String>[unit.parkingAssignment, unit.notes]),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      for (final tenant in draft.tenants) {
        final tenantName = tenant.tenantName.trim();
        final unitId = unitIdsByCode[tenant.unitCode.trim()];
        if (tenantName.isEmpty ||
            unitId == null ||
            tenant.leaseStart == null ||
            tenant.coldRent == null) {
          continue;
        }
        final tenantId = const Uuid().v4();
        await txn.insert(
          'tenants',
          <String, Object?>{
            'id': tenantId,
            'display_name': tenantName,
            'legal_name': null,
            'email': null,
            'phone': null,
            'alternative_contact': null,
            'billing_contact': null,
            'status': tenant.paymentStatus == 'arrears' ? 'watchlist' : 'active',
            'move_in_reference': null,
            'notes': _joinNotes(<String>[tenant.noticePeriod, tenant.notes]),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await txn.insert(
          'leases',
          <String, Object?>{
            'id': const Uuid().v4(),
            'asset_property_id': property.id,
            'unit_id': unitId,
            'tenant_id': tenantId,
            'lease_name': '$tenantName - ${tenant.unitCode.trim()}',
            'start_date': tenant.leaseStart,
            'end_date': tenant.leaseEnd,
            'move_in_date': null,
            'move_out_date': null,
            'status': 'active',
            'base_rent_monthly': tenant.coldRent,
            'currency_code': 'EUR',
            'security_deposit': tenant.deposit,
            'payment_day_of_month': null,
            'billing_frequency': 'monthly',
            'lease_signed_date': null,
            'notice_date': null,
            'renewal_option_date': null,
            'break_option_date': null,
            'executed_date': null,
            'deposit_status': tenant.deposit == null ? 'unknown' : 'available',
            'rent_free_period_months': null,
            'ancillary_charges_monthly': tenant.serviceCharges,
            'parking_other_charges_monthly': null,
            'notes': tenant.notes.trim().isEmpty ? null : tenant.notes.trim(),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      if (draft.hasLoan &&
          draft.loanAmount != null &&
          draft.interestRate != null &&
          draft.termYears != null) {
        await txn.insert(
          'loans',
          <String, Object?>{
            'id': const Uuid().v4(),
            'asset_property_id': property.id,
            'lender_name': _clean(draft.bank),
            'principal': draft.loanAmount,
            'interest_rate_percent': draft.interestRate,
            'term_years': draft.termYears,
            'start_date': now,
            'amortization_type': 'standard',
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      await txn.insert(
        'property_creation_profiles',
        <String, Object?>{
          'property_id': property.id,
          'creation_reason': draft.creationReason,
          'creation_mode': draft.creationMode,
          'object_status': draft.status,
          'external_reference': _clean(draft.externalReference),
          'asset_manager': _clean(draft.assetManager),
          'priority': draft.priority,
          'tags': _clean(draft.tags),
          'federal_state': _clean(draft.federalState),
          'location_quality': draft.locationQuality,
          'profile_json': jsonEncode(_profileJson(draft, assessment)),
          'metrics_json': jsonEncode(_metricsJson(assessment.metrics)),
          'data_quality_score': assessment.metrics.dataQualityScore,
          'data_quality_status': assessment.metrics.dataQualityStatus,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (final doc in draft.documents) {
        await txn.insert(
          'property_document_checklist',
          <String, Object?>{
            'id': const Uuid().v4(),
            'property_id': property.id,
            'document_key': doc.key,
            'label': doc.label,
            'status': doc.status,
            'upload_path': _clean(doc.uploadPath),
            'note': _clean(doc.note),
            'due_date': doc.dueDate,
            'owner': _clean(doc.owner),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final uploadPath = doc.uploadPath.trim();
        if (uploadPath.isEmpty || doc.status != 'vorhanden') {
          continue;
        }
        final documentId = const Uuid().v4();
        await txn.insert(
          'documents',
          <String, Object?>{
            'id': documentId,
            'entity_type': 'property',
            'entity_id': property.id,
            'type_id': null,
            'file_path': uploadPath,
            'file_name': _fileName(uploadPath),
            'mime_type': null,
            'size_bytes': null,
            'sha256': null,
            'created_at': now,
            'created_by': null,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await txn.insert(
          'document_metadata',
          <String, Object?>{
            'id': const Uuid().v4(),
            'document_id': documentId,
            'key': 'onboarding_status',
            'value': doc.status,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(property));
      if (scenario != null) {
        await searchRepo.upsertIndexEntry(searchRepo.buildScenarioRecord(scenario));
      }
    }
    await _recordAudit(
      entityType: 'property',
      entityId: property.id,
      action: 'create',
      summary: 'Property created from onboarding workflow: ${property.name}',
      newValues: property.toMap(),
    );

    return PropertyOnboardingCreateResult(property: property, scenario: scenario);
  }

  Future<void> update(PropertyRecord record) async {
    await _ensurePermission(
      permission: Permission.propertyUpdate,
      message: 'You do not have permission to update properties.',
    );
    final before = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[record.id],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedRecord = PropertyRecord(
      id: record.id,
      name: record.name,
      addressLine1: record.addressLine1,
      addressLine2: record.addressLine2,
      zip: record.zip,
      city: record.city,
      country: record.country,
      propertyType: record.propertyType,
      units: record.units,
      sqft: record.sqft,
      yearBuilt: record.yearBuilt,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: now,
      archived: record.archived,
      landArea: record.landArea,
      residentialArea: record.residentialArea,
      commercialArea: record.commercialArea,
      parkingSpots: record.parkingSpots,
      ownerCompany: record.ownerCompany,
      purchaseDate: record.purchaseDate,
      purchasePrice: record.purchasePrice,
      notary: record.notary,
      seller: record.seller,
      landRegistryDetails: record.landRegistryDetails,
      parcel: record.parcel,
      energyCertificate: record.energyCertificate,
      insuranceDetails: record.insuranceDetails,
      taxAssignment: record.taxAssignment,
    );

    await _db.update(
      'properties',
      updatedRecord.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[record.id],
    );

    final after = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[record.id],
      limit: 1,
    );

    if (before.isNotEmpty && after.isNotEmpty) {
      final searchRepo = _searchRepo;
      if (searchRepo != null) {
        await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(updatedRecord));
      }
      await _recordAudit(
        entityType: 'property',
        entityId: record.id,
        action: 'update',
        summary: 'Property updated: ${record.name}',
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
      );
    }
  }

  Future<void> archive(String id, {required bool archived}) async {
    await _ensurePermission(
      permission: Permission.propertyUpdate,
      message: 'You do not have permission to update properties.',
    );
    final before = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.update(
      'properties',
      <String, Object?>{
        'archived': archived ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final after = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      final updated = PropertyRecord.fromMap(after.first);
      final searchRepo = _searchRepo;
      if (searchRepo != null && updated.archived) {
        await searchRepo.deleteIndexEntryByEntity(
          entityType: 'property',
          entityId: id,
        );
      } else if (searchRepo != null) {
        await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(updated));
      }
      await _recordAudit(
        entityType: 'property',
        entityId: id,
        action: 'update',
        summary: archived ? 'Property archived' : 'Property unarchived',
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
      );
    }
  }

  /// Soft-tombstones the property (DEBT-012 / STM-002): marks `deleted_at`/
  /// `deleted_by` and sets `archived = 1` so every read that filters
  /// `archived = 0` hides it, while the row and all child records are kept for
  /// audit and restore. Writes an append-only `delete` audit event. No-op if the
  /// property does not exist or is already tombstoned.
  Future<void> tombstone(String id, {String? actorId}) async {
    await _ensurePermission(
      permission: Permission.propertyDelete,
      message: 'You do not have permission to delete properties.',
    );
    final before = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isEmpty) {
      return;
    }
    if ((before.first['deleted_at'] as num?) != null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'properties',
      <String, Object?>{
        'deleted_at': now,
        'deleted_by': actorId,
        'archived': 1,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );

    await _searchRepo?.deleteIndexEntryByEntity(
      entityType: 'property',
      entityId: id,
    );

    final after = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _recordAudit(
      entityType: 'property',
      entityId: id,
      action: 'delete',
      summary: 'Property deleted (soft tombstone)',
      oldValues: before.first,
      newValues: after.isNotEmpty ? after.first : null,
    );
  }

  /// Restores a tombstoned property (DEBT-012 / STM-002): clears `deleted_at`/
  /// `deleted_by` and sets `archived = 0`, bringing it back as an active record
  /// with its children intact, and re-indexes it for search. Writes an
  /// append-only audit event. No-op if the property does not exist or is not
  /// tombstoned.
  Future<void> restore(String id, {String? actorId}) async {
    await _ensurePermission(
      permission: Permission.propertyDelete,
      message: 'You do not have permission to restore properties.',
    );
    final before = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isEmpty) {
      return;
    }
    if ((before.first['deleted_at'] as num?) == null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'properties',
      <String, Object?>{
        'deleted_at': null,
        'deleted_by': null,
        'archived': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );

    final after = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final searchRepo = _searchRepo;
    if (after.isNotEmpty && searchRepo != null) {
      final restored = PropertyRecord.fromMap(after.first);
      await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(restored));
    }
    await _recordAudit(
      entityType: 'property',
      entityId: id,
      action: 'update',
      summary: 'Property restored',
      oldValues: before.first,
      newValues: after.isNotEmpty ? after.first : null,
    );
  }

  Future<void> _ensurePermission({
    required String permission,
    required String message,
  }) async {
    final guard = _permissionGuard;
    final contextResolver = _securityContextResolver;
    if (guard == null || contextResolver == null) {
      return;
    }
    final context = await contextResolver();
    guard.ensurePermission(
      role: context.user.role,
      permission: permission,
      context: PermissionContext(
        scopeType: PermissionScopeType.workspace,
        scopeId: context.workspace.id,
        workspaceId: context.workspace.id,
      ),
      message: message,
    );
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    List<AuditDiffItem> diffItems = const <AuditDiffItem>[],
  }) async {
    final auditWriter = _auditWriter;
    if (auditWriter != null) {
      await auditWriter.record(
        entityType: entityType,
        entityId: entityId,
        action: action,
        summary: summary,
        oldValues: oldValues,
        newValues: newValues,
        diffItems: diffItems,
      );
      return;
    }
    await _auditLogRepo?.recordEvent(
      entityType: entityType,
      entityId: entityId,
      action: action,
      summary: summary,
      oldValues: oldValues,
      newValues: newValues,
      diffItems: diffItems,
      source: 'ui',
    );
  }

  bool _shouldCreateScenario(PropertyCreationDraft draft) {
    return draft.purchasePrice != null ||
        draft.offerPrice != null ||
        draft.originalPurchasePrice != null ||
        draft.monthlyActualRent != null ||
        draft.annualColdRent != null ||
        draft.renovationBudget != null ||
        draft.hasLoan;
  }

  String _normalizeInternalId(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '-');
    if (cleaned.isEmpty) {
      return const Uuid().v4();
    }
    return cleaned;
  }

  String? _clean(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  String? _joinNotes(List<String> notes) {
    final cleaned = notes
        .map((note) => note.trim())
        .where((note) => note.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) {
      return null;
    }
    return cleaned.join('\n\n');
  }

  double? _monthlyFromAnnual(double? annualValue) {
    if (annualValue == null) {
      return null;
    }
    return annualValue / 12;
  }

  String _formatEpochDate(int millis) {
    return DateTime.fromMillisecondsSinceEpoch(millis)
        .toIso8601String()
        .substring(0, 10);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  Map<String, Object?> _profileJson(
    PropertyCreationDraft draft,
    PropertyCreationAssessment assessment,
  ) {
    return <String, Object?>{
      'entry': <String, Object?>{
        'propertyType': draft.propertyType,
        'creationReason': draft.creationReason,
        'creationMode': draft.creationMode,
      },
      'base': <String, Object?>{
        'externalReference': draft.externalReference,
        'shortDescription': draft.shortDescription,
        'assetManager': draft.assetManager,
        'priority': draft.priority,
        'tags': draft.tags,
      },
      'location': <String, Object?>{
        'street': draft.street,
        'houseNumber': draft.houseNumber,
        'federalState': draft.federalState,
        'locationQuality': draft.locationQuality,
        'microLocation': draft.microLocation,
        'macroLocation': draft.macroLocation,
        'transit': draft.transit,
        'parking': draft.parking,
        'environmentNotes': draft.environmentNotes,
        'risks': draft.locationRisks,
        'potentials': draft.locationPotentials,
      },
      'areas': <String, Object?>{
        'usableArea': draft.usableArea,
        'residentialUnits': draft.residentialUnits,
        'commercialUnits': draft.commercialUnits,
        'garages': draft.garages,
        'basementArea': draft.basementArea,
        'vacantArea': draft.vacantArea,
        'leasedArea': draft.leasedArea,
        'expansionPotential': draft.expansionPotential,
        'densificationPotential': draft.densificationPotential,
      },
      'usage': <String, Object?>{
        'mainUse': draft.mainUse,
        'usageMix': draft.usageMix,
        'leaseContractStatus': draft.leaseContractStatus,
        'indexedRent': draft.indexedRent,
        'steppedRent': draft.steppedRent,
        'rentArrears': draft.rentArrears,
        'specialLeaseTerms': draft.specialLeaseTerms,
        'captureTenantsNow': draft.captureTenantsNow,
      },
      'purchase': <String, Object?>{
        'broker': draft.broker,
        'propertyTransferTax': draft.propertyTransferTax,
        'notaryCosts': draft.notaryCosts,
        'landRegistryCosts': draft.landRegistryCosts,
        'brokerFee': draft.brokerFee,
        'otherAcquisitionCosts': draft.otherAcquisitionCosts,
        'transferBenefitsDate': draft.transferBenefitsDate,
        'bookValue': draft.bookValue,
        'marketValue': draft.marketValue,
        'lastInternalValuation': draft.lastInternalValuation,
        'valuationDate': draft.valuationDate,
        'historicNotes': draft.historicNotes,
      },
      'financing': <String, Object?>{
        'hasLoan': draft.hasLoan,
        'equity': draft.equity,
        'amortizationRate': draft.amortizationRate,
        'fixedInterestPeriod': draft.fixedInterestPeriod,
        'monthlyRate': draft.monthlyRate,
        'annualDebtService': draft.annualDebtService,
        'bank': draft.bank,
        'loanNumber': draft.loanNumber,
        'remainingDebt': draft.remainingDebt,
        'specialRepayment': draft.specialRepayment,
        'notes': draft.financingNotes,
      },
      'technical': <String, Object?>{
        'lastRenovationYear': draft.lastRenovationYear,
        'energyClass': draft.energyClass,
        'heatingType': draft.heatingType,
        'roofCondition': draft.roofCondition,
        'facadeCondition': draft.facadeCondition,
        'windowsCondition': draft.windowsCondition,
        'electricCondition': draft.electricCondition,
        'pipesCondition': draft.pipesCondition,
        'fireSafetyStatus': draft.fireSafetyStatus,
        'accessibility': draft.accessibility,
        'moistureDamage': draft.moistureDamage,
        'monumentProtection': draft.monumentProtection,
        'renovationNeed': draft.renovationNeed,
        'technicalRisks': draft.technicalRisks,
      },
      'legal': <String, Object?>{
        'knownBuildingCharges': draft.knownBuildingCharges,
        'legalMonumentProtection': draft.legalMonumentProtection,
        'declarationOfDivisionAvailable': draft.declarationOfDivisionAvailable,
        'weg': draft.weg,
        'easements': draft.easements,
        'legalDisputes': draft.legalDisputes,
        'propertyManagement': draft.propertyManagement,
        'internalContact': draft.internalContact,
        'externalContact': draft.externalContact,
        'criticalRisksConfirmed': draft.criticalRisksConfirmed,
      },
      'units': draft.units
          .map((unit) => <String, Object?>{
                'unitCode': unit.unitCode,
                'useType': unit.useType,
                'floor': unit.floor,
                'area': unit.area,
                'rooms': unit.rooms,
                'status': unit.status,
                'coldRent': unit.coldRent,
                'serviceCharge': unit.serviceCharge,
                'parkingAssignment': unit.parkingAssignment,
                'notes': unit.notes,
              })
          .toList(growable: false),
      'tenants': draft.tenants
          .map((tenant) => <String, Object?>{
                'tenantName': tenant.tenantName,
                'unitCode': tenant.unitCode,
                'leaseStart': tenant.leaseStart,
                'leaseEnd': tenant.leaseEnd,
                'noticePeriod': tenant.noticePeriod,
                'coldRent': tenant.coldRent,
                'serviceCharges': tenant.serviceCharges,
                'deposit': tenant.deposit,
                'paymentStatus': tenant.paymentStatus,
                'notes': tenant.notes,
              })
          .toList(growable: false),
      'assessment': <String, Object?>{
        'missingRequired': assessment.missingRequired,
        'recommended': assessment.recommended,
        'criticalWarnings': assessment.criticalWarnings,
      },
    };
  }

  Map<String, Object?> _metricsJson(PropertyCreationMetrics metrics) {
    return <String, Object?>{
      'purchasePricePerSqm': metrics.purchasePricePerSqm,
      'totalArea': metrics.totalArea,
      'leasedArea': metrics.leasedArea,
      'vacantArea': metrics.vacantArea,
      'vacancyRate': metrics.vacancyRate,
      'actualRentPerSqm': metrics.actualRentPerSqm,
      'targetRentPerSqm': metrics.targetRentPerSqm,
      'annualActualRent': metrics.annualActualRent,
      'annualTargetRent': metrics.annualTargetRent,
      'rentUpside': metrics.rentUpside,
      'purchaseFactorActual': metrics.purchaseFactorActual,
      'purchaseFactorTarget': metrics.purchaseFactorTarget,
      'acquisitionCosts': metrics.acquisitionCosts,
      'acquisitionCostRatio': metrics.acquisitionCostRatio,
      'totalInvestment': metrics.totalInvestment,
      'loanToValue': metrics.loanToValue,
      'equityRatio': metrics.equityRatio,
      'conditionScore': metrics.conditionScore,
      'dataQualityScore': metrics.dataQualityScore,
      'dataQualityStatus': metrics.dataQualityStatus,
    };
  }
}
