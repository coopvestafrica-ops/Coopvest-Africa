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
  bool _silentRetryScheduled = false;
  int _silentRetryCount = 0;
  static const int _maxSilentRetries = 3;

  /// Retry the KYC fetch quietly after a delay (gives a cold-starting backend
  /// time to wake). Silent retries never toggle the provider's loading status,
  /// so the dashboard stays on screen instead of flashing a spinner.
  void _scheduleSilentKycRetry() {
    if (_silentRetryScheduled || _silentRetryCount >= _maxSilentRetries) return;
    _silentRetryScheduled = true;
    Future.delayed(const Duration(seconds: 8), () async {
      _silentRetryScheduled = false;
      if (!mounted) return;
      _silentRetryCount++;
      await ref.read(kycProvider.notifier).initializeKYC(silent: true);
    });
  }

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

    // If the KYC fetch failed (e.g. a transient backend error / cold start on
    // Render), do NOT dead-end the member on a "Could not verify" screen.
    // Previously this blocked the app whenever /kyc/status timed out, even for
    // members whose KYC was already submitted/approved. Instead, trust the
    // profile's kycStatus returned by /auth/me: if it indicates the member has
    // submitted (or we simply cannot tell), let them through to the dashboard
    // and retry the KYC fetch in the background. Only prompt for KYC when the
    // profile itself explicitly says 'pending'.
    if (kycState.status == KYCStatus.error) {
      final profileStatus = (user?.kycStatus ?? '').toLowerCase();
      final profileSubmitted = profileStatus == 'submitted' ||
          profileStatus == 'approved' ||
          profileStatus == 'verified' ||
          profileStatus == 'in_review' ||
          profileStatus == 'rejected' ||
          profileStatus == 'unknown'; // backend unreachable — don't block
      if (profileSubmitted) {
        // Let the member straight through and refresh the KYC status via a
        // bounded, delayed, SILENT retry. The old per-build microtask retry
        // re-entered initializeKYC on every frame: each attempt flipped the
        // provider to loading (spinner) then back to error (dashboard),
        // trapping the app in a white-screen ↔ dashboard flicker loop after
        // every cold start while the backend was unreachable.
        _scheduleSilentKycRetry();
        return widget.child;
      }
      // Profile itself says pending AND we couldn't confirm via the KYC
      // endpoint — show a retryable error rather than forcing the flow.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              const Text('Could not verify your KYC status.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  _kycInitialized = false;
                  if (mounted) {
                    ref.read(kycProvider.notifier).initializeKYC();
                  }
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
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