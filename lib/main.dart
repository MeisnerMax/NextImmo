import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_backend_wiring.dart';
import 'core/config/app_environment.dart';
import 'features/identity_access/data/desktop_auth_deep_link_observer.dart';
import 'features/identity_access/data/supabase_entitlement_invalidation_adapter.dart';
import 'features/identity_access/data/supabase_identity_access_repository_adapter.dart';
import 'features/identity_access/data/supabase_membership_admin_repository_adapter.dart';
import 'features/portfolio_property/data/supabase_property_query_invalidation_adapter.dart';
import 'features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'features/identity_access/application/members_admin_controller.dart';
import 'features/reference_slice/application/reference_slice_controller.dart';

/// Supabase is the only application runtime backend (`DEC-024`, AP-X02-2b).
/// [AppEnvironment.fromDartDefines] fails closed before this point on anything
/// other than `NEXIMMO_DATA_BACKEND=supabase`, so there is no branch here and
/// no local database is ever opened by the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = AppEnvironment.fromDartDefines();

  await Supabase.initialize(
    url: environment.supabaseUrl!,
    publishableKey: environment.supabasePublishableKey!,
    // On web the browser owns the redirect and the SDK's own URL detection is
    // the right mechanism. On desktop it is not: it exchanges any URI carrying
    // a `code` parameter without checking where the URI came from, and the app
    // registers `neximmo:` system-wide. Desktop therefore validates the
    // callback itself, below.
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: kIsWeb),
  );
  final client = Supabase.instance.client;

  if (!kIsWeb) {
    // Lives for the process lifetime, like the observer it replaces. The
    // session it produces reaches the UI through `onAuthStateChange`, so no
    // navigation is wired here.
    DesktopAuthDeepLinkObserver.forClient(client).start();
  }

  runApp(
    ProviderScope(
      overrides: [
        identityAccessRepositoryProvider.overrideWithValue(
          SupabaseIdentityAccessRepositoryAdapter(client: client),
        ),
        entitlementInvalidationSourceProvider.overrideWithValue(
          SupabaseEntitlementInvalidationAdapter(client: client),
        ),
        membershipAdminRepositoryProvider.overrideWithValue(
          SupabaseMembershipAdminRepositoryAdapter(client: client),
        ),
        referencePropertyRepositoryProvider.overrideWithValue(
          SupabasePropertyRepositoryAdapter(client: client),
        ),
        propertyQueryInvalidationSourceProvider.overrideWithValue(
          SupabasePropertyQueryInvalidationAdapter(client: client),
        ),
        ...featureBackendOverrides(client: client),
      ],
      child: NexImmoApp(environment: environment),
    ),
  );
}
