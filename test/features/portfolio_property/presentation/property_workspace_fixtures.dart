import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

Widget wrapApp(Widget child, {bool dark = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: child),
  );
}

void setViewport(WidgetTester tester, Size viewport) {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const Set<String> fullPermissions = <String>{
  'property.read',
  'property.update',
};

WorkspaceAccess access({Set<String> permissions = fullPermissions}) {
  return WorkspaceAccess(
    workspace: const WorkspaceSummary(
      id: 'workspace-a',
      key: 'workspace-a',
      name: 'Workspace A',
      version: 1,
    ),
    membership: const MembershipSummary(
      id: 'membership-a',
      workspaceId: 'workspace-a',
      userId: 'user-a',
      roleId: 'manager',
      version: 1,
    ),
    permissions: permissions,
  );
}

PropertyDto property({
  String id = 'property-a',
  String name = 'Atlas House',
  String addressLine1 = 'Long Street 123',
  String? addressLine2,
  String zip = '10115',
  String city = 'Berlin',
  String country = 'de',
  String propertyType = 'mixed_use',
  int units = 12,
  double? sqft,
  int? yearBuilt,
  String? notes = 'Reference fixture',
  PropertyStatus status = PropertyStatus.active,
  int version = 1,
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
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
    status: status,
    createdAt: DateTime.utc(2026, 7, 1, 8, 30),
    updatedAt: DateTime.utc(2026, 7, 17, 9, 45),
    createdBy: 'actor-created-uuid',
    updatedBy: 'actor-updated-uuid',
    version: version,
  );
}

/// An authenticated aal2 session with a selected workspace and the given
/// list/detail phases.
ReferenceSliceState sliceState({
  ReferenceAuthPhase authPhase = ReferenceAuthPhase.authenticated,
  AuthenticationAssuranceLevel assuranceLevel =
      AuthenticationAssuranceLevel.aal2,
  WorkspacePhase workspacePhase = WorkspacePhase.selected,
  Set<String> permissions = fullPermissions,
  PropertyListPhase listPhase = PropertyListPhase.ready,
  List<PropertySummaryDto>? properties,
  String? nextCursor,
  bool includeArchived = false,
  String? loadMoreFailureMessage,
  PropertyDetailPhase detailPhase = PropertyDetailPhase.idle,
  PropertyDto? selectedProperty,
  PropertyMutationPhase mutationPhase = PropertyMutationPhase.idle,
  PropertyRepositoryFailureKind? failureKind,
  PropertyVersionConflict? versionConflict,
  String? message,
  bool liveUpdatesDegraded = false,
}) {
  return ReferenceSliceState(
    authPhase: authPhase,
    assuranceLevel: assuranceLevel,
    workspacePhase: workspacePhase,
    propertyListPhase: listPhase,
    propertyDetailPhase: detailPhase,
    mutationPhase: mutationPhase,
    userId: 'user-a',
    workspaces: <WorkspaceAccess>[access(permissions: permissions)],
    selectedWorkspaceId:
        workspacePhase == WorkspacePhase.selected ? 'workspace-a' : null,
    properties: properties ?? <PropertySummaryDto>[property()],
    nextCursor: nextCursor,
    selectedProperty: selectedProperty,
    failureKind: failureKind,
    versionConflict: versionConflict,
    message: message,
    liveUpdatesDegraded: liveUpdatesDegraded,
    includeArchived: includeArchived,
    loadMoreFailureMessage: loadMoreFailureMessage,
  );
}

/// A ready property context for the given property.
ReferenceSliceState detailState({
  PropertyDto? selected,
  Set<String> permissions = fullPermissions,
  AuthenticationAssuranceLevel assuranceLevel =
      AuthenticationAssuranceLevel.aal2,
  PropertyMutationPhase mutationPhase = PropertyMutationPhase.idle,
  PropertyRepositoryFailureKind? failureKind,
  PropertyVersionConflict? versionConflict,
  String? message,
  bool liveUpdatesDegraded = false,
  List<PropertySummaryDto>? properties,
}) {
  final resolved = selected ?? property();
  return sliceState(
    permissions: permissions,
    assuranceLevel: assuranceLevel,
    properties: properties ?? <PropertySummaryDto>[resolved],
    detailPhase: PropertyDetailPhase.ready,
    selectedProperty: resolved,
    mutationPhase: mutationPhase,
    failureKind: failureKind,
    versionConflict: versionConflict,
    message: message,
    liveUpdatesDegraded: liveUpdatesDegraded,
  );
}

/// A server overview payload. Every section defaults to *available with real
/// counts*; pass [PropertyOverviewSection.unavailable] to model a membership
/// that may not read one.
PropertyOverviewDto overview({
  String propertyId = 'property-a',
  DateTime? asOf,
  PropertyOverviewSection? leasing,
  PropertyOverviewSection? maintenance,
  PropertyOverviewSection? capex,
  PropertyOverviewSection? tasks,
  PropertyOverviewSection? documents,
  PropertyOverviewSection? valuation,
  List<PropertyOverviewAttention> attention =
      const <PropertyOverviewAttention>[],
  DateTime? lastValuationUpdatedAt,
}) {
  return PropertyOverviewDto(
    propertyId: propertyId,
    workspaceId: 'workspace-a',
    name: 'Atlas House',
    asOf: asOf ?? DateTime.utc(2026, 9, 6, 8, 15),
    leasing:
        leasing ??
        const PropertyOverviewSection.available(<String, int>{
          'units_total': 12,
          'units_occupied': 9,
          'units_vacant': 3,
          'units_offline': 0,
          'leases_active': 9,
          'leases_ending_90d': 2,
          'leases_expired_open': 1,
          'leasing_cases_open': 4,
        }),
    maintenance:
        maintenance ??
        const PropertyOverviewSection.available(<String, int>{
          'tickets_open': 5,
          'tickets_overdue': 2,
          'tickets_urgent_open': 1,
        }),
    capex:
        capex ??
        const PropertyOverviewSection.available(<String, int>{
          'projects_open': 3,
          'projects_before_approval': 1,
        }),
    tasks:
        tasks ??
        const PropertyOverviewSection.available(<String, int>{
          'tasks_open': 7,
          'tasks_overdue': 0,
          'tasks_blocked': 1,
        }),
    documents:
        documents ??
        const PropertyOverviewSection.available(<String, int>{
          'documents_total': 22,
          'requirements_total': 6,
          'requirements_overdue': 1,
          'requirements_waived': 2,
        }),
    valuation:
        valuation ??
        const PropertyOverviewSection.available(<String, int>{
          'cases_total': 2,
          'cases_open': 1,
        }),
    attention: attention,
    lastValuationUpdatedAt: lastValuationUpdatedAt,
  );
}

const List<Size> goldenViewports = <Size>[
  Size(320, 700),
  Size(390, 844),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
];
