import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/utils.dart';
import '../models/auth_models.dart';
import '../models/kyc_models.dart';

/// Auth Repository Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthRepository(apiClient);
});

/// Auth Repository — Supabase Auth + backend profile sync
///
/// Authentication flow:
///   1. Sign in/up directly with Supabase Auth SDK
///   2. Get the Supabase access token (JWT)
///   3. Send the access token to the backend to sync/create the profile row
///   4. Backend returns the full User payload
class AuthRepository {
  final ApiClient _apiClient;
  final sb.SupabaseClient _supabase = sb.Supabase.instance.client;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '1040576298736-991ja94slls4f6csarfheerlkg7bfpon.apps.googleusercontent.com',
  );
  User? _cachedUser;

  AuthRepository(this._apiClient);

  // ─── helpers ────────────────────────────────────────────────────────────────

  /// Attach the current Supabase session token to the API client.
  Future<String> _attachToken() async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw AuthException('No active Supabase session');
    final token = session.accessToken;
    _apiClient.setAuthToken(token);
    await TokenStorage.saveTokens(
      accessToken: token,
      refreshToken: session.refreshToken,
    );
    return token;
  }

  /// Check if there's a valid Supabase session.
  Future<bool> hasValidSession() async {
    return _supabase.auth.currentSession != null;
  }

  /// Get the current Supabase user.
  sb.User? get currentSupabaseUser => _supabase.auth.currentUser;

  /// Sync profile with backend after any Supabase sign-in and return User.
  Future<User> _syncWithBackend() async {
    await _attachToken();

    try {
      final response = await _apiClient.post('/auth/sync');
      final user = User.fromJson(response['user'] as Map<String, dynamic>);
      _cachedUser = user;
      return user;
    } catch (e) {
      logger.w('Backend sync failed: $e — using Supabase user data');

      // Fallback to /auth/me
      try {
        final meResponse = await _apiClient.get('/auth/me');
        if (meResponse is Map<String, dynamic>) {
          final userData = meResponse.containsKey('user')
              ? meResponse['user'] as Map<String, dynamic>
              : meResponse;
          final user = User.fromJson(userData);
          _cachedUser = user;
          return user;
        }
      } catch (meError) {
        logger.w('Backend /auth/me also failed: $meError');
      }

      // Last resort: build User from Supabase data
      final sbUser = _supabase.auth.currentUser;
      if (sbUser == null) throw AuthException('No authenticated user');
      final meta = sbUser.userMetadata ?? {};
      final user = User(
        id: sbUser.id,
        name: meta['name'] as String? ??
            sbUser.email?.split('@').first ??
            'User',
        email: sbUser.email ?? '',
        phone: meta['phone'] as String?,
        isEmailVerified: sbUser.emailConfirmedAt != null,
        kycStatus: 'pending',
        createdAt: DateTime.now(),
      );
      _cachedUser = user;
      return user;
    }
  }

  // ─── Sign-in methods ──────────────────────────────────────────────────────

  /// Email + password login
  Future<User> login({
    required String email,
    required String password,
    String? deviceId,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return await _syncWithBackend();
    } on sb.AuthException catch (e) {
      logger.e('Supabase login error: ${e.message}');
      throw AuthException(_mapSupabaseError(e));
    } catch (e) {
      logger.e('Login error: $e');
      rethrow;
    }
  }

  /// Register with email + password
  Future<User> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? deviceId,
    String? referralCode,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'name': name,
          'phone': phone,
          'referralCode': referralCode,
        },
      );

      if (response.user == null) {
        throw AuthException('Registration failed. Please try again.');
      }

      // If session exists, sync with backend. Otherwise email confirmation needed.
      if (response.session != null) {
        return await _syncWithBackend();
      } else {
        final sbUser = response.user!;
        final user = User(
          id: sbUser.id,
          name: name,
          email: sbUser.email ?? email,
          phone: phone,
          isEmailVerified: false,
          kycStatus: 'pending',
          createdAt: DateTime.now(),
        );
        _cachedUser = user;
        return user;
      }
    } on sb.AuthException catch (e) {
      logger.e('Supabase register error: ${e.message}');
      throw AuthException(_mapSupabaseError(e));
    } catch (e) {
      logger.e('Register error: $e');
      rethrow;
    }
  }

  /// Google Sign-In
  Future<User> googleSignIn({String? deviceId}) async {
    try {
      final googleAccount = await _googleSignIn.signIn();
      if (googleAccount == null) {
        throw AuthException('Google sign-in cancelled');
      }

      final googleAuth = await googleAccount.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) throw AuthException('Failed to get Google ID token');

      await _supabase.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      return await _syncWithBackend();
    } on sb.AuthException catch (e) {
      logger.e('Supabase Google sign-in error: ${e.message}');
      throw AuthException(_mapSupabaseError(e));
    } catch (e) {
      logger.e('Google sign-in error: $e');
      rethrow;
    }
  }

  /// Register FCM token with the backend
  Future<void> registerFcmToken(String fcmToken) async {
    try {
      await _apiClient.post('/notifications/fcm-token',
          data: {'token': fcmToken});
      logger.i('FCM token registered with backend');
    } catch (e) {
      logger.w('FCM token registration failed (non-fatal): $e');
    }
  }

  /// Update user profile on the backend
  Future<User> updateProfile({String? name, String? phone}) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (phone != null) data['phone'] = phone;

      final response = await _apiClient.put('/user/profile', data: data);
      final userData = response['user'] as Map<String, dynamic>;
      final user = _cachedUser?.copyWith(
        name: userData['name'] as String? ?? _cachedUser?.name,
        phone: userData['phone'] as String? ?? _cachedUser?.phone,
      ) ?? User.fromJson(userData);
      _cachedUser = user;
      return user;
    } catch (e) {
      logger.e('Update profile error: $e');
      rethrow;
    }
  }

  /// Submit KYC
  Future<void> submitKYC({required KYCSubmission submission}) async {
    try {
      await _apiClient.post('/auth/kyc/submit', data: submission.toJson());
    } catch (e) {
      logger.e('KYC submission error: $e');
      rethrow;
    }
  }

  /// Get KYC status
  Future<String> getKYCStatus() async {
    try {
      final response = await _apiClient.get('/auth/kyc/status');
      return response['status'] as String;
    } catch (e) {
      logger.e('Get KYC status error: $e');
      rethrow;
    }
  }

  /// Logout — signs out from Supabase and revokes backend tokens
  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout');
    } catch (e) {
      logger.w('Backend logout error (non-fatal): $e');
    } finally {
      await _googleSignIn.signOut();
      await _supabase.auth.signOut();
      _apiClient.clearAuthToken();
      await TokenStorage.clearTokens();
      _cachedUser = null;
    }
  }

  /// Get current user (with caching).
  ///
  /// On a transient backend failure (e.g. Render cold start, flaky mobile
  /// network), we must NOT fabricate a User with `kycStatus: 'pending'` and
  /// `registrationCompleted: false`. Doing so made AuthGuard believe the member
  /// had never registered/submitted KYC and re-prompted the login,
  /// onboarding, and KYC flows on every cold launch. Instead, prefer the last
  /// successfully cached profile; only fall back to a minimal Supabase-derived
  /// User (preserving any known KYC/registration state) when no cache exists.
  Future<User> getCurrentUser({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedUser != null) return _cachedUser!;

    try {
      final response = await _apiClient.get('/auth/me');
      if (response is Map<String, dynamic> && response.containsKey('user')) {
        _cachedUser =
            User.fromJson(response['user'] as Map<String, dynamic>);
      } else {
        _cachedUser = User.fromJson(response as Map<String, dynamic>);
      }
      return _cachedUser!;
    } catch (e) {
      logger.w('Get current user from backend failed: $e');

      // Serve the last known-good profile so a transient backend hiccup does
      // not kick the member out of their session or re-trigger KYC.
      if (_cachedUser != null) {
        return _cachedUser!;
      }

      final sbUser = _supabase.auth.currentUser;
      if (sbUser != null) {
        final meta = sbUser.userMetadata ?? {};
        // Preserve KYC/registration signals from Supabase metadata when
        // present; default to 'unknown' (not 'pending') so AuthGuard treats a
        // backend outage as "indeterminate" rather than "not submitted".
        final metaKyc = (meta['kyc_status'] ?? meta['kycStatus']) as String?;
        final metaReg = (meta['registration_completed'] ??
            meta['registrationCompleted']) as bool?;
        _cachedUser = User(
          id: sbUser.id,
          name: meta['name'] as String? ??
              sbUser.email?.split('@').first ??
              'User',
          email: sbUser.email ?? '',
          phone: meta['phone'] as String?,
          isEmailVerified: sbUser.emailConfirmedAt != null,
          kycStatus: (metaKyc != null && metaKyc.isNotEmpty)
              ? metaKyc
              : 'unknown',
          registrationCompleted: metaReg ?? false,
          createdAt: DateTime.now(),
        );
        return _cachedUser!;
      }
      rethrow;
    }
  }

  /// Password reset — sends Supabase reset email
  Future<void> requestPasswordReset(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email.trim());
    } on sb.AuthException catch (e) {
      // Always return success to prevent email enumeration
      logger.w('Password reset email error (non-fatal): ${e.message}');
    } catch (e) {
      logger.e('Request password reset error: $e');
      rethrow;
    }
  }

  /// Reset password with OTP token from Supabase email
  Future<void> resetPassword(
      {required String code, required String newPassword}) async {
    try {
      await _supabase.auth.verifyOTP(
        token: code,
        type: sb.OtpType.recovery,
      );
      await _supabase.auth.updateUser(sb.UserAttributes(password: newPassword));
    } on sb.AuthException catch (e) {
      throw AuthException(_mapSupabaseError(e));
    }
  }

  /// Change password — re-authenticates then updates in Supabase
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email == null) throw AuthException('Not authenticated');

      // Re-authenticate to confirm current password
      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      await _supabase.auth.updateUser(sb.UserAttributes(password: newPassword));
    } on sb.AuthException catch (e) {
      throw AuthException(_mapSupabaseError(e));
    }
  }

  /// Send / resend email verification
  Future<void> verifyEmail(String code) async {
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email == null) return;
      await _supabase.auth.resend(type: sb.OtpType.signup, email: email);
    } catch (e) {
      logger.e('Verify email error: $e');
      rethrow;
    }
  }

  /// Resend email verification
  Future<void> resendVerificationCode(String email) async {
    try {
      await _supabase.auth.resend(type: sb.OtpType.signup, email: email.trim());
      logger.i('Verification email resent to $email');
    } on sb.AuthException catch (e) {
      logger.e('Resend verification Supabase error: ${e.message}');
      throw AuthException(_mapSupabaseError(e));
    } catch (e) {
      logger.e('Resend verification error: $e');
      rethrow;
    }
  }

  /// Restore session on app startup using Supabase's persisted auth state
  Future<bool> restoreSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        logger.i('No Supabase session found — session not restored');
        return false;
      }

      logger.i(
          'Supabase session found: ${_supabase.auth.currentUser?.email} — restoring...');

      await _attachToken();

      try {
        await getCurrentUser(forceRefresh: true);
        logger.i('Session restored successfully from backend');
      } catch (e) {
        logger.w('Backend user fetch failed during restore: $e');
      }

      return true;
    } catch (e) {
      logger.e('Session restore failed: $e');
      if (_supabase.auth.currentSession == null) {
        _apiClient.clearAuthToken();
        await TokenStorage.clearTokens();
      }
      return false;
    }
  }

  /// Restore session for biometric login
  Future<User> restoreSessionWithBiometric() async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw AuthException('No authenticated session found');
    await _attachToken();
    return await getCurrentUser(forceRefresh: true);
  }

  /// Token refresh — uses Supabase session refresh
  Future<AuthResponse> refreshToken(String ignored) async {
    try {
      final currentSession = _supabase.auth.currentSession;
      if (currentSession == null) throw AuthException('No session to refresh');

      final response = await _supabase.auth.refreshSession();
      final newSession = response.session;
      if (newSession == null) throw AuthException('Token refresh failed');

      await TokenStorage.saveTokens(
        accessToken: newSession.accessToken,
        refreshToken: newSession.refreshToken,
      );
      _apiClient.setAuthToken(newSession.accessToken);

      final user = await getCurrentUser(forceRefresh: true);
      return AuthResponse(
        accessToken: newSession.accessToken,
        refreshToken: newSession.refreshToken ?? '',
        user: user,
        expiresAt: newSession.expiresAt != null
            ? DateTime.fromMillisecondsSinceEpoch(newSession.expiresAt! * 1000)
            : DateTime.now().add(const Duration(hours: 1)),
      );
    } catch (e) {
      logger.e('Token refresh error: $e');
      rethrow;
    }
  }

  Future<String> getUserId() async => (await getCurrentUser()).id;
  Future<String> getUserName() async => (await getCurrentUser()).name;
  Future<String?> getUserPhone() async => (await getCurrentUser()).phone;

  // ─── Error mapping ─────────────────────────────────────────────────────────

  String _mapSupabaseError(sb.AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') ||
        msg.contains('invalid email or password') ||
        msg.contains('user not found')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email already')) {
      return 'An account already exists with this email address.';
    }
    if (msg.contains('password') && msg.contains('short')) {
      return 'Password is too weak. Use at least 8 characters.';
    }
    if (msg.contains('email') && msg.contains('invalid')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('disabled') || msg.contains('banned')) {
      return 'This account has been disabled.';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    if (msg.contains('expired')) {
      return 'This link has expired. Please request a new one.';
    }
    return e.message.isNotEmpty
        ? e.message
        : 'Authentication failed. Please try again.';
  }
}
