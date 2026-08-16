/// Error messages with actionable guidance
class ErrorMessages {
  // Network errors
  static const String networkError = 'Unable to connect to the server. Please check your internet connection and try again.';
  static const String networkErrorAction = 'Check your internet connection';

  // Authentication errors
  static const String invalidCredentials = 'Invalid email or password. Please check your credentials and try again.';
  static const String sessionExpired = 'Your session has expired. Please log in again to continue.';
  static const String unauthorized = 'You are not authorized to perform this action.';

  // Registration errors
  static const String emailAlreadyExists = 'An account with this email already exists. Try logging in instead.';
  static const String invalidEmail = 'Please enter a valid email address.';
  static const String weakPassword = 'Password must be at least 8 characters with uppercase, lowercase, and numbers.';
  static const String passwordMismatch = 'Passwords do not match. Please try again.';

  // KYC errors
  static const String kycPending = 'Your KYC verification is still being processed. This usually takes 24-48 hours.';
  static const String kycRejected = 'Your KYC verification was rejected. Please update your documents and try again.';
  static const String kycIncomplete = 'Please complete your KYC verification to access this feature.';

  // Payment errors
  static const String paymentFailed = 'Payment could not be processed. Please try again or use a different payment method.';
  static const String insufficientFunds = 'Insufficient funds. Please add money to your wallet or use a different payment method.';
  static const String paymentCancelled = 'Payment was cancelled. No charges were made to your account.';

  // Loan errors
  static const String loanNotEligible = 'You are not eligible for a loan at this time. Please ensure your membership and contribution requirements are met.';
  static const String loanAmountTooHigh = 'The requested loan amount exceeds your eligibility. Please reduce the amount.';
  static const String guarantorRequired = 'Please add the required number of guarantors before submitting your loan application.';

  // General errors
  static const String somethingWentWrong = 'Something went wrong. Please try again in a few moments.';
  static const String serverError = 'Server error. Our team has been notified. Please try again later.';
  static const String tryAgainLater = 'Please try again in a few moments.';

  // Form validation
  static const String fieldRequired = 'This field is required. Please fill it in.';
  static const String invalidPhone = 'Please enter a valid phone number.';
  static const String invalidAmount = 'Please enter a valid amount.';

  /// Get user-friendly error message from API error code
  static String getMessage(String? errorCode) {
    switch (errorCode) {
      case 'NETWORK_ERROR':
        return networkError;
      case 'INVALID_CREDENTIALS':
        return invalidCredentials;
      case 'EMAIL_EXISTS':
        return emailAlreadyExists;
      case 'SESSION_EXPIRED':
        return sessionExpired;
      case 'UNAUTHORIZED':
        return unauthorized;
      case 'KYC_PENDING':
        return kycPending;
      case 'KYC_REJECTED':
        return kycRejected;
      case 'KYC_INCOMPLETE':
        return kycIncomplete;
      case 'PAYMENT_FAILED':
        return paymentFailed;
      case 'INSUFFICIENT_FUNDS':
        return insufficientFunds;
      case 'LOAN_NOT_ELIGIBLE':
        return loanNotEligible;
      case 'LOAN_AMOUNT_TOO_HIGH':
        return loanAmountTooHigh;
      case 'GUARANTOR_REQUIRED':
        return guarantorRequired;
      case 'SERVER_ERROR':
        return serverError;
      default:
        return somethingWentWrong;
    }
  }

  /// Get actionable advice for an error
  static String getAdvice(String? errorCode) {
    switch (errorCode) {
      case 'NETWORK_ERROR':
        return 'Check your Wi-Fi or mobile data connection';
      case 'INVALID_CREDENTIALS':
        return 'Reset your password if you\'ve forgotten it';
      case 'SESSION_EXPIRED':
        return 'Log in again to continue';
      case 'KYC_PENDING':
        return 'We\'ll notify you once verification is complete';
      case 'PAYMENT_FAILED':
        return 'Try a different payment method or contact support';
      default:
        return 'If the problem persists, contact support';
    }
  }
}
