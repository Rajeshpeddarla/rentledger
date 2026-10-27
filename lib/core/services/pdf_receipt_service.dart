import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';

class PdfReceiptService {
  static final PdfReceiptService instance = PdfReceiptService._internal();
  PdfReceiptService._internal();

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

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
    // Fallback to standard ASCII text if offline so no missing glyph box (rectangle-X) is shown
    return (store.currencySymbol == '₹') ? 'Rs. ' : store.currencySymbol;
  }

  /// Generates Handover & Deposit Receipt PDF for Lend/Dispatch
  Future<File> generateHandoverReceipt({
    required StoreModel store,
    required LeaseModel lease,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);
    final isPro = store.isPro;

    pdf.addPage(
      pw.Page(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        store.businessName,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#006948'),
                        ),
                      ),
                      if (store.phone != null && store.phone!.isNotEmpty)
                        pw.Text('Phone: ${store.phone}', style: const pw.TextStyle(fontSize: 10)),
                      if (store.email != null && store.email!.isNotEmpty)
                        pw.Text('Email: ${store.email}', style: const pw.TextStyle(fontSize: 10)),
                      if (store.address != null && store.address!.isNotEmpty)
                        pw.Text('Address: ${store.address}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#EFF4FF'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1')),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'HANDOVER RECEIPT',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#0F172A'),
                          ),
                        ),
                        pw.Text(
                          'Lease #${lease.shortId}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColor.fromHex('#565E74'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
              pw.SizedBox(height: 12),

              // Customer & Dates
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F8F9FF'),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('CUSTOMER DETAILS',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#565E74'))),
                          pw.SizedBox(height: 4),
                          pw.Text(lease.customer?.name ?? 'Customer',
                              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                          pw.Text(lease.customer?.phone ?? '-', style: const pw.TextStyle(fontSize: 10)),
                          if (lease.customer?.email != null)
                            pw.Text(lease.customer!.email!, style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F8F9FF'),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('RENTAL TIMELINE',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#565E74'))),
                          pw.SizedBox(height: 4),
                          pw.Text('Start: ${_dateFormat.format(lease.startTime)}', style: const pw.TextStyle(fontSize: 10)),
                          pw.Text('Expected Return: ${_dateFormat.format(lease.expectedEndTime)}',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#825100'))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Item Details
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('LEASED ITEM',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#565E74'))),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(lease.item?.name ?? 'Equipment Item',
                            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text(
                          '$currency${lease.item?.rateDaily.toStringAsFixed(2) ?? 0} / day',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#006948')),
                        ),
                      ],
                    ),
                    if (lease.item?.description != null)
                      pw.Text(lease.item!.description!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Financial Handover Table
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Table(
                  border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'))),
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F1F5F9')),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Financial Item', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Status', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Amount',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Security Deposit Expected', style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Standard Collateral', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${lease.depositExpected.toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Security Deposit Paid Now',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(lease.depositPaymentType.toUpperCase(),
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#006948'))),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${lease.depositPaid.toStringAsFixed(2)}',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#006948')),
                              textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    if (lease.advanceRentPaid > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Advance Rent Paid', style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Credited to final return', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$currency${lease.advanceRentPaid.toStringAsFixed(2)}',
                                style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Terms & Conditions
              pw.Text('TERMS & CONDITIONS',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#565E74'))),
              pw.SizedBox(height: 4),
              pw.Text(
                store.termsAndConditions.length > 300
                    ? '${store.termsAndConditions.substring(0, 300)}...'
                    : store.termsAndConditions,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Store Authorized Signature', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Customer Acceptance Signature', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Watermark / Branding footer
              pw.Center(
                child: pw.Text(
                  isPro
                      ? 'OFFICIAL RENTAL CERTIFICATE • ${store.businessName}'
                      : 'Managed with RentLedger • Equipment & Deposit Rental Manager',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: isPro ? PdfColor.fromHex('#006948') : PdfColors.grey600,
                    fontWeight: isPro ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
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

  /// Generates Return & Settlement Receipt PDF for Take Back
  Future<File> generateReturnSettlementReceipt({
    required StoreModel store,
    required LeaseModel lease,
  }) async {
    final pdfTheme = await _loadPdfTheme();
    final pdf = pw.Document(theme: pdfTheme);
    final currency = _resolveCurrency(store, pdfTheme);
    final isPro = store.isPro;
    final returnTime = lease.actualReturnTime ?? DateTime.now();

    pdf.addPage(
      pw.Page(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final isCollect = lease.finalSettlementBalance > 0;
          final isRefund = lease.finalSettlementBalance < 0;

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        store.businessName,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#006948'),
                        ),
                      ),
                      if (store.phone != null) pw.Text('Phone: ${store.phone}', style: const pw.TextStyle(fontSize: 10)),
                      if (store.address != null) pw.Text('Address: ${store.address}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#ECFDF5'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#A7F3D0')),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'SETTLEMENT RECEIPT',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#006948'),
                          ),
                        ),
                        pw.Text(
                          'Lease #${lease.shortId}',
                          style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#565E74')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
              pw.SizedBox(height: 12),

              // Customer & Inspection Banner
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('Customer: ${lease.customer?.name ?? "Customer"} (${lease.customer?.phone ?? "-"})',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#EFF4FF'),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text('Inspection Passed • Item Released',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#006948'))),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Handed out: ${_dateFormat.format(lease.startTime)}  |  Returned: ${_dateFormat.format(returnTime)}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 16),

              // Smart Ledger Table
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Table(
                  border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'))),
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F1F5F9')),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Ledger Breakdown', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Amount',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Gross Calculated Rent (${lease.billingUnitUsed})', style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${lease.calculatedRent.toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    if (lease.discountAmount > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Discount / Voucher Applied',
                                style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#006948'))),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('-$currency${lease.discountAmount.toStringAsFixed(2)}',
                                style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#006948')),
                                textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    if (lease.damageOrLateFee > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Damage / Overdue Fee',
                                style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#BA1A1A'))),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('+$currency${lease.damageOrLateFee.toStringAsFixed(2)}',
                                style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#BA1A1A')),
                                textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC')),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Net Rent Total Due',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$currency${lease.netRentTotal.toStringAsFixed(2)}',
                              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                    if (lease.depositPaid > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Less: Security Deposit Paid', style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('-$currency${lease.depositPaid.toStringAsFixed(2)}',
                                style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                    if (lease.advanceRentPaid > 0)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('Less: Advance Rent Paid at Handover', style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('-$currency${lease.advanceRentPaid.toStringAsFixed(2)}',
                                style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Final Settlement Card
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: isCollect
                      ? PdfColor.fromHex('#FEF2F2')
                      : (isRefund ? PdfColor.fromHex('#ECFDF5') : PdfColor.fromHex('#EFF4FF')),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                    color: isCollect
                        ? PdfColor.fromHex('#FECACA')
                        : (isRefund ? PdfColor.fromHex('#A7F3D0') : PdfColor.fromHex('#CBD5E1')),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          isCollect
                              ? 'FINAL AMOUNT COLLECTED'
                              : (isRefund ? 'DEPOSIT REFUNDED TO CLIENT' : 'FULLY SETTLED'),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: isCollect
                                ? PdfColor.fromHex('#991B1B')
                                : (isRefund ? PdfColor.fromHex('#065F46') : PdfColor.fromHex('#1E293B')),
                          ),
                        ),
                        pw.Text(
                          isCollect
                              ? 'Rent exceeded deposit held'
                              : (isRefund ? 'Deposit refunded after deducting rent' : 'Net zero balance'),
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Text(
                      '$currency${lease.finalSettlementBalance.abs().toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: isCollect
                            ? PdfColor.fromHex('#991B1B')
                            : (isRefund ? PdfColor.fromHex('#065F46') : PdfColor.fromHex('#1E293B')),
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Store Sign & Stamp', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Customer Acknowledgment', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Watermark / Branding footer
              pw.Center(
                child: pw.Text(
                  isPro
                      ? 'OFFICIAL SETTLEMENT RECORD • ${store.businessName}'
                      : 'Managed with RentLedger • Equipment & Deposit Rental Manager',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: isPro ? PdfColor.fromHex('#006948') : PdfColors.grey600,
                    fontWeight: isPro ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
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
