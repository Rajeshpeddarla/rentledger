import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/rate_calculator.dart';
import '../../data/models/lease_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/leased_sub_item_model.dart';
import '../../data/models/store_model.dart';

class PdfReceiptService {
  static final PdfReceiptService instance = PdfReceiptService._internal();
  PdfReceiptService._internal();

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
  final DateFormat _dateOnlyFormat = DateFormat('dd MMM yyyy');

  // Palette from rentledger_receipt_templates.html
  final PdfColor _navy = PdfColor.fromHex('#17324D');
  final PdfColor _navy2 = PdfColor.fromHex('#234766');
  final PdfColor _teal = PdfColor.fromHex('#16877A');
  final PdfColor _tealSoft = PdfColor.fromHex('#EAF6F4');
  final PdfColor _ink = PdfColor.fromHex('#243447');
  final PdfColor _muted = PdfColor.fromHex('#667789');
  final PdfColor _line = PdfColor.fromHex('#DCE4EB');
  final PdfColor _panel = PdfColor.fromHex('#F5F8FB');
  final PdfColor _green = PdfColor.fromHex('#177245');
  final PdfColor _greenSoft = PdfColor.fromHex('#EAF7EF');
  final PdfColor _amber = PdfColor.fromHex('#986515');
  final PdfColor _red = PdfColor.fromHex('#A63B3B');

  /// Loads Unicode-compatible font to render Indian Rupee (₹) and other Unicode symbols
  Future<pw.ThemeData?> _loadPdfTheme() async {
    try {
      final baseFont = await PdfGoogleFonts.notoSansDevanagariRegular();
      final boldFont = await PdfGoogleFonts.notoSansDevanagariBold();
      return pw.ThemeData.withFont(base: baseFont, bold: boldFont);
    } catch (e) {
      debugPrint('PdfReceiptService devanagari font load warning: $e');
    }

    try {
      final baseFont = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();
      return pw.ThemeData.withFont(base: baseFont, bold: boldFont);
    } catch (e) {
      debugPrint('PdfReceiptService roboto font load warning: $e');
    }

    try {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    } catch (_) {
      return null;
    }
  }

  String _resolveCurrency(StoreModel store, pw.ThemeData? theme) {
    if (theme != null) {
      return store.currencySymbol;
    }
    return (store.currencySymbol == '₹') ? 'Rs. ' : store.currencySymbol;
  }

