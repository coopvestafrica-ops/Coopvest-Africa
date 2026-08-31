import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/kyc_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import '../../../presentation/widgets/common/inputs.dart';

/// KYC Basic Info Screen
class KYCBasicInfoScreen extends ConsumerStatefulWidget {
  const KYCBasicInfoScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KYCBasicInfoScreen> createState() => _KYCBasicInfoScreenState();
}

class _KYCBasicInfoScreenState extends ConsumerState<KYCBasicInfoScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;
  
  String? _selectedGender;
  DateTime? _selectedDateOfBirth;
  
  final List<Map<String, dynamic>> _genders = [
    {'label': 'Male', 'value': 'male'},
    {'label': 'Female', 'value': 'female'},
    {'label': 'Other', 'value': 'other'},
  ];

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _dobController = TextEditingController();
    _prefillFromUser();
  }

  /// Pre-fill name/email/phone from the signed-in member's profile — these
  /// were already captured during registration and must not be re-typed.
  void _prefillFromUser() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      _firstNameController.text = parts.first;
      if (parts.length > 1) {
        _lastNameController.text = parts.sublist(1).join(' ');
      }
    }
    _emailController.text = user.email;
    if (user.phone != null && user.phone!.isNotEmpty) {
      _phoneController.text = user.phone!;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      builder: (context, child) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: CoopvestColors.primary,
              onPrimary: Colors.white,
              surface: isDarkMode ? CoopvestColors.darkSurface : Colors.white,
              onSurface: isDarkMode ? Colors.white : CoopvestColors.darkGray,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && mounted) {
      setState(() {
        _selectedDateOfBirth = picked;
        _dobController.text = _formatDate(picked);
      });
    }
  }

  String _formatDate(DateTime date) {
    return date.toIso8601String().split('T')[0];
  }

  void _validateAndContinue() {
    if (_firstNameController.text.isEmpty) {
      _showError('Please enter your first name');
      return;
    }

    if (_lastNameController.text.isEmpty) {
      _showError('Please enter your last name');
      return;
    }

    if (_emailController.text.isEmpty) {
      _showError('Please enter your email address');
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text)) {
      _showError('Please enter a valid email address');
      return;
    }

    if (_phoneController.text.isEmpty) {
      _showError('Please enter your phone number');
      return;
    }

    if (_selectedDateOfBirth == null) {
      _showError('Please select your date of birth');
      return;
    }

    if (_selectedGender == null) {
      _showError('Please select your gender');
      return;
    }

    Navigator.of(context).pushNamed('/kyc-personal-details');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CoopvestColors.error,
      ),
    );
  }

  void _goBack() {
    Navigator.of(context).pop();
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
          'Basic Information',
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress Indicator
              Row(
                children: [
                  _buildProgressStep(1, false),
                  _buildProgressLine(1),
                  _buildProgressStep(2, true),
                  _buildProgressLine(2),
                  _buildProgressStep(3, true),
                  _buildProgressLine(3),
                  _buildProgressStep(4, true),
                ],
              ),
              const SizedBox(height: 32),

              // Header
              Text(
                'Let\'s Start with Your Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Please provide your basic information to create your account',
                style: TextStyle(color: context.textSecondary),
              ),
              const SizedBox(height: 24),

              // First Name
              AppTextField(
                label: 'First Name *',
                hint: 'Enter your first name',
                controller: _firstNameController,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
              ),
              
              const SizedBox(height: 16),

              // Last Name
              AppTextField(
                label: 'Last Name *',
                hint: 'Enter your last name',
                controller: _lastNameController,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
              ),
              
              const SizedBox(height: 16),

              // Email
              AppTextField(
                label: 'Email Address *',
                hint: 'Enter your email address',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              
              const SizedBox(height: 16),

              // Phone
              AppTextField(
                label: 'Phone Number *',
                hint: 'Enter your phone number',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                maxLength: 11,
                prefixText: '+234 ',
              ),
              
              const SizedBox(height: 16),

              // Date of Birth
              GestureDetector(
                onTap: _selectDateOfBirth,
                child: AbsorbPointer(
                  child: AppTextField(
                    label: 'Date of Birth *',
                    hint: 'DD/MM/YYYY',
                    controller: _dobController,
                    suffixIcon: Icon(Icons.calendar_today, color: context.textSecondary),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),

              // Gender
              Text(
                'Gender *',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Row(
                children: _genders.map((gender) {
                  final isSelected = _selectedGender == gender['value'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedGender = gender['value'] as String;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? CoopvestColors.primary : context.cardBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? CoopvestColors.primary : context.dividerColor,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            gender['label'] as String,
                            style: TextStyle(
                              color: isSelected ? Colors.white : context.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 40),

              // Continue Button
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

  Widget _buildProgressStep(int step, bool isPending) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPending ? context.dividerColor : CoopvestColors.primary,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$step',
          style: TextStyle(
            color: isPending ? context.textSecondary : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressLine(int step) {
    return Expanded(
      child: Container(
        height: 2,
        color: context.dividerColor,
      ),
    );
  }
}
