import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../../data/models/kyc_models.dart';
import '../../../presentation/providers/kyc_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/inputs.dart';

/// KYC Employment Details Screen
class KYCEmploymentDetailsScreen extends ConsumerStatefulWidget {
  final bool isFromRegistration;
  
  const KYCEmploymentDetailsScreen({
    Key? key,
    this.isFromRegistration = false,
  }) : super(key: key);

  @override
  ConsumerState<KYCEmploymentDetailsScreen> createState() =>
      _KYCEmploymentDetailsScreenState();
}

class _KYCEmploymentDetailsScreenState
    extends ConsumerState<KYCEmploymentDetailsScreen> {
  late TextEditingController _dateOfBirthController;
  late TextEditingController _jobTitleController;
  late TextEditingController _addressController;
  late TextEditingController _organizationSearchController;
  // Extra employment fields (aligned with registration onboarding)
  late TextEditingController _occupationController;
  late TextEditingController _employerNameController;
  late TextEditingController _workAddressController;
  late TextEditingController _yearsOfEmploymentController;
  late TextEditingController _lgaController;

  String? _selectedEmploymentType;
  String? _selectedOrganization;
  String? _selectedIncomeRange;
  String? _selectedGender;
  String? _selectedCity;
  String? _selectedState;
  
  final List<String> _employmentTypes = EmploymentTypes.types;
  final List<String> _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
  final List<String> _cities = ['Lagos', 'Abuja', 'Port Harcourt', 'Ibadan', 'Kano', 'Other'];
  final List<String> _states = [
    'Lagos', 'Abuja FCT', 'Rivers', 'Oyo', 'Kano', 'Enugu', 'Delta', 'Other'
  ];

  // Pre-approved organizations
  final List<Map<String, dynamic>> _preApprovedOrganizations = [
    {
      'label': 'Government',
      'icon': Icons.account_balance,
      'organizations': [
        'Federal Government Ministries, Departments & Agencies (MDAs)',
        'State Government MDAs',
        'Local Government Councils',
      ]
    },
    {
      'label': 'Education',
      'icon': Icons.school,
      'organizations': [
        'Federal Universities',
        'State Universities',
        'Private Universities',
        'Federal Teaching Hospitals',
        'State Teaching Hospitals',
        'Polytechnics',
        'Colleges of Education',
      ]
    },
    {
      'label': 'Health',
      'icon': Icons.local_hospital,
      'organizations': [
        'Federal Health Institutions',
        'State Health Institutions',
        'Private Hospitals',
      ]
    },
    {
      'label': 'Banking & Finance',
      'icon': Icons.monetization_on,
      'organizations': [
        'Commercial Banks',
        'Microfinance Banks',
        'Insurance Companies',
        'Asset Management Companies',
      ]
    },
    {
      'label': 'Private Sector',
      'icon': Icons.business,
      'organizations': [
        'Registered Corporate Organizations',
        'Faith-Based Institutions',
        'Approved Private Companies',
      ]
    },
  ];

  List<String> _filteredOrganizations = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _dateOfBirthController = TextEditingController();
    _jobTitleController = TextEditingController();
    _addressController = TextEditingController();
    _organizationSearchController = TextEditingController();
    _occupationController = TextEditingController();
    _employerNameController = TextEditingController();
    _workAddressController = TextEditingController();
    _yearsOfEmploymentController = TextEditingController();
    _lgaController = TextEditingController();
    _organizationSearchController.addListener(_onOrganizationSearch);

    _filteredOrganizations = _preApprovedOrganizations
        .expand((cat) => cat['organizations'] as List)
        .cast<String>()
        .toList();

    // Make sure we have the member's existing KYC loaded so we can pre-fill
    // already-saved data and skip steps that are already complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-run the pre-fill/skip logic whenever the KYC state transitions to
      // 'loaded' (e.g. after the initializeKYC() call we trigger here).
      ref.listenManual(kycProvider, (prev, next) {
        if (next.status == KYCStatus.loaded &&
            (prev == null || prev.status != KYCStatus.loaded)) {
          _loadExistingAndMaybeSkip();
        }
      });
      _loadExistingAndMaybeSkip();
    });
  }

  /// Pre-fill the form from any existing KYC submission and, if every field
  /// on this step is already present, jump straight to the next incomplete
  /// step (so the member is only asked for data that's actually missing).
  void _loadExistingAndMaybeSkip() {
    final kycState = ref.read(kycProvider);
    if (kycState.status == KYCStatus.initial ||
        kycState.status == KYCStatus.loading) {
      // Trigger a load; the listener above will re-run us when it completes.
      ref.read(kycProvider.notifier).initializeKYC();
      return;
    }

    final sub = kycState.submission;
    if (sub == null) {
      // No existing submission — start fresh.
      return;
    }

    setState(() {
      _selectedEmploymentType =
          sub.employmentType.isNotEmpty ? sub.employmentType : null;
      _selectedOrganization = sub.organizationName;
      _jobTitleController.text = sub.jobTitle;
      _selectedIncomeRange =
          sub.monthlyIncomeRange.isNotEmpty ? sub.monthlyIncomeRange : null;
      _dateOfBirthController.text = sub.dateOfBirth ?? '';
      _selectedGender = sub.gender;
      _addressController.text = sub.residentialAddress;
      _selectedCity = sub.city;
      _selectedState = sub.state;
      // New aligned fields
      _occupationController.text = sub.occupation ?? '';
      _employerNameController.text = sub.employerName ?? '';
      _workAddressController.text = sub.workAddress ?? '';
      _yearsOfEmploymentController.text = sub.yearsOfEmployment ?? '';
      _lgaController.text = sub.lga ?? '';
    });

    // If this whole step is already complete, skip forward to the first
    // incomplete step.
    if (_isStepComplete(sub)) {
      _skipToNextIncompleteStep(sub);
    }
  }

  bool _isStepComplete(KYCSubmission sub) {
    return sub.employmentType.isNotEmpty &&
        sub.organizationName != null &&
        sub.jobTitle.isNotEmpty &&
        sub.monthlyIncomeRange.isNotEmpty &&
        sub.dateOfBirth != null &&
        sub.residentialAddress.isNotEmpty &&
        sub.state != null;
  }

  /// Navigate to the first KYC section that still has missing data, in flow
  /// order: employment → identification → next-of-kin → bank → success.
  void _skipToNextIncompleteStep(KYCSubmission sub) {
    final missing = sub.missingSections;
    if (missing.isEmpty || missing.first == 'employment') {
      return; // stay here (or nothing missing — shouldn't reach via this entry)
    }
    final route = {
      'identification': '/kyc-id-upload',
      'nextOfKin': '/kyc-next-of-kin',
      'bank': '/kyc-bank-info',
    }[missing.first];
    if (route != null) {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  @override
  void dispose() {
    _dateOfBirthController.dispose();
    _jobTitleController.dispose();
    _addressController.dispose();
    _organizationSearchController.dispose();
    _occupationController.dispose();
    _employerNameController.dispose();
    _workAddressController.dispose();
    _yearsOfEmploymentController.dispose();
    _lgaController.dispose();
    super.dispose();
  }

  void _onOrganizationSearch() {
    setState(() {
      _searchQuery = _organizationSearchController.text.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredOrganizations = _preApprovedOrganizations
            .expand((cat) => cat['organizations'] as List)
            .cast<String>()
            .toList();
      } else {
        _filteredOrganizations = _preApprovedOrganizations
            .expand((cat) => cat['organizations'] as List)
            .cast<String>()
            .where((org) => org.toLowerCase().contains(_searchQuery))
            .toList();
      }
    });
  }

  void _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 70)),
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

    if (picked != null) {
      setState(() {
        _dateOfBirthController.text = '${picked.day}/${picked.month}/${picked.year}';
      });
    }
  }

  void _validateAndContinue() {
    final errors = <String>[];
    
    if (_selectedEmploymentType == null) {
      errors.add('Employment Type is required');
    }
    if (_selectedOrganization == null) {
      errors.add('Organization is required');
    }
    if (_jobTitleController.text.isEmpty) {
      errors.add('Job title is required');
    }
    if (_selectedIncomeRange == null) {
      errors.add('Monthly income range is required');
    }
    if (_dateOfBirthController.text.isEmpty) {
      errors.add('Date of birth is required');
    }
    if (_addressController.text.isEmpty) {
      errors.add('Residential address is required');
    }

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: errors.map((e) => Text('• $e')).toList(),
          ),
          backgroundColor: CoopvestColors.error,
        ),
      );
      return;
    }

    // Update KYC state
    ref.read(kycProvider.notifier).updateEmploymentDetails(
      employmentType: _selectedEmploymentType,
      organizationName: _selectedOrganization,
      jobTitle: _jobTitleController.text,
      monthlyIncomeRange: _selectedIncomeRange,
      occupation: _occupationController.text.trim().isEmpty
          ? null
          : _occupationController.text.trim(),
      employerName: _employerNameController.text.trim().isEmpty
          ? null
          : _employerNameController.text.trim(),
      workAddress: _workAddressController.text.trim().isEmpty
          ? null
          : _workAddressController.text.trim(),
      yearsOfEmployment: _yearsOfEmploymentController.text.trim().isEmpty
          ? null
          : _yearsOfEmploymentController.text.trim(),
    );

    ref.read(kycProvider.notifier).updatePersonalDetails(
      dateOfBirth: _dateOfBirthController.text,
      gender: _selectedGender,
    );

    ref.read(kycProvider.notifier).updateAddress(
      residentialAddress: _addressController.text,
      city: _selectedCity,
      stateValue: _selectedState,
      lga: _lgaController.text.trim().isEmpty ? null : _lgaController.text.trim(),
    );

    // Navigate to next step
    Navigator.of(context).pushNamed('/kyc-id-upload');
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
          'Employment Details',
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
                  _buildProgressStep(1, true),
                  _buildProgressLine(1),
                  _buildProgressStep(2, false),
                  _buildProgressLine(2),
                  _buildProgressStep(3, false),
                ],
              ),
              const SizedBox(height: 32),

              // Personal Information Section
              Text(
                'Personal Information',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 16),

              // Date of Birth
              AppTextField(
                label: 'Date of Birth *',
                hint: 'Select your date of birth',
                controller: _dateOfBirthController,
                readOnly: true,
                onTap: _selectDateOfBirth,
                suffixIcon: Icon(
                  Icons.calendar_today,
                  color: CoopvestColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 20),

              // Gender
              AppDropdown<String>(
                label: 'Gender (Optional)',
                value: _selectedGender,
                items: _genders.map((gender) => DropdownMenuItem(
                  value: gender,
                  child: Text(gender),
                )).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                hint: 'Select your gender',
              ),
              const SizedBox(height: 20),

              // Employment Section
              Text(
                'Employment Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 16),

              // Employment Type
              AppDropdown<String>(
                label: 'Employment Type *',
                value: _selectedEmploymentType,
                items: _employmentTypes.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type),
                )).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedEmploymentType = value;
                  });
                },
                hint: 'Select employment type',
              ),
              const SizedBox(height: 20),

              // Organization
              Text(
                'Organization *',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showOrganizationPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.dividerColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedOrganization ?? 'Select your organization',
                          style: TextStyle(
                            color: _selectedOrganization == null 
                                ? context.textSecondary 
                                : context.textPrimary,
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down, color: context.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Job Title
              AppTextField(
                label: 'Job Title *',
                hint: 'Enter your job title',
                controller: _jobTitleController,
              ),
              const SizedBox(height: 20),

              // Income Range
              AppDropdown<String>(
                label: 'Monthly Income Range *',
                value: _selectedIncomeRange,
                items: IncomeRanges.ranges.map((range) => DropdownMenuItem<String>(
                  value: range['value'] as String,
                  child: Text(range['label'] as String),
                )).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedIncomeRange = value;
                  });
                },
                hint: 'Select income range',
              ),
              const SizedBox(height: 20),

              // Occupation (aligned with registration)
              AppTextField(
                label: 'Occupation',
                hint: 'Enter your occupation',
                controller: _occupationController,
              ),
              const SizedBox(height: 20),

              // Employer name
              AppTextField(
                label: 'Employer Name',
                hint: 'Enter your employer / organization name',
                controller: _employerNameController,
              ),
              const SizedBox(height: 20),

              // Work address
              AppTextField(
                label: 'Work Address',
                hint: 'Enter your work address',
                controller: _workAddressController,
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // Years of employment
              AppTextField(
                label: 'Years of Employment',
                hint: 'e.g. 3',
                controller: _yearsOfEmploymentController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),

              // Address Section
              Text(
                'Residential Address',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 16),

              // Address
              AppTextField(
                label: 'Residential Address *',
                hint: 'Enter your full residential address',
                controller: _addressController,
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // LGA (aligned with registration)
              AppTextField(
                label: 'LGA',
                hint: 'Enter your Local Government Area',
                controller: _lgaController,
              ),
              const SizedBox(height: 20),

              // State & City
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      label: 'State *',
                      value: _selectedState,
                      items: _states.map((state) => DropdownMenuItem(
                        value: state,
                        child: Text(state),
                      )).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedState = value;
                        });
                      },
                      hint: 'State',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppDropdown<String>(
                      label: 'City *',
                      value: _selectedCity,
                      items: _cities.map((city) => DropdownMenuItem(
                        value: city,
                        child: Text(city),
                      )).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCity = value;
                        });
                      },
                      hint: 'City',
                    ),
                  ),
                ],
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

  void _showOrganizationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: context.scaffoldBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _organizationSearchController,
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search organization...',
                    hintStyle: TextStyle(color: context.textSecondary),
                    prefixIcon: Icon(Icons.search, color: context.textSecondary),
                    filled: true,
                    fillColor: context.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setModalState(() {});
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredOrganizations.length,
                  itemBuilder: (context, index) {
                    final org = _filteredOrganizations[index];
                    return ListTile(
                      title: Text(org, style: TextStyle(color: context.textPrimary)),
                      onTap: () {
                        setState(() {
                          _selectedOrganization = org;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStep(int step, bool isCompleted) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isCompleted ? CoopvestColors.primary : context.dividerColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isCompleted 
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : Text(
              '$step',
              style: TextStyle(
                color: context.textSecondary,
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