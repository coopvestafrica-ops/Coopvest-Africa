import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../data/models/wallet_models.dart';
import '../../../presentation/providers/wallet_provider.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import '../../../core/services/logger_service.dart';

/// Statement Download Screen - Allows users to download their account statements
class StatementDownloadScreen extends ConsumerStatefulWidget {
  const StatementDownloadScreen({super.key});

  @override
  ConsumerState<StatementDownloadScreen> createState() => _StatementDownloadScreenState();
}

class _StatementDownloadScreenState extends ConsumerState<StatementDownloadScreen> {
  final LoggerService _logger = LoggerService();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isGenerating = false;
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  final List<Map<String, dynamic>> _statementTypes = [
    {'type': 'all', 'label': 'Complete Statement', 'icon': Icons.description_outlined},
    {'type': 'contributions', 'label': 'Contributions Only', 'icon': Icons.savings_outlined},
    {'type': 'loans', 'label': 'Loans Only', 'icon': Icons.monetization_on_outlined},
    {'type': 'transactions', 'label': 'Transactions Only', 'icon': Icons.swap_horiz_outlined},
  ];

  String _selectedType = 'all';

  String _capitalizeString(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: CoopvestColors.primary,
              onPrimary: Colors.white,
              surface: context.scaffoldBackground,
              onSurface: context.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _startDateController.text = DateFormat('MMM dd, yyyy').format(picked);
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: CoopvestColors.primary,
              onPrimary: Colors.white,
              surface: context.scaffoldBackground,
              onSurface: context.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _endDateController.text = DateFormat('MMM dd, yyyy').format(picked);
      });
    }
  }

  Future<void> _loadTransactions() async {
    try {
      await ref.read(walletProvider.notifier).loadTransactions(pageSize: 100);
    } catch (e) {
      logger.e('Load transactions error: $e');
    }
  }

  List<Transaction> _prepareStatementTransactions(
    List<Transaction> transactions,
    String statementType,
    DateTime startDate,
    DateTime endDate,
  ) {
    final rangeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final rangeEnd = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));
    final normalizedType = statementType.toLowerCase();

    final filtered = transactions.where((transaction) {
      final createdAt = transaction.createdAt.toLocal();
      final inDateRange = !createdAt.isBefore(rangeStart) && createdAt.isBefore(rangeEnd);
      final isCompleted = transaction.status.toLowerCase() == 'completed';
      if (!inDateRange || !isCompleted) return false;

      final type = transaction.type.toLowerCase();
      final description = (transaction.description ?? '').toLowerCase();
      switch (normalizedType) {
        case 'contributions':
          return type.contains('contribution') || description.contains('contribution');
        case 'loans':
          return type.contains('loan') || description.contains('loan');
        case 'transactions':
        case 'all':
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return filtered;
  }

  Future<void> _generateAndDownloadStatement() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date range'),
          backgroundColor: CoopvestColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      // First load real transactions from the API
      await _loadTransactions();
      
      final walletState = ref.read(walletProvider);
      final user = ref.read(currentUserProvider);
      
      // Get transactions - this should now have real data
      final transactions = walletState.transactions;

      // Include only completed transactions in the selected period and type,
      // sorted newest first for a predictable statement order.
      final filteredTransactions = _prepareStatementTransactions(
        transactions,
        _selectedType,
        _startDate!,
        _endDate!,
      );

      // Generate PDF
      final pdf = await _createPdf(
        user: user,
        transactions: filteredTransactions,
        wallet: walletState.wallet,
        startDate: _startDate!,
        endDate: _endDate!,
        statementType: _selectedType,
      );

      // Save and open the PDF
      final output = await getTemporaryDirectory();
      final fileName = 'CoopV_Statement_${DateFormat('yyyyMMdd').format(_startDate!)}_to_${DateFormat('yyyyMMdd').format(_endDate!)}.pdf';
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      // Show success and open file
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Statement downloaded: $fileName'),
            backgroundColor: CoopvestColors.success,
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => OpenFile.open(file.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating statement: $e'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<pw.Document> _createPdf({
    required dynamic user,
    required List<Transaction> transactions,
    required Wallet? wallet,
    required DateTime startDate,
    required DateTime endDate,
    required String statementType,
  }) async {
    final pdf = pw.Document();

    // Load the new CoopVest C/V brand icon for the statement header.
    final ByteData logoData = await rootBundle.load('assets/images/statement-logo.png');
    final Uint8List logoBytes = logoData.buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);
    final ByteData watermarkData = await rootBundle.load('assets/images/watermark-logo.png');
    final pw.MemoryImage watermarkImage = pw.MemoryImage(watermarkData.buffer.asUint8List());
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Center(
              child: pw.Opacity(
                opacity: 0.045,
                child: pw.Image(
                  watermarkImage,
                  width: 300,
                  height: 300,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        footer: (context) => _buildPdfPageFooter(context),
        build: (context) => [
          // Header with Logo
          _buildPdfHeader(logoImage, user, startDate, endDate),
          pw.SizedBox(height: 20),
          // Account Summary
          _buildPdfAccountSummary(wallet, transactions),
          pw.SizedBox(height: 20),
          // Statement Type Header
          _buildPdfStatementType(statementType),
          pw.SizedBox(height: 10),
          // Transactions table repeats its header automatically across pages.
          _buildPdfTransactions(transactions),
          // Summary Footer
          _buildPdfSummary(transactions, wallet),
        ],
      ),
    );

    return pdf;
  }

  // Footer for each page
  pw.Widget _buildPdfPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Coopvest Africa - Empowering Cooperative Finance',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfHeader(pw.MemoryImage logoImage, dynamic user, DateTime startDate, DateTime endDate) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Logo and Title Row
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [PdfColors.green800, PdfColors.green600],
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
            ),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 124,
                height: 78,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'COOPVEST AFRICA',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    pw.Text(
                      'Member Account Statement',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Container(
                width: 108,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0x33FFFFFF),
                  borderRadius: pw.BorderRadius.circular(20),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Statement Date',
                      maxLines: 1,
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
                    ),
                    pw.Text(
                      DateFormat('MMM dd, yyyy').format(DateTime.now()),
                      maxLines: 1,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        // Member Info Card
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            borderRadius: pw.BorderRadius.circular(12),
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text('Member Information', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(user?.name ?? 'Member', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text(user?.email ?? '', style: const pw.TextStyle(fontSize: 10)),
                    if (user?.phone != null) pw.Text(user?.phone ?? '', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.Container(
                width: 1,
                height: 60,
                color: PdfColors.grey300,
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text('Statement Period', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(DateFormat('MMMM dd, yyyy').format(startDate),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('to', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(DateFormat('MMMM dd, yyyy').format(endDate),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.Container(
                width: 1,
                height: 60,
                color: PdfColors.grey300,
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text('Generated On', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(DateFormat('EEEE').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(DateFormat('hh:mm a').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfAccountSummary(Wallet? wallet, List<Transaction> transactions) {
    final totalCredits = transactions
        .where((transaction) => transaction.isCredit)
        .fold<double>(0, (sum, transaction) => sum + transaction.amount.abs());
    final totalDebits = transactions
        .where((transaction) => !transaction.isCredit)
        .fold<double>(0, (sum, transaction) => sum + transaction.amount.abs());
    final closingBalance = wallet?.balance ?? 0;
    final openingBalance = closingBalance - totalCredits + totalDebits;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildPdfStatItem('Opening Balance', 'NGN ${openingBalance.formatNumber()}', false),
          _buildPdfStatItem('Closing Balance', 'NGN ${closingBalance.formatNumber()}', true),
          _buildPdfStatItem('Available Withdrawal', 'NGN ${(wallet?.availableForWithdrawal ?? 0).formatNumber()}', false),
        ],
      ),
    );
  }

  pw.Widget _buildPdfStatItem(String label, String value, bool isPrimary) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: isPrimary ? PdfColor.fromInt(CoopvestColors.primary.value) : PdfColors.black,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfStatementType(String type) {
    String typeLabel = 'Complete Account Statement';
    switch (type) {
      case 'contributions':
        typeLabel = 'Contributions Statement';
        break;
      case 'loans':
        typeLabel = 'Loans Statement';
        break;
      case 'transactions':
        typeLabel = 'Transaction History';
        break;
    }
    return pw.Text(
      typeLabel,
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromInt(CoopvestColors.primary.value),
      ),
    );
  }

  pw.Widget _buildPdfTransactions(List<Transaction> transactions) {
    if (transactions.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(20),
        child: pw.Center(
          child: pw.Text(
            'No completed transactions found for this period',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
          ),
        ),
      );
    }

    final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey800,
    );

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4), child: pw.Text('Date', style: headerStyle)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4), child: pw.Text('Description', style: headerStyle)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4), child: pw.Text('Type', style: headerStyle)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4), child: pw.Text('Amount (NGN)', style: headerStyle, textAlign: pw.TextAlign.right)),
          ],
        ),
        ...transactions.map((txn) {
          final isCredit = txn.isCredit;
          final absoluteAmount = txn.amount.abs();
          final amount = '${isCredit ? '+' : '-'}NGN ${absoluteAmount.formatNumber()}';
          return pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: pw.Text(DateFormat('MMM dd, yyyy').format(txn.createdAt.toLocal()), style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: pw.Text(txn.description ?? _capitalizeString(txn.type.replaceAll('_', ' ')), style: const pw.TextStyle(fontSize: 9), maxLines: 2)),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: pw.Text(_capitalizeString(txn.type.replaceAll('_', ' ')), style: const pw.TextStyle(fontSize: 9), maxLines: 2)),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: pw.Text(
                  amount,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: isCredit ? PdfColors.green700 : PdfColors.red700),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildPdfSummary(List<Transaction> transactions, Wallet? wallet) {
    // Calculate totals based on actual transaction amounts
    double totalCredits = 0.0;
    double totalDebits = 0.0;
    
    for (final t in transactions) {
      if (t.isCredit) {
        totalCredits += t.amount.abs();
      } else {
        totalDebits += t.amount.abs();
      }
    }
    
    // Net change: Credits minus Debits
    final netChange = totalCredits - totalDebits;

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildPdfSummaryItem('Total Deposits', totalCredits, true),
          _buildPdfSummaryItem('Total Withdrawals', totalDebits, false),
          _buildPdfSummaryItem('Net Change', netChange, netChange >= 0),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryItem(String label, double amount, bool isPositive) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Text(
          'NGN ${amount.formatNumber()}',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: amount >= 0 ? PdfColors.green700 : PdfColors.red700,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final transactions = walletState.transactions;

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Download Statement'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: context.iconPrimary),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: context.cardBackground,
                  title: Text('Statement Help', style: TextStyle(color: context.textPrimary)),
                  content: Text(
                    'Generate and download your account statement as a PDF file.\n\n'
                    '1. Select a date range for the statement\n'
                    '2. Choose the type of transactions to include\n'
                    '3. Tap Download to generate and save the PDF\n\n'
                    'The statement will include:\n'
                    '- Your account summary\n'
                    '- All transactions within the selected period\n'
                    '- Total credits and debits\n\n'
                    'Note: PDF generation requires storage permission.',
                    style: TextStyle(color: context.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Range Selection
            Text(
              'Select Date Range',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    child: InkWell(
                      onTap: () => _selectStartDate(context),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: CoopvestColors.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'From Date',
                                    style: TextStyle(fontSize: 10, color: context.textSecondary),
                                  ),
                                  Text(
                                    _startDateController.text.isEmpty ? 'Select date' : _startDateController.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _startDateController.text.isEmpty ? context.textSecondary : context.textPrimary,
                                      fontWeight: _startDateController.text.isEmpty ? FontWeight.normal : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppCard(
                    child: InkWell(
                      onTap: () => _selectEndDate(context),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: CoopvestColors.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'To Date',
                                    style: TextStyle(fontSize: 10, color: context.textSecondary),
                                  ),
                                  Text(
                                    _endDateController.text.isEmpty ? 'Select date' : _endDateController.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _endDateController.text.isEmpty ? context.textSecondary : context.textPrimary,
                                      fontWeight: _endDateController.text.isEmpty ? FontWeight.normal : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Statement Type Selection
            Text(
              'Statement Type',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ..._statementTypes.map((type) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    child: RadioListTile<String>(
                      value: type['type'] as String,
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value!;
                        });
                      },
                      secondary: Icon(type['icon'] as IconData, color: CoopvestColors.primary),
                      title: Text(
                        type['label'] as String,
                        style: TextStyle(color: context.textPrimary),
                      ),
                      activeColor: CoopvestColors.primary,
                    ),
                  ),
                )).toList(),
            const SizedBox(height: 24),

            // Preview Section
            if (_startDate != null && _endDate != null) ...[
              Text(
                'Preview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Transactions in range:', style: TextStyle(color: context.textSecondary)),
                          Text(
                            '${transactions.where((t) => t.createdAt.isAfter(_startDate!.subtract(const Duration(days: 1))) && t.createdAt.isBefore(_endDate!.add(const Duration(days: 1)))).length}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Date range:', style: TextStyle(color: context.textSecondary)),
                          Text(
                            '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Download Button
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                onPressed: _isGenerating ? () async {} : _generateAndDownloadStatement,
                isLoading: _isGenerating,
                icon: const Icon(Icons.download_outlined),
                label: _isGenerating
                    ? 'Generating PDF...'
                    : 'Download Statement (PDF)',
              ),
            ),

            const SizedBox(height: 16),

            // Alternative: Share Option
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isGenerating
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Use the Download button to generate a PDF statement'),
                            backgroundColor: CoopvestColors.primary,
                          ),
                        );
                      },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share Statement'),
              ),
            ),

            const SizedBox(height: 24),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CoopvestColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CoopvestColors.info.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: CoopvestColors.info, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Statements are generated as PDF files. You can open them in any PDF reader app.',
                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}