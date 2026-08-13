import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../data/models/kyc_models.dart';
import '../../../presentation/providers/kyc_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import '../../../presentation/widgets/common/inputs.dart';

/// KYC ID Upload Screen
class KYCIDUploadScreen extends ConsumerStatefulWidget {
  const KYCIDUploadScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KYCIDUploadScreen> createState() => _KYCIDUploadScreenState();
}

class _KYCIDUploadScreenState extends ConsumerState<KYCIDUploadScreen> {
  late TextEditingController _idNumberController;
  late TextEditingController _staffIdController;

  String? _selectedIDType;
  String? _idImagePath;

  final List<Map<String, dynamic>> _idTypes = IDTypes.types;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _idNumberController = TextEditingController();
    _staffIdController = TextEditingController();
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

  /// Pre-fill from an existing KYC submission and skip this step entirely if
  /// it's already complete.
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
      _selectedIDType = sub.idType.isNotEmpty ? sub.idType : null;
      _idNumberController.text = sub.idNumber ?? '';
      _staffIdController.text = sub.staffId ?? '';
      _idImagePath = sub.idPhotoPath;
    });

    if (sub.idType.isNotEmpty &&
        sub.idNumber != null &&
        sub.idPhotoPath != null) {
      // Identification complete — jump to the next incomplete step.
      _skipToNextIncompleteStep(sub);
    }
  }

  void _skipToNextIncompleteStep(KYCSubmission sub) {
    final missing = sub.missingSections;
    if (missing.isEmpty || missing.first == 'identification') return;
    final route = {
      'nextOfKin': '/kyc-next-of-kin',
      'bank': '/kyc-bank-info',
    }[missing.first];
    if (route != null) {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    _staffIdController.dispose();
    super.dispose();
  }

  Future<void> _pickIDImage() async {
    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.scaffoldBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose Image Source',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildImageSourceOption(
                      icon: Icons.camera_alt,
                      label: 'Camera',
                      onTap: _pickFromCamera,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildImageSourceOption(
                      icon: Icons.photo_library,
                      label: 'Gallery',
                      onTap: _pickFromGallery,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.dividerColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: CoopvestColors.primary, size: 48),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    Navigator.of(context).pop();
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (photo != null && mounted) {
        setState(() {
          _idImagePath = photo.path;
        });
      }
    } catch (e) {
      _showError('Failed to capture image: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    Navigator.of(context).pop();
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() {
          _idImagePath = image.path;
        });
      }
    } catch (e) {
      _showError('Failed to select image: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: CoopvestColors.error),
      );
    }
  }

  void _validateAndContinue() {
    if (_selectedIDType == null) {
      _showError('Please select an ID type');
      return;
    }
    if (_idNumberController.text.isEmpty) {
      _showError('Please enter your ID number');
      return;
    }
    if (_idImagePath == null) {
      _showError('Please upload a photo of your ID');
      return;
    }

    // Save ID details (and optional staff id) into the KYC state, then upload
    // the ID photo and capture a selfie next.
    final staffId = _staffIdController.text.trim().isEmpty
        ? null
        : _staffIdController.text.trim();
    ref.read(kycProvider.notifier).updateIDDetails(
          idType: _selectedIDType,
          idNumber: _idNumberController.text.trim(),
          idPhotoPath: _idImagePath,
          staffId: staffId,
        );

    _uploadAndContinue();
  }

  Future<void> _uploadAndContinue() async {
    // Only upload if the stored path looks like a local file (not an existing
    // remote URL already on the server).
    final isLocalFile = _idImagePath != null &&
        !_idImagePath!.startsWith('http') &&
        File(_idImagePath!).existsSync();
    if (isLocalFile) {
      try {
        await ref.read(kycProvider.notifier).uploadIDDocument(_idImagePath!);
      } catch (e) {
        _showError('Failed to upload ID photo: $e');
        return;
      }
    }
    if (mounted) Navigator.of(context).pushNamed('/kyc-selfie');
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
          'ID Verification',
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
                  _buildProgressStep(2, true),
                  _buildProgressLine(2),
                  _buildProgressStep(3, false),
                  _buildProgressLine(3),
                  _buildProgressStep(4, true),
                ],
              ),
              const SizedBox(height: 32),

              Text(
                'Upload Your ID',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Please provide a valid government-issued ID for verification',
                style: TextStyle(color: context.textSecondary),
              ),
              const SizedBox(height: 24),

              AppDropdown<String>(
                label: 'ID Type *',
                hint: 'Select ID type',
                value: _selectedIDType,
                items: _idTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['value'] as String?,
                    child: Text(type['label'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedIDType = value;
                  });
                },
              ),
              const SizedBox(height: 20),

              AppTextField(
                label: 'ID Number *',
                hint: 'Enter your ID number',
                controller: _idNumberController,
              ),
              const SizedBox(height: 20),

              AppTextField(
                label: 'Staff ID Number (if employed)',
                hint: 'Leave blank if not applicable',
                controller: _staffIdController,
              ),
              const SizedBox(height: 24),

              Text(
                'ID Photo *',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickIDImage,
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.dividerColor, style: BorderStyle.solid),
                  ),
                  child: _idImagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(_idImagePath!), fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 48, color: context.textSecondary),
                            const SizedBox(height: 12),
                            Text('Tap to upload ID photo', style: TextStyle(color: context.textSecondary)),
                          ],
                        ),
                ),
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
