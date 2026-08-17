import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../widgets/common/buttons.dart';
import '../../widgets/common/inputs.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/kyc_models.dart';

// ---------------------------------------------------------------------------
// Contribution type enum
// ---------------------------------------------------------------------------
enum _ContributionType { directDeposit, salaryDeduction }

// ---------------------------------------------------------------------------
// Data collected across all onboarding steps
// ---------------------------------------------------------------------------
class _OnboardingData {
  // Contribution Type (set from navigation arguments)
  _ContributionType contributionType = _ContributionType.directDeposit;

  // Step 2 – Personal Information
  String gender = '';
  String dateOfBirth = '';
  String residentialAddress = '';
  String state = '';
  String lga = '';

  // Step 3 – Identification
  File? selfiePhoto;
  File? idDocumentPhoto;
  String idType = 'NIN';
  String idNumber = '';
  String staffId = '';

  // Step 4 – Employment (required for salary deduction, optional for direct deposit)
  String occupation = '';
  String employerName = '';
  String employmentType = '';
  String employerStaffId = '';
  String workAddress = '';
  String yearsOfEmployment = '';

  // Step 5 – Contribution Setup
  double monthlyAmount = 5000;
  String contributionMethod = 'manual';
  int preferredPaymentDay = 5;

  // Step 6 – Next of Kin
  String nokName = '';
  String nokRelationship = '';
  String nokPhone = '';
  String nokAddress = '';

  // Step 7 – Bank Information
  String bankName = '';
  String bankCode = '';
  String accountNumber = '';
  String accountName = '';
  String accountType = '';

  // Step 8 – Terms
  bool acceptedTerms = false;
  bool acceptedContributionPolicy = false;
  bool acceptedLoanPolicy = false;
  bool acceptedGuarantorRequirement = false; // Section 5.1: 3 guarantors
  bool acceptedDefaultPolicy = false; // Section 5.1: guarantors contacted on default
  bool acceptedRegistrationFeePolicy = false;
  bool acceptedPrivacyPolicy = false;

  bool get allTermsAccepted =>
      acceptedTerms &&
      acceptedContributionPolicy &&
      acceptedLoanPolicy &&
      acceptedGuarantorRequirement &&
      acceptedDefaultPolicy &&
      acceptedRegistrationFeePolicy &&
      acceptedPrivacyPolicy;

  /// Returns true if employer info is required (salary deduction selected)
  bool get requiresEmployerInfo => contributionType == _ContributionType.salaryDeduction;
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------
class RegistrationOnboardingScreen extends ConsumerStatefulWidget {
  final Map<String, String> registrationData;

  const RegistrationOnboardingScreen({
    Key? key,
    required this.registrationData,
  }) : super(key: key);

  @override
  ConsumerState<RegistrationOnboardingScreen> createState() =>
      _RegistrationOnboardingScreenState();
}

class _RegistrationOnboardingScreenState
    extends ConsumerState<RegistrationOnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  final _data = _OnboardingData();
  bool _isSubmitting = false;
  bool _isCheckingStatus = true;

  static const int _totalSteps = 8;

  final _stepTitles = [
    'Welcome',
    'Personal Info',
    'Identification',
    'Employment',
    'Contribution',
    'Next of Kin',
    'Bank Info',
    'Terms',
  ];

  // Form keys for each step
  final _step2Key = GlobalKey<FormState>();
  final _step4Key = GlobalKey<FormState>();
  final _step6Key = GlobalKey<FormState>();

  // Step 2 controllers
  final _addressCtrl = TextEditingController();
  final _lgaCtrl = TextEditingController();

  // Step 3 controllers
  final _idNumberCtrl = TextEditingController();

  // Step 4 controllers
  final _occupationCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _employerStaffIdCtrl = TextEditingController();
  final _workAddressCtrl = TextEditingController();

  // Step 6 controllers
  final _nokNameCtrl = TextEditingController();
  final _nokPhoneCtrl = TextEditingController();
  final _nokAddressCtrl = TextEditingController();

  // Step 7 controllers (Bank Info)
  final _bankNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  String? _selectedBank;
  String? _selectedAccountType;

  @override
  void initState() {
    super.initState();
    // Read contribution type from navigation arguments
    final contributionType = widget.registrationData['contribution_type'];
    if (contributionType == 'salary_deduction') {
      _data.contributionType = _ContributionType.salaryDeduction;
    } else {
      _data.contributionType = _ContributionType.directDeposit;
    }
    // Check if this user already completed onboarding (e.g. returned after
    // a crash or re-login). If so, skip straight to the next screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAlreadyCompleted());
  }

