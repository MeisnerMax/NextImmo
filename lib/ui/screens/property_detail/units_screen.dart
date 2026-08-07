import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'leasing/leases_panel.dart';
import 'leasing/leasing_pipeline_panel.dart';
import 'leasing/tenants_panel.dart';
import 'leasing/units_panel.dart';
import 'leasing/widgets/leasing_area_gate.dart';
import 'property_tasks_screen.dart';

/// The five leasing tabs of a property. This is a tab host and nothing else —
/// each tab owns its own data, so there is no shared state left to load here
/// (Welle 3: AP1 took the units tab onto the P2-D05 contract, AP3 the leases
/// tab, AP4 the pipeline tab, AP5 the tenants tab; only tasks remain legacy).
class UnitsScreen extends ConsumerStatefulWidget {
  const UnitsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends ConsumerState<UnitsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _tabIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The property-kind gate sits on the whole area, not on one tab: a hotel
    // has guests, not tenants — and not units to let, leases or a pipeline
    // either. Gating only the tenants tab, as the legacy screen did, guarded
    // nothing.
    return LeasingAreaGate(
      propertyId: widget.propertyId,
      child: _buildTabs(context),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          // Was hardcoded white, which painted a white bar across the top of
          // the screen in dark mode.
          color: Theme.of(context).colorScheme.surface,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Einheiten'),
                Tab(text: 'Mieter'),
                Tab(text: 'Mietverträge'),
                Tab(text: 'Vermietungspipeline'),
                Tab(text: 'Aufgaben'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildActiveTab()),
      ],
    );
  }

  Widget _buildActiveTab() {
    switch (_tabIndex) {
      case 0:
        return UnitsPanel(propertyId: widget.propertyId);
      case 1:
        // The tenant list is the party directory scoped to the tenant role, and
        // that directory is workspace-wide — hence no propertyId here.
        return const TenantsPanel();
      case 2:
        return LeasesPanel(propertyId: widget.propertyId);
      case 3:
        return LeasingPipelinePanel(propertyId: widget.propertyId);
      case 4:
        return PropertyTasksScreen(propertyId: widget.propertyId);
      default:
        return const SizedBox.shrink();
    }
  }
}
