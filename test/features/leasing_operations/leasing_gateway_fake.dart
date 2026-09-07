/// A gateway that answers one RPC and refuses everything else.
///
/// Shared rather than copied per test file: a fake that quietly returns an
/// empty list for a method a test did not mean to call is how a test ends up
/// asserting nothing. Every method here throws except the one under test.
library;

import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';

/// Minimal gateway: this file exercises one RPC, so everything else refuses
/// rather than returning an empty list that could quietly stand in for one.
class FakeLeasingGateway implements LeasingSupabaseGateway {
  Object? rpcResult;
  String? lastRpcName;
  Map<String, Object?>? lastRpcParameters;

  @override
  String? get currentUserId => 'aa000000-0000-0000-0000-000000000001';

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    lastRpcName = function;
    lastRpcParameters = parameters;
    return rpcResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listUnits({
    required String workspaceId,
    required String? propertyId,
    required String? status,
    required String? afterId,
    required int limit,
  }) async => throw UnimplementedError('listUnits');

  @override
  Future<List<Map<String, dynamic>>> getUnit({
    required String workspaceId,
    required String unitId,
  }) async => throw UnimplementedError('getUnit');

  @override
  Future<List<Map<String, dynamic>>> listLeases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? tenantPartyId,
    required String? status,
    required String? afterId,
    required int limit,
  }) async => throw UnimplementedError('listLeases');

  @override
  Future<List<Map<String, dynamic>>> getLease({
    required String workspaceId,
    required String leaseId,
  }) async => throw UnimplementedError('getLease');

  @override
  Future<List<Map<String, dynamic>>> listLeasingCases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? status,
    required bool openOnly,
    required String? afterId,
    required int limit,
  }) async => throw UnimplementedError('listLeasingCases');

  @override
  Future<List<Map<String, dynamic>>> getLeasingCase({
    required String workspaceId,
    required String caseId,
  }) async => throw UnimplementedError('getLeasingCase');

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshots({
    required String workspaceId,
    required String propertyId,
    required String? afterId,
    required int limit,
  }) async => throw UnimplementedError('listRentRollSnapshots');

  @override
  Future<List<Map<String, dynamic>>> getRentRollSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) async => throw UnimplementedError('getRentRollSnapshot');

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshotLines({
    required String workspaceId,
    required String snapshotId,
  }) async => throw UnimplementedError('listRentRollSnapshotLines');
}
