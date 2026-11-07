import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/admin_repository.dart';
import 'admin_store_detail_screen.dart';

class AdminStoresListScreen extends StatefulWidget {
  const AdminStoresListScreen({super.key});

  @override
  State<AdminStoresListScreen> createState() => _AdminStoresListScreenState();
}

class _AdminStoresListScreenState extends State<AdminStoresListScreen> {
  final AdminRepository _repo = AdminRepository();
  List<StoreModel> _stores = [];
  bool _isLoading = true;
  String _selectedFilter = 'All'; // 'All', 'Free', 'Pro', 'Suspended'

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _isLoading = true);
    final res = await _repo.getAllStores();
    if (mounted) {
      setState(() {
        _stores = res;
        _isLoading = false;
      });
    }
  }

  List<StoreModel> get _filteredList {
    if (_selectedFilter == 'Free') {
      return _stores.where((s) => !s.planTier.contains('pro')).toList();
    } else if (_selectedFilter == 'Pro') {
      return _stores.where((s) => s.planTier.contains('pro')).toList();
    } else if (_selectedFilter == 'Suspended') {
      return _stores.where((s) => s.isSuspended).toList();
    }
    return _stores;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Stores & Accounts Management'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStores,
              child: Column(
                children: [
                  // Filter Chips
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: isDark ? AppColors.darkCard : Colors.white,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Free', 'Pro', 'Suspended'].map((f) {
                          final isSel = _selectedFilter == f;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                f,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppColors.primary,
                              backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                              onSelected: (_) => setState(() => _selectedFilter = f),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  Expanded(
                    child: _filteredList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.storefront_outlined, size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                const SizedBox(height: 12),
                                const Text('No Stores Found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredList.length,
                            separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                            itemBuilder: (ctx, idx) {
                              final store = _filteredList[idx];
                              final isPro = store.planTier.contains('pro');

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkCard : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: store.isSuspended
                                        ? AppColors.errorRed
                                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                    width: store.isSuspended ? 1.5 : 1.0,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AdminStoreDetailScreen(storeId: store.id),
                                      ),
                                    );
                                    _loadStores();
                                  },
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
                                                  store.businessName,
                                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Owner: ${store.ownerName ?? "Client"} (${store.email ?? store.phone ?? "No Email"})',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isPro ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isPro ? Icons.workspace_premium : Icons.person_outline,
                                                      size: 13,
                                                      color: isPro ? const Color(0xFF92400E) : Colors.black54,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      isPro ? 'PRO' : 'FREE',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: isPro ? const Color(0xFF92400E) : Colors.black87,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(Icons.chevron_right, color: AppColors.secondary),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Location: ${store.country ?? "India"}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                            ),
                                          ),
                                          if (store.isSuspended)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEE2E2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'SUSPENDED',
                                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
