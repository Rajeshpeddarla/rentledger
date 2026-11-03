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

class RestockDisplayItem {
  final String id; // unit id or component unit id
  final String parentItemId;
  final String parentItemName;
  final String assetCode;
  final String title; // "Physical Set #1 (CAM-0001)" or "18V Battery"
  final String? serialNumber;
  final double replacementCost;
  final String currentStatus; // 'maintenance' (damaged) or 'lost'
  final bool isWholeUnit; // true if whole unit is damaged/lost, false if individual component
  final String? parentUnitId; // unit id if this is a component

  RestockDisplayItem({
    required this.id,
    required this.parentItemId,
    required this.parentItemName,
    required this.assetCode,
    required this.title,
    this.serialNumber,
    required this.replacementCost,
    required this.currentStatus,
    required this.isWholeUnit,
    this.parentUnitId,
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
  List<RestockDisplayItem> _restockItems = [];
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
      final List<RestockDisplayItem> items = [];
      final Set<String> wholeUnitIds = {};

      // 1. Fetch Whole Physical Units marked as Damaged (maintenance) or Lost
      final unitRes = await _client
          .from('inventory_units')
          .select('*, inventory_items(name)')
          .eq('store_id', user.id)
          .inFilter('status', ['maintenance', 'lost', 'damaged']);

      for (final json in unitRes as List) {
        final u = InventoryUnitModel.fromJson(json as Map<String, dynamic>);
        final pName = json['inventory_items'] != null ? json['inventory_items']['name'] as String : 'Equipment Item';
        wholeUnitIds.add(u.id);

        items.add(RestockDisplayItem(
          id: u.id,
          parentItemId: u.inventoryItemId,
          parentItemName: pName,
          title: 'Physical Set #${u.unitNumber} (${u.assetCode})',
          assetCode: u.assetCode,
          replacementCost: 0.0,
          currentStatus: u.status.toLowerCase() == 'damaged' ? 'maintenance' : u.status.toLowerCase(),
          isWholeUnit: true,
        ));
      }

      // 2. Fetch Specific Component Units marked as Damaged or Lost
      final compRes = await _client
          .from('inventory_component_units')
          .select('*, inventory_items(name)')
          .eq('store_id', user.id)
          .inFilter('status', ['maintenance', 'lost', 'damaged']);

      for (final json in compRes as List) {
        final c = InventoryComponentUnitModel.fromJson(json as Map<String, dynamic>);
        final pName = json['inventory_items'] != null ? json['inventory_items']['name'] as String : 'Equipment Item';

        // Only add component separately if its parent unit is NOT ALREADY listed as a whole unit
        if (!wholeUnitIds.contains(c.inventoryUnitId)) {
          items.add(RestockDisplayItem(
            id: c.id,
            parentItemId: c.inventoryItemId,
            parentItemName: pName,
            title: c.componentName,
            serialNumber: c.serialNumber,
            assetCode: c.assetCode,
            replacementCost: c.replacementCost,
            currentStatus: c.status.toLowerCase() == 'damaged' ? 'maintenance' : c.status.toLowerCase(),
            isWholeUnit: false,
            parentUnitId: c.inventoryUnitId,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _restockItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading restock assets: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAssetStatus(RestockDisplayItem item, String newStatus) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final storeState = context.read<StoreCubit>().state;
    final storeId = storeState is StoreLoaded ? storeState.store.id : user.id;

    final targetDbStatus = (newStatus == 'damaged' || newStatus == 'maintenance') ? 'maintenance' : newStatus;

    try {
      if (item.isWholeUnit) {
        // 1. Update Whole Unit status
        await _client
            .from('inventory_units')
            .update({
              'status': targetDbStatus,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', item.id);

        // Update all component units under this physical set unit
        await _client
            .from('inventory_component_units')
            .update({
              'status': targetDbStatus,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('inventory_unit_id', item.id);
      } else {
        // 2. Update Specific Component status
        await _client
            .from('inventory_component_units')
            .update({
              'status': targetDbStatus,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', item.id);

        // If component parent unit exists, re-evaluate parent unit status
        if (item.parentUnitId != null && item.parentUnitId!.isNotEmpty) {
          final allCompsRes = await _client
              .from('inventory_component_units')
              .select('status')
              .eq('inventory_unit_id', item.parentUnitId!);

          final List<String> compStatuses = (allCompsRes as List)
              .map((c) => (c['status'] as String? ?? 'available').toLowerCase())
              .toList();

          String parentUnitTargetStatus = 'available';
          if (compStatuses.any((s) => s == 'maintenance' || s == 'damaged')) {
            parentUnitTargetStatus = 'maintenance';
          } else if (compStatuses.any((s) => s == 'lost')) {
            parentUnitTargetStatus = 'lost';
          }

          await _client
              .from('inventory_units')
              .update({
                'status': parentUnitTargetStatus,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', item.parentUnitId!);
        }
      }

      // 3. Log Audit Trail Entry
      final historyRepo = InventoryItemHistoryRepository();
      await historyRepo.logHistory(InventoryItemHistoryModel(
        id: UuidGenerator.generateV4(),
        storeId: storeId,
        inventoryItemId: item.parentItemId,
        inventoryUnitId: item.isWholeUnit ? item.id : item.parentUnitId,
        inventoryComponentUnitId: item.isWholeUnit ? null : item.id,
        eventType: targetDbStatus == 'available' ? 'restocked' : targetDbStatus,
        previousStatus: item.currentStatus,
        newStatus: targetDbStatus,
        notes: 'Status updated to ${targetDbStatus == "maintenance" ? "Damaged" : targetDbStatus.toUpperCase()} for ${item.title}',
        createdAt: DateTime.now(),
      ));

      // 4. Reload InventoryCubit and refresh restock screen
      if (mounted) {
        await context.read<InventoryCubit>().loadInventory();
        await _loadRestockAssets();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated "${item.title}" status to ${targetDbStatus == "maintenance" ? "Damaged" : targetDbStatus.toUpperCase()}!'),
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

  List<RestockDisplayItem> get _filteredItems {
    if (_selectedFilter == 'All') return _restockItems;
    final filter = _selectedFilter.toLowerCase();

    return _restockItems.where((item) {
      final st = item.currentStatus.toLowerCase();
      if (filter == 'damaged') {
        return st == 'maintenance' || st == 'damaged';
      }
      if (filter == 'lost') {
        return st == 'lost';
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';
    final displayList = _filteredItems;

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
                : displayList.isEmpty
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
                        itemCount: displayList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          final isDamaged = item.currentStatus == 'maintenance' || item.currentStatus == 'damaged';

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
                                // Item Header
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.parentItemName,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item.title,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                          if (item.serialNumber != null && item.serialNumber!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Serial No: ${item.serialNumber}',
                                              style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                            ),
                                          ],
                                          if (item.replacementCost > 0) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Replacement / Repair Fee: $currency${item.replacementCost.toStringAsFixed(0)}',
                                              style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDamaged
                                            ? (isDark ? const Color(0xFF3B2314) : const Color(0xFFFEF3C7))
                                            : (isDark ? const Color(0xFF3B1515) : const Color(0xFFFEE2E2)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isDamaged ? 'DAMAGED' : 'LOST',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isDamaged ? Colors.amber.shade800 : AppColors.errorRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),
                                Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder, height: 1),
                                const SizedBox(height: 10),

                                // Status Action Toggle Buttons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Change Status:',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildStatusChip(
                                          label: 'Available',
                                          targetStatus: 'available',
                                          currentStatus: item.currentStatus,
                                          activeColor: AppColors.primary,
                                          isDark: isDark,
                                          onTap: () => _updateAssetStatus(item, 'available'),
                                        ),
                                        const SizedBox(width: 6),
                                        _buildStatusChip(
                                          label: 'Damaged',
                                          targetStatus: 'maintenance',
                                          currentStatus: item.currentStatus,
                                          activeColor: AppColors.tertiaryAmber,
                                          isDark: isDark,
                                          onTap: () => _updateAssetStatus(item, 'maintenance'),
                                        ),
                                        const SizedBox(width: 6),
                                        _buildStatusChip(
                                          label: 'Lost',
                                          targetStatus: 'lost',
                                          currentStatus: item.currentStatus,
                                          activeColor: AppColors.errorRed,
                                          isDark: isDark,
                                          onTap: () => _updateAssetStatus(item, 'lost'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
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

  Widget _buildStatusChip({
    required String label,
    required String targetStatus,
    required String currentStatus,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final isSelected = currentStatus == targetStatus || (targetStatus == 'maintenance' && currentStatus == 'damaged');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : (isDark ? AppColors.darkSurfaceLow : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor : (isDark ? AppColors.darkBorder : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }
}
