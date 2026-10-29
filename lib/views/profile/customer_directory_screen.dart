import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_theme.dart';
import '../../core/utils/uuid_generator.dart';
import '../../core/utils/whatsapp_launcher.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/lease_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/customer/customer_cubit.dart';
import '../../viewmodels/customer/customer_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../widgets/shimmer_loading.dart';

class CustomerDirectoryScreen extends StatefulWidget {
  const CustomerDirectoryScreen({super.key});

  @override
  State<CustomerDirectoryScreen> createState() => _CustomerDirectoryScreenState();
}

class _CustomerDirectoryScreenState extends State<CustomerDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<CustomerCubit>().loadCustomers();
    context.read<LeaseCubit>().loadLeases();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openAddOrEditCustomerModal([CustomerModel? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'Add Customer' : 'Edit Customer Details',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Customer Name', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email (Optional)', prefixIcon: Icon(Icons.email_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Notes (e.g. KYC, verification)', prefixIcon: Icon(Icons.notes_outlined)),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final phone = phoneCtrl.text.trim();

                                if (name.isEmpty) {
                                  _showErrorSnackBar('Please enter customer name');
                                  return;
                                }
                                if (phone.isEmpty) {
                                  _showErrorSnackBar('Please enter phone number');
                                  return;
                                }

                                setModalState(() => isSaving = true);

                                try {
                                  final customerCubit = context.read<CustomerCubit>();
                                  final storeState = context.read<StoreCubit>().state;
                                  final storeId = storeState is StoreLoaded ? storeState.store.id : 'demo_store_1';

                                  final customer = CustomerModel(
                                    id: existing?.id ?? UuidGenerator.generateV4(),
                                    storeId: storeId,
                                    name: name,
                                    phone: phone,
                                    email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                                    notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                                    totalLeasesCount: existing?.totalLeasesCount ?? 0,
                                    createdAt: existing?.createdAt ?? DateTime.now(),
                                    updatedAt: DateTime.now(),
                                  );

                                  await customerCubit.saveCustomer(customer);
                                  if (!modalCtx.mounted) return;
                                  Navigator.pop(modalCtx);
                                  _showSuccessSnackBar(
                                    existing == null
                                        ? 'Customer "$name" added successfully!'
                                        : 'Customer "$name" updated successfully!',
                                  );
                                } catch (e) {
                                  _showErrorSnackBar('Failed to save customer: $e');
                                } finally {
                                  setModalState(() => isSaving = false);
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                              )
                            : Text(existing == null ? 'Save Customer' : 'Update Customer'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteCustomer(CustomerModel customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Customer', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${customer.name}" from your customer directory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        final customerCubit = context.read<CustomerCubit>();
        await customerCubit.deleteCustomer(customer.id);
        _showSuccessSnackBar('Customer "${customer.name}" deleted successfully!');
      } catch (e) {
        _showErrorSnackBar('Failed to delete customer: $e');
      }
    }
  }

  Future<void> _handleReceiptAction(BuildContext context, LeaseModel lease) async {
    final storeState = context.read<StoreCubit>().state;
    if (storeState is! StoreLoaded) return;
    final store = storeState.store;
    final isReturned = lease.status == 'returned';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isReturned ? 'Return Settlement Receipt' : 'Lease Agreement / Handover Receipt',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${lease.item?.name ?? "Equipment"} • ${lease.customer?.name ?? "Customer"}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final file = await PdfReceiptService.instance.generateReceiptForLease(store: store, lease: lease);
                  await PdfReceiptService.instance.printReceipt(file);
                },
                icon: const Icon(Icons.print, size: 18, color: Colors.white),
                label: const Text('Print / Save PDF Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final file = await PdfReceiptService.instance.generateReceiptForLease(store: store, lease: lease);
                  final msg = isReturned
                      ? 'Return settlement receipt for ${lease.item?.name} from ${store.businessName}'
                      : 'Rental lease receipt for ${lease.item?.name} from ${store.businessName}';
                  await PdfReceiptService.instance.shareReceipt(file, msg);
                },
                icon: Icon(Icons.share, size: 18, color: isDark ? Colors.white : AppColors.primary),
                label: Text(
                  'Share Receipt via WhatsApp / App',
                  style: TextStyle(color: isDark ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomerLeaseHistoryBottomSheet(BuildContext context, CustomerModel customer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leaseState = context.read<LeaseCubit>().state;
    final leases = leaseState is LeaseLoaded
        ? leaseState.allLeases.where((l) => l.customerId == customer.id).toList()
        : <LeaseModel>[];
    final storeState = context.read<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: const Icon(Icons.person, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${customer.name}\'s Rental History',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Phone: ${customer.phone} • Total Leases: ${leases.length}',
                          style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Expanded(
                child: leases.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            const SizedBox(height: 8),
                            Text('No past lending records found for ${customer.name}.'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: leases.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (lCtx, index) {
                          final lease = leases[index];
                          final String itemName = '${lease.quantity > 1 ? '${lease.quantity}x ' : ''}${lease.item?.name ?? "Equipment Item"}';
                          final startDateStr = '${lease.startTime.day}/${lease.startTime.month}/${lease.startTime.year}';
                          final endDateStr = '${lease.expectedEndTime.day}/${lease.expectedEndTime.month}/${lease.expectedEndTime.year}';

                          Color statusColor;
                          if (lease.status == 'returned') {
                            statusColor = Colors.green;
                          } else if (lease.isOverdue) {
                            statusColor = Colors.red;
                          } else if (lease.status == 'active') {
                            statusColor = AppColors.primary;
                          } else {
                            statusColor = Colors.orange;
                          }

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      itemName,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        lease.status.toUpperCase(),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Rental Window: $startDateStr - $endDateStr',
                                  style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Deposit Paid: $currency${lease.depositPaid.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Rent Total: $currency${lease.netRentTotal.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _handleReceiptAction(context, lease),
                                    icon: const Icon(Icons.receipt_long, size: 14),
                                    label: Text(
                                      lease.status == 'returned' ? 'Settlement Receipt' : 'Lease Receipt',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                      side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                    ),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final storeName = storeState is StoreLoaded ? storeState.store.businessName : 'our store';
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Customers Directory'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined, color: AppColors.primary),
            onPressed: () => _openAddOrEditCustomerModal(),
            tooltip: 'Add Customer',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                context.read<CustomerCubit>().setSearchQuery(val);
              },
              decoration: InputDecoration(
                hintText: 'Search customer by name or phone...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          context.read<CustomerCubit>().setSearchQuery('');
                        },
                      )
                    : null,
              ),
            ),
          ),

          Expanded(
            child: BlocBuilder<CustomerCubit, CustomerState>(
              builder: (context, state) {
                if (state is CustomerLoading || state is CustomerInitial) {
                  return const ShimmerListPlaceholder(itemCount: 6, itemHeight: 90);
                }

                if (state is CustomerError) {
                  return Center(child: Text('Error loading customers: ${state.message}'));
                }

                final customers = state is CustomerLoaded ? state.filteredCustomers : <CustomerModel>[];

                if (customers.isEmpty) {
                  return Center(
                    child: Text(
                      'No customers found in directory.',
                      style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: customers.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = customers[index];

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
                          // Top Row: Avatar + Details + Edit/Delete Buttons
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                                child: const Icon(Icons.person, color: AppColors.primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (c.isRepeatCustomer) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryFixed,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'REPEAT',
                                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppColors.onPrimaryFixed),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.phone,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                      ),
                                    ),
                                    if (c.email != null && c.email!.isNotEmpty)
                                      Text(
                                        c.email!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                        ),
                                      ),
                                    if (c.notes != null && c.notes!.isNotEmpty)
                                      Text(
                                        c.notes!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('🪙 ', style: TextStyle(fontSize: 10)),
                                          Text(
                                            '${c.loyaltyPoints} Pts ($currency${c.loyaltyMonetaryValue.toStringAsFixed(2)})',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Edit & Delete Buttons
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                    onPressed: () => _openAddOrEditCustomerModal(c),
                                    tooltip: 'Edit Customer',
                                  ),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                    onPressed: () => _confirmDeleteCustomer(c),
                                    tooltip: 'Delete Customer',
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),
                          Divider(
                            height: 1,
                            thickness: 0.8,
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                          const SizedBox(height: 8),

                          // Bottom Row: Call, Message, Lend History (Instant Search)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              // Call Button
                              InkWell(
                                onTap: () => WhatsAppLauncher.callPhone(c.phone),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.phone_outlined, size: 16, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Call',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Message Button (WhatsApp)
                              InkWell(
                                onTap: () => WhatsAppLauncher.sendWhatsAppMessage(
                                  phone: c.phone,
                                  message: 'Hi ${c.name}, welcome to $storeName!',
                                ),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF25D366)),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Message',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF25D366),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Lend History Button
                              InkWell(
                                onTap: () => _showCustomerLeaseHistoryBottomSheet(context, c),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.history, size: 16, color: Colors.amber.shade800),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Lend History',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.amber.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
