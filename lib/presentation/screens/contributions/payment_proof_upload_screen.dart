import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/theme_config.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/payment_proof_model.dart';
import '../../widgets/common/buttons.dart';

/// Payment Proof Upload Screen
/// Allows members to submit proof of payment after making direct contributions
class PaymentProofUploadScreen extends ConsumerStatefulWidget {
  const PaymentProofUploadScreen({super.key});

  @override
  ConsumerState<PaymentProofUploadScreen> createState() => _PaymentProofUploadScreenState();
}

class _PaymentProofUploadScreenState extends ConsumerState<PaymentProofUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form Controllers
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();
  
  // State
  PaymentProofType? _selectedPaymentType;
  PaymentMethod? _selectedPaymentMethod;
  DateTime _selectedPaymentDate = DateTime.now();
  BankAccount? _selectedBankAccount;
  File? _selectedFile;
  String? _uploadedProofUrl;
  bool _isUploading = false;
  bool _isSubmitting = false;
  
  List<BankAccount> _bankAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadBankAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadBankAccounts() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final service = PaymentProofApiService(apiClient.dio);
      final accounts = await service.getAvailableBankAccounts();
      if (mounted) {
        setState(() {
          _bankAccounts = accounts;
          if (accounts.isNotEmpty) {
            _selectedBankAccount = accounts.first;
          }
        });
      }
    } catch (e) {
      // Use default bank accounts
      if (mounted) {
        setState(() {
          _bankAccounts = [
            const BankAccount(
              bankName: 'First Bank of Nigeria',
              accountName: 'Coopvest Africa Savings',
              accountNumber: '3085749012',
              bankCode: '011',
            ),
            const BankAccount(
              bankName: 'Guaranty Trust Bank',
              accountName: 'Coopvest Africa Microfinance',
              accountNumber: '0145689231',
              bankCode: '058',
            ),
          ];
          _selectedBankAccount = _bankAccounts.first;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedFile = File(pickedFile.path);
          _uploadedProofUrl = null;
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final service = PaymentProofApiService(apiClient.dio);
      
      final fileBytes = await _selectedFile!.readAsBytes();
      final filename = _selectedFile!.path.split('/').last;
      final mimeType = filename.toLowerCase().endsWith('.pdf') 
          ? 'application/pdf' 
          : 'image/jpeg';

      final result = await service.uploadProofFile(
        filename: filename,
        mimeType: mimeType,
        fileBytes: fileBytes,
      );

      setState(() {
        _uploadedProofUrl = result['proof_url'] as String;
        _isUploading = false;
      });

      _showSuccess('File uploaded successfully!');
    } catch (e) {
      setState(() => _isUploading = false);
      _showError('Failed to upload file: $e');
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedPaymentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedPaymentDate = picked);
    }
  }

  Future<void> _submitProof() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPaymentType == null) {
      _showError('Please select a payment type');
      return;
    }
    if (_selectedPaymentMethod == null) {
      _showError('Please select a payment method');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final service = PaymentProofApiService(apiClient.dio);

      await service.submitPaymentProof(
        paymentType: _selectedPaymentType!,
        amount: double.parse(_amountController.text.replaceAll(',', '')),
        paymentDate: _selectedPaymentDate,
        paymentMethod: _selectedPaymentMethod,
        receivingBank: _selectedBankAccount?.bankName,
        bankAccountName: _selectedBankAccount?.accountName,
        bankAccountNumber: _selectedBankAccount?.accountNumber,
        transactionReference: _referenceController.text.isNotEmpty 
            ? _referenceController.text 
            : null,
        proofUrl: _uploadedProofUrl,
        proofType: _uploadedProofUrl != null 
            ? (_selectedFile!.path.toLowerCase().endsWith('.pdf') ? 'pdf' : 'image')
            : null,
        originalFilename: _selectedFile?.path.split('/').last,
        fileSize: _selectedFile != null ? await _selectedFile!.length() : null,
        memberNote: _noteController.text.isNotEmpty ? _noteController.text : null,
      );

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to submit: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: CoopvestColors.success, size: 28),
            const SizedBox(width: 12),
            const Text('Submission Successful'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thank you! Your payment proof has been submitted successfully and is awaiting verification by the Coopvest Africa team.',
            ),
            SizedBox(height: 12),
            Text(
              'You will receive a notification once it has been reviewed.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, true);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CoopvestColors.error,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CoopvestColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Payment Proof'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Payment Type Selection
            _buildSectionTitle('Contribution Details'),
            _buildPaymentTypeSelector(),
            const SizedBox(height: 20),

            // Amount and Date
            Row(
              children: [
                Expanded(
                  child: _buildAmountField(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDateField(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Payment Method
            _buildSectionTitle('Payment Method'),
            _buildPaymentMethodSelector(),
            const SizedBox(height: 20),

            // Bank Account Selection
            _buildSectionTitle('Receiving Bank'),
            _buildBankAccountSelector(),
            const SizedBox(height: 20),

            // Transaction Reference
            _buildSectionTitle('Transaction Reference'),
            _buildReferenceField(),
            const SizedBox(height: 20),

            // Proof of Payment Upload
            _buildSectionTitle('Proof of Payment'),
            _buildProofUploader(),
            const SizedBox(height: 20),

            // Optional Note
            _buildSectionTitle('Additional Note (Optional)'),
            _buildNoteField(),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : PrimaryButton(
                      label: 'Submit Payment Proof',
                      onPressed: _submitProof,
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: CoopvestColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildPaymentTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PaymentProofType.values.map((type) {
        final isSelected = _selectedPaymentType == type;
        return ChoiceChip(
          label: Text(type.displayName),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedPaymentType = selected ? type : null;
            });
          },
          selectedColor: CoopvestColors.primary.withOpacity(0.2),
          labelStyle: TextStyle(
            color: isSelected ? CoopvestColors.primary : CoopvestColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d,]')),
      ],
      decoration: const InputDecoration(
        labelText: 'Amount (₦)',
        prefixText: '₦ ',
        hintText: '10,000',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Required';
        }
        final amount = double.tryParse(value.replaceAll(',', ''));
        if (amount == null || amount <= 0) {
          return 'Invalid amount';
        }
        return null;
      },
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _selectDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Payment Date',
          suffixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(
          '${_selectedPaymentDate.day}/${_selectedPaymentDate.month}/${_selectedPaymentDate.year}',
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PaymentMethod.values.map((method) {
        final isSelected = _selectedPaymentMethod == method;
        return ChoiceChip(
          label: Text(method.displayName),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedPaymentMethod = selected ? method : null;
            });
          },
          selectedColor: CoopvestColors.primary.withOpacity(0.2),
          labelStyle: TextStyle(
            color: isSelected ? CoopvestColors.primary : CoopvestColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBankAccountSelector() {
    return DropdownButtonFormField<BankAccount>(
      value: _selectedBankAccount,
      decoration: const InputDecoration(
        hintText: 'Select receiving bank',
      ),
      items: _bankAccounts.map((account) {
        return DropdownMenuItem<BankAccount>(
          value: account,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.bankName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${account.accountName} - ${account.accountNumber}',
                style: const TextStyle(
                  fontSize: 12,
                  color: CoopvestColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedBankAccount = value;
        });
      },
      validator: (value) {
        if (value == null) {
          return 'Please select a bank account';
        }
        return null;
      },
    );
  }

  Widget _buildReferenceField() {
    return TextFormField(
      controller: _referenceController,
      decoration: const InputDecoration(
        labelText: 'Transaction Reference',
        hintText: 'e.g., TRF123456789',
        helperText: 'Enter the reference number from your bank transfer',
      ),
    );
  }

  Widget _buildProofUploader() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: CoopvestColors.lightGray),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _selectedFile != null
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _selectedFile!.path.toLowerCase().endsWith('.pdf')
                            ? Icons.picture_as_pdf
                            : Icons.image,
                        color: CoopvestColors.primary,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFile!.path.split('/').last,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${(_selectedFile!.lengthSync() / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                color: CoopvestColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedFile = null;
                            _uploadedProofUrl = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                if (_uploadedProofUrl == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: _isUploading
                          ? const Center(child: CircularProgressIndicator())
                          : OutlinedButton.icon(
                              onPressed: _uploadFile,
                              icon: const Icon(Icons.cloud_upload),
                              label: const Text('Upload Proof'),
                            ),
                    ),
                  ),
              ],
            )
          : InkWell(
              onTap: _pickImage,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 48,
                      color: CoopvestColors.primary.withOpacity(0.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap to upload proof of payment',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: CoopvestColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'JPG, PNG or PDF (max 10MB)',
                      style: TextStyle(
                        fontSize: 12,
                        color: CoopvestColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      maxLines: 3,
      decoration: const InputDecoration(
        hintText: 'Add any additional information about this payment...',
      ),
    );
  }
}
