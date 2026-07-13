import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../../core/network/api_client.dart';
import '../../../presentation/providers/wallet_provider.dart';
import '../../../presentation/providers/payment_settings_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import '../../../presentation/widgets/common/inputs.dart';

/// Deposit Screen
class DepositScreen extends ConsumerStatefulWidget {
  final String userId;

  const DepositScreen({super.key, required this.userId});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedPaymentMethod = 'bank_transfer';
  bool _isProcessing = false;
  File? _proofFile;
  bool _isUploadingProof = false;
  String? _proofUrl;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(paymentSettingsProvider.notifier).loadFromApi();
    });
  }

  final List<Map<String, dynamic>> _paymentMethods = [
    {'value': 'bank_transfer', 'label': 'Bank Transfer', 'icon': Icons.account_balance},
    {'value': 'card', 'label': 'Debit Card', 'icon': Icons.credit_card},
    {'value': 'ussd', 'label': 'USSD', 'icon': Icons.phone_android},
  ];

  Future<void> _pickProofImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _proofFile = File(picked.path);
          _proofUrl = null; // reset previously uploaded URL
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e'), backgroundColor: CoopvestColors.error),
        );
      }
    }
  }

  void _showProofSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Upload Transfer Proof', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: _proofSourceTile(ctx, Icons.camera_alt, 'Camera', () => _pickProofImage(ImageSource.camera)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _proofSourceTile(ctx, Icons.photo_library, 'Gallery', () => _pickProofImage(ImageSource.gallery)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proofSourceTile(BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CoopvestColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(icon, size: 36, color: CoopvestColors.primary),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary)),
        ]),
      ),
    );
  }

  Widget _buildProofPicker(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Proof of Payment', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: CoopvestColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Recommended', style: TextStyle(fontSize: 10, color: CoopvestColors.success, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Attach a screenshot of your bank transfer receipt to speed up verification.',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _showProofSourceSheet,
            child: Container(
              width: double.infinity,
              padding: _proofFile != null ? EdgeInsets.zero : const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _proofFile != null ? CoopvestColors.success : context.dividerColor,
                  width: _proofFile != null ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: _proofFile != null
                    ? CoopvestColors.success.withOpacity(0.04)
                    : context.cardBackground,
              ),
              child: _proofFile != null
                  ? Column(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                          child: Image.file(
                            _proofFile!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: CoopvestColors.success, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _proofFile!.path.split('/').last,
                                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() { _proofFile = null; _proofUrl = null; }),
                                child: Icon(Icons.close, size: 18, color: context.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(children: [
                      Icon(Icons.upload_file, size: 40, color: context.textSecondary.withOpacity(0.5)),
                      const SizedBox(height: 8),
                      Text('Tap to attach receipt', style: TextStyle(color: context.textSecondary)),
                      const SizedBox(height: 4),
                      Text('JPG or PNG, max 10 MB', style: TextStyle(fontSize: 11, color: context.textSecondary.withOpacity(0.6))),
                    ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processDeposit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isProcessing = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));

      // Upload proof image if user attached one
      String? proofUrl = _proofUrl;
      if (_proofFile != null && proofUrl == null) {
        setState(() { _isUploadingProof = true; });
        try {
          final apiClient = ref.read(apiClientProvider);
          final formData = FormData.fromMap({
            'proof': await MultipartFile.fromFile(_proofFile!.path, filename: _proofFile!.path.split('/').last),
          });
          final uploadResp = await apiClient.dio.post('/wallet/upload-proof', data: formData);
          if (uploadResp.data['success'] == true) {
            proofUrl = uploadResp.data['url'] as String?;
          }
        } catch (uploadErr) {
          // Non-fatal: continue deposit without proof
        } finally {
          setState(() { _isUploadingProof = false; });
        }
      }

      final result = await ref.read(walletProvider.notifier).makeContribution(
        amount: amount,
        description: 'Wallet deposit via ${_selectedPaymentMethod.replaceAll('_', ' ')}',
        proofUrl: proofUrl,
      );
      
      // Safely extract the message from the result
      String message = 'Your deposit is pending verification.';
      if (result != null && result['message'] != null) {
        final msgValue = result['message'];
        if (msgValue is String) {
          message = msgValue;
        } else if (msgValue is Map) {
          message = msgValue.toString();
        }
      }
      
      _showPendingDialog(message);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deposit failed: $e'), backgroundColor: CoopvestColors.error),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: CoopvestColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showPendingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.cardBackground,
        title: Row(
          children: [
            const Icon(Icons.hourglass_empty, color: CoopvestColors.warning),
            const SizedBox(width: 8),
            Text('Pending Verification', style: TextStyle(color: context.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your deposit of ₦${_amountController.text} has been submitted for verification.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CoopvestColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: CoopvestColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: CoopvestColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedPaymentMethod == 'bank_transfer') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CoopvestColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Please transfer the exact amount to the Opay account and include your registered name as the narration. Your deposit will be verified by an admin.',
                  style: TextStyle(color: CoopvestColors.primary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _goBack() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Widget _buildBankTransferDetails(BuildContext context) {
    final account = ref.watch(paymentSettingsProvider);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CoopvestColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CoopvestColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance, color: CoopvestColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Bank Transfer Details',
                style: TextStyle(
                  color: CoopvestColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            label: 'Bank',
            value: account.bank,
            canCopy: false,
          ),
          const SizedBox(height: 10),
          _buildDetailRow(
            context,
            label: 'Account Name',
            value: account.accountName,
            canCopy: true,
          ),
          const SizedBox(height: 10),
          _buildDetailRow(
            context,
            label: 'Account Number',
            value: account.accountNumber,
            canCopy: true,
            isHighlighted: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CoopvestColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: CoopvestColors.warning, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transfer the exact amount and use your registered name as the narration. Account details are subject to change.',
                    style: TextStyle(color: CoopvestColors.warning, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    required bool canCopy,
    bool isHighlighted = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isHighlighted ? CoopvestColors.primary : context.textPrimary,
              fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
              fontSize: isHighlighted ? 16 : 13,
              letterSpacing: isHighlighted ? 1.5 : 0,
            ),
          ),
        ),
        if (canCopy)
          GestureDetector(
            onTap: () => _copyToClipboard(value, label),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.copy, color: CoopvestColors.primary, size: 16),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: _goBack,
        ),
        title: Text(
          'Deposit Funds',
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Amount',
                  hint: 'Enter deposit amount',
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  prefixText: '₦ ',
                  onChanged: (value) => setState(() {}),
                ),

                const SizedBox(height: 24),

                Text('Quick Select:', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [1000, 5000, 10000, 25000, 50000, 100000].map((amount) {
                    return GestureDetector(
                      onTap: () {
                        _amountController.text = amount.toString();
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.dividerColor),
                        ),
                        child: Text('₦${amount.formatNumber()}', style: TextStyle(color: context.textPrimary)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                const SizedBox(height: 12),

                Column(
                  children: _paymentMethods.map((method) {
                    final isSelected = _selectedPaymentMethod == method['value'];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedPaymentMethod = method['value'] as String),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected ? CoopvestColors.primary.withOpacity(0.1) : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? CoopvestColors.primary : context.dividerColor,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (method['icon'] as IconData?) ?? Icons.payment,
                              color: isSelected ? CoopvestColors.primary : context.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                method['label'] as String,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: CoopvestColors.primary),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Bank transfer details panel
                if (_selectedPaymentMethod == 'bank_transfer')
                  _buildBankTransferDetails(context),

                // Proof of payment (bank transfer only)
                if (_selectedPaymentMethod == 'bank_transfer')
                  _buildProofPicker(context),

                const SizedBox(height: 24),

                AppCard(
                  backgroundColor: CoopvestColors.info.withOpacity(0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: CoopvestColors.info),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedPaymentMethod == 'bank_transfer'
                              ? 'After transferring, submit this form and your wallet will be credited once payment is confirmed.'
                              : 'Deposits are processed instantly. Bank transfers may take 1-2 minutes to reflect.',
                          style: TextStyle(color: context.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                _isProcessing
                    ? Column(children: [
                        const Center(child: CircularProgressIndicator(color: CoopvestColors.primary)),
                        if (_isUploadingProof) ...[
                          const SizedBox(height: 8),
                          Text('Uploading proof...', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                        ],
                      ])
                    : PrimaryButton(
                        label: 'Deposit ₦${_amountController.text.isEmpty ? '0' : _amountController.text}',
                        onPressed: _processDeposit,
                        width: double.infinity,
                      ),

                const SizedBox(height: 16),
                SecondaryButton(
                  label: 'Go Back',
                  onPressed: _goBack,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
