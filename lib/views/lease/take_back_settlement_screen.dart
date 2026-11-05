import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/utils/uuid_generator.dart';
import '../../data/models/damage_loss_incident_model.dart';
import '../../data/models/discount_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/lease_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/inventory_item_history_model.dart';
import '../../data/models/leased_sub_item_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/sub_item_model.dart';
import '../../data/repositories/damage_loss_repository.dart';
import '../../data/repositories/inventory_item_history_repository.dart';
import '../../data/repositories/inventory_unit_repository.dart';
import '../../data/repositories/sub_item_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/discount/discount_cubit.dart';
import '../../viewmodels/discount/discount_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';

class ItemSmartBreakdown {
  final String name;
  final int quantity;
  final RentalBreakdown breakdown;
  final double lineTotalRent;

  ItemSmartBreakdown({
    required this.name,
    required this.quantity,
    required this.breakdown,
    required this.lineTotalRent,
  });
}

class TakeBackSettlementScreen extends StatefulWidget {
  final LeaseModel lease;

  const TakeBackSettlementScreen({super.key, required this.lease});

  @override
  State<TakeBackSettlementScreen> createState() => _TakeBackSettlementScreenState();
}

class _TakeBackSettlementScreenState extends State<TakeBackSettlementScreen> {
  late DateTime _actualReturnTime;

  final String _billingMode = 'auto';
  String _returnStatus = 'available';

  // Item, Unit & Sub-items status tracking
  final Map<String, String> _itemStatusMap = {};
  final Map<String, String> _unitStatusMap = {};
  List<SubItemModel> _subItems = [];
  final Map<String, String> _subItemStatusMap = {};
  final Map<String, double> _compUnitCostMap = {};

  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _damageFeeController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();

  DiscountModel? _appliedDiscount;

  RentalBreakdown? _breakdown;
  final List<ItemSmartBreakdown> _itemBreakdowns = [];
  double _calculatedRent = 0.0;
  double _netRent = 0.0;
  double _finalBalance = 0.0;
  bool _isSettling = false;

  bool _isLoadingComponents = true;
  final Map<String, List<SubItemModel>> _itemComponentTemplates = {};

