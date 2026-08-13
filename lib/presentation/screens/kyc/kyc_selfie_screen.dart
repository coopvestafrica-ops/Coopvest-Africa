import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/theme_config.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/kyc_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';

/// KYC Selfie Capture Screen
///
/// Captures a real selfie using the device camera (or gallery as a fallback),
/// uploads it via the KYC repository, then submits the KYC record.
class KYCSelfieScreen extends ConsumerStatefulWidget {
  const KYCSelfieScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KYCSelfieScreen> createState() => _KYCSelfieScreenState();
}

class _KYCSelfieScreenState extends ConsumerState<KYCSelfieScreen> {
  File? _selfieFile;
  bool _isCapturing = false;
  bool _showGuidelines = true;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showGuidelines = false);
    });
  }

  Future<void> _captureSelfie() async {
    setState(() {
      _isCapturing = true;
      _showGuidelines = false;
    });
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (photo == null) {
        // User cancelled — no error.
        if (mounted) setState(() => _isCapturing = false);
        return;
      }
      if (mounted) {
        setState(() => _selfieFile = File(photo.path));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selfie captured successfully'),
            backgroundColor: CoopvestColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture selfie: $e'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() => _showGuidelines = false);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image == null) return;
      if (mounted) setState(() => _selfieFile = File(image.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select image: $e'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose Image Source',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color:
                    Theme.of(sheetContext).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSourceOption(
                    context: sheetContext,
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _captureSelfie();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSourceOption(
                    context: sheetContext,
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickFromGallery();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: CoopvestColors.primary, size: 48),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _validateAndSubmit() async {
    if (_selfieFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a selfie'),
          backgroundColor: CoopvestColors.error,
        ),
      );
      return;
    }

    try {
      // Upload the selfie and store the returned storage URL on the KYC
      // submission before submitting the whole record.
      await ref
          .read(kycProvider.notifier)
          .uploadSelfie(_selfieFile!.path);
      await ref.read(kycProvider.notifier).submitKYC();
      // Reflect the new lifecycle status in the auth state so AuthGuard won't
      // re-prompt KYC after this submission.
      ref.read(authProvider.notifier).markKycSubmitted();
      if (mounted) Navigator.of(context).pushReplacementNamed('/kyc-next-of-kin');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit KYC: $e'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = ref.watch(kycProvider).isSubmitting;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Take Selfie',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.grey[900],
                    child: _selfieFile == null
                        ? _buildCameraPreview()
                        : ClipRect(
                            child:
                                Image.file(_selfieFile!, fit: BoxFit.cover),
                          ),
                  ),
                  if (_showGuidelines && _selfieFile == null)
                    _buildGuidelinesOverlay(),
                  if (!_showGuidelines && _selfieFile == null)
                    _buildFaceFrameGuide(),
                ],
              ),
            ),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_isCapturing || isSubmitting)
                    const Text('Capturing...',
                        style: TextStyle(color: Colors.white, fontSize: 16))
                  else if (_selfieFile == null)
                    const Text(
                      'Position your face in the frame',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    )
                  else
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle,
                            color: CoopvestColors.success),
                        SizedBox(width: 8),
                        Text(
                          'Selfie captured successfully',
                          style: TextStyle(
                              color: CoopvestColors.success, fontSize: 14),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  if (_selfieFile == null)
                    _isCapturing
                        ? const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          )
                        : Center(
                            child: GestureDetector(
                              onTap: _captureSelfie,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                      color: Colors.white, width: 4),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: CoopvestColors.primary,
                                  size: 40,
                                ),
                              ),
                            ),
                          )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Retake',
                            onPressed: () => setState(() {
                              _selfieFile = null;
                              _showGuidelines = true;
                            }),
                            textStyle: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Submit',
                            onPressed: _validateAndSubmit,
                            isEnabled: !isSubmitting,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (_selfieFile == null)
                    TextButton(
                      onPressed: _showImageSourceSheet,
                      child: const Text(
                        'Choose from Gallery',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: () => setState(
                          () => _showGuidelines = !_showGuidelines),
                      child: Text(
                        _showGuidelines
                            ? 'Hide Guidelines'
                            : 'Show Guidelines',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
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

  Widget _buildCameraPreview() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, color: Colors.grey[700], size: 80),
            const SizedBox(height: 16),
            Text('Camera Preview',
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to take a selfie',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );

  Widget _buildGuidelinesOverlay() => Container(
        color: Colors.black.withOpacity(0.7),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Selfie Guidelines',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildGuidelineItem(
                Icons.wb_sunny_outlined, 'Ensure good lighting'),
            _buildGuidelineItem(
                Icons.face_retouching_natural, 'Remove glasses or hats'),
            _buildGuidelineItem(
                Icons.center_focus_strong, 'Keep your face in the frame'),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Got it',
              onPressed: () => setState(() => _showGuidelines = false),
              width: 120,
            ),
          ],
        ),
      );

  Widget _buildGuidelineItem(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Icon(icon, color: CoopvestColors.primary, size: 24),
            const SizedBox(width: 16),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      );

  Widget _buildFaceFrameGuide() => Center(
        child: Container(
          width: 280,
          height: 380,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
            borderRadius: BorderRadius.circular(140),
          ),
        ),
      );
}
