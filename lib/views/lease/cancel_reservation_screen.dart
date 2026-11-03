import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/lease_model.dart';
import '../../data/repositories/lease_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/lease/lease_cubit.dart';

class CancelReservationScreen extends StatefulWidget {
  final LeaseModel lease;

  const CancelReservationScreen({
    super.key,
    required this.lease,
  });

  @override
  State<CancelReservationScreen> createState() => _CancelReservationScreenState();
}

class _CancelReservationScreenState extends State<CancelReservationScreen> {
  late double _advanceCollected;
  late TextEditingController _refundAmountController;
  final TextEditingController _reasonController = TextEditingController();

  String _selectedRefundChip = 'full'; // 'full', 'partial', 'none'
  bool _isCanceling = false;

  @override
  void initState() {
    super.initState();
    _advanceCollected = widget.lease.advanceRentPaid > 0
        ? widget.lease.advanceRentPaid
        : widget.lease.depositPaid;

    if (_advanceCollected <= 0) {
      _selectedRefundChip = 'none';
      _refundAmountController = TextEditingController(text: '0');
    } else {
      _refundAmountController = TextEditingController(text: _advanceCollected.toStringAsFixed(0));
    }
  }

  @override
  void dispose() {
    _refundAmountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _onChipSelected(String type) {
    setState(() {
      _selectedRefundChip = type;
      if (type == 'full') {
        _refundAmountController.text = _advanceCollected.toStringAsFixed(0);
      } else if (type == 'none') {
        _refundAmountController.text = '0';
      } else if (type == 'partial') {
        final current = double.tryParse(_refundAmountController.text) ?? 0.0;
        if (current >= _advanceCollected || current <= 0) {
          _refundAmountController.text = (_advanceCollected / 2).toStringAsFixed(0);
        }
      }
    });
  }

  void _onRefundAmountChanged(String val) {
    final entered = double.tryParse(val.trim()) ?? 0.0;
    setState(() {
      if (entered >= _advanceCollected && _advanceCollected > 0) {
        _selectedRefundChip = 'full';
      } else if (entered <= 0) {
        _selectedRefundChip = 'none';
      } else {
        _selectedRefundChip = 'partial';
      }
    });
  }

  Future<void> _handleConfirmCancel() async {
    setState(() => _isCanceling = true);

    try {
      final refundAmt = double.tryParse(_refundAmountController.text.trim()) ?? 0.0;
      final reasonStr = _reasonController.text.trim();

      String refundNote = '';
      if (_advanceCollected > 0) {
        if (_selectedRefundChip == 'full') {
          refundNote = 'Full Advance Refunded: ${_advanceCollected.toStringAsFixed(0)}';
        } else if (_selectedRefundChip == 'none') {
          refundNote = 'Advance Forfeited/Retained: ${_advanceCollected.toStringAsFixed(0)}';
        } else {
          final retained = _advanceCollected - refundAmt;
          refundNote = 'Partial Refund: ${refundAmt.toStringAsFixed(0)}, Retained Fee: ${retained > 0 ? retained.toStringAsFixed(0) : "0"}';
        }
      }

      final String fullNotes = 'CANCELED RESERVATION. ${refundNote.isNotEmpty ? "$refundNote. " : ""}${reasonStr.isNotEmpty ? "Reason: $reasonStr" : ""}';

      final repo = LeaseRepository();
      await repo.cancelLease(
        leaseId: widget.lease.id,
        cancellationNotes: fullNotes,
        refundAmount: refundAmt,
      );

      if (!mounted) return;
      await context.read<LeaseCubit>().loadLeases();
      await context.read<InventoryCubit>().loadInventory();

      if (!mounted) return;
      Navigator.of(context).pop(true); // Return success to previous screen

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reservation for ${widget.lease.customer?.name ?? "Customer"} canceled successfully!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error canceling reservation: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCanceling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Cancel Reservation & Refund'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Reserved Equipment Units Card
            Container(
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
                      Row(
                        children: [
                          Icon(Icons.event_seat_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          const SizedBox(width: 6),
                          const Text('Reserved Equipment Order', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'RESERVED',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.lease.itemNamesSummary,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Client: ${widget.lease.customer?.name ?? "Customer"} • ${widget.lease.customer?.phone ?? "-"}',
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick-up Date: ${DateFormat("dd MMM yyyy, hh:mm a").format(widget.lease.startTime)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Advance Collected Display Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _advanceCollected > 0
                    ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                    : (isDark ? AppColors.darkCard : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _advanceCollected > 0
                      ? (isDark ? AppColors.primary : const Color(0xFFA7F3D0))
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Advance / Deposit Collected:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$currency${_advanceCollected.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _advanceCollected > 0
                        ? 'Advance rent or security deposit collected when booking this reservation.'
                        : 'No advance money was collected for this reservation.',
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                ],
              ),
            ),

            if (_advanceCollected > 0) ...[
              const SizedBox(height: 14),

              // 3. Refund Options & Dynamic Amount Input
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Advance Refund Settlement:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // Choice Chips: Full, Partial, No Refund
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Full Refund', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          selected: _selectedRefundChip == 'full',
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(color: _selectedRefundChip == 'full' ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                          backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          onSelected: (_) => _onChipSelected('full'),
                        ),
                        ChoiceChip(
                          label: const Text('Partial Refund', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          selected: _selectedRefundChip == 'partial',
                          selectedColor: Colors.amber.shade800,
                          labelStyle: TextStyle(color: _selectedRefundChip == 'partial' ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                          backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          onSelected: (_) => _onChipSelected('partial'),
                        ),
                        ChoiceChip(
                          label: const Text('No Refund (Forfeit)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          selected: _selectedRefundChip == 'none',
                          selectedColor: AppColors.errorRed,
                          labelStyle: TextStyle(color: _selectedRefundChip == 'none' ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                          backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          onSelected: (_) => _onChipSelected('none'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _refundAmountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Refund Amount to Customer ($currency)',
                        prefixText: '$currency ',
                        helperText: 'Amount returned to customer upon cancellation',
                      ),
                      onChanged: _onRefundAmountChanged,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // 4. Cancellation Reason Notes
            TextFormField(
              controller: _reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Cancellation Reason / Notes (Optional)',
                hintText: 'Customer travel delayed, requested cancellation...',
              ),
            ),

            const SizedBox(height: 24),

            // 5. Confirm Cancellation Action Button
            ElevatedButton.icon(
              onPressed: _isCanceling ? null : _handleConfirmCancel,
              icon: const Icon(Icons.cancel_outlined, size: 20),
              label: Text(_isCanceling ? 'Canceling Reservation...' : 'Confirm Reservation Cancellation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
