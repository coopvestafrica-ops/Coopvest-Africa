import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/widgets/common/cards.dart';
import 'guarantor_verification_screen.dart';

/// QR Scanner Screen
///
/// Scans a loan QR code, fetches real loan details from the backend,
/// then opens GuarantorVerificationScreen with actual borrower data.
class QRScannerScreen extends ConsumerStatefulWidget {
  final String guarantorId;
  final String guarantorName;

  const QRScannerScreen({
    super.key,
    required this.guarantorId,
    required this.guarantorName,
  });

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  // An explicit controller ensures detection reliably starts with the screen
  // and is properly released on dispose. noDuplicates avoids re-firing on the
  // same code every frame.
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;
  bool _isProcessing = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture barcodes) {
    if (_hasScanned || _isProcessing) return;
    for (final barcode in barcodes.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        setState(() { _hasScanned = true; });
        _processScannedQR(raw);
        break;
      }
    }
  }

  Future<void> _processScannedQR(String rawValue) async {
    setState(() { _isProcessing = true; _errorMessage = ''; });
    try {
      // Trim whitespace from the raw scan value first
      final cleanRawValue = rawValue.trim();

      // Parse the QR code - supports both JSON and pipe-separated format
      late final String qrId;
      late final String loanId;
      late final String borrowerName;
      late final double loanAmount;
      late final String loanType;
      late final int loanTenor;

      // Try JSON format first (from backend)
      try {
        final Map<String, dynamic> qrData = json.decode(cleanRawValue) as Map<String, dynamic>;
        qrId  = (qrData['qrId']  as String? ?? '').trim();
        loanId = (qrData['loanId'] as String? ?? '').trim();
        borrowerName = (qrData['borrowerName'] as String?) ?? 
                       (qrData['applicantName'] as String?) ?? 'Coopvest Member';
        loanAmount = ((qrData['loanAmount'] as num?)?.toDouble()) ?? 
                     ((qrData['amount'] as num?)?.toDouble()) ?? 0.0;
        loanType = (qrData['loanType'] as String?) ?? 
                   (qrData['type'] as String?) ?? 'Quick Loan';
        loanTenor = (qrData['loanTenure'] as int?) ?? 
                    (qrData['tenor'] as int?) ?? 12;
      } catch (_) {
        // Try pipe-separated format: COOPVEST_LOAN|loanId|type|amount|name|phone|status
        if (cleanRawValue.startsWith('COOPVEST_LOAN|')) {
          final parts = cleanRawValue.split('|');
          if (parts.length >= 6) {
            loanId = parts[1].trim();
            qrId = loanId;
            loanType = parts[2].trim();
            // Remove currency symbol if present
            final amountStr = parts[3].replaceAll(RegExp(r'[^\d.]'), '');
            loanAmount = double.tryParse(amountStr) ?? 0.0;
            borrowerName = parts[4].trim();
            loanTenor = 12; // Default tenor
          } else {
            throw Exception('Invalid QR code format');
          }
        } else {
          // Fallback: treat rawValue as a bare qrId/loanId
          qrId  = cleanRawValue;
          loanId = cleanRawValue;
          borrowerName = 'Coopvest Member';
          loanAmount = 0.0;
          loanType = 'Quick Loan';
          loanTenor = 12;
        }
      }

      // Guard against using a raw value as a qrId if it contains spaces (except for names) or is too long
      if (qrId.contains(' ') && !qrId.contains('|')) {
        setState(() {
          _errorMessage = 'Invalid QR code. Please scan a valid loan QR code.';
          _isProcessing = false;
          _hasScanned = false;
        });
        return;
      }

      if (qrId.isEmpty && loanId.isEmpty) {
        setState(() { _errorMessage = 'Invalid QR code format'; _isProcessing = false; _hasScanned = false; });
        return;
      }

      // Try to fetch real loan details from the backend
      final apiClient = ref.read(apiClientProvider);
      try {
        final encodedQrId = Uri.encodeComponent(qrId);
        final encodedLoanId = Uri.encodeComponent(loanId);
        final lookupPath = qrId.isNotEmpty ? '/loans/qr/$encodedQrId' : '/loans/$encodedLoanId';
        final response = await apiClient.dio.get(lookupPath);
        final data = response.data as Map<String, dynamic>;

        if (data['success'] == true) {
          if (data['isExpired'] == true) {
            setState(() { _errorMessage = 'This QR code has expired. Ask the borrower to generate a new one.'; _isProcessing = false; _hasScanned = false; });
            return;
          }

          // Use backend data if available
          if (mounted) {
            final authState = ref.read(authProvider);
            final userPhone = authState.user?.phone;
            
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => GuarantorVerificationScreen(
                  loanId:       (data['loanId']      as String?) ?? loanId,
                  borrowerName: (data['borrowerName'] as String?) ?? borrowerName,
                  loanAmount:   ((data['loanAmount']  as num?)?.toDouble()) ?? loanAmount,
                  loanType:     (data['loanType']     as String?) ?? loanType,
                  loanTenor:    (data['loanTenure']   as int?)    ?? loanTenor,
                  guarantorId:  widget.guarantorId,
                  guarantorName: widget.guarantorName,
                  guarantorPhone: userPhone,
                ),
              ),
            );
          }
          return;
        }
      } catch (_) {
        // Backend not available - continue with local QR data
        debugPrint('Backend not available, using local QR data');
      }

      // If backend fails, use the parsed local QR data
      if (mounted) {
        final authState = ref.read(authProvider);
        final userPhone = authState.user?.phone;
        
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => GuarantorVerificationScreen(
              loanId: loanId,
              borrowerName: borrowerName,
              loanAmount: loanAmount,
              loanType: loanType,
              loanTenor: loanTenor,
              guarantorId: widget.guarantorId,
              guarantorName: widget.guarantorName,
              guarantorPhone: userPhone,
            ),
          ),
        );
      }
    } catch (e) {
      String friendlyMessage = 'Error processing QR code: $e';
      if (e is DioException) {
        final response = e.response;
        if (response != null && response.data is Map) {
          final data = response.data as Map;
          friendlyMessage = data['error']?.toString() ?? 
                            data['message']?.toString() ?? 
                            'Invalid QR code or request details. Please try again.';
        } else {
          friendlyMessage = 'Unable to connect to the server. Please check your connection.';
        }
      } else {
        friendlyMessage = e.toString();
        if (friendlyMessage.startsWith('Exception: ')) {
          friendlyMessage = friendlyMessage.substring(11);
        }
      }
      setState(() {
        _errorMessage = friendlyMessage;
        _isProcessing = false;
        _hasScanned = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Scan Loan QR Code', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _handleBarcode,
                  // Surface camera/permission failures instead of showing a
                  // silent black preview.
                  errorBuilder: (context, exception, child) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Camera unavailable (${exception.errorCode}). '
                          'Please allow camera access for Coopvest in your device settings and try again.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: CoopvestColors.primary, width: 3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Position QR code within the frame',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black.withOpacity(0.8),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: CoopvestColors.primary),
                          SizedBox(height: 16),
                          Text('Fetching loan details...', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                if (_errorMessage.isNotEmpty)
                  Positioned(
                    bottom: 100,
                    left: 24,
                    right: 24,
                    child: AppCard(
                      backgroundColor: CoopvestColors.error.withOpacity(0.9),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_errorMessage, style: const TextStyle(color: Colors.white))),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() => _errorMessage = ''),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                AppCard(
                  backgroundColor: CoopvestColors.primary.withOpacity(0.2),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: CoopvestColors.primary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Scan a loan QR code to confirm your guarantee',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        'By scanning, you agree to be responsible for 1/3 of the loan amount if the borrower defaults.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Scanning as: ${widget.guarantorName}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
