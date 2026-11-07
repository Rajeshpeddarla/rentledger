import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/repositories/admin_repository.dart';

class AdminLeasesListScreen extends StatefulWidget {
  const AdminLeasesListScreen({super.key});

  @override
  State<AdminLeasesListScreen> createState() => _AdminLeasesListScreenState();
}

class _AdminLeasesListScreenState extends State<AdminLeasesListScreen> {
  final AdminRepository _repo = AdminRepository();
  List<AdminLeaseOverview> _leases = [];
  bool _isLoading = true;
  String _selectedStatusFilter = 'All'; // 'All', 'Reserved', 'Rented', 'Returned', 'Cancelled'

  @override
  void initState() {
    super.initState();
    _loadLeases();
  }

  Future<void> _loadLeases() async {
    setState(() => _isLoading = true);
    final res = await _repo.getAdminLeases();
    if (mounted) {
      setState(() {
        _leases = res;
        _isLoading = false;
      });
    }
  }

  List<AdminLeaseOverview> get _filteredList {
    if (_selectedStatusFilter == 'Reserved') {
      return _leases.where((l) => l.lease.status == 'reserved' || l.lease.status == 'upcoming').toList();
    } else if (_selectedStatusFilter == 'Rented') {
      return _leases.where((l) => l.lease.status == 'active').toList();
    } else if (_selectedStatusFilter == 'Returned') {
      return _leases.where((l) => l.lease.status == 'returned').toList();
    } else if (_selectedStatusFilter == 'Cancelled') {
      return _leases.where((l) => l.lease.status == 'cancelled').toList();
    }
    return _leases;
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'reserved':
      case 'upcoming':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        label = 'RESERVED';
        break;
      case 'active':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        label = 'RENTED';
        break;
      case 'returned':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        label = 'RETURNED';
        break;
      case 'cancelled':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        label = 'CANCELLED';
        break;
      default:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('System Leases Overview'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLeases,
              child: Column(
                children: [
                  // Filter Chips Row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: isDark ? AppColors.darkCard : Colors.white,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Reserved', 'Rented', 'Returned', 'Cancelled'].map((f) {
                          final isSel = _selectedStatusFilter == f;
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
                              onSelected: (_) => setState(() => _selectedStatusFilter = f),
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
                                Icon(Icons.assignment_outlined, size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                const SizedBox(height: 12),
                                const Text('No Leases Found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredList.length,
                            separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                            itemBuilder: (ctx, idx) {
                              final item = _filteredList[idx];
                              final lease = item.lease;

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
                                                lease.customer?.name ?? 'Client',
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                'Store: ${item.storeName}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildStatusBadge(lease.status),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Equipment: ${lease.itemNamesSummary}',
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Start: ${DateFormat("dd MMM, hh:mm a").format(lease.startTime)}',
                                                style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                              ),
                                              Text(
                                                'End: ${DateFormat("dd MMM, hh:mm a").format(lease.expectedEndTime)}',
                                                style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
