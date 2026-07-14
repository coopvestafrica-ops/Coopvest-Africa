import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'core/services/logger_service.dart';
import 'config/app_config.dart';
import 'config/theme_config.dart';
import 'config/theme_enhanced.dart';
import 'core/services/feature_service.dart';
import 'core/services/security_service.dart';
import 'core/services/notification_service.dart';
import 'data/models/auth_models.dart';
import 'data/models/loan_models.dart';
import 'data/repositories/auth_repository.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/screens/auth/welcome_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_step1_screen.dart';
import 'presentation/screens/auth/register_step2_screen.dart';
import 'presentation/screens/auth/registration_onboarding_screen.dart';
import 'presentation/screens/auth/contribution_type_selection_screen.dart';
import 'presentation/screens/auth/google_complete_screen.dart';
import 'presentation/screens/auth/salary_deduction_consent_screen.dart';
import 'presentation/screens/auth/account_activation_screen.dart';
import 'presentation/screens/auth/forgot_password_screen.dart';
import 'presentation/screens/auth/reset_password_otp_screen.dart';
import 'presentation/screens/auth/email_verification_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'presentation/screens/support/support_home_screen.dart';
import 'presentation/screens/support/ticket_creation_screen.dart';
import 'presentation/screens/support/ticket_list_screen.dart';
import 'presentation/screens/support/ticket_detail_screen.dart';
import 'presentation/screens/home/home_dashboard_screen.dart';
import 'presentation/screens/main_container.dart';
import 'presentation/screens/kyc/kyc_employment_details_screen.dart';
import 'presentation/screens/kyc/kyc_id_upload_screen.dart';
import 'presentation/screens/kyc/kyc_selfie_screen.dart';
import 'presentation/screens/kyc/kyc_success_screen.dart';
import 'presentation/screens/kyc/kyc_bank_info_screen.dart';
import 'presentation/screens/loan/loan_dashboard_screen.dart';
import 'presentation/screens/loan/loan_application_screen.dart';
import 'presentation/screens/loan/guarantor_verification_screen.dart';
import 'presentation/screens/loan/loan_details_screen.dart';
import 'presentation/screens/profile/profile_settings_screen.dart';
import 'presentation/screens/security/security_settings_screen.dart';
import 'presentation/screens/savings/savings_goals_screen.dart';
import 'presentation/screens/search/global_search_screen.dart';
import 'config/env_config.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/rollover/rollover_eligibility_screen.dart';
import 'presentation/screens/rollover/rollover_request_screen.dart';
import 'presentation/screens/rollover/guarantor_consent_screen.dart';
import 'presentation/screens/rollover/guarantor_response_screen.dart';
import 'presentation/screens/rollover/rollover_status_screen.dart';
import 'presentation/widgets/auth_guard.dart';
import 'core/services/connectivity_service.dart';
import 'presentation/widgets/error_widgets.dart';

// Supabase project credentials (anon key is safe to embed in client code)
const _supabaseUrl = 'https://nyoauzqezpxeonmrxxgi.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im55b2F1enFlenB4ZW9ubXJ4eGdpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyODI3MzUsImV4cCI6MjA4OTg1ODczNX0.5WfECoO2Xu5VfBzFbQd2CA8rIeBVnOkiKmnnbYRA8VU';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Top-level FCM background message handler.
/// MUST be a top-level function — FCM runs it in a separate isolate.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM Background] Message received: ${message.messageId}');
  debugPrint('[FCM Background] Type: ${message.data['type']}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up global error handler for uncaught Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'Uncaught Flutter Error',
      details.exception,
      details.stack,
    );
    
    // Report to Crashlytics in production
    FirebaseCrashlytics.instance.recordError(
      details.exception,
      details.stack,
      reason: 'Uncaught Flutter error in main isolate',
    );
    
    // Re-throw to let Flutter handle it
    FlutterError.presentError(details);
  };

  // Set up async error handler for unhandled promise rejections
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error(
      'Unhandled Platform Error',
      error,
      stack,
    );
    
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: 'Unhandled platform error',
    );
    
    return true;
  };

  const envString = String.fromEnvironment('ENV', defaultValue: 'prod');
  final env = Environment.values.firstWhere(
    (e) => e.toString().split('.').last == envString,
    orElse: () => Environment.prod,
  );
  EnvironmentContext.setEnvironment(env);

  // Initialize Supabase Auth
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  final securityService = SecurityService();
  await securityService.initialize();

  final featureService = FeatureService();
  try {
    await featureService.init().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Feature service initialization failed: $e');
  }

  // Firebase is kept for push notifications, analytics and crashlytics only.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
    await NotificationService().init();
  } catch (e) {
    debugPrint('Firebase/Notification initialization failed: $e');
  }

  runApp(
    const ProviderScope(
      child: CoopvestApp(),
    ),
  );
}

class CoopvestApp extends ConsumerStatefulWidget {
  const CoopvestApp({Key? key}) : super(key: key);

  @override
  ConsumerState<CoopvestApp> createState() => _CoopvestAppState();
}