  Future<void> _checkAlreadyCompleted() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response =
          await apiClient.get('/auth/complete-registration/status');
      final data = response.data as Map<String, dynamic>?;
      if ((data?['completed'] as bool? ?? false) && mounted) {
        // Salary consent is only required for members who chose salary
        // deduction. Direct-deposit members go straight to activation.
        final nextRoute = _data.contributionType == _ContributionType.salaryDeduction
            ? '/salary-deduction-consent'
            : '/account-activation';
        Navigator.of(context).pushReplacementNamed(
          nextRoute,
          arguments: widget.registrationData,
        );
        return;
      }
    } catch (_) {
      // Non-fatal — if the check fails, the user continues through the form normally.
    }
    if (mounted) setState(() => _isCheckingStatus = false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _addressCtrl.dispose();
    _lgaCtrl.dispose();
    _idNumberCtrl.dispose();
    _occupationCtrl.dispose();
    _employerCtrl.dispose();
    _employerStaffIdCtrl.dispose();
    _workAddressCtrl.dispose();
    _nokNameCtrl.dispose();
    _nokPhoneCtrl.dispose();
    _nokAddressCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountNameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep == 1) {
      if (!_validateStep2()) return;
    }
    if (_currentStep == 2) {
      if (!_validateStep3()) return;
    }
    if (_currentStep == 3) {
      if (!_validateStep4()) return;
    }
    if (_currentStep == 5) {
      if (!_validateStep6()) return;
    }
    if (_currentStep == 6) {
      if (!_validateStep7()) return;
    }
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _validateStep2() {
    if (_data.gender.isEmpty) {
      _showError('Please select your gender.');
      return false;
    }
    if (_data.dateOfBirth.isEmpty) {
      _showError('Please enter your date of birth.');
      return false;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      _showError('Please enter your residential address.');
      return false;
    }
    if (_data.state.isEmpty) {
      _showError('Please select your state.');
      return false;
    }
    if (_lgaCtrl.text.trim().isEmpty) {
      _showError('Please enter your Local Government Area.');
      return false;
    }
    _data.residentialAddress = _addressCtrl.text.trim();
    _data.lga = _lgaCtrl.text.trim();
    return true;
  }

  bool _validateStep3() {
    if (_data.selfiePhoto == null) {
      _showError('Please upload or take a selfie photo.');
      return false;
    }
    if (_data.idDocumentPhoto == null) {
      _showError('Please upload a photo of your ID document.');
      return false;
    }
    if (_idNumberCtrl.text.trim().isEmpty) {
      _showError('Please enter your NIN / ID number.');
      return false;
    }
    _data.idNumber = _idNumberCtrl.text.trim();
    return true;
  }

  bool _validateStep4() {
    if (_occupationCtrl.text.trim().isEmpty) {
      _showError('Please enter your occupation.');
      return false;
    }

    // Employer info is required only for salary deduction
    if (_data.requiresEmployerInfo) {
      if (_employerCtrl.text.trim().isEmpty) {
        _showError('Please enter your employer/organization name.');
        return false;
      }
      if (_data.employmentType.isEmpty) {
        _showError('Please select your employment type.');
        return false;
      }
      if (_employerStaffIdCtrl.text.trim().isEmpty) {
        _showError('Please enter your staff ID number.');
        return false;
      }
      if (_workAddressCtrl.text.trim().isEmpty) {
        _showError('Please enter your work address.');
        return false;
      }
      if (_data.yearsOfEmployment.isEmpty) {
        _showError('Please select your years of employment.');
        return false;
      }
    }

    _data.occupation = _occupationCtrl.text.trim();
    _data.employerName = _employerCtrl.text.trim();
    _data.employerStaffId = _employerStaffIdCtrl.text.trim();
    // Staff ID is now collected only in the Employment step; keep the legacy
    // staffId field in sync so the backend still receives staff_id.
    _data.staffId = _employerStaffIdCtrl.text.trim();
    _data.workAddress = _workAddressCtrl.text.trim();
    return true;
  }

  bool _validateStep6() {
    if (_nokNameCtrl.text.trim().isEmpty) {
      _showError('Please enter your next of kin\'s name.');
      return false;
    }
    if (_data.nokRelationship.isEmpty) {
      _showError('Please select your relationship with next of kin.');
      return false;
    }
    if (_nokPhoneCtrl.text.trim().isEmpty) {
      _showError('Please enter your next of kin\'s phone number.');
      return false;
    }
    if (_nokAddressCtrl.text.trim().isEmpty) {
      _showError('Please enter your next of kin\'s address.');
      return false;
    }
    _data.nokName = _nokNameCtrl.text.trim();
    _data.nokPhone = _nokPhoneCtrl.text.trim();
    _data.nokAddress = _nokAddressCtrl.text.trim();
    return true;
  }

  bool _validateStep7() {
    if (_selectedBank == null || _selectedBank!.isEmpty) {
      _showError('Please select your bank.');
      return false;
    }
    if (_accountNumberCtrl.text.trim().length != 10) {
      _showError('Account number must be 10 digits.');
      return false;
    }
    if (_accountNameCtrl.text.trim().isEmpty) {
      _showError('Please verify your account name.');
      return false;
    }
    if (_selectedAccountType == null || _selectedAccountType!.isEmpty) {
      _showError('Please select your account type.');
      return false;
    }
    _data.bankName = _selectedBank!;
    _data.bankCode = _getBankCode(_selectedBank!);
    _data.accountNumber = _accountNumberCtrl.text.trim();
    _data.accountName = _accountNameCtrl.text.trim();
    _data.accountType = _selectedAccountType!;
    return true;
  }

  String _getBankCode(String bankName) {
    return BankTypes.getBankCode(bankName);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: CoopvestColors.error,
      duration: const Duration(seconds: 3),
    ));
  }

  void _verifyAccountName() async {
    if (_selectedBank == null || _accountNumberCtrl.text.length != 10) {
      _showError('Please select a bank and enter 10-digit account number');
      return;
    }
    // In production, call your API to verify account name
    // For now, simulate verification
    setState(() {
      _accountNameCtrl.text = 'Verified Account Name';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account verified successfully'),
        backgroundColor: CoopvestColors.success,
      ),
    );
  }

  /// Shows a dialog with the error message and two actions:
  /// "Try Again" re-invokes [_submit]; "Cancel" dismisses so the user can
  /// review their data before retrying manually.
  Future<void> _showRetryDialog(String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: CoopvestColors.error, size: 22),
            const SizedBox(width: 10),
            const Text('Submission Failed'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CoopvestColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _submit();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_data.allTermsAccepted) {
      _showError(
          'Please accept all policies and terms before proceeding.');
      return;
    }
    setState(() => _isSubmitting = true);

    try {
      // Collect all data into a single map to pass forward
      final combined = {
        ...widget.registrationData,
        'gender': _data.gender,
        'date_of_birth': _data.dateOfBirth,
        'address': _data.residentialAddress,
        'state': _data.state,
        'lga': _data.lga,
        'id_type': _data.idType,
        'id_number': _data.idNumber,
        'staff_id': _data.staffId,
        'occupation': _data.occupation,
        'employer_name': _data.employerName,
        'employment_type': _data.employmentType,
        'employer_staff_id': _data.employerStaffId,
        'work_address': _data.workAddress,
        'years_of_employment': _data.yearsOfEmployment,
        'monthly_amount': _data.monthlyAmount.toStringAsFixed(0),
        'contribution_method': _data.contributionMethod,
        'preferred_payment_day': _data.preferredPaymentDay.toString(),
        'nok_name': _data.nokName,
        'nok_relationship': _data.nokRelationship,
        'nok_phone': _data.nokPhone,
        'nok_address': _data.nokAddress,
        // Bank Information
        'bank_name': _data.bankName,
        'bank_code': _data.bankCode,
        'account_number': _data.accountNumber,
        'account_name': _data.accountName,
        'account_type': _data.accountType,
        // Add contribution type to submission
        'contribution_type': _data.contributionType == _ContributionType.salaryDeduction
            ? 'salary_deduction'
            : 'direct_deposit',
      };

      // Submit registration data to backend — failure is a hard stop;
      // an incomplete backend record must not silently enter the salary flow.
      final apiClient = ref.read(apiClientProvider);
      try {
        await apiClient.post('/auth/complete-registration', data: combined);
      } catch (e) {
        logger.e('Registration data submission error: \$e');
        if (mounted) {
          final errorDetail = e.toString().replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
          await _showRetryDialog(
            'Could not save your registration details: \$errorDetail. '
            'Please check your connection and try again.',
          );
        }
        return;
      }

      if (mounted) {
        // Salary consent is mandatory only for salary-deduction members.
        // Direct-deposit members skip consent and go to account activation.
        final nextRoute = _data.contributionType == _ContributionType.salaryDeduction
            ? '/salary-deduction-consent'
            : '/account-activation';
        Navigator.of(context).pushNamed(
          nextRoute,
          arguments: combined,
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Submission failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: context.scaffoldBackground,
        leading: _currentStep > 0
            ? IconButton(
                icon:
                    Icon(Icons.arrow_back, color: context.iconPrimary),
                onPressed: _back,
              )
            : null,
        automaticallyImplyLeading: false,
        title: Text(
          _stepTitles[_currentStep],
          style: TextStyle(
              color: context.textPrimary,
              fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: context.dividerColor,
            color: CoopvestColors.primary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Step dots
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalSteps, (i) {
                final done = i < _currentStep;
                final active = i == _currentStep;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: done || active
                        ? CoopvestColors.primary
                        : context.dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _WelcomeStep(
                    registrationData: widget.registrationData,
                    onNext: _next),
                _PersonalInfoStep(data: _data, addressCtrl: _addressCtrl, lgaCtrl: _lgaCtrl),
                _IdentificationStep(data: _data, idNumberCtrl: _idNumberCtrl),
                _EmploymentStep(
                    data: _data,
                    occupationCtrl: _occupationCtrl,
                    employerCtrl: _employerCtrl,
                    employerStaffIdCtrl: _employerStaffIdCtrl,
                    workAddressCtrl: _workAddressCtrl),
                _ContributionStep(data: _data),
                _NextOfKinStep(
                    data: _data,
                    nokNameCtrl: _nokNameCtrl,
                    nokPhoneCtrl: _nokPhoneCtrl,
                    nokAddressCtrl: _nokAddressCtrl),
                _BankInfoStep(
                    data: _data,
                    selectedBank: _selectedBank,
                    selectedAccountType: _selectedAccountType,
                    accountNumberCtrl: _accountNumberCtrl,
                    accountNameCtrl: _accountNameCtrl,
                    onBankChanged: (bank) => setState(() => _selectedBank = bank),
                    onAccountTypeChanged: (type) => setState(() => _selectedAccountType = type),
                    onVerifyAccount: _verifyAccountName,
                ),
                _TermsStep(
                    data: _data,
                    onAcceptAll: () => setState(() {})),
              ],
            ),
          ),

          // Bottom navigation buttons
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _currentStep == _totalSteps - 1
                  ? _isSubmitting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: CoopvestColors.primary))
                      : PrimaryButton(
                          label: 'Complete Registration',
                          onPressed: _submit,
                          width: double.infinity,
                        )
                  : _currentStep == 0
                      ? PrimaryButton(
                          label: 'Get Started',
                          onPressed: _next,
                          width: double.infinity,
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                label: 'Back',
                                onPressed: _back,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: PrimaryButton(
                                label: _currentStep == _totalSteps - 2
                                    ? 'Review Terms'
                                    : 'Continue',
                                onPressed: _next,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ],
      ),
    ),
        // ── Status-check loading overlay ──────────────────────────────────
        if (_isCheckingStatus)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CoopvestColors.primary.withOpacity(0.08),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: CoopvestColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Just a moment…',
                      style: TextStyle(
                        color: CoopvestColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Welcome
// ---------------------------------------------------------------------------
class _WelcomeStep extends StatelessWidget {
  final Map<String, String> registrationData;
  final VoidCallback onNext;

  const _WelcomeStep({
    required this.registrationData,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: CoopvestColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waving_hand,
                  size: 40, color: CoopvestColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Welcome to Coopvest Africa',
              style: TextStyle(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Hi ${registrationData['name'] ?? 'there'}, before we activate your account, '
              'let\'s complete your profile. This takes about 5 minutes.',
              style: TextStyle(
                  color: context.textSecondary, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          // Registration fee notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CoopvestColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: CoopvestColors.warning.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: CoopvestColors.warning, size: 18),
                    SizedBox(width: 8),
                    Text('Important Notice',
                        style: TextStyle(
                            color: CoopvestColors.warning,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'A one-time non-refundable registration fee of ₦5,000 applies to all new members. '
                  'This will be added to your first monthly contribution.',
                  style: TextStyle(
                      color: CoopvestColors.warning,
                      fontSize: 12,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Key policies
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CoopvestColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: CoopvestColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Key Policies',
                    style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 12),
                _policyRow(Icons.savings_outlined,
                    'Minimum monthly contribution: ₦5,000'),
                _policyRow(Icons.trending_up,
                    'You can increase your contribution anytime'),
                _policyRow(Icons.schedule,
                    'Contribution reductions require 3-month notice'),
                _policyRow(Icons.account_balance_outlined,
                    'Consistent contributions improve loan eligibility'),
                _policyRow(Icons.history,
                    'Your contribution history is tracked digitally'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Steps ahead
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What we\'ll collect',
                    style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 12),
                ...[
                  'Personal details & address',
                  'Government-issued ID (NIN)',
                  'Employment information',
                  'Contribution preferences',
                  'Next of kin details',
                  'Policy agreements',
                ].asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: CoopvestColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${e.key + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(e.value,
                              style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 13)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _policyRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CoopvestColors.primary, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: CoopvestColors.primary,
                    fontSize: 12,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Personal Information
// ---------------------------------------------------------------------------
class _PersonalInfoStep extends StatefulWidget {
  final _OnboardingData data;
  final TextEditingController addressCtrl;
  final TextEditingController lgaCtrl;

  const _PersonalInfoStep({
    required this.data,
    required this.addressCtrl,
    required this.lgaCtrl,
  });

  @override
  State<_PersonalInfoStep> createState() => _PersonalInfoStepState();
}

class _PersonalInfoStepState extends State<_PersonalInfoStep> {
  late TextEditingController _dobCtrl;
  final _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  final _nigerianStates = [
    'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa',
    'Benue', 'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti',
    'Enugu', 'FCT - Abuja', 'Gombe', 'Imo', 'Jigawa', 'Kaduna', 'Kano',
    'Katsina', 'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa', 'Niger',
    'Ogun', 'Ondo', 'Osun', 'Oyo', 'Plateau', 'Rivers', 'Sokoto',
    'Taraba', 'Yobe', 'Zamfara',
  ];

  @override
  void initState() {
    super.initState();
    _dobCtrl = TextEditingController(text: widget.data.dateOfBirth);
  }

  @override
  void dispose() {
    _dobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.person_outline,
              title: 'Personal Information',
              subtitle: 'Fill in your personal details as they appear on your official ID.'),
          const SizedBox(height: 20),

          // Gender
          _FieldLabel(label: 'Gender *'),
          const SizedBox(height: 8),
          _ChipSelector(
            options: _genders,
            selected: widget.data.gender,
            onSelected: (v) => setState(() => widget.data.gender = v),
          ),
          const SizedBox(height: 20),

          // Date of Birth
          AppTextField(
            label: 'Date of Birth *',
            hint: 'DD/MM/YYYY',
            readOnly: true,
            controller: _dobCtrl,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1940),
                lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: CoopvestColors.primary,
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(() {
                  final formatted =
                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                  widget.data.dateOfBirth = formatted;
                  _dobCtrl.text = formatted;
                });
              }
            },
          ),
          const SizedBox(height: 20),

          // Address
          AppTextField(
            label: 'Residential Address *',
            hint: 'House number, street name',
            controller: widget.addressCtrl,
          ),
          const SizedBox(height: 20),

          // State
          _FieldLabel(label: 'State *'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: widget.data.state.isEmpty ? null : widget.data.state,
            hint: const Text('Select State'),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: _nigerianStates
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => widget.data.state = v ?? ''),
          ),
          const SizedBox(height: 20),

          // LGA
          AppTextField(
            label: 'Local Government Area (LGA) *',
            hint: 'Enter your LGA',
            controller: widget.lgaCtrl,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Identification
// ---------------------------------------------------------------------------
class _IdentificationStep extends StatefulWidget {
  final _OnboardingData data;
  final TextEditingController idNumberCtrl;

  const _IdentificationStep({
    required this.data,
    required this.idNumberCtrl,
  });

  @override
  State<_IdentificationStep> createState() => _IdentificationStepState();
}

class _IdentificationStepState extends State<_IdentificationStep> {
  final _picker = ImagePicker();
  final _idTypes = ['NIN', 'Voters Card', 'International Passport', 'Drivers License'];

  Future<void> _pickImage(bool isSelfie) async {
    final source = isSelfie ? ImageSource.camera : ImageSource.gallery;
    final file = await _picker.pickImage(
        source: source, maxWidth: 800, imageQuality: 85);
    if (file != null) {
      setState(() {
        if (isSelfie) {
          widget.data.selfiePhoto = File(file.path);
        } else {
          widget.data.idDocumentPhoto = File(file.path);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.badge_outlined,
              title: 'Identification',
              subtitle: 'Upload your ID documents and a clear selfie photo.'),
          const SizedBox(height: 20),

          // Selfie photo
          _PhotoUploadCard(
            title: 'Passport Photo / Selfie *',
            subtitle: 'Take a clear selfie or upload a passport photo',
            icon: Icons.face,
            file: widget.data.selfiePhoto,
            onTap: () => _pickImage(true),
            onGalleryTap: () async {
              final file = await _picker.pickImage(
                  source: ImageSource.gallery, maxWidth: 800);
              if (file != null) {
                setState(() =>
                    widget.data.selfiePhoto = File(file.path));
              }
            },
          ),
          const SizedBox(height: 20),

          // ID type
          _FieldLabel(label: 'ID Type *'),
          const SizedBox(height: 8),
          _ChipSelector(
            options: _idTypes,
            selected: widget.data.idType,
            onSelected: (v) => setState(() => widget.data.idType = v),
          ),
          const SizedBox(height: 20),

          // ID Number / NIN
          AppTextField(
            label: '${widget.data.idType} Number *',
            hint: 'Enter your ${widget.data.idType} number',
            controller: widget.idNumberCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),

          // ID document photo
          _PhotoUploadCard(
            title: 'ID Document Photo *',
            subtitle: 'Upload a clear photo of your ${widget.data.idType}',
            icon: Icons.credit_card,
            file: widget.data.idDocumentPhoto,
            onTap: () => _pickImage(false),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CoopvestColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline,
                    color: CoopvestColors.info, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ensure all photos are clear, unobstructed, and taken in good lighting. Staff ID is collected in the Employment step.',
                    style: TextStyle(
                        color: CoopvestColors.info, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: Employment Information
// ---------------------------------------------------------------------------
class _EmploymentStep extends StatefulWidget {
  final _OnboardingData data;
  final TextEditingController occupationCtrl;
  final TextEditingController employerCtrl;
  final TextEditingController employerStaffIdCtrl;
  final TextEditingController workAddressCtrl;

  const _EmploymentStep({
    required this.data,
    required this.occupationCtrl,
    required this.employerCtrl,
    required this.employerStaffIdCtrl,
    required this.workAddressCtrl,
  });

  @override
  State<_EmploymentStep> createState() => _EmploymentStepState();
}

class _EmploymentStepState extends State<_EmploymentStep> {
  final _employmentTypes = [
    'Full-time Employee',
    'Part-time Employee',
    'Contract / Freelance',
    'Civil Servant',
    'Self-Employed',
    'Retired',
    'Other',
  ];

  final _yearsOptions = [
    'Less than 1 year',
    '1 - 2 years',
    '3 - 5 years',
    '6 - 10 years',
    '11 - 15 years',
    'More than 15 years',
  ];

  @override
  Widget build(BuildContext context) {
    final bool requiresEmployerInfo = widget.data.requiresEmployerInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.business_center_outlined,
              title: 'Employment Information',
              subtitle: requiresEmployerInfo
                  ? 'Your employer information is required for salary deduction setup.'
                  : 'This helps us assess your financial profile for loan eligibility.'),
          const SizedBox(height: 20),

          AppTextField(
            label: 'Occupation *',
            hint: 'e.g. Software Engineer, Teacher, Nurse',
            controller: widget.occupationCtrl,
          ),
          const SizedBox(height: 20),

          // Employer fields - required when salary deduction is selected
          if (requiresEmployerInfo) ...[
            AppTextField(
              label: 'Employer / Organization Name *',
              hint: 'Enter your organization\'s full name',
              controller: widget.employerCtrl,
            ),
            const SizedBox(height: 20),

            _FieldLabel(label: 'Employment Type *'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: widget.data.employmentType.isEmpty
                  ? null
                  : widget.data.employmentType,
              hint: const Text('Select Employment Type'),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: _employmentTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => widget.data.employmentType = v ?? ''),
            ),
            const SizedBox(height: 20),

            AppTextField(
              label: 'Staff ID Number *',
              hint: 'Your official staff/employee ID',
              controller: widget.employerStaffIdCtrl,
            ),
            const SizedBox(height: 20),

            AppTextField(
              label: 'Work Address *',
              hint: 'Office address of your employer',
              controller: widget.workAddressCtrl,
            ),
            const SizedBox(height: 20),

            _FieldLabel(label: 'Years of Employment *'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: widget.data.yearsOfEmployment.isEmpty
                  ? null
                  : widget.data.yearsOfEmployment,
              hint: const Text('Select years of employment'),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: _yearsOptions
                  .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => widget.data.yearsOfEmployment = v ?? ''),
            ),
          ] else ...[
            // For direct deposit, employer fields are optional
            AppTextField(
              label: 'Employer / Organization Name (Optional)',
              hint: 'Enter your organization\'s full name',
              controller: widget.employerCtrl,
            ),
            const SizedBox(height: 20),

            _FieldLabel(label: 'Employment Type (Optional)'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: widget.data.employmentType.isEmpty
                  ? null
                  : widget.data.employmentType,
              hint: const Text('Select Employment Type'),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: _employmentTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => widget.data.employmentType = v ?? ''),
            ),
            const SizedBox(height: 20),

            AppTextField(
              label: 'Staff ID Number (Optional)',
              hint: 'Your official staff/employee ID',
              controller: widget.employerStaffIdCtrl,
            ),
            const SizedBox(height: 20),

            AppTextField(
              label: 'Work Address (Optional)',
              hint: 'Office address of your employer',
              controller: widget.workAddressCtrl,
            ),
            const SizedBox(height: 20),

            _FieldLabel(label: 'Years of Employment (Optional)'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: widget.data.yearsOfEmployment.isEmpty
                  ? null
                  : widget.data.yearsOfEmployment,
              hint: const Text('Select years of employment'),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: _yearsOptions
                  .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => widget.data.yearsOfEmployment = v ?? ''),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5: Contribution Setup
// ---------------------------------------------------------------------------
class _ContributionStep extends StatefulWidget {
  final _OnboardingData data;
  const _ContributionStep({required this.data});

  @override
  State<_ContributionStep> createState() => _ContributionStepState();
}

class _ContributionStepState extends State<_ContributionStep> {
  final _customCtrl = TextEditingController();
  bool _showCustom = false;

  final _presetAmounts = [5000.0, 10000.0, 20000.0, 50000.0];
  final _paymentDays = [1, 5, 10, 15, 20, 25, 28];

  String _fmt(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.savings_outlined,
              title: 'Contribution Setup',
              subtitle: 'Set your monthly contribution. First payment includes the ₦5,000 registration fee.'),
          const SizedBox(height: 16),

          // Registration fee breakdown
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CoopvestColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CoopvestColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                _feeRow(context, 'Registration Fee (one-time)', '₦5,000'),
                const SizedBox(height: 4),
                _feeRow(context, 'Your Monthly Contribution',
                    '₦${_fmt(widget.data.monthlyAmount)}'),
                const Divider(height: 16),
                _feeRow(context, 'First Payment Total',
                    '₦${_fmt(widget.data.monthlyAmount + 5000)}',
                    bold: true, color: CoopvestColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Amount selection
          _FieldLabel(label: 'Preferred Monthly Contribution *'),
          const SizedBox(height: 12),
          Text(
            'You can increase your monthly contribution later from your dashboard.',
            style: TextStyle(
                color: context.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._presetAmounts.map((amt) {
                final isSelected = !_showCustom &&
                    widget.data.monthlyAmount == amt;
                return GestureDetector(
                  onTap: () => setState(() {
                    widget.data.monthlyAmount = amt;
                    _showCustom = false;
                  }),
                  child: _ContributionChip(
                      label: '₦${_fmt(amt)}',
                      isSelected: isSelected),
                );
              }),
              GestureDetector(
                onTap: () => setState(() => _showCustom = true),
                child: _ContributionChip(
                    label: 'Custom',
                    isSelected: _showCustom),
              ),
            ],
          ),
          if (_showCustom) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _customCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '₦ ',
                hintText: 'Min ₦5,000',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onChanged: (v) {
                final val = double.tryParse(v);
                if (val != null) {
                  setState(() => widget.data.monthlyAmount = val);
                }
              },
            ),
          ],
          const SizedBox(height: 24),

          // Contribution Method
          _FieldLabel(label: 'Contribution Method *'),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.calendar_month_outlined,
            title: 'Monthly Self Contribution',
            subtitle: 'You make payments manually each month',
            isSelected: widget.data.contributionMethod == 'manual',
            onTap: () =>
                setState(() => widget.data.contributionMethod = 'manual'),
          ),
          const SizedBox(height: 10),
          _MethodCard(
            icon: Icons.business_center_outlined,
            title: 'Salary Deduction (Payroll)',
            subtitle: 'Employer deducts from your salary monthly',
            isSelected: widget.data.contributionMethod == 'payroll',
            onTap: () =>
                setState(() => widget.data.contributionMethod = 'payroll'),
          ),
          const SizedBox(height: 24),

          // Preferred payment day
          _FieldLabel(label: 'Preferred Payment Day (1–28)'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _paymentDays.map((day) {
              final isSelected = widget.data.preferredPaymentDay == day;
              return GestureDetector(
                onTap: () =>
                    setState(() => widget.data.preferredPaymentDay = day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? CoopvestColors.primary
                        : context.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? CoopvestColors.primary
                          : context.dividerColor,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isSelected ? Colors.white : context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(BuildContext context, String label, String value,
      {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ),
        Text(value,
            style: TextStyle(
              color: color ?? context.textPrimary,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: bold ? 15 : 13,
            )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 6: Next of Kin
// ---------------------------------------------------------------------------
class _NextOfKinStep extends StatefulWidget {
  final _OnboardingData data;
  final TextEditingController nokNameCtrl;
  final TextEditingController nokPhoneCtrl;
  final TextEditingController nokAddressCtrl;

  const _NextOfKinStep({
    required this.data,
    required this.nokNameCtrl,
    required this.nokPhoneCtrl,
    required this.nokAddressCtrl,
  });

  @override
  State<_NextOfKinStep> createState() => _NextOfKinStepState();
}

class _NextOfKinStepState extends State<_NextOfKinStep> {
  final _relationships = [
    'Spouse', 'Parent', 'Sibling', 'Child',
    'Relative', 'Friend', 'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.family_restroom,
              title: 'Next of Kin',
              subtitle:
                  'This information is required for loan security purposes.'),
          const SizedBox(height: 20),

          AppTextField(
            label: 'Full Name *',
            hint: 'Next of kin\'s full name',
            controller: widget.nokNameCtrl,
          ),
          const SizedBox(height: 20),

          _FieldLabel(label: 'Relationship *'),
          const SizedBox(height: 8),
          _ChipSelector(
            options: _relationships,
            selected: widget.data.nokRelationship,
            onSelected: (v) =>
                setState(() => widget.data.nokRelationship = v),
          ),
          const SizedBox(height: 20),

          AppTextField(
            label: 'Phone Number *',
            hint: '+234 801 234 5678',
            controller: widget.nokPhoneCtrl,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),

          AppTextField(
            label: 'Residential Address *',
            hint: 'Next of kin\'s home address',
            controller: widget.nokAddressCtrl,
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CoopvestColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: CoopvestColors.warning.withOpacity(0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: CoopvestColors.warning, size: 15),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your next of kin will be contacted only in the event of an emergency or unresolved account situation.',
                    style: TextStyle(
                        color: CoopvestColors.warning,
                        fontSize: 11,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 7: Terms & Agreement
// ---------------------------------------------------------------------------
class _BankInfoStep extends StatelessWidget {
  final _OnboardingData data;
  final String? selectedBank;
  final String? selectedAccountType;
  final TextEditingController accountNumberCtrl;
  final TextEditingController accountNameCtrl;
  final Function(String?) onBankChanged;
  final Function(String?) onAccountTypeChanged;
  final VoidCallback onVerifyAccount;

  const _BankInfoStep({
    required this.data,
    required this.selectedBank,
    required this.selectedAccountType,
    required this.accountNumberCtrl,
    required this.accountNameCtrl,
    required this.onBankChanged,
    required this.onAccountTypeChanged,
    required this.onVerifyAccount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bank Information',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your bank account details for receiving payouts and refunds',
            style: TextStyle(color: context.textSecondary),
          ),
          const SizedBox(height: 24),
          // Bank Dropdown
          Text(
            'Select Bank *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: context.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedBank,
                hint: const Text('Select your bank'),
                isExpanded: true,
                items: BankTypes.banks.map((bank) {
                  return DropdownMenuItem<String>(
                    value: bank['label'] as String,
                    child: Text(bank['label'] as String),
                  );
                }).toList(),
                onChanged: onBankChanged,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Account Number
          Text(
            'Account Number *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: accountNumberCtrl,
            keyboardType: TextInputType.number,
            maxLength: 10,
            decoration: InputDecoration(
              hintText: 'Enter 10-digit account number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          // Verify Account Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onVerifyAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: CoopvestColors.primary,
                side: const BorderSide(color: CoopvestColors.primary),
              ),
              child: const Text('Verify Account'),
            ),
          ),
          const SizedBox(height: 20),
          // Account Name (verified)
          Text(
            'Account Name',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: accountNameCtrl,
            readOnly: true,
            decoration: InputDecoration(
              hintText: 'Verified account name will appear here',
              filled: true,
              fillColor: CoopvestColors.success.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: CoopvestColors.success),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: CoopvestColors.success),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Account Type
          Text(
            'Account Type *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: context.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedAccountType,
                hint: const Text('Select account type'),
                isExpanded: true,
                items: BankAccountTypes.types.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['value'] as String,
                    child: Text(type['label'] as String),
                  );
                }).toList(),
                onChanged: onAccountTypeChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TermsStep extends StatelessWidget {
  final _OnboardingData data;
  final VoidCallback onAcceptAll;

  const _TermsStep({required this.data, required this.onAcceptAll});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.policy_outlined,
              title: 'Terms & Agreement',
              subtitle:
                  'Please read and accept all policies before activating your account.'),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CoopvestColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: CoopvestColors.warning.withOpacity(0.3)),
            ),
            child: const Text(
              'Welcome to Coopvest Africa. A one-time non-refundable registration fee of ₦5,000 '
              'applies to all new members. The minimum monthly contribution is ₦5,000. Members may '
              'increase their monthly contribution at any time through the app. Consistent contributions '
              'improve eligibility for future financial support services. Contribution history and '
              'account records are tracked digitally for transparency.',
              style: TextStyle(
                  color: CoopvestColors.warning,
                  fontSize: 12,
                  height: 1.6),
            ),
          ),
          const SizedBox(height: 20),

          _TermsCheckbox(
            title: 'Terms & Conditions',
            subtitle:
                'I have read and accept the Coopvest Africa Terms and Conditions governing membership.',
            value: data.acceptedTerms,
            onChanged: (v) {
              data.acceptedTerms = v ?? false;
              onAcceptAll();
            },
          ),
          _TermsCheckbox(
            title: 'Contribution Policy',
            subtitle:
                'I understand the monthly contribution rules: minimum ₦5,000, increases allowed anytime, reductions require 3-month notice.',
            value: data.acceptedContributionPolicy,
            onChanged: (v) {
              data.acceptedContributionPolicy = v ?? false;
              onAcceptAll();
            },
          ),
          _TermsCheckbox(
            title: 'Loan Policy',
            subtitle:
                'I understand the loan eligibility criteria, guarantor requirements, and repayment obligations.',
            value: data.acceptedLoanPolicy,
            onChanged: (v) {
              data.acceptedLoanPolicy = v ?? false;
              onAcceptAll();
            },
          ),
          _TermsCheckbox(
            title: 'Guarantor Requirement',
            subtitle:
                'I understand that loans under the direct contribution model require three guarantors.',
            value: data.acceptedGuarantorRequirement,
            onChanged: (v) {
              data.acceptedGuarantorRequirement = v ?? false;
              onAcceptAll();
            },
          ),
          _TermsCheckbox(
            title: 'Default & Recovery Policy',
            subtitle:
                'I understand that guarantors may be contacted in the event of prolonged loan default.',
            value: data.acceptedDefaultPolicy,
            onChanged: (v) {
              data.acceptedDefaultPolicy = v ?? false;
              onAcceptAll();
            },
          ),
          _TermsCheckbox(
            title: 'Registration Fee Policy',
            subtitle:
                'I understand that the ₦5,000 registration fee is non-refundable and will be added to my first contribution.',
            value: data.acceptedRegistrationFeePolicy,
            onChanged: (v) {
              data.acceptedRegistrationFeePolicy = v ?? false;
              onAcceptAll();
            },
          ),
          _TermsCheckbox(
            title: 'Privacy Policy',
            subtitle:
                'I consent to the collection, storage, and use of my personal and financial data as described in the Privacy Policy.',
            value: data.acceptedPrivacyPolicy,
            onChanged: (v) {
              data.acceptedPrivacyPolicy = v ?? false;
              onAcceptAll();
            },
          ),

          const SizedBox(height: 12),

          // Accept all shortcut
          GestureDetector(
            onTap: () {
              data.acceptedTerms = true;
              data.acceptedContributionPolicy = true;
              data.acceptedLoanPolicy = true;
              data.acceptedGuarantorRequirement = true;
              data.acceptedDefaultPolicy = true;
              data.acceptedRegistrationFeePolicy = true;
              data.acceptedPrivacyPolicy = true;
              onAcceptAll();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CoopvestColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: CoopvestColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    data.allTermsAccepted
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: CoopvestColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Accept all policies at once',
                      style: TextStyle(
                          color: CoopvestColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: CoopvestColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: CoopvestColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13));
  }
}

class _ChipSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt;
        return GestureDetector(
          onTap: () => onSelected(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? CoopvestColors.primary
                  : context.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? CoopvestColors.primary
                    : context.dividerColor,
              ),
            ),
            child: Text(
              opt,
              style: TextStyle(
                color: isSelected ? Colors.white : context.textPrimary,
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PhotoUploadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;
  final VoidCallback? onGalleryTap;

  const _PhotoUploadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.file,
    required this.onTap,
    this.onGalleryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: title),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: file != null
                  ? Colors.transparent
                  : CoopvestColors.primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: file != null
                    ? CoopvestColors.success
                    : context.dividerColor,
                width: file != null ? 2 : 1,
                style: file != null
                    ? BorderStyle.solid
                    : BorderStyle.solid,
              ),
            ),
            child: file != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(file!, fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 36,
                          color: CoopvestColors.primary.withOpacity(0.6)),
                      const SizedBox(height: 8),
                      Text('Tap to capture',
                          style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 11),
                          textAlign: TextAlign.center),
                    ],
                  ),
          ),
        ),
        if (onGalleryTap != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onGalleryTap,
            child: const Text('Or upload from gallery',
                style: TextStyle(
                    color: CoopvestColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ],
        if (file != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: const Text('Retake / Change photo',
                style: TextStyle(
                    color: CoopvestColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ],
    );
  }
}

class _ContributionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  const _ContributionChip(
      {required this.label, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? CoopvestColors.primary
            : context.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isSelected
                ? CoopvestColors.primary
                : context.dividerColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : context.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? CoopvestColors.primary.withOpacity(0.07)
              : context.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? CoopvestColors.primary : context.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? CoopvestColors.primary.withOpacity(0.15)
                    : context.dividerColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: isSelected
                      ? CoopvestColors.primary
                      : context.textSecondary,
                  size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: isSelected
                        ? CoopvestColors.primary
                        : context.dividerColor,
                    width: 2),
                color: isSelected
                    ? CoopvestColors.primary
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 12)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _TermsCheckbox({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? CoopvestColors.success.withOpacity(0.06)
            : context.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? CoopvestColors.success.withOpacity(0.4)
              : context.dividerColor,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: CoopvestColors.success,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 11,
                          height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
