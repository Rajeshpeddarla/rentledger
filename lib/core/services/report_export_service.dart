import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';

class ReportExportService {
  static final ReportExportService instance = ReportExportService._internal();
  ReportExportService._internal();

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  /// Exports financial leases to CSV format
  Future<File> exportLeasesCsv({
    required StoreModel store,
    required List<LeaseModel> leases,
  }) async {
    final List<List<dynamic>> rows = [
      [
        'Lease ID',
        'Item Name',
        'Customer Name',
        'Customer Phone',
        'Status',
        'Start Time',
        'Expected Return Time',
        'Actual Return Time',
        'Deposit Expected (${store.currencySymbol})',
        'Deposit Paid (${store.currencySymbol})',
        'Advance Rent Paid (${store.currencySymbol})',
        'Calculated Rent (${store.currencySymbol})',
        'Discount (${store.currencySymbol})',
        'Damage / Late Fee (${store.currencySymbol})',
        'Net Rent Total (${store.currencySymbol})',
        'Final Settlement (${store.currencySymbol})',
      ]
    ];

    for (final l in leases) {
      rows.add([
        l.id,
        l.item?.name ?? 'Item',
        l.customer?.name ?? 'Customer',
        l.customer?.phone ?? '-',
        l.status,
        _dateFormat.format(l.startTime),
        _dateFormat.format(l.expectedEndTime),
        l.actualReturnTime != null ? _dateFormat.format(l.actualReturnTime!) : '-',
        l.depositExpected,
        l.depositPaid,
        l.advanceRentPaid,
        l.calculatedRent,
        l.discountAmount,
        l.damageOrLateFee,
        l.netRentTotal,
        l.finalSettlementBalance,
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/rentledger_financial_report_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvData);
    return file;
  }

  /// Exports financial summary PDF
  Future<File> exportSummaryPdf({
    required StoreModel store,
    required List<LeaseModel> leases,
    required double totalRevenue,
    required double totalDepositsHeld,
    required int activeLeasesCount,
    required int overdueCount,
  }) async {
    final pdf = pw.Document();
    final currency = store.currencySymbol;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        store.businessName,
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#006948')),
                      ),
                      pw.Text('Operations & Financial Report', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text('Generated: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
              pw.SizedBox(height: 16),

              // KPI Cards Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfKpiCard('Total Revenue', '$currency${totalRevenue.toStringAsFixed(2)}', '#006948'),
                  _buildPdfKpiCard('Deposits Held', '$currency${totalDepositsHeld.toStringAsFixed(2)}', '#0F172A'),
                  _buildPdfKpiCard('Active Leases', '$activeLeasesCount Active', '#565E74'),
                  _buildPdfKpiCard('Overdue', '$overdueCount Flagged', '#BA1A1A'),
                ],
              ),
              pw.SizedBox(height: 24),

              pw.Text('RECENT LEASE ACTIVITY',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0F172A'))),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'))),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F1F5F9')),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Item', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Customer', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Status', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Net Rent', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  ...leases.take(15).map(
                    (l) => pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(l.item?.name ?? 'Item', style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(l.customer?.name ?? 'Customer', style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(l.status.toUpperCase(), style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$currency${l.netRentTotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),
              pw.Center(
                child: pw.Text('RentLedger Business Intelligence Report • Confidential',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/rentledger_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  pw.Widget _buildPdfKpiCard(String label, String value, String hexColor) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8F9FF'),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex(hexColor)),
          ),
        ],
      ),
    );
  }

  Future<void> shareFile(File file, String text) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: text,
      ),
    );
  }
}
