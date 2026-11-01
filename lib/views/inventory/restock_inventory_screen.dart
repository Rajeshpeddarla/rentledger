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

class RestockItemDisplayModel {
  final String id; // unit id or component unit id
  final String parentItemId;
  final String parentItemName;
  final String name;
  final String? serialNumber;
  final String assetCode;
  final double cost;
  final String status; // 'maintenance' or 'lost'
  final bool isComponent; // true if component unit, false if main unit

  RestockItemDisplayModel({
    required this.id,
    required this.parentItemId,
    required this.parentItemName,
    required this.name,
    this.serialNumber,
    required this.assetCode,
    required this.cost,
    required this.status,
    required this.isComponent,
  });
}

class RestockInventoryScreen extends StatefulWidget {
  const RestockInventoryScreen({super.key});

  @override
  State<RestockInventoryScreen> createState() => _RestockInventoryScreenState();
}

class _RestockInventoryScreenState extends State<RestockInventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseClient _client = Supabase.instance.client;

  List<RestockItemDisplayModel> _damagedItems = [];
  List<RestockItemDisplayModel> _lostItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDamagedAndLostAssets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDamagedAndLostAssets() async {
    setState(() => _isLoading = true);

    final user = _client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final List<RestockItemDisplayModel> damaged = [];
      final List<RestockItemDisplayModel> lost = [];

      // 1. Fetch Damaged / Lost Physical Units from inventory_units
      final unitRes = await _client
          .from('inventory_units')
          .select('*, inventory_items(name)')
          .eq('store_id', user.id)
          .inFilter('status', ['maintenance', 'lost']);

      for (final json in unitRes as List) {
        final u = InventoryUnitModel.fromJson(json as Map<String, dynamic>);
        final pName = json['inventory_items'] != null ? json['inventory_items']['name'] as String : 'Equipment Item';
        final model = RestockItemDisplayModel(
          id: u.id,
          parentItemId: u.inventoryItemId,
          parentItemName: pName,
          name: 'Physical Set #${u.unitNumber} (${u.assetCode})',
          assetCode: u.assetCode,
          cost: 0.0,
          status: u.status,
          isComponent: false,
        );

        if (u.status == 'maintenance') {
          damaged.add(model);
        } else if (u.status == 'lost') {
          lost.add(model);
        }
      }

      // 2. Fetch Damaged / Lost Components from inventory_component_units
      final compRes = await _client
          .from('inventory_component_units')
          .select('*, inventory_items(name)')
          .eq('store_id', user.id)
          .inFilter('status', ['maintenance', 'lost']);

      for (final json in compRes as List) {
        final c = InventoryComponentUnitModel.fromJson(json as Map<String, dynamic>);
        final pName = json['inventory_items'] != null ? json['inventory_items']['name'] as String : 'Equipment Item';
        final model = RestockItemDisplayModel(
          id: c.id,
          parentItemId: c.inventoryItemId,
          parentItemName: pName,
          name: c.componentName,
          serialNumber: c.serialNumber,
          assetCode: c.assetCode,
          cost: c.replacementCost,
          status: c.status,
          isComponent: true,
        );

        if (c.status == 'maintenance') {
          damaged.add(model);
        } else if (c.status == 'lost') {
          lost.add(model);
        }
      }

      if (mounted) {
        setState(() {
          _damagedItems = damaged;
          _lostItems = lost;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading damaged & lost assets: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRestockAction(RestockItemDisplayModel asset, String actionType, double costIncurred, String? newSerial, String? notes) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final storeState = context.read<StoreCubit>().state;
      final storeId = storeState is StoreLoaded ? storeState.store.id : user.id;

      // 1. Update status to 'available' in database
      if (asset.isComponent) {
        final updatePayload = <String, dynamic>{
          'status': 'available',
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (newSerial != null && newSerial.trim().isNotEmpty) {
          updatePayload['serial_number'] = newSerial.trim();
        }
        await _client.from('inventory_component_units').update(updatePayload).eq('id', asset.id);
      } else {
        await _client.from('inventory_units').update({
          'status': 'available',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', asset.id);
      }

      // 2. Log History Audit Trail Entry
      final historyRepo = InventoryItemHistoryRepository();
      await historyRepo.logHistory(InventoryItemHistoryModel(
        id: UuidGenerator.generateV4(),
        storeId: storeId,
        inventoryItemId: asset.parentItemId,
        inventoryUnitId: asset.isComponent ? null : asset.id,
        inventoryComponentUnitId: asset.isComponent ? asset.id : null,
        eventType: actionType, // 'repaired' or 'replaced'
        previousStatus: asset.status,
        newStatus: 'available',
        notes: notes != null && notes.trim().isNotEmpty ? notes.trim() : '$actionType ${asset.name} and restored to available stock.',
        costIncurred: costIncurred,
        createdAt: DateTime.now(),
      ));

      // 3. Reload inventory cubit so stock levels refresh
      if (mounted) {
        await context.read<InventoryCubit>().loadInventory();
        await _loadDamagedAndLostAssets();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully ${actionType == "repaired" ? "repaired" : "replaced"} "${asset.name}" & restored to available stock!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing restock: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRestockModal(BuildContext context, RestockItemDisplayModel asset, String currency) {
    final isRepaired = asset.status == 'maintenance';
    final actionTitle = isRepaired ? 'Mark Repaired & Restock' : 'Mark Replaced & Restock';
    final actionType = isRepaired ? 'repaired' : 'replaced';

    final costCtrl = TextEditingController(text: asset.cost > 0 ? asset.cost.toStringAsFixed(0) : '0');
    final serialCtrl = TextEditingController(text: asset.serialNumber ?? '');
    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isRepaired ? Icons.build_outlined : Icons.find_replace_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      actionTitle,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.lightOnSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${asset.parentItemName} • ${asset.name}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppColors.primaryLight : AppColors.primary),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isRepaired ? 'Actual Repair Cost ($currency)' : 'Replacement Cost ($currency)',
                  prefixText: '$currency ',
                  helperText: 'Recorded in store audit history log',
                ),
              ),
              const SizedBox(height: 12),

              if (!isRepaired && asset.isComponent) ...[
                TextFormField(
                  controller: serialCtrl,
                  decoration: const InputDecoration(
                    labelText: 'New Serial Number (Optional)',
                    hintText: 'e.g. SN-90124',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Repair / Restock Notes (Optional)',
                  hintText: 'Replaced damaged cable, tested working OK...',
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                        Navigator.pop(ctx);
                        _handleRestockAction(asset, actionType, cost, serialCtrl.text, notesCtrl.text);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirm Restock'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Refill & Restock Assets'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: isDark ? AppColors.primaryLight : AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
          tabs: [
            Tab(text: 'In Repair / Damaged (${_damagedItems.length})'),
            Tab(text: 'Lost & Missing (${_lostItems.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAssetListSection(_damagedItems, 'damaged', currency, isDark),
                _buildAssetListSection(_lostItems, 'lost', currency, isDark),
              ],
            ),
    );
  }

  Widget _buildAssetListSection(List<RestockItemDisplayModel> items, String type, String currency, bool isDark) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified, size: 48, color: AppColors.primaryLight),
              const SizedBox(height: 12),
              Text(
                type == 'damaged' ? 'No Damaged Assets in Maintenance!' : 'No Missing / Lost Assets!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.slateNavy),
              ),
              const SizedBox(height: 4),
              Text(
                type == 'damaged'
                    ? 'All equipment sets and components are 100% in good working condition.'
                    : 'No equipment items or accessories are currently recorded as lost.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final isDamaged = type == 'damaged';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDamaged
                          ? (isDark ? const Color(0xFF3B2E15) : const Color(0xFFFFFBEB))
                          : (isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDamaged ? Icons.build_outlined : Icons.find_replace_outlined,
                      color: isDamaged ? AppColors.tertiaryAmber : AppColors.errorRed,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.parentItemName,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '• ${item.name}${item.serialNumber != null && item.serialNumber!.isNotEmpty ? " (SN: ${item.serialNumber})" : ""}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDamaged ? AppColors.tertiaryAmber.withValues(alpha: 0.15) : AppColors.errorRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isDamaged ? 'UNDER MAINTENANCE' : 'LOST / MISSING',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDamaged ? AppColors.tertiaryAmber : AppColors.errorRed),
                    ),
                  ),
                  if (item.cost > 0)
                    Text(
                      'Est. Cost: $currency${item.cost.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showRestockModal(context, item, currency),
                  icon: Icon(isDamaged ? Icons.build_circle_outlined : Icons.check_circle_outline, size: 16),
                  label: Text(
                    isDamaged ? 'Mark Repaired & Restock' : 'Mark Replaced & Restock',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
