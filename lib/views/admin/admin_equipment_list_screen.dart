import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';
import '../../data/repositories/admin_repository.dart';

class AdminEquipmentListScreen extends StatefulWidget {
  const AdminEquipmentListScreen({super.key});

  @override
  State<AdminEquipmentListScreen> createState() => _AdminEquipmentListScreenState();
}

class _AdminEquipmentListScreenState extends State<AdminEquipmentListScreen> {
  final AdminRepository _repo = AdminRepository();
  List<AdminEquipmentOverview> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    setState(() => _isLoading = true);
    final res = await _repo.getAdminEquipment();
    if (mounted) {
      setState(() {
        _items = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('System Equipment Fleet'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEquipment,
              child: _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          const SizedBox(height: 12),
                          const Text('No Equipment Items Found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) {
                        final overview = _items[idx];
                        final item = overview.item;

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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'Store: ${overview.storeName} • Category: ${item.category}',
                                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${overview.totalUnits} Units',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Live Status Breakdown Chips
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      'Available: ${overview.availableUnits}',
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      'Rented: ${overview.rentedUnits}',
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                    ),
                                  ),
                                  if (overview.maintenanceUnits > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        'Maintenance: ${overview.maintenanceUnits}',
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
