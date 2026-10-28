import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/rate_calculator.dart';
import '../../data/models/lease_model.dart';
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
    } catch (_) {
      try {
        final baseFont = await PdfGoogleFonts.robotoRegular();
        final boldFont = await PdfGoogleFonts.robotoBold();
        return pw.ThemeData.withFont(base: baseFont, bold: boldFont);
      } catch (_) {
        return null;
      }
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

  /// Generates Handover & Deposit Receipt PDF matching Template 1
  Future<File> generateHandoverReceipt({
    required StoreModel store,
    required LeaseModel lease,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);

    final duration = lease.expectedEndTime.difference(lease.startTime);
    final durationText = _formatExactDuration(duration);

    final estimatedRent = lease.item != null
        ? RateCalculator.calculateReturnRent(
            startTime: lease.startTime,
            actualReturnTime: lease.expectedEndTime,
            rateHourly: lease.item!.rateHourly,
            rateDaily: lease.item!.rateDaily,
            rateWeekly: lease.item!.rateWeekly,
            rateMonthly: lease.item!.rateMonthly,
          )
        : 0.0;

    final depositOutstanding = (lease.depositExpected - lease.depositPaid) < 0
        ? 0.0
        : (lease.depositExpected - lease.depositPaid);

    String displayRateUnit = '/ day';
    double displayRate = lease.item?.rateDaily ?? 0.0;
    if (duration.inHours < 24 && (lease.item?.rateHourly ?? 0) > 0) {
      displayRateUnit = '/ hr';
      displayRate = lease.item!.rateHourly;
    }

    pdf.addPage(
      pw.Page(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
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
                          pw.Text(_dateOnlyFormat.format(lease.startTime), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
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
                          pw.Text('Branch: Main store', style: pw.TextStyle(fontSize: 10, color: _muted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Rented Item Table
              pw.Text('RENTED ITEM', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
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
                          child: pw.Text('Rate', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
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
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(_getLeaseItemDisplayName(lease), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy)),
                              pw.Text('Asset SKU: ${lease.item?.displaySku ?? "-"}', style: pw.TextStyle(fontSize: 9, color: _muted)),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${displayRate.toStringAsFixed(2)}\n$displayRateUnit', style: pw.TextStyle(fontSize: 10, color: _ink)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(durationText, style: pw.TextStyle(fontSize: 10, color: _ink), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${estimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F7FAFC')),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Estimated Rental Charges', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${estimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
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
                                    pw.Text('$currency${estimatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
                                    pw.Text('$currency${(estimatedRent - lease.advanceRentPaid).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
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
                                    pw.Text('$currency${lease.depositExpected.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
                                    pw.Text('$currency${depositOutstanding.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
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
                  'Deposit Status: $currency${lease.depositPaid.toStringAsFixed(2)} received out of $currency${lease.depositExpected.toStringAsFixed(2)} required. Remaining deposit: $currency${depositOutstanding.toStringAsFixed(2)}. Estimated rent is shown separately from the security deposit.',
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
              pw.SizedBox(height: 12),

              // Footer
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Generated on ${_dateFormat.format(DateTime.now())}', style: pw.TextStyle(fontSize: 8, color: _muted)),
                    pw.Text('Managed with RentLedger • Rental & Asset Management', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy2)),
                    pw.Text('Page 1 of 1', style: pw.TextStyle(fontSize: 8, color: _muted)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/handover_receipt_${lease.shortId}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generates Return & Settlement Receipt PDF for Take Back (Handles ALL scenarios: damaged or not, late fees or not, refund vs collection)
  Future<File> generateReturnSettlementReceipt({
    required StoreModel store,
    required LeaseModel lease,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);
    final returnTime = lease.actualReturnTime ?? DateTime.now();

    final duration = returnTime.difference(lease.startTime);
    final actualDurationText = _formatExactDuration(duration);

    final isCollect = lease.finalSettlementBalance > 0;
    final isRefund = lease.finalSettlementBalance < 0;

    // Determine Callout Banner Colors & Content matching Template 2
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
      pw.Page(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
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

              // Rental Charge Breakdown Table
              pw.Text('RENTAL CHARGE BREAKDOWN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
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
                          child: pw.Text('Description', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Calculation', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Amount', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Base rental charge', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Recorded duration: $actualDurationText', style: pw.TextStyle(fontSize: 9, color: _muted)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${lease.calculatedRent.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    if (lease.discountAmount > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Discount / Voucher (-)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Promotional coupon discount', style: pw.TextStyle(fontSize: 9, color: _muted)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('-$currency${lease.discountAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    if (lease.damageOrLateFee > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Damage / Overdue Fee (+)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Late return or inspection damage charges', style: pw.TextStyle(fontSize: 9, color: _muted)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('+$currency${lease.damageOrLateFee.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F7FAFC')),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Total Net Rental Charges', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navy)),
                        ),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${lease.netRentTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.right),
                        ),
                      ],
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
              pw.SizedBox(height: 12),

              // Footer
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Generated on ${_dateFormat.format(DateTime.now())}', style: pw.TextStyle(fontSize: 8, color: _muted)),
                    pw.Text('Managed with RentLedger • Rental & Asset Management', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy2)),
                    pw.Text('Page 1 of 1', style: pw.TextStyle(fontSize: 8, color: _muted)),
                  ],
                ),
              ),
            ],
          );
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
