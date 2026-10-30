import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../core/utils/uuid_generator.dart';
import '../../data/models/damage_loss_incident_model.dart';
import '../../data/models/damage_loss_payment_model.dart';
import '../../data/repositories/damage_loss_repository.dart';

class DamageLossDetailScreen extends StatefulWidget {
  final DamageLossIncidentModel incident;
  final String currency;

  const DamageLossDetailScreen({
    super.key,
    required this.incident,
    required this.currency,
  });

  @override
  State<DamageLossDetailScreen> createState() => _DamageLossDetailScreenState();
}

class _DamageLossDetailScreenState extends State<DamageLossDetailScreen> {
  late DamageLossIncidentModel _incident;
  bool _isUpdating = false;

  final TextEditingController _estCostCtrl = TextEditingController();
  final TextEditingController _actCostCtrl = TextEditingController();
  final TextEditingController _chargeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _incident = widget.incident;
    _estCostCtrl.text = _incident.estimatedRepairCost.toStringAsFixed(0);
    _actCostCtrl.text = _incident.actualRepairCost.toStringAsFixed(0);
    _chargeCtrl.text = _incident.customerCharge.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _estCostCtrl.dispose();
    _actCostCtrl.dispose();
    _chargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _recordPaymentModal() async {
    final payAmountCtrl = TextEditingController(text: _incident.outstandingBalance.toStringAsFixed(0));
    String payMethod = 'cash';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              Text('Record Customer Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 12),
              TextFormField(
                controller: payAmountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount Received (${widget.currency})',
                  prefixText: '${widget.currency} ',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: payMethod,
                decoration: const InputDecoration(labelText: 'Payment Method', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI / Google Pay')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                ],
                onChanged: (val) {
                  if (val != null) payMethod = val;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(payAmountCtrl.text) ?? 0.0;
                    if (amt <= 0) return;

                    final payment = DamageLossPaymentModel(
                      id: UuidGenerator.generateV4(),
                      incidentId: _incident.id,
                      storeId: _incident.storeId,
                      amountPaid: amt,
                      paymentMethod: payMethod,
                      paidAt: DateTime.now(),
                      createdAt: DateTime.now(),
                    );

                    await DamageLossRepository().recordPayment(payment);
                    if (ctx.mounted) Navigator.pop(ctx);

                    // Reload incidents list
                    final updatedList = await DamageLossRepository().getIncidents();
                    final refreshed = updatedList.where((i) => i.id == _incident.id).firstOrNull;
                    if (refreshed != null && mounted) {
                      setState(() {
                        _incident = refreshed;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Confirm Payment Entry', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateRepairStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final est = double.tryParse(_estCostCtrl.text) ?? 0.0;
      final act = double.tryParse(_actCostCtrl.text) ?? 0.0;
      final chg = double.tryParse(_chargeCtrl.text) ?? 0.0;

      await DamageLossRepository().updateRepairStatus(
        incidentId: _incident.id,
        repairStatus: newStatus,
        actualRepairCost: act,
        customerCharge: chg,
      );

      final updatedList = await DamageLossRepository().getIncidents();
      final refreshed = updatedList.where((i) => i.id == _incident.id).firstOrNull;
      if (refreshed != null && mounted) {
        setState(() {
          _incident = refreshed;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Incident Details & Action'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Tile
            Container(
              padding: const EdgeInsets.all(16),
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
                      Text(
                        _incident.incidentType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _incident.incidentType == 'damaged' ? Colors.amber.shade900 : AppColors.errorRed,
                        ),
                      ),
                      Text('Reported ${DateFormat("dd MMM yyyy").format(_incident.reportedAt)}', style: const TextStyle(fontSize: 11, color: AppColors.secondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_incident.description ?? 'Equipment Incident', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Financial Recovery & Charge Configuration
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Financial Recovery & Costs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _estCostCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Est. Repair Cost (${widget.currency})'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _actCostCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Actual Repair Cost (${widget.currency})'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _chargeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Customer Charge (${widget.currency})'),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Paid: ${widget.currency}${_incident.customerAmountPaid.toStringAsFixed(0)} / ${widget.currency}${_incident.customerCharge.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        onPressed: _recordPaymentModal,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Record Payment'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Repair Operational Status Dropdown
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Operational Repair Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _incident.repairStatus,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'reported', child: Text('Reported')),
                      DropdownMenuItem(value: 'awaiting_repair', child: Text('Awaiting Repair')),
                      DropdownMenuItem(value: 'in_repair', child: Text('In Repair')),
                      DropdownMenuItem(value: 'repaired', child: Text('Repaired & Restocked')),
                      DropdownMenuItem(value: 'replaced', child: Text('Replaced')),
                      DropdownMenuItem(value: 'written_off', child: Text('Written Off')),
                      DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        _updateRepairStatus(val);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Payment History Ledger
            if (_incident.payments.isNotEmpty) ...[
              const Text('Partial Payment Ledger', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _incident.payments.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final pay = _incident.payments[index];
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Paid via ${pay.paymentMethod.toUpperCase()} on ${DateFormat("dd MMM yyyy").format(pay.paidAt)}', style: const TextStyle(fontSize: 11)),
                        Text('+${widget.currency}${pay.amountPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
