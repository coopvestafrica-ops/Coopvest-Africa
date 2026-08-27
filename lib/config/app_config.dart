import 'env_config.dart';

/// App Configuration
/// Contains all app-level configuration constants

class AppConfig {
  // App Info
  static String get appName => EnvironmentContext.config.appName;
  static const String appVersion = '1.0.0';
  static const String appBuild = '1';

  // API Configuration
  static String get apiBaseUrl => EnvironmentContext.config.apiBaseUrl;
  static const Duration apiTimeout = Duration(seconds: 60);
  // Fast timeout for the KYC status probe. AuthGuard gates navigation on this
  // call, so a slow or cold-starting backend must not leave the member staring
  // at a loading screen for the full 60s apiTimeout.
  static const Duration kycStatusTimeout = Duration(seconds: 8);
  static const int maxRetries = 3;

  // Session Configuration
  static const Duration sessionTimeout = Duration(minutes: 30);
  static const Duration tokenRefreshThreshold = Duration(minutes: 5);

  // Loan Configuration
  // NOTE: Loan limits are savings-based per product (enforced server-side):
  //   Quick/Flexi/Stable loans: 3x total savings
  //   Premium Loan: 4x total savings
  //   Maxi Loan: 5x total savings
  // [loanMultiplier] is the generic/default multiplier used for estimates.
  static const double loanMultiplier = 3.0; // Default: 3x savings
  static const Map<String, double> loanMultipliers = {
    'Quick Loan': 3.0,
    'Flexi Loan': 3.0,
    'Stable Loan (12 months)': 3.0,
    'Stable Loan (18 months)': 3.0,
    'Premium Loan': 4.0,
    'Maxi Loan': 5.0,
  };
  static const int loanEligibilityMonths = 0; // TEMP: set to 0 for testing (restore to 6)
  static const List<int> loanTenures = [3, 6, 12];
  static const double baseInterestRate = 10.0;
  static const int guarantorsRequired = 3;
  static const double maxGuarantorLimit = 5000000;

  // Monthly Deductions Configuration
  static const double agmLevy = 1000.0; // AGM Levy - monthly
  static const double developmentLevy = 500.0; // Development Levy - monthly
  static const double totalMonthlyLevies = 1500.0; // AGM + Development
  static const double entranceFee = 5000.0; // One-time entrance fee

  // Contribution Configuration
  static const double minContribution = 5000;
  static const double maxContribution = 500000;

  // QR Code Configuration
  static const Duration qrCodeExpiry = Duration(days: 7);
  static const int maxQRScans = 3;

  // Cache Configuration
  static const Duration cacheExpiry = Duration(hours: 24);
  static const int maxCacheSize = 100; // MB

  // Feature Flags
  static const bool enableBiometric = true;
  static const bool enableOfflineMode = true;
  static const bool enableAnalytics = true;
  static const bool enableCrashlytics = true;

  // Pagination
  static const int pageSize = 20;
  static const int maxPages = 100;

  // Validation
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int pinLength = 4;
  static const int maxPinAttempts = 3;

  // Retry Configuration
  static const Duration retryDelay = Duration(seconds: 2);
  static const double retryBackoffMultiplier = 1.5;
  static const Duration maxRetryDelay = Duration(seconds: 30);

  // Network Configuration
  // SSL Pinning disabled for Render deployment - Render handles SSL automatically
  // Re-enable and set fingerprint when using custom domain with known certificate
  static const bool enableSSLPinning = false;
  static const String sslFingerprint = ''; // Set SHA-256 fingerprint when SSL pinning is enabled
  static const bool enableRequestLogging = true;
  static const bool enableResponseLogging = true;

  // Security
  static const bool enableJailbreakDetection = true;
  static const bool terminateOnJailbreak = true;
  static const bool enableDebuggerDetection = true;
  static const bool enableCodeObfuscation = true;

  // Localization
  static const String defaultLanguage = 'en';
  static const String defaultCurrency = 'NGN';
  static const String defaultCountry = 'NG';

  // Date & Time
  static const String dateFormat = 'dd/MM/yyyy';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';

  // Notification Configuration
  static const Duration notificationTimeout = Duration(seconds: 5);
  static const int maxNotifications = 50;

  // Analytics Events
  static const String eventAppLaunched = 'app_launched';
  static const String eventUserRegistered = 'user_registered';
  static const String eventUserLoggedIn = 'user_logged_in';
  static const String eventLoanApplied = 'loan_applied';
  static const String eventGuarantorApproved = 'guarantor_approved';
  static const String eventContributionMade = 'contribution_made';
  static const String eventInvestmentParticipated = 'investment_participated';
}
