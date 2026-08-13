import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../data/models/kyc_models.dart';
import '../../../presentation/providers/kyc_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/inputs.dart';

/// KYC Next of Kin Screen — collects next of kin details, aligned with the
/// registration onboarding flow. Pre-fills existing data and skips itself if
/// already complete.
class KYCNextOfKinScreen extends ConsumerStatefulWidget {
  const KYCNextOfKinScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KYCNextOfKinScreen> createState() =>
      _KYCNextOfKinScreenState();
}

class _KYCNextOfKinScreenState extends ConsumerState<KYCNextOfKinScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  String? _selectedRelationship;

  final List<String> _relationships = [
    'Parent',
    'Spouse',
    'Sibling',
    'Child',
    'Relative',
    'Friend',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(kycProvider, (prev, next) {
        if (next.status == KYCStatus.loaded &&
            (prev == null || prev.status != KYCStatus.loaded)) {
          _loadExistingAndMaybeSkip();
        }
      });
      _loadExistingAndMaybeSkip();
    });
  }

  void _loadExistingAndMaybeSkip() {
    final kycState = ref.read(kycProvider);
    if (kycState.status == KYCStatus.initial ||
        kycState.status == KYCStatus.loading) {
      ref.read(kycProvider.notifier).initializeKYC();
      return;
    }

    final sub = kycState.submission;
    if (sub == null) return;

    setState(() {
      _nameController.text = sub.nokName ?? '';
      _phoneController.text = sub.nokPhone ?? '';
      _addressController.text = sub.nokAddress ?? '';
      _selectedRelationship = sub.nokRelationship;
    });

    if (sub.nokName != null &&
        sub.nokRelationship != null &&
        sub.nokPhone != null) {
      _skipToNextIncompleteStep(sub);
    }
  }

  void _skipToNextIncompleteStep(KYCSubmission sub) {
    final missing = sub.missingSections;
    if (missing.isEmpty || missing.first == 'nextOfKin') return;
    final route = {'bank': '/kyc-bank-info'}[missing.first];
    if (route != null) {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: CoopvestColors.error),
    );
  }

  void _validateAndContinue() {
    if (_nameController.text.trim().isEmpty) {
      _showError('Next of kin name is required');
      return;
    }
    if (_selectedRelationship == null) {
      _showError('Relationship is required');
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      _showError('Next of kin phone is required');
      return;
    }

    final address = _addressController.text.trim().isEmpty
        ? null
        : _addressController.text.trim();
    ref.read(kycProvider.notifier).updateNextOfKin(
          nokName: _nameController.text.trim(),
          nokRelationship: _selectedRelationship,
          nokPhone: _phoneController.text.trim(),
          nokAddress: address,
        );

    Navigator.of(context).pushNamed('/kyc-bank-info');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Next of Kin',
          style: TextStyle(
              color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next of Kin Details',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Provide a contact we can reach on your behalf.',
                style: TextStyle(color: context.textSecondary),
              ),
              const SizedBox(height: 24),

              AppTextField(
                label: 'Full Name *',
                hint: 'Enter next of kin full name',
                controller: _nameController,
              ),
              const SizedBox(height: 20),

              AppDropdown<String>(
                label: 'Relationship *',
                hint: 'Select relationship',
                value: _selectedRelationship,
                items: _relationships
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedRelationship = value);
                },
              ),
              const SizedBox(height: 20),

              AppTextField(
                label: 'Phone Number *',
                hint: 'Enter phone number',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),

              AppTextField(
                label: 'Address',
                hint: 'Enter next of kin address',
                controller: _addressController,
                maxLines: 2,
              ),
              const SizedBox(height: 40),

              PrimaryButton(
                label: 'Continue',
                onPressed: _validateAndContinue,
                width: double.infinity,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
