import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/utils.dart';
import '../../data/models/auth_models.dart';
import '../../data/models/kyc_models.dart';
import '../../data/repositories/auth_repository.dart';

/// Auth State Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final ApiClient _apiClient;

  AuthNotifier(this._authRepository, this._apiClient) : super(const AuthState());

  /// Register FCM token with the backend after a successful auth event.
  Future<void> _registerFcmToken() async {
    try {
      final token = await NotificationService().getDeviceToken();
      if (token != null && token.isNotEmpty) {
        await _authRepository.registerFcmToken(token);
      }
    } catch (e) {
      logger.w('FCM token registration skipped: $e');
    }
  }

  /// Email + password login via Firebase Auth
  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final user = await _authRepository.login(email: email, password: password);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
      );

      _registerFcmToken();
    } catch (e) {
      logger.e('Login error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Google Sign-In via Firebase Auth
  Future<void> googleSignIn([String? unused]) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final user = await _authRepository.googleSignIn();

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
      );

      _registerFcmToken();
    } catch (e) {
      logger.e('Google Sign-In error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Register with Firebase Auth
  /// After successful registration, user remains authenticated
  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? referralCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final user = await _authRepository.register(
        email: email,
        password: password,
        name: name,
        phone: phone,
        referralCode: referralCode,
      );

      // User is now authenticated and should stay logged in
      // Set to authenticated (not just kycPending) so session persists
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
      );

      _registerFcmToken();
    } catch (e) {
      logger.e('Register error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Update user profile
  Future<void> updateProfile({String? name, String? phone}) async {
    try {
      final user = await _authRepository.updateProfile(name: name, phone: phone);
      state = state.copyWith(user: user);
    } catch (e) {
      logger.e('Update profile error: $e');
      rethrow;
    }
  }

  /// Submit KYC
  Future<void> submitKYC({required KYCSubmission submission}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _authRepository.submitKYC(submission: submission);
      // Mark KYC as submitted (awaiting admin review). We deliberately do NOT
      // set 'approved' here — approval is an admin action. Using 'submitted'
      // (rather than the old 'pending') lets AuthGuard distinguish members who
      // have already submitted from those who haven't, so the KYC prompt no
      // longer re-appears on every app start for pending-review members.
      state = state.copyWith(
        status: AuthStatus.kycPending,
        user: state.user?.copyWith(kycStatus: 'submitted'),
      );
    } catch (e) {
      logger.e('Submit KYC error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Mark the current user's KYC as submitted (awaiting review). Called by the
  /// KYC flow after a successful `/kyc/submit` so the auth state reflects the
  /// new lifecycle status without a full re-fetch.
  void markKycSubmitted() {
    if (state.user == null) return;
    state = state.copyWith(
      status: AuthStatus.kycPending,
      user: state.user!.copyWith(kycStatus: 'submitted'),
    );
  }

  /// Check KYC status
  Future<void> checkKYCStatus() async {
    try {
      final status = await _authRepository.getKYCStatus();
      if (status == 'approved') {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: state.user?.copyWith(kycStatus: 'approved'),
        );
      } else if (status == 'rejected') {
        state = state.copyWith(
          status: AuthStatus.kycRejected,
          user: state.user?.copyWith(kycStatus: 'rejected'),
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.kycPending,
          user: state.user?.copyWith(kycStatus: 'pending'),
        );
      }
    } catch (e) {
      logger.e('Check KYC status error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
    }
  }

  /// Logout — Firebase sign-out + backend token revocation
  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _authRepository.logout();
      _apiClient.clearAuthToken();
      state = const AuthState(status: AuthStatus.unauthenticated);
    } catch (e) {
      logger.e('Logout error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Refresh the Firebase ID token and re-attach to API client
  Future<void> refreshAccessToken() async {
    try {
      await _authRepository.refreshToken('');
    } catch (e) {
      logger.e('Refresh token error: $e');
      _apiClient.clearAuthToken();
      state = const AuthState(status: AuthStatus.unauthenticated);
      rethrow;
    }
  }

  /// Fetch and update the current user from the backend
  /// Also sets auth status to authenticated if user is found
  Future<void> getCurrentUser() async {
    try {
      final user = await _authRepository.getCurrentUser();
      state = state.copyWith(
        user: user,
        status: AuthStatus.authenticated,
      );
      logger.i('Current user fetched: ${user.email}');
    } catch (e) {
      logger.e('Get current user error: $e');
    }
  }

  /// Restore session from Firebase (called on app startup)
  Future<bool> restoreSession() async {
    try {
      final success = await _authRepository.restoreSession();
      if (success) {
        final user = await _authRepository.getCurrentUser();
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
        );
        logger.i('Session restored for: ${user.email}');
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Restore session error: $e');
      return false;
    }
  }

  /// Email verification — sends a verification email via Firebase
  Future<void> verifyEmail(String code) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _authRepository.verifyEmail(code);
      state = state.copyWith(status: AuthStatus.authenticated);
    } catch (e) {
      logger.e('Verify email error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Resend email verification
  Future<void> resendVerificationCode(String email) async {
    try {
      await _authRepository.resendVerificationCode(email);
    } catch (e) {
      logger.e('Resend verification error: $e');
      rethrow;
    }
  }

  /// Request password reset email via Firebase
  Future<void> requestPasswordReset(String email) async {
    try {
      await _authRepository.requestPasswordReset(email);
    } catch (e) {
      logger.e('Request password reset error: $e');
      rethrow;
    }
  }

  /// Reset password with action code from Firebase email link
  Future<void> resetPassword({
    required String code,
    required String newPassword,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _authRepository.resetPassword(code: code, newPassword: newPassword);
      state = state.copyWith(status: AuthStatus.unauthenticated);
    } catch (e) {
      logger.e('Reset password error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// Change password via Firebase re-authentication
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _authRepository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(status: AuthStatus.authenticated);
    } catch (e) {
      logger.e('Change password error: $e');
      state = state.copyWith(status: AuthStatus.error, error: e.toString());
      rethrow;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Auth Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(authRepository, apiClient);
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});

final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authProvider).status;
});

final isKycPendingProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isKycPending;
});

final isKycRejectedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isKycRejected;
});

final authErrorProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).error;
});
