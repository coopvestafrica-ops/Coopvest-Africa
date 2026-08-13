import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/kyc_models.dart';
import '../providers/auth_provider.dart';
import '../providers/kyc_provider.dart';
import '../screens/auth/registration_onboarding_screen.dart';
import '../screens/kyc/kyc_employment_details_screen.dart';

/// AuthGuard determines where to send the user based on their auth state:
/// - Not authenticated → child (Welcome/Login)
/// - Authenticated but registration not complete → Continue registration
/// - Authenticated but KYC not yet submitted → Continue KYC
/// - Authenticated and KYC already submitted (pending review/approved) → Dashboard
///
/// Previously this forced the KYC flow whenever `user.kycStatus != 'approved'`,
/// which re-prompted KYC on every app start for members who had already
/// submitted but were still awaiting admin approval. We now gate on whether the
/// member has *submitted* KYC (loaded from the backend), not on approval.
class AuthGuard extends ConsumerStatefulWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  ConsumerState<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends ConsumerState<AuthGuard> {
  bool _kycInitialized = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // If not authenticated, show the child (WelcomeScreen)
    if (!authState.isAuthenticated) {
      return widget.child;
    }

    // Check if registration is complete
    if (user != null && !user.registrationCompleted) {
      return const RegistrationOnboardingScreen(registrationData: {});
    }

    // Registration complete — ensure we know the member's KYC submission
    // status before deciding whether to prompt for KYC. Fetch once per
    // authenticated session.
    final kycState = ref.watch(kycProvider);
    if (!_kycInitialized) {
      _kycInitialized = true;
      Future.microtask(() {
        if (mounted) ref.read(kycProvider.notifier).initializeKYC();
      });
    }

    // While KYC status is still loading, show a neutral placeholder so we
    // don't flash the KYC flow for users who have already submitted.
    if (kycState.isLoading || kycState.status == KYCStatus.initial) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final submitted = _hasSubmittedKyc(kycState);
    if (!submitted) {
      // Member hasn't submitted KYC yet — guide them through it.
      return const KYCEmploymentDetailsScreen(isFromRegistration: false);
    }

    // KYC submitted (pending review / approved / rejected) → dashboard.
    return widget.child;
  }

  /// True when the member has already submitted KYC, i.e. their KYC record
  /// carries a "submitted" lifecycle status (not just the initial "pending"
  /// draft that exists before any submission).
  bool _hasSubmittedKyc(KYCState kycState) {
    final status = kycState.submission?.status ?? 'pending';
    return status == 'submitted' ||
        status == 'in_review' ||
        status == 'verified' ||
        status == 'approved' ||
        status == 'rejected';
  }
}