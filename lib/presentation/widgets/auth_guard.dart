import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme_config.dart';
import '../../data/models/auth_models.dart';
import '../../data/models/kyc_models.dart';
import '../providers/auth_provider.dart';
import '../providers/kyc_provider.dart';
import '../screens/auth/registration_onboarding_screen.dart';
import '../screens/kyc/kyc_employment_details_screen.dart';
import '../screens/membership/account_activation_screen.dart';

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

  /// Safety net: if /kyc/status hasn't resolved within this window, stop
  /// blocking and route from the profile alone. Backs up the fast request
  /// timeout so a member can never be stuck on the loading screen.
  static const Duration _guardTimeout = Duration(seconds: 15);
  bool _guardTimedOut = false;

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

  /// True when the profile's kycStatus (from /auth/me) already tells us the
  /// member has submitted KYC — or that we simply can't tell because the
  /// backend was unreachable ('unknown'). In these cases AuthGuard can route
  /// immediately without an extra /kyc/status round-trip.
  bool _profileSubmitted(String profileStatus) {
    return profileStatus == 'submitted' ||
        profileStatus == 'approved' ||
        profileStatus == 'verified' ||
        profileStatus == 'in_review' ||
        profileStatus == 'rejected' ||
        profileStatus == 'unknown'; // backend unreachable — don't block
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
      _guardTimedOut = false;
      Future.microtask(() {
        if (mounted) ref.read(kycProvider.notifier).initializeKYC();
      });
      // Safety net: if the probe hasn't resolved, fall back to profile-driven
      // routing so a hung screen can never strand the member.
      Future.delayed(_guardTimeout, () {
        if (!mounted) return;
        setState(() => _guardTimedOut = true);
      });
    }

    // Once /kyc/status has resolved, decide from its returned submission.
    if (kycState.status == KYCStatus.loaded ||
        kycState.status == KYCStatus.submitted) {
      if (!_hasSubmittedKyc(kycState)) {
        // Member hasn't submitted KYC yet — guide them through it.
        return const KYCEmploymentDetailsScreen(isFromRegistration: false);
      }
      // KYC submitted — now enforce the membership activation gate:
      // if the member's KYC is approved but the registration fee hasn't been
      // settled, route them to the Account Activation screen instead of the
      // dashboard. The server-side gate is authoritative; this mirrors it so
      // the mobile UI shows the correct onboarding step.
      final activation = _activationGate(user);
      if (activation == _ActivationStage.kycApprovedFeePending) {
        return const AccountActivationScreen();
      }
      // Everything satisfied (or KYC awaiting admin approval) → dashboard.
      return widget.child;
    }

    // The member's profile already indicates their KYC was submitted (or that
    // the backend is unreachable), so don't block navigation on a redundant
    // /kyc/status round-trip. Refresh it in the background instead.
    final profileStatus = (user?.kycStatus ?? '').toLowerCase();
    if (_profileSubmitted(profileStatus) || _guardTimedOut) {
      _scheduleSilentKycRetry();
      // Enforce the activation gate from the profile alone: if the backend says
      // KYC is approved but the registration fee isn't settled yet, route to
      // Account Activation rather than the dashboard.
      final activation = _activationGate(user);
      if (activation == _ActivationStage.kycApprovedFeePending) {
        return const AccountActivationScreen();
      }
      return widget.child;
    }

    // Still loading and the profile is ambiguous ('pending' — could mean never
    // submitted OR awaiting admin review). Show a branded loading screen while
    // the fast-timed /kyc/status probe completes.
    if (kycState.isLoading || kycState.status == KYCStatus.initial) {
      return const _KycLoadingScreen();
    }

    // The probe failed and the profile explicitly says 'pending' — we can't
    // confirm submission and don't want to dead-end the member, so show a
    // retryable error rather than forcing the flow.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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

  /// Determines the membership-activation stage from the profile alone.
  ///
  /// The activation screen only renders when the *backend* confirms KYC is
  /// approved (kyc_verified) but the registration fee is not yet settled. A
  /// member whose KYC is merely submitted-but-awaiting-approval, or a profile
  /// that is 'unknown' (backend unreachable) is NOT routed here — we must never
  /// block an existing member behind a stale/ambiguous flag.
  _ActivationStage _activationGate(User? user) {
    if (user == null) return _ActivationStage.active;
    final kycStatus = (user.kycStatus ?? '').toLowerCase();
    final kycApproved = kycStatus == 'approved' || kycStatus == 'verified';
    if (!kycApproved) {
      // KYC not (yet) confirmed approved — not the activation screen's job.
      return _ActivationStage.awaitingKyc;
    }
    if (!user.registrationFeePaid) {
      return _ActivationStage.kycApprovedFeePending;
    }
    return _ActivationStage.active;
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

/// Membership-activation stages used by AuthGuard to decide between the
/// dashboard, the KYC flow, and the Account Activation (registration fee) screen.
enum _ActivationStage {
  /// KYC not yet confirmed approved — handled by the KYC flow.
  awaitingKyc,
  /// KYC approved but registration fee not settled → Account Activation screen.
  kycApprovedFeePending,
  /// Fully activated (or KYC awaiting admin approval / unflagged) → dashboard.
  active,
}

/// Branded loading placeholder shown only while AuthGuard waits on the
/// (fast-timed) /kyc/status probe. Uses the app's background color so it
/// renders cleanly in light and dark themes instead of a bare black spinner.
class _KycLoadingScreen extends StatelessWidget {
  const _KycLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CoopvestColors.primary.withOpacity(0.12),
              ),
              child: const Icon(
                Icons.account_balance_rounded,
                size: 36,
                color: CoopvestColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: CoopvestColors.primary),
            const SizedBox(height: 24),
            Text(
              'Checking your account...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CoopvestColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}