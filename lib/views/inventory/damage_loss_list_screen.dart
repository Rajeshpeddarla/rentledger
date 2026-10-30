import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/damage_loss_incident_model.dart';
import '../../data/repositories/damage_loss_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import 'damage_loss_detail_screen.dart';

class DamageLossListScreen extends StatefulWidget {
  const DamageLossListScreen({super.key});

  @override
  State<DamageLossListScreen> createState() => _DamageLossListScreenState();
}

class _DamageLossListScreenState extends State<DamageLossListScreen> {
  List<DamageLossIncidentModel> _incidents = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all', 'damaged', 'lost', 'unpaid', 'in_repair', 'resolved'

  @override
  void initState() {
    super.initState();
    _loadIncidents();
  }

  Future<void> _loadIncidents() async {
    try {
      final list = await DamageLossRepository().getIncidents();
      if (mounted) {
        setState(() {
          _incidents = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    final filtered = _incidents.where((i) {
      if (_selectedFilter == 'damaged') return i.incidentType == 'damaged';
      if (_selectedFilter == 'lost') return i.incidentType == 'lost';
      if (_selectedFilter == 'unpaid') return i.paymentStatus != 'fully_paid';
      if (_selectedFilter == 'in_repair') return i.repairStatus == 'in_repair' || i.repairStatus == 'awaiting_repair';
      if (_selectedFilter == 'resolved') return i.isResolved;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Damage & Loss Management'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: Column(
        children: [
          // Filter Chips Strip
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                _buildFilterChip('All', 'all', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Damaged', 'damaged', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Lost', 'lost', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Unpaid', 'unpaid', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('In Repair', 'in_repair', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Resolved', 'resolved', isDark),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.report_off_outlined, size: 48, color: isDark ? AppColors.darkBorder : Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text('No incident records match the filter.', style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final incident = filtered[index];
                          final isDamaged = incident.incidentType == 'damaged';

                          return InkWell(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DamageLossDetailScreen(incident: incident, currency: currency),
                                ),
                              );
                              _loadIncidents();
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkCard : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDamaged ? Colors.amber.shade700 : AppColors.errorRed,
                                  width: 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isDamaged ? Colors.amber.withValues(alpha: 0.2) : AppColors.errorRed.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              incident.incidentType.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isDamaged ? Colors.amber.shade900 : AppColors.errorRed,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Reported ${DateFormat("dd MMM").format(incident.reportedAt)}',
                                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: incident.paymentStatus == 'fully_paid'
                                              ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                              : (isDark ? const Color(0xFF3B2E15) : const Color(0xFFFFFBEB)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          incident.paymentStatus.replaceAll('_', ' ').toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: incident.paymentStatus == 'fully_paid' ? AppColors.primaryLight : AppColors.tertiaryAmber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  Text(
                                    incident.description ?? 'Equipment Incident',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Charge: $currency${incident.customerCharge.toStringAsFixed(0)} • Paid: $currency${incident.customerAmountPaid.toStringAsFixed(0)}',
                                        style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                      ),
                                      Text(
                                        'Status: ${incident.repairStatus.replaceAll('_', ' ').toUpperCase()}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black))),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      onSelected: (_) => setState(() => _selectedFilter = value),
    );
  }
}