class _CoopvestAppState extends ConsumerState<CoopvestApp>
    with WidgetsBindingObserver {
  bool _isSessionRestored = false;
  bool _isCheckingBiometric = false;
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    }
    if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      _checkBiometricOnResume();
    }
  }

  Future<void> _restoreSession() async {
    try {
      final success =
          await ref.read(authProvider.notifier).restoreSession();
      if (success) {
        debugPrint('[CoopvestApp] Session restored successfully');
      } else {
        debugPrint('[CoopvestApp] No session to restore');
      }
    } catch (e) {
      debugPrint('[CoopvestApp] Session restore error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSessionRestored = true;
        });
      }
    }
  }

  Future<void> _checkBiometricOnResume() async {
    if (_isCheckingBiometric) return;

    final authStatus = ref.read(authStatusProvider);
    if (authStatus != AuthStatus.authenticated) return;

    final securityService = SecurityService();
    final isBiometricEnabled = await securityService.isBiometricEnabled();

    if (isBiometricEnabled) {
      _isCheckingBiometric = true;
      try {
        final authenticated = await securityService.authenticate();
        if (!authenticated && mounted) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            const SnackBar(
              content: Text('Biometric authentication required'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } finally {
        _isCheckingBiometric = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final authStatus = ref.watch(authStatusProvider);

    final app = MaterialApp(
      title: AppConfig.appName,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: CoopvestTheme.lightTheme,
      darkTheme: CoopvestTheme.darkTheme,
      themeMode: themeMode,
      home: Consumer(
        builder: (context, ref, _) {
          // Listen for connectivity changes
          final connectivity = ref.watch(connectivityProvider);
          
          return Column(
            children: [
              // Offline banner at top when offline
              if (!connectivity.isOnline)
                const OfflineBanner(),
              
              // Main app content with AuthGuard
              Expanded(
                child: AuthGuard(
                  child: authStatus == AuthStatus.authenticated
                      ? const MainContainer()
                      : const WelcomeScreen(),
                ),
              ),
            ],
          );
        },
      ),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterStep1Screen(),
        '/register-step2': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, String>?;
          return RegisterStep2Screen(
            email: args?['email'] ?? '',
            registrationData: args ?? {},
          );
        },
        '/contribution-type-selection': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, String>?;
          return ContributionTypeSelectionScreen(
            registrationData: args ?? {},
          );
        },
        '/register-step3': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, String>?;
          return RegistrationOnboardingScreen(
            registrationData: args ?? {},
          );
        },
        '/salary-deduction-consent': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, String>?;
          return SalaryDeductionConsentScreen(
            registrationData: args ?? {},
          );
        },
        '/account-activation': (context) => const AccountActivationScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/reset-password-otp': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return ResetPasswordOtpScreen(email: args?['email'] ?? '');
        },
        '/verify-email': (context) => const EmailVerificationScreen(),
        '/google-complete': (context) {
          final googleUser = ModalRoute.of(context)?.settings.arguments
              as GoogleSignInAccount?;
          return CompleteRegistrationScreen(googleUser: googleUser!);
        },

        '/support': (context) => const SupportHomeScreen(),
        '/create-ticket': (context) => const TicketCreationScreen(),
        '/tickets': (context) => const TicketListScreen(),
        '/ticket-detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return TicketDetailScreen(
            ticketId: args?['ticketId'] ?? '',
          );
        },

        '/kyc-employment-details': (context) =>
            const KYCEmploymentDetailsScreen(),
        '/kyc-id-upload': (context) => const KYCIDUploadScreen(),
        '/kyc-selfie': (context) => const KYCSelfieScreen(),
        '/kyc-bank-info': (context) => const KYCBankInfoScreen(),
        '/kyc-success': (context) => const KYCSuccessScreen(),
        '/kyc-complete': (context) => const KYCSuccessScreen(),

        '/home': (context) => const MainContainer(),

        '/loan-dashboard': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return LoanDashboardScreen(
            userId: args?['userId'] ?? '',
            userName: args?['userName'] ?? '',
            userPhone: args?['userPhone'] ?? '',
          );
        },
        '/loan-application': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return LoanApplicationScreen(
            userId: args?['userId'] ?? '',
            userName: args?['userName'] ?? 'User',
            userPhone: args?['userPhone'] ?? '',
          );
        },
        '/loan-details': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return LoanDetailsScreen(
            loanId: args?['loanId'] ?? '',
          );
        },
        '/guarantor-verification': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return GuarantorVerificationScreen(
            loanId: args?['loanId'] ?? '',
            guarantorId: args?['guarantorId'] ?? '',
            borrowerName: args?['borrowerName'] ?? '',
            guarantorName: args?['guarantorName'] ?? '',
            loanAmount: args?['loanAmount']?.toDouble() ?? 0.0,
            loanType: args?['loanType'] ?? 'Quick Loan',
            loanTenor: args?['loanTenor'] ?? 4,
          );
        },

        '/profile': (context) => const ProfileSettingsScreen(),
        '/security': (context) => const SecuritySettingsScreen(),

        '/savings-goal': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return SavingsGoalsScreen(
            userId: args?['userId'] ?? '',
          );
        },

        '/search': (context) => const GlobalSearchScreen(),

        '/rollover/eligibility': (context) {
          final loan =
              ModalRoute.of(context)?.settings.arguments as Loan;
          return RolloverEligibilityScreen(loan: loan);
        },
        '/rollover/request': (context) {
          final loan =
              ModalRoute.of(context)?.settings.arguments as Loan;
          return RolloverRequestScreen(loan: loan);
        },
        '/rollover/consent': (context) {
          final rolloverId =
              ModalRoute.of(context)?.settings.arguments as String;
          return GuarantorConsentScreen(rolloverId: rolloverId);
        },
        '/rollover/status': (context) {
          final rolloverId =
              ModalRoute.of(context)?.settings.arguments as String;
          return RolloverStatusScreen(rolloverId: rolloverId);
        },
        '/rollover/guarantor-response': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, String>;
          return GuarantorResponseScreen(
            rolloverId: args['rolloverId']!,
            guarantorId: args['guarantorId']!,
          );
        },

        '/deposit-status': (context) => const DepositStatusScreen(),
      },
    );

    return SplashScreen(
      isReady: _isSessionRestored,
      child: app,
    );
  }
}