  Future<void> _loadAllItemComponents() async {
    setState(() => _isLoadingComponents = true);

    final unitRepo = InventoryUnitRepository();
    final subRepo = SubItemRepository();

    final List<String> itemIds = [];
    if (widget.lease.leaseItems.isNotEmpty) {
      for (final line in widget.lease.leaseItems) {
        if (line.itemId.isNotEmpty && !itemIds.contains(line.itemId)) {
          itemIds.add(line.itemId);
        }
      }
    } else if (widget.lease.itemId.isNotEmpty) {
      itemIds.add(widget.lease.itemId);
    }

    for (final itemId in itemIds) {
      final List<SubItemModel> compList = [];

      try {
        final subs = await subRepo.getSubItems(parentItemId: itemId);
        compList.addAll(subs);
      } catch (_) {}

      if (compList.isEmpty) {
        try {
          final defs = await unitRepo.getDefinitionsForProduct(itemId);
          for (final d in defs) {
            compList.add(SubItemModel(
              id: d.id,
              parentItemId: itemId,
              storeId: widget.lease.storeId,
              name: d.componentName,
              serialNumber: null,
              status: 'available',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          }
        } catch (_) {}
      }

      if (compList.isEmpty) {
        try {
          final units = await unitRepo.getUnitsForProduct(itemId);
          if (units.isNotEmpty && units.first.components.isNotEmpty) {
            for (final c in units.first.components) {
              compList.add(SubItemModel(
                id: c.id,
                parentItemId: itemId,
                storeId: widget.lease.storeId,
                name: c.componentName,
                serialNumber: c.serialNumber,
                status: 'available',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ));
            }
          }
        } catch (_) {}
      }

      _itemComponentTemplates[itemId] = compList;
    }

    if (mounted) {
      setState(() {
        _isLoadingComponents = false;
        for (final compList in _itemComponentTemplates.values) {
          for (final s in compList) {
            if (!_subItemStatusMap.containsKey(s.id)) {
              _subItemStatusMap[s.id] = 'available';
            }
          }
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _actualReturnTime = DateTime.now();

    // Populate item & sub-item return status maps
    if (widget.lease.leaseItems.isNotEmpty) {
      for (final line in widget.lease.leaseItems) {
        _itemStatusMap[line.id] = line.returnStatus == 'rented' ? 'available' : line.returnStatus;
        for (final sub in line.leasedSubItems) {
          if (!sub.isExcluded) {
            _subItemStatusMap[sub.id] = sub.conditionStatus == 'rented' ? 'available' : sub.conditionStatus;
          }
        }
      }
    } else {
      _itemStatusMap[widget.lease.itemId] = 'available';
    }

    _loadAllItemComponents();

    InventoryUnitRepository().getUnitsForProduct(widget.lease.itemId).then((units) {
      if (mounted && units.isNotEmpty) {
        setState(() {
          for (final u in units) {
            for (final c in u.components) {
              if (c.replacementCost > 0) {
                _compUnitCostMap[c.id] = c.replacementCost;
                _compUnitCostMap[c.componentName] = c.replacementCost;
                _compUnitCostMap[c.componentName.trim().toLowerCase()] = c.replacementCost;
              }
            }
          }
          _updateAutoDamageFee();
        });
      }
    });

    InventoryUnitRepository().getDefinitionsForProduct(widget.lease.itemId).then((defs) {
      if (mounted && defs.isNotEmpty) {
        setState(() {
          for (final d in defs) {
            if (d.replacementCost > 0) {
              _compUnitCostMap[d.componentName] = d.replacementCost;
              _compUnitCostMap[d.componentName.trim().toLowerCase()] = d.replacementCost;
            }
          }
          _updateAutoDamageFee();
        });
      }
    });

    _recalculate();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _damageFeeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _getLeaseItemDisplayName() {
    return widget.lease.itemNamesSummary;
  }

  void _recalculate() {
    double totalCalculated = 0.0;
    _itemBreakdowns.clear();

    if (widget.lease.leaseItems.isNotEmpty) {
      for (final li in widget.lease.leaseItems) {
        final b = RateCalculator.getReturnRentBreakdown(
          startTime: widget.lease.startTime,
          actualReturnTime: _actualReturnTime,
          rateHourly: li.effectiveRateHourly > 0 ? li.effectiveRateHourly : (li.item?.rateHourly ?? 0.0),
          rateDaily: li.effectiveRateDaily > 0 ? li.effectiveRateDaily : (li.item?.rateDaily ?? 0.0),
          rateWeekly: li.effectiveRateWeekly > 0 ? li.effectiveRateWeekly : (li.item?.rateWeekly ?? 0.0),
          rateMonthly: li.effectiveRateMonthly > 0 ? li.effectiveRateMonthly : (li.item?.rateMonthly ?? 0.0),
        );
        final lineRent = b.totalRent * li.quantity;
        totalCalculated += lineRent;

        _itemBreakdowns.add(ItemSmartBreakdown(
          name: li.item?.name ?? 'Equipment Item',
          quantity: li.quantity,
          breakdown: b,
          lineTotalRent: lineRent,
        ));
      }
    } else {
      InventoryItemModel? item = widget.lease.item;
      if (item == null) {
        try {
          final invState = context.read<InventoryCubit>().state;
          if (invState is InventoryLoaded) {
            item = invState.allItems.firstWhere((i) => i.id == widget.lease.itemId);
          }
        } catch (_) {}
      }

      if (item != null) {
        final b = RateCalculator.getReturnRentBreakdown(
          startTime: widget.lease.startTime,
          actualReturnTime: _actualReturnTime,
          rateHourly: item.rateHourly,
          rateDaily: item.rateDaily,
          rateWeekly: item.rateWeekly,
          rateMonthly: item.rateMonthly,
        );
        totalCalculated = b.totalRent * widget.lease.quantity;

        _itemBreakdowns.add(ItemSmartBreakdown(
          name: item.name,
          quantity: widget.lease.quantity,
          breakdown: b,
          lineTotalRent: totalCalculated,
        ));
      } else {
        totalCalculated = widget.lease.calculatedRent;
      }
    }

    _calculatedRent = totalCalculated;

    final discountVal = double.tryParse(_discountController.text) ?? 0.0;
    final damageFeeVal = double.tryParse(_damageFeeController.text) ?? 0.0;

    _netRent = (_calculatedRent - discountVal + damageFeeVal);
    if (_netRent < 0) _netRent = 0.0;

    final totalUpfrontCredit = widget.lease.depositPaid + widget.lease.advanceRentPaid;
    _finalBalance = _netRent - totalUpfrontCredit;
  }

  Future<void> _selectReturnDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _actualReturnTime,
      firstDate: widget.lease.startTime,
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_actualReturnTime),
    );

    final selectedTime = pickedTime ?? TimeOfDay.fromDateTime(_actualReturnTime);

    setState(() {
      _actualReturnTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
    _recalculate();
  }

  void _handleSettlement() async {
    setState(() => _isSettling = true);

    try {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      if (store == null) throw Exception('Store not found');

      // Construct updated line items and sub-items with exact selected return/condition statuses
      List<LeaseItemModel> updatedLeaseItems = [];

      if (widget.lease.leaseItems.isNotEmpty) {
        updatedLeaseItems = widget.lease.leaseItems.map((line) {
          final st = _itemStatusMap[line.id] ?? 'available';
          final updatedSubItems = line.leasedSubItems.map((sub) {
            final subSt = _subItemStatusMap[sub.id] ?? 'available';
            final dbSt = (subSt == 'maintenance' || subSt == 'damaged') ? 'damaged' : subSt;
            return sub.copyWith(conditionStatus: dbSt);
          }).toList();

          return line.copyWith(
            returnStatus: st,
            leasedSubItems: updatedSubItems,
          );
        }).toList();
      } else {
        final st = _itemStatusMap[widget.lease.itemId] ?? 'available';
        final updatedSubItems = _subItems.map((s) {
          final subSt = _subItemStatusMap[s.id] ?? 'available';
          return LeasedSubItemModel(
            id: s.id,
            leaseId: widget.lease.id,
            leaseItemId: widget.lease.id,
            subItemId: s.id,
            itemId: widget.lease.itemId,
            storeId: widget.lease.storeId,
            itemName: s.name,
            serialNumber: s.serialNumber,
            conditionStatus: subSt,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }).toList();

        updatedLeaseItems.add(LeaseItemModel(
          id: widget.lease.id,
          leaseId: widget.lease.id,
          storeId: widget.lease.storeId,
          itemId: widget.lease.itemId,
          quantity: widget.lease.quantity,
          rateHourly: widget.lease.item?.rateHourly ?? 0,
          rateDaily: widget.lease.item?.rateDaily ?? 0,
          rateWeekly: widget.lease.item?.rateWeekly ?? 0,
          rateMonthly: widget.lease.item?.rateMonthly ?? 0,
          depositAmount: widget.lease.depositExpected,
          lineCalculatedRent: widget.lease.calculatedRent,
          returnStatus: st,
          createdAt: widget.lease.createdAt,
          updatedAt: DateTime.now(),
          item: widget.lease.item,
          leasedSubItems: updatedSubItems,
        ));
      }

      final updatedLease = widget.lease.copyWith(
        actualReturnTime: _actualReturnTime,
        billingUnitUsed: _billingMode,
        calculatedRent: _calculatedRent,
        discountAmount: double.tryParse(_discountController.text) ?? 0.0,
        damageOrLateFee: double.tryParse(_damageFeeController.text) ?? 0.0,
        netRentTotal: _netRent,
        finalSettlementBalance: _finalBalance,
        returnNotes: _notesController.text.trim(),
        status: 'returned',
        leaseItems: updatedLeaseItems,
      );

      final settled = await context.read<LeaseCubit>().returnAndSettle(updatedLease);

      // Create damage/loss incidents if any physical component is marked damaged or lost
      final damageRepo = DamageLossRepository();

      for (final line in settled.leaseItems) {
        for (final sub in line.leasedSubItems) {
          if (!sub.isExcluded) {
            final st = sub.conditionStatus;
            if (st == 'maintenance' || st == 'lost' || st == 'damaged') {
              final incidentType = st == 'lost' ? 'lost' : 'damaged';
              final cost = _resolveComponentReplacementCost(sub);

              // Satisfy DB constraint check_exactly_one_asset_ref: exactly one of inventory_unit_id or inventory_component_unit_id must be NOT NULL
              String? compUnitId = (sub.inventoryComponentUnitId != null && sub.inventoryComponentUnitId!.isNotEmpty)
                  ? sub.inventoryComponentUnitId
                  : null;

              String? unitId = compUnitId == null
                  ? ((sub.leaseItemUnitId != null && sub.leaseItemUnitId!.isNotEmpty) ? sub.leaseItemUnitId : null)
                  : null;

              // Fallback to guarantee exactly one non-null reference
              if (compUnitId == null && unitId == null) {
                if (sub.subItemId.isNotEmpty) {
                  compUnitId = sub.subItemId;
                } else if (sub.id.isNotEmpty) {
                  compUnitId = sub.id;
                } else {
                  unitId = line.itemId.isNotEmpty ? line.itemId : settled.id;
                }
              }

              try {
                final incident = DamageLossIncidentModel(
                  id: UuidGenerator.generateV4(),
                  storeId: store.id,
                  leaseId: settled.id,
                  leaseItemId: line.id,
                  inventoryUnitId: unitId,
                  inventoryComponentUnitId: compUnitId,
                  incidentType: incidentType,
                  description: 'Reported $incidentType during return inspection of ${sub.itemName}',
                  customerCharge: cost > 0 ? cost : (incidentType == 'lost' ? 1500.0 : 500.0),
                  estimatedRepairCost: cost > 0 ? cost : (incidentType == 'lost' ? 0.0 : 400.0),
                  reportedAt: DateTime.now(),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await damageRepo.createIncident(incident);
                debugPrint('--> [SETTLE INCIDENT SUCCESS] Incident logged for ${sub.itemName}');

                // Log audit history entry
                final historyRepo = InventoryItemHistoryRepository();
                await historyRepo.logHistory(InventoryItemHistoryModel(
                  id: UuidGenerator.generateV4(),
                  storeId: store.id,
                  inventoryItemId: line.itemId,
                  inventoryUnitId: sub.leaseItemUnitId,
                  inventoryComponentUnitId: sub.inventoryComponentUnitId,
                  leaseId: settled.id,
                  eventType: incidentType, // 'damaged' or 'lost'
                  previousStatus: 'rented',
                  newStatus: st == 'lost' ? 'lost' : 'maintenance',
                  notes: 'Reported $incidentType during return inspection of ${sub.itemName}',
                  costIncurred: cost,
                  createdAt: DateTime.now(),
                ));
              } catch (incErr) {
                debugPrint('--> [SETTLE INCIDENT WARNING] DamageLossIncident creation warning: $incErr');
              }
            }
          }
        }
      }

      // Reload inventory so available quantities immediately update across all screens
      if (mounted) {
        context.read<InventoryCubit>().loadInventory();
      }

      final pdfFile = await PdfReceiptService.instance.generateReturnSettlementReceipt(
        store: store,
        lease: settled,
      );

      if (!mounted) return;
      _showSettlementSuccessSheet(store, settled, pdfFile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error settling return: $e'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  void _showPaymentQrModal(StoreModel store) {
    final upiId = store.upiId;
    final businessName = Uri.encodeComponent(store.businessName);
    final amount = _finalBalance.abs().toStringAsFixed(2);
    final upiUri = 'upi://pay?pa=$upiId&pn=$businessName&am=$amount&cu=INR';

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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Collect ${store.currencySymbol}$amount',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Scan with Google Pay, PhonePe, Paytm or any UPI App',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : AppColors.secondary),
              ),
              const SizedBox(height: 16),
              if (upiId != null && upiId.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                    ),
                    child: QrImageView(data: upiUri, version: QrVersions.auto, size: 200),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  child: const Text('Add your UPI ID in Profile tab to enable dynamic amount QR codes.'),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Payment Received'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettlementSuccessSheet(StoreModel store, LeaseModel lease, File pdfFile) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Settlement Completed & Item Returned!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.lightOnSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Settlement PDF ready for ${lease.customer?.name ?? "Customer"}.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : AppColors.secondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  final msg =
                      'Hello ${lease.customer?.name ?? "Customer"}, here is your official return settlement statement from ${store.businessName} for ${lease.itemNamesSummary}. Final balance: ${store.currencySymbol}${lease.finalSettlementBalance.abs().toStringAsFixed(2)}. Thank you for renting with us!';

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) Navigator.pop(context);

                  await PdfReceiptService.instance.shareReceipt(pdfFile, msg);
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Share Settlement Statement via WhatsApp'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await PdfReceiptService.instance.printReceipt(pdfFile);
                },
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print / Preview Statement'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Done & Return to Dashboard'),
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
    final store = storeState is StoreLoaded ? storeState.store : null;
    final currency = store?.currencySymbol ?? '₹';

    final duration = _actualReturnTime.difference(widget.lease.startTime);
    final totalMinutes = duration.inMinutes < 1 ? 1 : duration.inMinutes;

    final days = totalMinutes ~/ (24 * 60);
    final minutesAfterDays = totalMinutes % (24 * 60);
    final hours = minutesAfterDays ~/ 60;
    final minutes = minutesAfterDays % 60;

    String fallbackDurationText = '';
    if (days > 0) fallbackDurationText += '$days Day${days > 1 ? 's' : ''}, ';
    if (hours > 0) fallbackDurationText += '$hours Hr${hours > 1 ? 's' : ''}, ';
    fallbackDurationText += '$minutes Min${minutes > 1 ? 's' : ''}';

    final durationDisplay = _breakdown?.durationText ?? fallbackDurationText;

    // Calculate damaged & lost components repair/replacement costs
    double totalEstDamageCost = 0.0;
    final List<Map<String, dynamic>> damagedCompBreakdown = [];

    final hasLineItems = widget.lease.leaseItems.isNotEmpty;
    final itemsCount = hasLineItems ? widget.lease.leaseItems.length : 1;

    for (int i = 0; i < itemsCount; i++) {
      final lineItem = hasLineItems ? widget.lease.leaseItems[i] : null;
      final key = lineItem?.id ?? widget.lease.itemId;
      final mainSt = _itemStatusMap[key] ?? 'available';

      final List<dynamic> subItemsList = lineItem != null && lineItem.leasedSubItems.isNotEmpty
          ? lineItem.leasedSubItems
          : (i == 0 ? _subItems : []);

      for (final sub in subItemsList) {
        final subId = sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id;
        final isExcluded = sub is LeasedSubItemModel ? sub.isExcluded : false;
        if (!isExcluded) {
          final subSt = _subItemStatusMap[subId] ?? 'available';
          if (subSt == 'maintenance' || subSt == 'lost') {
            final double repCost = _resolveComponentReplacementCost(sub);
            final cost = repCost > 0 ? repCost : (subSt == 'lost' ? 1500.0 : 500.0);
            totalEstDamageCost += cost;
            damagedCompBreakdown.add({
              'name': sub is LeasedSubItemModel ? sub.itemName : (sub as SubItemModel).name,
              'serial': sub is LeasedSubItemModel ? sub.serialNumber : (sub as SubItemModel).serialNumber,
              'status': subSt == 'lost' ? 'LOST' : 'DAMAGED',
              'cost': cost,
            });
          }
        }
      }

      if (subItemsList.isEmpty && (mainSt == 'maintenance' || mainSt == 'lost')) {
        final cost = mainSt == 'lost' ? 1500.0 : 500.0;
        totalEstDamageCost += cost;
        damagedCompBreakdown.add({
          'name': lineItem?.item?.name ?? _getLeaseItemDisplayName(),
          'serial': null,
          'status': mainSt == 'lost' ? 'LOST' : 'DAMAGED',
          'cost': cost,
        });
      }
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Return & Final Settlement'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Rental Duration & Timeline Card
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
                          Icon(Icons.timer_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          const SizedBox(width: 6),
                          const Text('Rental Duration & Timeline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          durationDisplay,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Handover Date', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                            Text(DateFormat('dd MMM, hh:mm a').format(widget.lease.startTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        InkWell(
                          onTap: _selectReturnDateTime,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit, size: 10, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                    const SizedBox(width: 3),
                                    Text('Actual Return', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                  ],
                                ),
                                Text(DateFormat('dd MMM, hh:mm a').format(_actualReturnTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Recorded Duration: $durationDisplay',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Master Quick Action Control
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quick Inspection Actions',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      Text(
                        '(Mark condition for all equipment)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // 1. Ready / OK Button
                      Expanded(
                        child: _returnStatus == 'available'
                            ? ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final k in _itemStatusMap.keys) {
                                      _itemStatusMap[k] = 'available';
                                    }
                                    for (final k in _unitStatusMap.keys) {
                                      _unitStatusMap[k] = 'available';
                                    }
                                    for (final k in _subItemStatusMap.keys) {
                                      _subItemStatusMap[k] = 'available';
                                    }
                                    _returnStatus = 'available';
                                    _updateAutoDamageFee();
                                  });
                                },
                                icon: const Icon(Icons.check_circle, size: 14, color: Colors.white),
                                label: const Text(
                                  'Ready / OK',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final k in _itemStatusMap.keys) {
                                      _itemStatusMap[k] = 'available';
                                    }
                                    for (final k in _unitStatusMap.keys) {
                                      _unitStatusMap[k] = 'available';
                                    }
                                    for (final k in _subItemStatusMap.keys) {
                                      _subItemStatusMap[k] = 'available';
                                    }
                                    _returnStatus = 'available';
                                    _updateAutoDamageFee();
                                  });
                                },
                                icon: const Icon(Icons.check_circle_outline, size: 14, color: AppColors.primary),
                                label: const Text(
                                  'Ready / OK',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),

                      // 2. Damaged Button
                      Expanded(
                        child: _returnStatus == 'maintenance'
                            ? ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final k in _itemStatusMap.keys) {
                                      _itemStatusMap[k] = 'maintenance';
                                    }
                                    for (final k in _unitStatusMap.keys) {
                                      _unitStatusMap[k] = 'maintenance';
                                    }
                                    for (final k in _subItemStatusMap.keys) {
                                      _subItemStatusMap[k] = 'maintenance';
                                    }
                                    _returnStatus = 'maintenance';
                                    _updateAutoDamageFee();
                                  });
                                },
                                icon: const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.white),
                                label: const Text(
                                  'Damaged',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.tertiaryAmber,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final k in _itemStatusMap.keys) {
                                      _itemStatusMap[k] = 'maintenance';
                                    }
                                    for (final k in _unitStatusMap.keys) {
                                      _unitStatusMap[k] = 'maintenance';
                                    }
                                    for (final k in _subItemStatusMap.keys) {
                                      _subItemStatusMap[k] = 'maintenance';
                                    }
                                    _returnStatus = 'maintenance';
                                    _updateAutoDamageFee();
                                  });
                                },
                                icon: const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.tertiaryAmber),
                                label: const Text(
                                  'Damaged',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.tertiaryAmber),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  side: const BorderSide(color: AppColors.tertiaryAmber),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),

                      // 3. Lost Button
                      Expanded(
                        child: _returnStatus == 'lost'
                            ? ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final k in _itemStatusMap.keys) {
                                      _itemStatusMap[k] = 'lost';
                                    }
                                    for (final k in _unitStatusMap.keys) {
                                      _unitStatusMap[k] = 'lost';
                                    }
                                    for (final k in _subItemStatusMap.keys) {
                                      _subItemStatusMap[k] = 'lost';
                                    }
                                    _returnStatus = 'lost';
                                    _updateAutoDamageFee();
                                  });
                                },
                                icon: const Icon(Icons.highlight_off, size: 14, color: Colors.white),
                                label: const Text(
                                  'Lost',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.errorRed,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final k in _itemStatusMap.keys) {
                                      _itemStatusMap[k] = 'lost';
                                    }
                                    for (final k in _unitStatusMap.keys) {
                                      _unitStatusMap[k] = 'lost';
                                    }
                                    for (final k in _subItemStatusMap.keys) {
                                      _subItemStatusMap[k] = 'lost';
                                    }
                                    _returnStatus = 'lost';
                                    _updateAutoDamageFee();
                                  });
                                },
                                icon: const Icon(Icons.highlight_off, size: 14, color: AppColors.errorRed),
                                label: const Text(
                                  'Lost',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  side: const BorderSide(color: AppColors.errorRed),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. Equipment Condition Inspection Cards (Single Spot per Item)
            Text(
              'Equipment Condition Inspection',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            const SizedBox(height: 8),

            ..._buildIndividualItemCards(context, isDark),

            const SizedBox(height: 6),

            // 4. Inspection Proof Photos taken when leasing
            if (widget.lease.beforePhotoUrls.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
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
                            Icon(Icons.photo_library_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            const SizedBox(width: 6),
                            const Text('Photos Taken When Leasing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text('${widget.lease.beforePhotoUrls.length} Photos',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.lease.beforePhotoUrls.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _buildConditionPhotoThumbnail(
                          context,
                          widget.lease.beforePhotoUrls[index],
                          index,
                          isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 5. Prior Upfront Payments & Deposit Credit Card
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
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 6),
                      const Text('Prior Upfront Payments & Credits', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Security deposit paid upfront', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('$currency${widget.lease.depositPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Advance rent paid upfront', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('$currency${widget.lease.advanceRentPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Upfront Credit Available', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                      Text(
                        '$currency${(widget.lease.depositPaid + widget.lease.advanceRentPaid).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 6. Smart Ledger Calculation Breakdown Card
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
                    children: [
                      Icon(Icons.calculate_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 6),
                      const Text('Smart Ledger Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Display Itemized Component Breakdown List for ALL items in order
                  if (_itemBreakdowns.isNotEmpty) ...[
                    ..._itemBreakdowns.map((itemBk) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${itemBk.quantity}x ${itemBk.name}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                                ),
                                Text(
                                  '$currency${itemBk.lineTotalRent.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...itemBk.breakdown.components.map((comp) {
                              final compSubtotal = comp.amount * itemBk.quantity;
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '• ${comp.label}: ${comp.calculation}',
                                        style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                      ),
                                    ),
                                    Text(
                                      itemBk.quantity > 1
                                          ? '$currency${comp.amount.toStringAsFixed(2)} / pc ($currency${compSubtotal.toStringAsFixed(2)})'
                                          : '$currency${comp.amount.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (itemBk.quantity > 1) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Formula: ${itemBk.quantity} pcs × $currency${itemBk.breakdown.totalRent.toStringAsFixed(2)} / pc = $currency${itemBk.lineTotalRent.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    const SizedBox(height: 6),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gross Rent Subtotal', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('$currency${_calculatedRent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Coupon / Discount row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Discount / Coupon ($currency)',
                            prefixText: '$currency ',
                          ),
                          onChanged: (_) => setState(_recalculate),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.local_offer_outlined, color: AppColors.primary),
                        tooltip: 'Apply Coupon',
                        onPressed: () => _openDiscountPickerModal(context),
                      ),
                    ],
                  ),
                  if (_appliedDiscount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Applied Coupon: ${_appliedDiscount!.code} (${_appliedDiscount!.discountText})',
                        style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Itemized Damage / Loss Replacement Cost Summary Box
                  if (damagedCompBreakdown.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Damaged / Lost Items Estimated Cost:',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                              ),
                              Text(
                                '$currency${totalEstDamageCost.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...damagedCompBreakdown.map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '• ${item['name']}${item['serial'] != null && (item['serial'] as String).isNotEmpty ? " (${item['serial']})" : ""} [${item['status']}]',
                                      style: const TextStyle(fontSize: 10, color: AppColors.errorRed, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '$currency${(item['cost'] as double).toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  TextFormField(
                    controller: _damageFeeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Damage / Inspection / Overdue Fee ($currency)',
                      prefixText: '$currency ',
                      helperText: 'Added to final rental charges upon inspection',
                    ),
                    onChanged: (_) => setState(_recalculate),
                  ),

                  const SizedBox(height: 12),
                  Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Final Net Rental Charge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
                      Text('$currency${_netRent.toStringAsFixed(2)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 7. Final Settlement Reconciliation Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _finalBalance > 0
                    ? (isDark ? const Color(0xFF3B2E15) : const Color(0xFFFFFBEB))
                    : (_finalBalance < 0
                        ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                        : (isDark ? AppColors.darkCard : Colors.white)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _finalBalance > 0
                      ? AppColors.tertiaryAmber
                      : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _finalBalance > 0
                            ? 'Client Owes Store (Additional Collect)'
                            : (_finalBalance < 0 ? 'Store Refund to Client' : 'Fully Settled (Net Zero Balance)'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _finalBalance > 0
                              ? Colors.amber.shade900
                              : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? Colors.white : AppColors.slateNavy)),
                        ),
                      ),
                      if (store != null && _finalBalance > 0)
                        IconButton(
                          icon: const Icon(Icons.qr_code, color: AppColors.primary),
                          tooltip: 'Show UPI QR Code',
                          onPressed: () => _showPaymentQrModal(store),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$currency${_finalBalance.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _finalBalance > 0
                          ? AppColors.errorRed
                          : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? Colors.white : AppColors.slateNavy)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _finalBalance > 0
                        ? 'Collect $currency${_finalBalance.toStringAsFixed(2)} via Cash / UPI QR Code.'
                        : (_finalBalance < 0
                            ? 'Refund $currency${_finalBalance.abs().toStringAsFixed(2)} security deposit balance to client.'
                            : 'Security deposit matches rental charges exactly.'),
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 8. Return Notes Input
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Return Notes (Optional)',
                hintText: 'Accessories verified, minor scratches recorded...',
              ),
            ),

            const SizedBox(height: 24),

            // 9. Primary Settlement Button
            ElevatedButton.icon(
              onPressed: _isSettling ? null : _handleSettlement,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text(_isSettling ? 'Finalizing Settlement...' : 'Confirm Return & Finalize Settlement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
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

  double _resolveComponentReplacementCost(dynamic sub) {
    double repCost = sub is LeasedSubItemModel ? sub.replacementCost : 0.0;

    if (repCost <= 0) {
      if (sub is LeasedSubItemModel && sub.inventoryComponentUnitId != null && sub.inventoryComponentUnitId!.isNotEmpty) {
        repCost = _compUnitCostMap[sub.inventoryComponentUnitId!] ?? 0.0;
      }
      if (repCost <= 0) {
        final name = sub is LeasedSubItemModel ? sub.itemName : (sub as SubItemModel).name;
        repCost = _compUnitCostMap[name] ?? _compUnitCostMap[name.trim().toLowerCase()] ?? 0.0;
      }
    }

    return repCost;
  }

  void _updateAutoDamageFee() {
    double totalEstDamageCost = 0.0;
    final hasLineItems = widget.lease.leaseItems.isNotEmpty;
    final itemsCount = hasLineItems ? widget.lease.leaseItems.length : 1;

    for (int i = 0; i < itemsCount; i++) {
      final lineItem = hasLineItems ? widget.lease.leaseItems[i] : null;
      final key = lineItem?.id ?? widget.lease.itemId;

      final List<dynamic> subItemsList = lineItem != null && lineItem.leasedSubItems.isNotEmpty
          ? lineItem.leasedSubItems
          : (i == 0 ? _subItems : []);

      for (final sub in subItemsList) {
        final subId = sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id;
        final isExcluded = sub is LeasedSubItemModel ? sub.isExcluded : false;
        if (!isExcluded) {
          final subSt = _subItemStatusMap[subId] ?? 'available';
          if (subSt == 'maintenance' || subSt == 'lost') {
            final double repCost = _resolveComponentReplacementCost(sub);
            totalEstDamageCost += repCost;
          }
        }
      }
    }

    if (totalEstDamageCost > 0) {
      _damageFeeController.text = totalEstDamageCost.toStringAsFixed(0);
    } else {
      _damageFeeController.text = '0';
    }
    _recalculate();
  }

  void _propagateParentStatusToSubItems(String newStatus, List<dynamic> subItemsList) {
    for (final sub in subItemsList) {
      final subId = sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id;
      final isExcluded = sub is LeasedSubItemModel ? sub.isExcluded : false;
      if (!isExcluded) {
        _subItemStatusMap[subId] = newStatus;
      }
    }
    _updateAutoDamageFee();
  }

  List<Widget> _buildIndividualItemCards(BuildContext context, bool isDark) {
    final List<Widget> cards = [];

    final hasLineItems = widget.lease.leaseItems.isNotEmpty;
    final itemsCount = hasLineItems ? widget.lease.leaseItems.length : 1;

    for (int i = 0; i < itemsCount; i++) {
      final lineItem = hasLineItems ? widget.lease.leaseItems[i] : null;
      final key = lineItem?.id ?? widget.lease.itemId;
      final itemName = lineItem?.item?.name ?? (hasLineItems ? 'Equipment Item #${i + 1}' : _getLeaseItemDisplayName());
      final qty = lineItem?.quantity ?? widget.lease.quantity;
      final sku = lineItem?.item?.displaySku ?? widget.lease.item?.displaySku ?? '-';

      final String currentItemId = lineItem?.itemId ?? widget.lease.itemId;

      // Get sub-items / components for this line item
      final List<dynamic> subItemsList = (lineItem != null && lineItem.leasedSubItems.isNotEmpty)
          ? lineItem.leasedSubItems
          : (_itemComponentTemplates[currentItemId] ?? _subItems);

      // Group sub-items into physical sets / units
      final Map<String, List<dynamic>> groupedUnitsMap = {};

      bool hasUnitKeys = subItemsList.any((s) => s is LeasedSubItemModel && s.leaseItemUnitId != null && s.leaseItemUnitId!.isNotEmpty);

      if (hasUnitKeys) {
        for (final sub in subItemsList) {
          final unitKey = (sub is LeasedSubItemModel && sub.leaseItemUnitId != null && sub.leaseItemUnitId!.isNotEmpty)
              ? sub.leaseItemUnitId!
              : 'unit_${sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id}';
          groupedUnitsMap.putIfAbsent(unitKey, () => []).add(sub);
        }
      } else {
        // Replicate full list of sub-components for EACH physical unit set!
        final numSets = qty > 0 ? qty : 1;
        for (int setIdx = 1; setIdx <= numSets; setIdx++) {
          final unitKey = 'set_${i}_$setIdx';
          final List<dynamic> replicatedComps = [];

          for (final sub in subItemsList) {
            if (sub is LeasedSubItemModel) {
              final String compSetId = '${sub.id}_set_$setIdx';
              replicatedComps.add(sub.copyWith(id: compSetId));
            } else if (sub is SubItemModel) {
              final String compSetId = '${sub.id}_set_$setIdx';
              replicatedComps.add(SubItemModel(
                id: compSetId,
                parentItemId: sub.parentItemId,
                storeId: sub.storeId,
                name: sub.name,
                serialNumber: sub.serialNumber,
                status: sub.status,
                createdAt: sub.createdAt,
                updatedAt: sub.updatedAt,
              ));
            }
          }
          groupedUnitsMap[unitKey] = replicatedComps;
        }
      }

      debugPrint('--> [TAKE BACK DIAGNOSTIC] Item #$i ($itemName): qty=$qty, subItemsList length=${subItemsList.length}');
      debugPrint('--> [TAKE BACK DIAGNOSTIC] groupedUnitsMap length=${groupedUnitsMap.length}');
      for (final entry in groupedUnitsMap.entries) {
        debugPrint('--> [TAKE BACK DIAGNOSTIC] UnitKey ${entry.key}: ${entry.value.length} components');
      }

      // Render a top-level card for EACH Physical Set / Unit!
      int setIndex = 1;
      for (final mapEntry in groupedUnitsMap.entries) {
        final unitKeyId = mapEntry.key;
        final unitSubs = mapEntry.value;

        // Determine Unit-level condition: only show 'available', 'maintenance', or 'lost' if ALL unit sub-items share the exact same status!
        String unitStatus = _unitStatusMap[unitKeyId] ?? 'available';

        if (unitSubs.isNotEmpty) {
          final firstUnitSub = unitSubs.first;
          final firstUnitSubId = firstUnitSub is LeasedSubItemModel ? firstUnitSub.id : (firstUnitSub as SubItemModel).id;
          final firstUnitSt = _subItemStatusMap[firstUnitSubId] ?? 'available';

          bool allUnitSubsSame = true;
          for (final s in unitSubs) {
            final subId = s is LeasedSubItemModel ? s.id : (s as SubItemModel).id;
            final st = _subItemStatusMap[subId] ?? 'available';
            if (st != firstUnitSt) {
              allUnitSubsSame = false;
              break;
            }
          }

          if (allUnitSubsSame) {
            unitStatus = firstUnitSt;
            _unitStatusMap[unitKeyId] = firstUnitSt;
          } else {
            unitStatus = 'available';
            _unitStatusMap[unitKeyId] = 'available';
          }
        }

        final bool isUnitException = unitStatus == 'maintenance' || unitStatus == 'lost';
        final bool hasDamagedComponent = unitSubs.any((s) {
          final subId = s is LeasedSubItemModel ? s.id : (s as SubItemModel).id;
          return (_subItemStatusMap[subId] ?? 'available') != 'available';
        });

        final Color cardBgColor = (isUnitException || hasDamagedComponent)
            ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2))
            : (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5));

        final Color cardBorderColor = (isUnitException || hasDamagedComponent)
            ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA))
            : (isDark ? AppColors.primary : const Color(0xFFA7F3D0));

        final String statusLabel = isUnitException
            ? (unitStatus == 'lost' ? 'UNIT LOST' : 'UNIT DAMAGED')
            : (hasDamagedComponent ? 'PARTIAL EXCEPTION' : 'RETURNED - GOOD CONDITION');

        final Color badgeBg = (isUnitException || hasDamagedComponent)
            ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFFDAD6))
            : (isDark ? AppColors.darkSurfaceLow : const Color(0xFFD1FAE5));

        final Color badgeTextColor = (isUnitException || hasDamagedComponent) ? AppColors.errorRed : AppColors.primary;

        final firstSerialObj = unitSubs.where((s) => (s is LeasedSubItemModel ? s.serialNumber : (s as SubItemModel).serialNumber) != null).firstOrNull;
        final String? unitSerial = firstSerialObj != null
            ? (firstSerialObj is LeasedSubItemModel ? firstSerialObj.serialNumber : (firstSerialObj as SubItemModel).serialNumber)
            : null;

        final unitTitle = '📦 Physical Set #$setIndex ${unitSerial != null && unitSerial.isNotEmpty ? "($unitSerial)" : ""}';

        cards.add(
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorderColor, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Set Unit Card Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unitTitle,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Equipment: $itemName • SKU: $sku',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: badgeTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Per-Unit Condition Choice Chips Header
                Text(
                  'Set Unit Condition:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 6),

                // Choice Chips for this Physical Unit Set
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildConditionChoiceChip(
                      label: 'Available (OK)',
                      value: 'available',
                      selectedGroupValue: unitStatus,
                      onSelected: () {
                        setState(() {
                          _unitStatusMap[unitKeyId] = 'available';
                          _propagateParentStatusToSubItems('available', unitSubs);
                        });
                      },
                      isDark: isDark,
                      activeColor: AppColors.primary,
                    ),
                    _buildConditionChoiceChip(
                      label: 'Damaged',
                      value: 'maintenance',
                      selectedGroupValue: unitStatus,
                      onSelected: () {
                        setState(() {
                          _unitStatusMap[unitKeyId] = 'maintenance';
                          _propagateParentStatusToSubItems('maintenance', unitSubs);
                        });
                      },
                      isDark: isDark,
                      activeColor: AppColors.errorRed,
                    ),
                    _buildConditionChoiceChip(
                      label: 'Lost',
                      value: 'lost',
                      selectedGroupValue: unitStatus,
                      onSelected: () {
                        setState(() {
                          _unitStatusMap[unitKeyId] = 'lost';
                          _propagateParentStatusToSubItems('lost', unitSubs);
                        });
                      },
                      isDark: isDark,
                      activeColor: AppColors.errorRed,
                    ),
                  ],
                ),

                // Sub-Components list under this Physical Unit Set
                if (unitSubs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  const SizedBox(height: 8),

                  Text(
                    'Unit Components Condition:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                  const SizedBox(height: 8),

                  ...unitSubs.map((sub) {
                    final String subId = sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id;
                    final String subName = sub is LeasedSubItemModel ? sub.itemName : (sub as SubItemModel).name;
                    final String? subSerial = sub is LeasedSubItemModel ? sub.serialNumber : (sub as SubItemModel).serialNumber;
                    final bool isExcluded = sub is LeasedSubItemModel ? sub.isExcluded : false;

                    if (isExcluded) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '• $subName [EXCLUDED FROM RENTAL - NOT EXPECTED]',
                          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      );
                    }

                    final String currentSubSt = _subItemStatusMap[subId] ?? 'available';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '• $subName${subSerial != null && subSerial.isNotEmpty ? " (SN: $subSerial)" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildConditionChoiceChip(
                                label: 'OK',
                                value: 'available',
                                selectedGroupValue: currentSubSt,
                                onSelected: () {
                                  setState(() {
                                    _subItemStatusMap[subId] = 'available';
                                    _updateAutoDamageFee();
                                  });
                                },
                                isDark: isDark,
                                activeColor: AppColors.primary,
                                isCompact: true,
                              ),
                              const SizedBox(width: 4),
                              _buildConditionChoiceChip(
                                label: 'Damaged',
                                value: 'maintenance',
                                selectedGroupValue: currentSubSt,
                                onSelected: () {
                                  setState(() {
                                    _subItemStatusMap[subId] = 'maintenance';
                                    _updateAutoDamageFee();
                                  });
                                },
                                isDark: isDark,
                                activeColor: AppColors.errorRed,
                                isCompact: true,
                              ),
                              const SizedBox(width: 4),
                              _buildConditionChoiceChip(
                                label: 'Lost',
                                value: 'lost',
                                selectedGroupValue: currentSubSt,
                                onSelected: () {
                                  setState(() {
                                    _subItemStatusMap[subId] = 'lost';
                                    _updateAutoDamageFee();
                                  });
                                },
                                isDark: isDark,
                                activeColor: AppColors.errorRed,
                                isCompact: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ] else ...[
                  const SizedBox(height: 12),
                  Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  const SizedBox(height: 8),
                  if (_isLoadingComponents)
                    const Row(
                      children: [
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading unit components...', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    )
                  else
                    Text(
                      'No sub-components configured for this unit set.',
                      style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                    ),
                ],
              ],
            ),
          ),
        );
        setIndex++;
      }
    }

    return cards;
  }

  Widget _buildConditionChoiceChip({
    required String label,
    required String value,
    required String selectedGroupValue,
    required VoidCallback onSelected,
    required bool isDark,
    required Color activeColor,
    bool isCompact = false,
  }) {
    final bool isSelected = selectedGroupValue == value;

    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 10,
          vertical: isCompact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? AppColors.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: isCompact ? 12 : 14,
              color: isSelected ? Colors.white : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
            ),
            SizedBox(width: isCompact ? 4 : 6),
            Text(
              label,
              style: TextStyle(
                fontSize: isCompact ? 10 : 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionPhotoThumbnail(BuildContext context, String photoUrl, int index, bool isDark) {
    return GestureDetector(
      onTap: () => _showEnlargedPhotoDialog(context, photoUrl, index),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(photoUrl, fit: BoxFit.cover),
        ),
      ),
    );
  }

  void _showEnlargedPhotoDialog(BuildContext context, String photoUrl, int index) {
    showDialog(
      context: context,
      builder: (dCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    child: Image.network(photoUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dCtx),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Close Photo Preview'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDiscountPickerModal(BuildContext context) {
    final discountState = context.read<DiscountCubit>().state;
    final discounts = discountState is DiscountLoaded ? discountState.discounts : <DiscountModel>[];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        final isDark = Theme.of(modalCtx).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Discount Coupons',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.lightOnSurface),
              ),
              const SizedBox(height: 12),
              if (discounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No discount coupons active.')),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    itemCount: discounts.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final disc = discounts[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: const Icon(Icons.local_offer, color: AppColors.primary),
                          title: Text(disc.code, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(disc.title),
                          trailing: Text(disc.discountText, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                          onTap: () {
                            final discAmt = disc.calculateDiscountAmount(_calculatedRent);
                            setState(() {
                              _appliedDiscount = disc;
                              _discountController.text = discAmt.toStringAsFixed(0);
                              _recalculate();
                            });
                            Navigator.pop(modalCtx);
                          },
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
}