  String _getStoreInitials(String name) {
    if (name.trim().isEmpty) return 'RL';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _getLeaseItemDisplayName(LeaseModel lease) {
    if (lease.returnNotes != null && lease.returnNotes!.contains('Leased Equipment Items:')) {
      final noteStr = lease.returnNotes!.replaceFirst('Leased Equipment Items:', '').trim();
      if (noteStr.isNotEmpty) return noteStr;
    }
    return lease.item?.name ?? 'Equipment Item';
  }

  String _formatExactDuration(Duration duration) {
    final totalMinutes = duration.inMinutes < 1 ? 1 : duration.inMinutes;
    final days = totalMinutes ~/ (24 * 60);
    final minutesAfterDays = totalMinutes % (24 * 60);
    final hours = minutesAfterDays ~/ 60;
    final minutes = minutesAfterDays % 60;

    final List<String> parts = [];
    if (days > 0) parts.add('$days day${days > 1 ? "s" : ""}');
    if (hours > 0) parts.add('$hours hr${hours > 1 ? "s" : ""}');
    if (minutes > 0 || parts.isEmpty) parts.add('$minutes min${minutes > 1 ? "s" : ""}');

    return parts.join(', ');
  }

  /// Automatically generates the exact correct receipt (Handover, Reservation, or Settlement) based on lease status
  Future<File> generateReceiptForLease({
    required StoreModel store,
    required LeaseModel lease,
    List<LeaseModel>? multiItemLeases,
  }) async {
    if (lease.status == 'returned') {
      return generateReturnSettlementReceipt(store: store, lease: lease, multiItemLeases: multiItemLeases);
    } else if (lease.status == 'reserved' || lease.isFutureReservation) {
      return generateReservationReceipt(store: store, lease: lease, multiItemLeases: multiItemLeases);
    } else {
      return generateHandoverReceipt(store: store, lease: lease, multiItemLeases: multiItemLeases);
    }
  }

  /// Generates Handover & Deposit Receipt PDF matching Template 1
  Future<File> generateHandoverReceipt({
    required StoreModel store,
    required LeaseModel lease,
    List<LeaseModel>? multiItemLeases,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);

    final duration = lease.expectedEndTime.difference(lease.startTime);
    final durationText = _formatExactDuration(duration);
    final issueDateStr = _dateOnlyFormat.format(lease.createdAt);

    final List<LeaseItemModel> lineItemsToRender = [];
    if (lease.leaseItems.isNotEmpty) {
      lineItemsToRender.addAll(lease.leaseItems);
    } else if (multiItemLeases != null && multiItemLeases.isNotEmpty) {
      for (final l in multiItemLeases) {
        if (l.leaseItems.isNotEmpty) {
          lineItemsToRender.addAll(l.leaseItems);
        } else {
          lineItemsToRender.add(LeaseItemModel(
            id: l.id,
            leaseId: l.id,
            storeId: l.storeId,
            itemId: l.itemId,
            quantity: l.quantity,
            rateHourly: l.item?.rateHourly ?? 0,
            rateDaily: l.item?.rateDaily ?? 0,
            rateWeekly: l.item?.rateWeekly ?? 0,
            rateMonthly: l.item?.rateMonthly ?? 0,
            depositAmount: l.depositExpected,
            lineCalculatedRent: l.calculatedRent,
            createdAt: l.createdAt,
            updatedAt: l.updatedAt,
            item: l.item,
          ));
        }
      }
    } else {
      lineItemsToRender.add(LeaseItemModel(
        id: lease.id,
        leaseId: lease.id,
        storeId: lease.storeId,
        itemId: lease.itemId,
        quantity: lease.quantity,
        rateHourly: lease.item?.rateHourly ?? 0,
        rateDaily: lease.item?.rateDaily ?? 0,
        rateWeekly: lease.item?.rateWeekly ?? 0,
        rateMonthly: lease.item?.rateMonthly ?? 0,
        depositAmount: lease.depositExpected,
        lineCalculatedRent: lease.calculatedRent,
        createdAt: lease.createdAt,
        updatedAt: lease.updatedAt,
        item: lease.item,
      ));
    }

    double totalGrandEstimatedRent = 0.0;
    double totalGrandExpectedDeposit = 0.0;

    for (final line in lineItemsToRender) {
      final b = RateCalculator.getReturnRentBreakdown(
        startTime: lease.startTime,
        actualReturnTime: lease.expectedEndTime,
        rateHourly: line.effectiveRateHourly,
        rateDaily: line.effectiveRateDaily,
        rateWeekly: line.effectiveRateWeekly,
        rateMonthly: line.effectiveRateMonthly,
        currency: currency,
      );
      final unitRent = b.totalRent;
      totalGrandEstimatedRent += (unitRent * line.quantity);
      totalGrandExpectedDeposit += (line.depositAmount * line.quantity);
    }

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox.shrink();
          }
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${store.businessName} • Handover Receipt HO-${lease.shortId}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy),
                ),
                pw.Text(
                  'Issued: $issueDateStr',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${_dateFormat.format(DateTime.now())} • RentLedger',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy2),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Header Block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 44,
                      height: 44,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: _navy,
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Text(
                        _getStoreInitials(store.businessName),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          store.businessName,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        if (store.address != null && store.address!.isNotEmpty)
                          pw.Text(store.address!, style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (store.phone != null && store.phone!.isNotEmpty)
                          pw.Text('Phone: ${store.phone}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (store.email != null && store.email!.isNotEmpty)
                          pw.Text('Email: ${store.email}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (store.isTaxRegistered && store.taxRegistrationNumber != null)
                          pw.Text('Tax Reg No: ${store.taxRegistrationNumber}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'RENTAL DOCUMENT',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _teal,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Handover Receipt',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('Receipt No. ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text('HO-${lease.shortId}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('Lease ID ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text(lease.shortId, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('Issued ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text(issueDateStr, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: _greenSoft,
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.Text(
                        'Item handed over',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(color: _navy, thickness: 1.5),
            pw.SizedBox(height: 12),

            // Customer & Timeline Cards Row
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: _panel,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: _line),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CUSTOMER DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                        pw.SizedBox(height: 6),
                        pw.Text(lease.customer?.name ?? 'Customer', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
                        pw.Text('Phone: ${lease.customer?.phone ?? "-"}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (lease.customer?.email != null)
                          pw.Text('Email: ${lease.customer!.email}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text('Customer ID: CUS-${lease.customer?.shortId ?? "001"}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: _panel,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: _line),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('RENTAL TIMELINE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                        pw.SizedBox(height: 6),
                        pw.Text('Handover: ${_dateFormat.format(lease.startTime)}', style: pw.TextStyle(fontSize: 10, color: _ink)),
                        pw.Text('Expected return: ${_dateFormat.format(lease.expectedEndTime)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _amber)),
                        pw.Text('Planned duration: $durationText', style: pw.TextStyle(fontSize: 10, color: _muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Rented Equipment Items Table
            pw.Text('RENTED EQUIPMENT ITEMS (${lineItemsToRender.length})', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 6),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Table(
                border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: _line)),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F4F8')),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Item / Asset', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Qty', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Base Rate', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Duration', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Estimated Rent', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  ...lineItemsToRender.expand((line) {
                    final itemDuration = lease.expectedEndTime.difference(lease.startTime);
                    final itemDurationText = _formatExactDuration(itemDuration);
                    final itemBreakdown = RateCalculator.getReturnRentBreakdown(
                      startTime: lease.startTime,
                      actualReturnTime: lease.expectedEndTime,
                      rateHourly: line.effectiveRateHourly,
                      rateDaily: line.effectiveRateDaily,
                      rateWeekly: line.effectiveRateWeekly,
                      rateMonthly: line.effectiveRateMonthly,
                      currency: currency,
                    );

                    final singleUnitCost = itemBreakdown.totalRent;
                    final itemSubtotalCost = singleUnitCost * line.quantity;

                    String itemDisplayRateUnit = '/ day';
                    double itemDisplayRate = line.effectiveRateDaily;
                    if (itemDuration.inHours < 24 && line.effectiveRateHourly > 0) {
                      itemDisplayRateUnit = '/ hr';
                      itemDisplayRate = line.effectiveRateHourly;
                    }

                    return [
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  '${line.quantity > 1 ? '${line.quantity}x ' : ''}${line.item?.name ?? "Equipment Item"}',
                                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy),
                                ),
                                pw.Text('Asset SKU: ${line.item?.displaySku ?? "-"}', style: pw.TextStyle(fontSize: 8, color: _muted)),
                              ],
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '${line.quantity} ${line.quantity > 1 ? "pcs" : "pc"}',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('$currency${itemDisplayRate.toStringAsFixed(2)}$itemDisplayRateUnit', style: pw.TextStyle(fontSize: 9, color: _ink)),
                                if (line.quantity > 1)
                                  pw.Text('($currency${(itemDisplayRate * line.quantity).toStringAsFixed(2)}$itemDisplayRateUnit combined)', style: pw.TextStyle(fontSize: 7, color: _muted)),
                              ],
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(itemDurationText, style: pw.TextStyle(fontSize: 9, color: _ink), textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$currency${itemSubtotalCost.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    ];
                  }),
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F4F8')),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Total Estimated Rental Charges', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
                      ),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('$currency${totalGrandEstimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Side-by-Side Physical Set Piece Cards & Component Handover Chips
            if (lineItemsToRender.any((l) => l.leasedSubItems.isNotEmpty)) ...[
              pw.SizedBox(height: 12),
              pw.Text('PHYSICAL SET ASSIGNMENTS & COMPONENT HANDOVER CHIPS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.SizedBox(height: 6),

              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (() {
                  final List<pw.Widget> pieceCards = [];

                  for (final line in lineItemsToRender) {
                    final skuTag = (line.item?.sku != null && line.item!.sku.trim().isNotEmpty)
                        ? line.item!.sku.trim().toUpperCase()
                        : 'UNIT';

                    final Map<String, List<LeasedSubItemModel>> groupedByUnit = {};

                    for (final sub in line.leasedSubItems) {
                      final unitKey = (sub.leaseItemUnitId != null && sub.leaseItemUnitId!.isNotEmpty)
                          ? sub.leaseItemUnitId!
                          : 'unit_default';
                      groupedByUnit.putIfAbsent(unitKey, () => []).add(sub);
                    }

                    int pieceNum = 1;
                    for (final entry in groupedByUnit.entries) {
                      final subList = entry.value;
                      final assetCode = '$skuTag-${pieceNum.toString().padLeft(4, '0')}';

                      pieceCards.add(
                        pw.Container(
                          width: 250,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: _panel,
                            borderRadius: pw.BorderRadius.circular(6),
                            border: pw.Border.all(color: _line),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Expanded(
                                    child: pw.Text(
                                      line.item?.name ?? "Equipment Set",
                                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _navy),
                                    ),
                                  ),
                                  pw.SizedBox(width: 6),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: pw.BoxDecoration(
                                      color: _navy,
                                      borderRadius: pw.BorderRadius.circular(4),
                                    ),
                                    child: pw.Text(
                                      assetCode,
                                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 6),

                              pw.Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: subList.map((sub) {
                                  final isExcluded = sub.isExcluded;
                                  final chipText = isExcluded
                                      ? '[EXCLUDED] ${sub.itemName}'
                                      : '${sub.itemName}${sub.serialNumber != null ? " [SN: ${sub.serialNumber}]" : ""}';
                                  return pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: pw.BoxDecoration(
                                      color: isExcluded ? PdfColor.fromHex('#FCE8E6') : PdfColor.fromHex('#E6F4EA'),
                                      borderRadius: pw.BorderRadius.circular(4),
                                      border: pw.Border.all(
                                        color: isExcluded ? _red : _green,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: pw.Text(
                                      chipText,
                                      style: pw.TextStyle(
                                        fontSize: 7,
                                        fontWeight: pw.FontWeight.bold,
                                        color: isExcluded ? _red : _green,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }
                  return pieceCards;
                })(),
              ),
            ],
            pw.SizedBox(height: 16),

            // Financial Summary Grid
            pw.Text('FINANCIAL SUMMARY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _line),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          color: _panel,
                          width: double.infinity,
                          child: pw.Text('Rental Estimate', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Column(
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Subtotal (Equipment rent)', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${totalGrandEstimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              if (lease.discountAmount > 0) ...[
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Discount applied', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                    pw.Text('-$currency${lease.discountAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red)),
                                  ],
                                ),
                              ],
                              if (lease.taxAmount > 0) ...[
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Taxes (${lease.appliedTaxType} ${lease.appliedTaxRate.toInt()}%)', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                    pw.Text('${lease.isTaxInclusive ? "" : "+"}$currency${lease.taxAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _teal)),
                                  ],
                                ),
                              ],
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Advance rent received', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${lease.advanceRentPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Divider(color: _line),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Estimated rent balance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                  pw.Text(
                                    '$currency${((lease.discountedNetRentTotal > 0 ? lease.discountedNetRentTotal : lease.netRentTotal) - lease.advanceRentPaid < 0 ? 0.0 : (lease.discountedNetRentTotal > 0 ? lease.discountedNetRentTotal : lease.netRentTotal) - lease.advanceRentPaid).toStringAsFixed(2)}',
                                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _line),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          color: _panel,
                          width: double.infinity,
                          child: pw.Text('Security Deposit', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Column(
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Deposit required', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${totalGrandExpectedDeposit.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Deposit received (${lease.depositPaymentType.toUpperCase()})', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${lease.depositPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Divider(color: _line),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Deposit outstanding', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                  pw.Text('$currency${(totalGrandExpectedDeposit - lease.depositPaid < 0 ? 0.0 : totalGrandExpectedDeposit - lease.depositPaid).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: _tealSoft,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColor.fromHex('#CCE6E1')),
              ),
              child: pw.Text(
                'Deposit Status: $currency${lease.depositPaid.toStringAsFixed(2)} received out of $currency${totalGrandExpectedDeposit.toStringAsFixed(2)} required. Remaining deposit: $currency${(totalGrandExpectedDeposit - lease.depositPaid < 0 ? 0.0 : totalGrandExpectedDeposit - lease.depositPaid).toStringAsFixed(2)}. Estimated rent is shown separately from the security deposit.',
                style: pw.TextStyle(fontSize: 8.5, color: PdfColor.fromHex('#285E58')),
              ),
            ),

            pw.SizedBox(height: 14),

            // Rental Terms
            pw.Text('RENTAL TERMS & CONDITIONS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 4),
            pw.Text(
              store.termsAndConditions.length > 300
                  ? '${store.termsAndConditions.substring(0, 300)}...'
                  : store.termsAndConditions,
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),

            pw.Spacer(),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColor.fromHex('#9EACB9')),
                    pw.SizedBox(height: 4),
                    pw.Text('For ${store.businessName}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                    pw.Text('Authorized signature / store stamp', style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColor.fromHex('#9EACB9')),
                    pw.SizedBox(height: 4),
                    pw.Text('Customer acceptance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                    pw.Text('Customer signature', style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/handover_receipt_${lease.shortId}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generates Reservation Receipt PDF for Future Bookings
  Future<File> generateReservationReceipt({
    required StoreModel store,
    required LeaseModel lease,
    List<LeaseModel>? multiItemLeases,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);

    final leaseList = (multiItemLeases != null && multiItemLeases.isNotEmpty)
        ? multiItemLeases
        : [lease];

    final duration = lease.expectedEndTime.difference(lease.startTime);
    final durationText = _formatExactDuration(duration);
    final issueDateStr = _dateOnlyFormat.format(lease.createdAt);

    double totalGrandEstimatedRent = 0.0;
    double totalGrandExpectedDeposit = 0.0;

    for (final l in leaseList) {
      if (l.leaseItems.isNotEmpty) {
        for (final line in l.leaseItems) {
          final b = RateCalculator.getReturnRentBreakdown(
            startTime: l.startTime,
            actualReturnTime: l.expectedEndTime,
            rateHourly: line.effectiveRateHourly,
            rateDaily: line.effectiveRateDaily,
            rateWeekly: line.effectiveRateWeekly,
            rateMonthly: line.effectiveRateMonthly,
            currency: currency,
          );
          totalGrandEstimatedRent += (b.totalRent * line.quantity);
          totalGrandExpectedDeposit += (line.depositAmount * line.quantity);
        }
      } else {
        final item = l.item;
        final b = item != null
            ? RateCalculator.getReturnRentBreakdown(
                startTime: l.startTime,
                actualReturnTime: l.expectedEndTime,
                rateHourly: item.rateHourly,
                rateDaily: item.rateDaily,
                rateWeekly: item.rateWeekly,
                rateMonthly: item.rateMonthly,
                currency: currency,
              )
            : null;
        final unitRent = b?.totalRent ?? 0.0;
        totalGrandEstimatedRent += (unitRent * l.quantity);
        totalGrandExpectedDeposit += l.depositExpected;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox.shrink();
          }
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${store.businessName} • Reservation Receipt RES-${lease.shortId}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy),
                ),
                pw.Text(
                  'Issued: $issueDateStr',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${_dateFormat.format(DateTime.now())} • RentLedger',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy2),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Header Block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 44,
                      height: 44,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: _navy,
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Text(
                        _getStoreInitials(store.businessName),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          store.businessName,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        if (store.address != null && store.address!.isNotEmpty)
                          pw.Text(store.address!, style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (store.phone != null && store.phone!.isNotEmpty)
                          pw.Text('Phone: ${store.phone}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (store.email != null && store.email!.isNotEmpty)
                          pw.Text('Email: ${store.email}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (store.isTaxRegistered && store.taxRegistrationNumber != null)
                          pw.Text('Tax Reg No: ${store.taxRegistrationNumber}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'RENTAL RESERVATION',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _teal,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Reservation Receipt',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('Receipt No. ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text('RES-${lease.shortId}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('Lease ID ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text(lease.shortId, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('Issued ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text(issueDateStr, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: _panel,
                        borderRadius: pw.BorderRadius.circular(12),
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Text(
                        'Item reserved for future',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _amber),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(color: _navy, thickness: 1.5),
            pw.SizedBox(height: 12),

            // Customer & Timeline Cards Row
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: _panel,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: _line),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CUSTOMER DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                        pw.SizedBox(height: 6),
                        pw.Text(lease.customer?.name ?? 'Customer', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
                        pw.Text('Phone: ${lease.customer?.phone ?? "-"}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        if (lease.customer?.email != null)
                          pw.Text('Email: ${lease.customer!.email}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        pw.Text('Customer ID: CUS-${lease.customer?.shortId ?? "001"}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: _panel,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: _line),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('RENTAL TIMELINE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                        pw.SizedBox(height: 6),
                        pw.Text('Reserved for: ${_dateFormat.format(lease.startTime)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        pw.Text('Expected return: ${_dateFormat.format(lease.expectedEndTime)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _amber)),
                        pw.Text('Planned duration: $durationText', style: pw.TextStyle(fontSize: 10, color: _muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Reserved Equipment Items Table
            pw.Text('RESERVED EQUIPMENT ITEMS (${leaseList.length})', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 6),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Table(
                border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: _line)),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F4F8')),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Item / Asset', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Qty', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Base Rate', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Duration', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Estimated Rent', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  ...leaseList.expand((itemLease) {
                    final itemDuration = itemLease.expectedEndTime.difference(itemLease.startTime);
                    final itemDurationText = _formatExactDuration(itemDuration);
                    final item = itemLease.item;
                    final itemBreakdown = RateCalculator.getReturnRentBreakdown(
                      startTime: itemLease.startTime,
                      actualReturnTime: itemLease.expectedEndTime,
                      rateHourly: itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateHourly : (item?.rateHourly ?? 0.0),
                      rateDaily: itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateDaily : (item?.rateDaily ?? 0.0),
                      rateWeekly: itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateWeekly : (item?.rateWeekly ?? 0.0),
                      rateMonthly: itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateMonthly : (item?.rateMonthly ?? 0.0),
                      currency: currency,
                    );

                    final singleUnitCost = itemBreakdown.totalRent;
                    final itemSubtotalCost = singleUnitCost * itemLease.quantity;

                    String itemDisplayRateUnit = '/ day';
                    double itemDisplayRate = itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateDaily : (item?.rateDaily ?? 0.0);
                    if (itemDuration.inHours < 24 && (itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateHourly : (item?.rateHourly ?? 0.0)) > 0) {
                      itemDisplayRateUnit = '/ hr';
                      itemDisplayRate = itemLease.leaseItems.isNotEmpty ? itemLease.leaseItems.first.effectiveRateHourly : (item?.rateHourly ?? 0.0);
                    }

                    return [
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  '${itemLease.quantity > 1 ? '${itemLease.quantity}x ' : ''}${itemLease.item?.name ?? _getLeaseItemDisplayName(itemLease)}',
                                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy),
                                ),
                                pw.Text('Asset SKU: ${itemLease.item?.displaySku ?? "-"}', style: pw.TextStyle(fontSize: 8, color: _muted)),
                              ],
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '${itemLease.quantity} ${itemLease.quantity > 1 ? "pcs" : "pc"}',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('$currency${itemDisplayRate.toStringAsFixed(2)}$itemDisplayRateUnit', style: pw.TextStyle(fontSize: 9, color: _ink)),
                                if (itemLease.quantity > 1)
                                  pw.Text('($currency${(itemDisplayRate * itemLease.quantity).toStringAsFixed(2)}$itemDisplayRateUnit combined)', style: pw.TextStyle(fontSize: 7, color: _muted)),
                              ],
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(itemDurationText, style: pw.TextStyle(fontSize: 9, color: _ink), textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$currency${itemSubtotalCost.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    ];
                  }),
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F4F8')),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Total Estimated Rental Charges', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
                      ),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('$currency${totalGrandEstimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Financial Summary Grid
            pw.Text('FINANCIAL SUMMARY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _line),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          color: _panel,
                          width: double.infinity,
                          child: pw.Text('Rental Estimate', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Column(
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Estimated rental charges', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${totalGrandEstimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Advance rent received', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${lease.advanceRentPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Divider(color: _line),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Estimated rent balance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                  pw.Text('$currency${(totalGrandEstimatedRent - lease.advanceRentPaid < 0 ? 0.0 : totalGrandEstimatedRent - lease.advanceRentPaid).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _line),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          color: _panel,
                          width: double.infinity,
                          child: pw.Text('Security Deposit', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Column(
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Deposit required', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${totalGrandExpectedDeposit.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Deposit received (${lease.depositPaymentType.toUpperCase()})', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                  pw.Text('$currency${lease.depositPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green)),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Divider(color: _line),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Deposit outstanding', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                  pw.Text('$currency${(totalGrandExpectedDeposit - lease.depositPaid < 0 ? 0.0 : totalGrandExpectedDeposit - lease.depositPaid).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: _tealSoft,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColor.fromHex('#CCE6E1')),
              ),
              child: pw.Text(
                'Reservation Notice: Equipment is reserved for specified dates. Deposit status: $currency${lease.depositPaid.toStringAsFixed(2)} received out of $currency${totalGrandExpectedDeposit.toStringAsFixed(2)} required.',
                style: pw.TextStyle(fontSize: 8.5, color: PdfColor.fromHex('#285E58')),
              ),
            ),

            pw.SizedBox(height: 14),

            // Rental Terms
            pw.Text('RENTAL TERMS & CONDITIONS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 4),
            pw.Text(
              store.termsAndConditions.length > 300
                  ? '${store.termsAndConditions.substring(0, 300)}...'
                  : store.termsAndConditions,
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),

            pw.Spacer(),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColor.fromHex('#9EACB9')),
                    pw.SizedBox(height: 4),
                    pw.Text('For ${store.businessName}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                    pw.Text('Authorized signature / store stamp', style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColor.fromHex('#9EACB9')),
                    pw.SizedBox(height: 4),
                    pw.Text('Customer acceptance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                    pw.Text('Customer signature', style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/reservation_receipt_${lease.shortId}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generates Return & Settlement Receipt PDF for Take Back
  Future<File> generateReturnSettlementReceipt({
    required StoreModel store,
    required LeaseModel lease,
    List<LeaseModel>? multiItemLeases,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);
    final returnTime = lease.actualReturnTime ?? DateTime.now();

    final duration = returnTime.difference(lease.startTime);
    final actualDurationText = _formatExactDuration(duration);

    final isCollect = lease.finalSettlementBalance > 0;
    final isRefund = lease.finalSettlementBalance < 0;

    final List<LeaseItemModel> lineItemsToRender = [];
    if (lease.leaseItems.isNotEmpty) {
      lineItemsToRender.addAll(lease.leaseItems);
    } else if (multiItemLeases != null && multiItemLeases.isNotEmpty) {
      for (final l in multiItemLeases) {
        if (l.leaseItems.isNotEmpty) {
          lineItemsToRender.addAll(l.leaseItems);
        } else {
          lineItemsToRender.add(LeaseItemModel(
            id: l.id,
            leaseId: l.id,
            storeId: l.storeId,
            itemId: l.itemId,
            quantity: l.quantity,
            rateHourly: l.item?.rateHourly ?? 0,
            rateDaily: l.item?.rateDaily ?? 0,
            rateWeekly: l.item?.rateWeekly ?? 0,
            rateMonthly: l.item?.rateMonthly ?? 0,
            depositAmount: l.depositExpected,
            lineCalculatedRent: l.calculatedRent,
            createdAt: l.createdAt,
            updatedAt: l.updatedAt,
            item: l.item,
            returnStatus: l.status,
          ));
        }
      }
    } else {
      lineItemsToRender.add(LeaseItemModel(
        id: lease.id,
        leaseId: lease.id,
        storeId: lease.storeId,
        itemId: lease.itemId,
        quantity: lease.quantity,
        rateHourly: lease.item?.rateHourly ?? 0,
        rateDaily: lease.item?.rateDaily ?? 0,
        rateWeekly: lease.item?.rateWeekly ?? 0,
        rateMonthly: lease.item?.rateMonthly ?? 0,
        depositAmount: lease.depositExpected,
        lineCalculatedRent: lease.calculatedRent,
        createdAt: lease.createdAt,
        updatedAt: lease.updatedAt,
        item: lease.item,
        returnStatus: lease.status,
      ));
    }

    // Determine Callout Banner Colors & Content
    PdfColor calloutBg = _navy;
    String calloutHeadline = 'Fully Settled (Net Zero Balance)';
    String calloutNote = 'Security deposit matched net rent charges exactly.';
    String calloutAmount = '$currency 0.00';

    if (isCollect) {
      calloutBg = PdfColor.fromHex('#7B4D16'); // Amber/Outstanding
      calloutHeadline = 'Additional amount collected';
      calloutNote = 'Payment recorded as successful · Cash / Digital Transfer';
      calloutAmount = '+$currency${lease.finalSettlementBalance.toStringAsFixed(2)}';
    } else if (isRefund) {
      calloutBg = PdfColor.fromHex('#155B4F'); // Teal/Refund
      calloutHeadline = 'Deposit refunded to client';
      calloutNote = 'Deposit refunded in full after deducting net rental charges';
      calloutAmount = '$currency${lease.finalSettlementBalance.abs().toStringAsFixed(2)}';
    }

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox.shrink();
          }
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${store.businessName} • Settlement Receipt SR-${lease.shortId}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy),
                ),
                pw.Text(
                  'Settled: ${_dateOnlyFormat.format(returnTime)}',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${_dateFormat.format(DateTime.now())} • RentLedger',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy2),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
              // Header Block
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 44,
                        height: 44,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          color: _navy,
                          borderRadius: pw.BorderRadius.circular(10),
                        ),
                        child: pw.Text(
                          _getStoreInitials(store.businessName),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            store.businessName,
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: _navy,
                            ),
                          ),
                          if (store.address != null && store.address!.isNotEmpty)
                            pw.Text(store.address!, style: pw.TextStyle(fontSize: 10, color: _muted)),
                          if (store.phone != null && store.phone!.isNotEmpty)
                            pw.Text('Phone: ${store.phone}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          if (store.email != null && store.email!.isNotEmpty)
                            pw.Text('Email: ${store.email}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          if (store.isTaxRegistered && store.taxRegistrationNumber != null)
                            pw.Text('Tax Reg No: ${store.taxRegistrationNumber}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'RENTAL DOCUMENT',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: _teal,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Settlement Receipt',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text('Receipt No. ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text('SR-${lease.shortId}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                        ],
                      ),
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text('Lease ID ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text(lease.shortId, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                        ],
                      ),
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text('Settled on ', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text(_dateOnlyFormat.format(returnTime), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: _greenSoft,
                          borderRadius: pw.BorderRadius.circular(12),
                        ),
                        child: pw.Text(
                          'Return inspected',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: _navy, thickness: 1.5),
              pw.SizedBox(height: 12),

              // Customer & Return Details 2-Card Row
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: _panel,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('CUSTOMER DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                          pw.SizedBox(height: 6),
                          pw.Text(lease.customer?.name ?? 'Customer', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
                          pw.Text('Phone: ${lease.customer?.phone ?? "-"}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          if (lease.customer?.email != null)
                            pw.Text('Email: ${lease.customer!.email}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text('Customer ID: CUS-${lease.customer?.shortId ?? "001"}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: _panel,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('RETURN DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                          pw.SizedBox(height: 6),
                          pw.Text('Item: ${_getLeaseItemDisplayName(lease)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                          pw.Text('Handover: ${_dateFormat.format(lease.startTime)}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text('Actual Return: ${_dateFormat.format(returnTime)}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text('Duration: $actualDurationText', style: pw.TextStyle(fontSize: 10, color: _muted)),
                          pw.Text(
                            lease.damageOrLateFee > 0
                                ? 'Inspection: Exception · Fee Charged'
                                : 'Inspection: Passed · Item Released',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: lease.damageOrLateFee > 0 ? _red : _green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Itemized Rental Charges & Condition Inspection
              pw.Text('ITEMIZED RENTAL CHARGES & RETURN INSPECTION', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.SizedBox(height: 6),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    // Table Header Row
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      color: PdfColor.fromHex('#F0F4F8'),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text('Item Description & Condition Status', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text('Rate Breakdown', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                          ),
                          pw.Text('Subtotal', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.right),
                        ],
                      ),
                    ),
                    pw.Divider(color: _line, height: 1),

                    // Item Rows
                    ...lineItemsToRender.map((line) {
                      final b = RateCalculator.getReturnRentBreakdown(
                        startTime: lease.startTime,
                        actualReturnTime: returnTime,
                        rateHourly: line.rateHourly > 0 ? line.rateHourly : (line.item?.rateHourly ?? 0.0),
                        rateDaily: line.rateDaily > 0 ? line.rateDaily : (line.item?.rateDaily ?? 0.0),
                        rateWeekly: line.rateWeekly > 0 ? line.rateWeekly : (line.item?.rateWeekly ?? 0.0),
                        rateMonthly: line.rateMonthly > 0 ? line.rateMonthly : (line.item?.rateMonthly ?? 0.0),
                      );
                      final lineSubtotal = b.totalRent * line.quantity;

                      final String statusKey = line.returnStatus.toLowerCase();
                      final bool isLineDamaged = statusKey.contains('maintenance') || statusKey.contains('damaged');
                      final bool isLost = statusKey.contains('lost');
                      final bool isInspection = statusKey.contains('awaiting') || statusKey.contains('inspection');

                      final bool hasDamagedSubItem = line.leasedSubItems.any((sub) {
                        final st = sub.conditionStatus.toLowerCase();
                        return st.contains('maintenance') || st.contains('damaged') || st.contains('lost') || st.contains('awaiting');
                      });

                      final bool isDamaged = isLineDamaged || hasDamagedSubItem;

                      final String badgeText = isLineDamaged
                          ? 'DAMAGED - FEE APPLIED'
                          : (isLost
                              ? 'LOST / UNRETURNED'
                              : (hasDamagedSubItem
                                  ? 'DAMAGED ACCESSORY'
                                  : (isInspection ? 'UNDER MAINTENANCE' : 'RETURNED - GOOD CONDITION')));

                      final PdfColor badgeBg = isDamaged || isLost
                          ? PdfColor.fromHex('#FCE8E6')
                          : (isInspection ? PdfColor.fromHex('#FEF3D6') : PdfColor.fromHex('#E6F4EA'));

                      final PdfColor badgeTextColor = isDamaged || isLost
                          ? _red
                          : (isInspection ? PdfColor.fromHex('#B45309') : _green);

                      final bool hasProblem = isDamaged || isLost || isInspection;

                      return pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          color: hasProblem ? PdfColor.fromHex('#FFF5F5') : PdfColors.white,
                          border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Expanded(
                                  child: pw.Row(
                                    children: [
                                      pw.Text(
                                        '${line.quantity}x ${line.item?.name ?? "Equipment Item"}',
                                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy),
                                      ),
                                      pw.SizedBox(width: 8),
                                      pw.Container(
                                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: pw.BoxDecoration(
                                          color: badgeBg,
                                          borderRadius: pw.BorderRadius.circular(4),
                                        ),
                                        child: pw.Text(
                                          badgeText,
                                          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: badgeTextColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                pw.Text(
                                  '$currency${lineSubtotal.toStringAsFixed(2)}',
                                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 4),

                            // Rate components breakdown
                            ...b.components.map((comp) {
                              final compTotal = comp.amount * line.quantity;
                              return pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text(
                                      '  • ${comp.label}: ${comp.calculation}',
                                      style: pw.TextStyle(fontSize: 8.5, color: _muted),
                                    ),
                                    pw.Text(
                                      line.quantity > 1
                                          ? '$currency${comp.amount.toStringAsFixed(2)} / pc ($currency${compTotal.toStringAsFixed(2)})'
                                          : '$currency${comp.amount.toStringAsFixed(2)}',
                                      style: pw.TextStyle(fontSize: 8.5, color: _ink),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            if (line.quantity > 1) ...[
                              pw.SizedBox(height: 2),
                              pw.Text(
                                '  Piece Formula: ${line.quantity} pcs × $currency${b.totalRent.toStringAsFixed(2)} / pc = $currency${lineSubtotal.toStringAsFixed(2)}',
                                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _teal),
                              ),
                            ],

                            // Sub-items if any
                            if (line.leasedSubItems.isNotEmpty) ...[
                              pw.SizedBox(height: 4),
                              pw.Text('  Sub-Items & Accessories Inspection:', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _navy)),
                              ...line.leasedSubItems.map((sub) {
                                final subSt = sub.conditionStatus.toLowerCase();
                                final bool subDamaged = subSt.contains('maintenance') || subSt.contains('damaged') || subSt.contains('lost');
                                return pw.Padding(
                                  padding: const pw.EdgeInsets.only(left: 8, top: 2),
                                  child: pw.Text(
                                    '    - ${sub.itemName}${sub.serialNumber != null ? " (SN: ${sub.serialNumber})" : ""}: ${subDamaged ? "[DAMAGED / EXCEPTION]" : "[GOOD CONDITION]"}',
                                    style: pw.TextStyle(
                                      fontSize: 8,
                                      fontWeight: subDamaged ? pw.FontWeight.bold : pw.FontWeight.normal,
                                      color: subDamaged ? _red : _muted,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    }),

                    if (lease.discountAmount > 0)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Promotional Discount / Coupon (-)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green)),
                            pw.Text('-$currency${lease.discountAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green)),
                          ],
                        ),
                      ),

                    if (lease.damageOrLateFee > 0)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Inspection Damage / Overdue Fee (+)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red)),
                            pw.Text('+$currency${lease.damageOrLateFee.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red)),
                          ],
                        ),
                      ),

                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      color: PdfColor.fromHex('#F7FAFC'),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Total Net Rental Charges', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                          pw.Text('$currency${lease.netRentTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Deposit Reconciliation Grid
              pw.Text('DEPOSIT RECONCILIATION', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.SizedBox(height: 6),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _line),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            color: _panel,
                            width: double.infinity,
                            child: pw.Text('Final Rental Ledger', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Column(
                              children: [
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Security deposit received', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                    pw.Text('$currency${lease.depositPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                  ],
                                ),
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Total net rental charges', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                    pw.Text('$currency${lease.netRentTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                  ],
                                ),
                                pw.SizedBox(height: 4),
                                pw.Divider(color: _line),
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Net balance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                    pw.Text('$currency${lease.finalSettlementBalance.abs().toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _line),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            color: _panel,
                            width: double.infinity,
                            child: pw.Text('Collection / Refund Status', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Column(
                              children: [
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Additional amount collected', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                    pw.Text('$currency${isCollect ? lease.finalSettlementBalance.toStringAsFixed(2) : "0.00"}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                  ],
                                ),
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Refund paid to client', style: pw.TextStyle(fontSize: 10, color: _muted)),
                                    pw.Text('$currency${isRefund ? lease.finalSettlementBalance.abs().toStringAsFixed(2) : "0.00"}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                  ],
                                ),
                                pw.SizedBox(height: 4),
                                pw.Divider(color: _line),
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Outstanding balance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                                    pw.Text('$currency 0.00', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),

              // Settlement Callout Box (Template 2 Callout Box)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: calloutBg,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('SETTLEMENT OUTCOME', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 1.0)),
                        pw.SizedBox(height: 2),
                        pw.Text(calloutHeadline, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                        pw.SizedBox(height: 2),
                        pw.Text(calloutNote, style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#D9E6EF'))),
                      ],
                    ),
                    pw.Text(
                      calloutAmount,
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // Return Acknowledgment
              pw.Text('RETURN ACKNOWLEDGMENT', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.SizedBox(height: 4),
              pw.Text(
                'The equipment return and final financial settlement have been inspected and verified as shown above. Please retain this settlement receipt for your records.',
                style: pw.TextStyle(fontSize: 8.5, color: _muted),
              ),

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColor.fromHex('#9EACB9')),
                      pw.SizedBox(height: 4),
                      pw.Text('For ${store.businessName}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                      pw.Text('Authorized signature / store stamp', style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColor.fromHex('#9EACB9')),
                      pw.SizedBox(height: 4),
                      pw.Text('Customer acceptance', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                      pw.Text('Customer signature', style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/settlement_receipt_${lease.shortId}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Direct share intent for WhatsApp or Email
  Future<void> shareReceipt(File file, String text) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: text,
        subject: 'Rental Receipt',
      ),
    );
  }

  /// Print or preview PDF
  Future<void> printReceipt(File file) async {
    final bytes = await file.readAsBytes();
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }
}
