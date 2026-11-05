import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../core/utils/uuid_generator.dart';
import '../../data/models/inventory_component_unit_model.dart';
import '../../data/models/inventory_item_history_model.dart';
import '../../data/models/inventory_unit_model.dart';
import '../../data/repositories/inventory_item_history_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';

class RestockUnitGroup {
  final InventoryUnitModel unit;
  final String parentItemName;
  final List<InventoryComponentUnitModel> affectedComponents;
  final bool isWholeUnitDamagedOrLost;

  RestockUnitGroup({
    required this.unit,
    required this.parentItemName,
    required this.affectedComponents,
    required this.isWholeUnitDamagedOrLost,
  });
}

class RestockInventoryScreen extends StatefulWidget {
  const RestockInventoryScreen({super.key});

  @override
  State<RestockInventoryScreen> createState() => _RestockInventoryScreenState();
}

class _RestockInventoryScreenState extends State<RestockInventoryScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  String _selectedFilter = 'All'; // 'All', 'Damaged', 'Lost'
  List<RestockUnitGroup> _unitGroups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRestockAssets();
  }

  Future<void> _loadRestockAssets() async {
    setState(() => _isLoading = true);

    final user = _client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final List<RestockUnitGroup> groups = [];

      // 1. Fetch units that have status = maintenance, lost, in_maintenance, or needed_restock
      // or contain component units with those exception statuses
      final unitRes = await _client
          .from('inventory_units')
          .select('*, inventory_items(name), inventory_component_units(*)')
          .eq('store_id', user.id)
          .order('unit_number', ascending: true);

      for (final json in unitRes as List) {
        final u = InventoryUnitModel.fromJson(json as Map<String, dynamic>);
        final pName = json['inventory_items'] != null ? json['inventory_items']['name'] as String : 'Equipment Item';

        final unitSt = u.status.toLowerCase();
        final bool isWholeUnitException = unitSt == 'maintenance' ||
            unitSt == 'damaged' ||
            unitSt == 'in_maintenance' ||
            unitSt == 'lost' ||
            unitSt == 'needed_restock';

        // Filter affected sub-components
        final List<InventoryComponentUnitModel> affectedComps = [];

        if (isWholeUnitException) {
          // If whole unit is damaged/lost, show all components of that unit
          affectedComps.addAll(u.components);
        } else {
          // Only show components that are explicitly damaged, in_maintenance, lost, or needed_restock
          for (final c in u.components) {
            final cSt = c.status.toLowerCase();
            if (cSt == 'maintenance' ||
                cSt == 'damaged' ||
                cSt == 'in_maintenance' ||
                cSt == 'lost' ||
                cSt == 'needed_restock') {
              affectedComps.add(c);
            }
          }
        }

        // Only include unit card if the unit itself is an exception OR has affected components
        if (isWholeUnitException || affectedComps.isNotEmpty) {
          groups.add(RestockUnitGroup(
            unit: u,
            parentItemName: pName,
            affectedComponents: affectedComps,
            isWholeUnitDamagedOrLost: isWholeUnitException,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _unitGroups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading restock assets: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateComponentStatus(
    InventoryComponentUnitModel comp,
    String newStatus,
    String parentItemId,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final storeState = context.read<StoreCubit>().state;
    final storeId = storeState is StoreLoaded ? storeState.store.id : user.id;

    try {
      final oldStatus = comp.status;

      // 1. Update component status in database
      await _client
          .from('inventory_component_units')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', comp.id);

      // Note: Parent unit status (inventory_units) is kept independent as configured by user,
      // unless user explicitly updates the parent unit status header directly.

      // 3. Log Audit Trail
      final historyRepo = InventoryItemHistoryRepository();
      String eventType = 'damaged';
      if (newStatus == 'available') {
        eventType = oldStatus.contains('lost') || oldStatus.contains('restock') ? 'replaced' : 'repaired';
      } else if (newStatus.contains('lost') || newStatus.contains('restock')) {
        eventType = 'lost';
      }

      await historyRepo.logHistory(InventoryItemHistoryModel(
        id: UuidGenerator.generateV4(),
        storeId: storeId,
        inventoryItemId: parentItemId,
        inventoryUnitId: comp.inventoryUnitId,
        inventoryComponentUnitId: comp.id,
        eventType: eventType,
        previousStatus: oldStatus,
        newStatus: newStatus,
        notes: 'Status updated from $oldStatus to $newStatus for ${comp.componentName}',
        costIncurred: comp.replacementCost,
        createdAt: DateTime.now(),
      ));

      // 4. Refresh State
      if (mounted) {
        await context.read<InventoryCubit>().loadInventory();
        await _loadRestockAssets();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated "${comp.componentName}" status to ${_getReadableStatus(newStatus)}!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateUnitHeaderStatus(
    RestockUnitGroup group,
    String newStatus,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final storeState = context.read<StoreCubit>().state;
    final storeId = storeState is StoreLoaded ? storeState.store.id : user.id;

    try {
      final oldStatus = group.unit.status;

      // 1. Update Unit status
      await _client
          .from('inventory_units')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', group.unit.id);

      // 2. Propagate status to all affected sub-components under this unit
      for (final comp in group.affectedComponents) {
        await _client
            .from('inventory_component_units')
            .update({
              'status': newStatus,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', comp.id);
      }

      // 3. Log Audit Trail
      final historyRepo = InventoryItemHistoryRepository();
      String eventType = 'damaged';
      if (newStatus == 'available') {
        eventType = oldStatus.contains('lost') || oldStatus.contains('restock') ? 'replaced' : 'repaired';
      } else if (newStatus.contains('lost') || newStatus.contains('restock')) {
        eventType = 'lost';
      }

      await historyRepo.logHistory(InventoryItemHistoryModel(
        id: UuidGenerator.generateV4(),
        storeId: storeId,
        inventoryItemId: group.unit.inventoryItemId,
        inventoryUnitId: group.unit.id,
        eventType: eventType,
        previousStatus: oldStatus,
        newStatus: newStatus,
        notes: 'Unit Set #${group.unit.unitNumber} status updated to $newStatus',
        createdAt: DateTime.now(),
      ));

      // 4. Refresh State
      if (mounted) {
        await context.read<InventoryCubit>().loadInventory();
        await _loadRestockAssets();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated Set #${group.unit.unitNumber} status to ${_getReadableStatus(newStatus)}!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error updating unit status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating unit status: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _getReadableStatus(String raw) {
    final st = raw.toLowerCase();
    if (st == 'maintenance' || st == 'damaged') return 'Damaged';
    if (st == 'in_maintenance') return 'In Maintenance';
    if (st == 'lost') return 'Lost';
    if (st == 'needed_restock') return 'Needed Restock';
    if (st == 'available') return 'Available (Restocked)';
    return raw.toUpperCase();
  }

  List<RestockUnitGroup> get _filteredGroups {
    if (_selectedFilter == 'All') return _unitGroups;
    final filter = _selectedFilter.toLowerCase();

    return _unitGroups.where((g) {
      final unitSt = g.unit.status.toLowerCase();
      final hasDamagedComp = g.affectedComponents.any((c) {
        final st = c.status.toLowerCase();
        return st == 'maintenance' || st == 'damaged' || st == 'in_maintenance';
      });
      final hasLostComp = g.affectedComponents.any((c) {
        final st = c.status.toLowerCase();
        return st == 'lost' || st == 'needed_restock';
      });

      if (filter == 'damaged') {
        return unitSt == 'maintenance' || unitSt == 'damaged' || unitSt == 'in_maintenance' || hasDamagedComp;
      }
      if (filter == 'lost') {
        return unitSt == 'lost' || unitSt == 'needed_restock' || hasLostComp;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';
    final displayGroups = _filteredGroups;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Restock & Repair Management'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: Column(
        children: [
          // Filter Chips Header Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? AppColors.darkCard : Colors.white,
            child: Row(
              children: [
                _buildFilterChip('All', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Damaged', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Lost', isDark),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayGroups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 48,
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No Assets Pending Restock or Repair',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All physical sets and accessories are 100% available in stock.',
                              style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: displayGroups.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final group = displayGroups[index];
                          return _buildUnitGroupCard(group, currency, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitGroupCard(RestockUnitGroup group, String currency, bool isDark) {
    final unit = group.unit;
    final unitSt = unit.status.toLowerCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Parent Item & Physical Set Unit Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.parentItemName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '📦 Physical Set #${unit.unitNumber} (${unit.assetCode})',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(unitSt, isDark),
            ],
          ),
          const SizedBox(height: 10),

          // Unit Header Status Control Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Set Status:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
              ),
              _buildStatusDropdown(
                currentStatus: unitSt,
                isDark: isDark,
                onChanged: (newSt) {
                  if (newSt != null) {
                    _updateUnitHeaderStatus(group, newSt);
                  }
                },
              ),
            ],
          ),

          // 2. Sub-Components List under this Unit
          if (group.affectedComponents.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            const SizedBox(height: 8),

            Text(
              group.isWholeUnitDamagedOrLost
                  ? 'All Unit Sub-Components (${group.affectedComponents.length}):'
                  : 'Damaged / Lost Sub-Components (${group.affectedComponents.length}):',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            const SizedBox(height: 8),

            ...group.affectedComponents.map((comp) {
              final compSt = comp.status.toLowerCase();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ${comp.componentName}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (comp.serialNumber != null && comp.serialNumber!.isNotEmpty)
                                Text(
                                  'SN: ${comp.serialNumber}',
                                  style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                              if (comp.replacementCost > 0)
                                Text(
                                  'Replacement Fee: $currency${comp.replacementCost.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                            ],
                          ),
                        ),
                        _buildStatusBadge(compSt, isDark),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Component Status Dropdown Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Change Status:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                        _buildStatusDropdown(
                          currentStatus: compSt,
                          isDark: isDark,
                          onChanged: (newSt) {
                            if (newSt != null) {
                              _updateComponentStatus(comp, newSt, group.unit.inventoryItemId);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String rawStatus, bool isDark) {
    final st = rawStatus.toLowerCase();

    String label = 'AVAILABLE';
    Color bg = isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5);
    Color textCol = AppColors.primary;

    if (st == 'maintenance' || st == 'damaged') {
      label = 'DAMAGED';
      bg = isDark ? const Color(0xFF3B2314) : const Color(0xFFFEF3C7);
      textCol = Colors.amber.shade800;
    } else if (st == 'in_maintenance') {
      label = 'IN MAINTENANCE';
      bg = isDark ? const Color(0xFF133238) : const Color(0xFFE0F2FE);
      textCol = Colors.lightBlue.shade800;
    } else if (st == 'lost') {
      label = 'LOST';
      bg = isDark ? const Color(0xFF3B1515) : const Color(0xFFFEE2E2);
      textCol = AppColors.errorRed;
    } else if (st == 'needed_restock') {
      label = 'NEEDED RESTOCK';
      bg = isDark ? const Color(0xFF31123F) : const Color(0xFFF3E8FF);
      textCol = Colors.purple.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textCol),
      ),
    );
  }

  Widget _buildStatusDropdown({
    required String currentStatus,
    required bool isDark,
    required ValueChanged<String?> onChanged,
  }) {
    final st = currentStatus.toLowerCase();
    final bool isDamagedFlow = st == 'maintenance' || st == 'damaged' || st == 'in_maintenance';

    final List<DropdownMenuItem<String>> items = isDamagedFlow
        ? const [
            DropdownMenuItem(value: 'maintenance', child: Text('Damaged', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'in_maintenance', child: Text('In Maintenance', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'available', child: Text('Available (Restocked)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          ]
        : const [
            DropdownMenuItem(value: 'lost', child: Text('Lost', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'needed_restock', child: Text('Needed Restock', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'available', child: Text('Available (Restocked)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          ];

    String valueToUse = st;
    if (st == 'damaged') valueToUse = 'maintenance';
    if (!items.any((i) => i.value == valueToUse)) {
      valueToUse = items.first.value!;
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceLow : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valueToUse,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: isDark ? AppColors.primaryLight : AppColors.primary, size: 18),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isDark) {
    final isSelected = _selectedFilter == label;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
      onSelected: (_) {
        setState(() {
          _selectedFilter = label;
        });
      },
    );
  }
}
