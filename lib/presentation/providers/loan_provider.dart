import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../core/services/logger_service.dart';
import '../../data/api/loan_api_service.dart';
import '../../data/models/loan_models.dart';
import '../../data/repositories/auth_repository.dart';

/// Convert LoanData (API model) to Loan (domain model)
Loan _convertLoanDataToLoan(LoanData data) {
  return Loan(
    id: data.id,
    userId: data.userId,
    type: data.loanType,
    amount: data.amount,
    tenure: data.tenure,
    interestRate: data.interestRate,
    monthlyRepayment: data.monthlyRepayment,
    totalRepayment: data.totalRepayment > 0
        ? data.totalRepayment
        : data.monthlyRepayment * data.tenure,
    status: data.status,
    purpose: data.purpose,
    qrId: data.qrId,
    qrCode: data.qrCode,
    qrData: data.qrData,
    qrExpiresAt: data.qrExpiresAt,
    qrStatus: data.qrStatus,
    guarantorsAccepted: data.guarantorsAccepted,
    guarantorsRequired: data.guarantorsRequired,
    createdAt: data.createdAt,
    updatedAt: data.createdAt,
    approvedAt: null,
    disbursedAt: null,
    remainingBalance: data.remainingBalance,
  );
}

/// Loan Provider - Uses official ApiClient through Riverpod
final loanProvider = StateNotifierProvider<LoanNotifier, LoansState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final loanApiService = ref.watch(loanApiServiceProvider);
  return LoanNotifier(authRepository, loanApiService);
});

/// Loan Notifier
class LoanNotifier extends StateNotifier<LoansState> {
  final AuthRepository _authRepository;
  final LoanApiService _loanApiService;

  LoanNotifier(this._authRepository, this._loanApiService)
      : super(const LoansState());

  /// Apply for a loan
  Future<void> applyForLoan({
    required String loanType,
    required double amount,
    required String purpose,
    required double monthlySavings,
  }) async {
    state = state.copyWith(status: LoanStatus.loading);
    try {
      final userId = await _authRepository.getUserId();
      final response = await _loanApiService.applyForLoan(
        LoanApplicationRequest(
          loanType: loanType,
          loanAmount: amount,
          tenureMonths: 12, // Default tenure
          purpose: purpose,
        ),
      );

      if (response.success && response.loan != null) {
        final loan = _convertLoanDataToLoan(response.loan!);
        state = state.copyWith(
          status: LoanStatus.loaded,
          loans: [...state.loans, loan],
        );
      } else {
        state = state.copyWith(
          status: LoanStatus.error,
          error: response.message,
        );
      }
    } catch (e) {
      logger.e('Apply for loan error: $e');
      state = state.copyWith(
        status: LoanStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Get all loans
  Future<void> getLoans() async {
    state = state.copyWith(status: LoanStatus.loading);
    try {
      // The backend resolves the user from the JWT; getUserId() is not needed
      // for the request itself but we call it to surface auth issues early.
      await _authRepository.getUserId();
      final response = await _loanApiService.getUserLoans();

      if (response.success) {
        final loans = response.loans.map(_convertLoanDataToLoan).toList();
        state = state.copyWith(
          status: LoanStatus.loaded,
          loans: loans,
        );
      } else {
        state = state.copyWith(
          status: LoanStatus.error,
          error: 'Failed to fetch loans',
        );
      }
    } catch (e) {
      logger.e('Get loans error: $e');
      state = state.copyWith(
        status: LoanStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Get loan details
  Future<LoanDetailsResponse?> getLoanDetails(String loanId) async {
    try {
      final response = await _loanApiService.getLoanDetails(loanId);
      if (response.success) {
        return response;
      }
      return null;
    } catch (e) {
      logger.e('Get loan details error: $e');
      return null;
    }
  }

  /// Get loan status
  Future<LoanStatusResponse?> getLoanStatus(String loanId) async {
    try {
      final response = await _loanApiService.getLoanStatus(loanId);
      if (response.success) {
        return response;
      }
      return null;
    } catch (e) {
      logger.e('Get loan status error: $e');
      return null;
    }
  }

  /// Get guarantors
  Future<List<GuarantorData>> getGuarantors(String loanId) async {
    try {
      final response = await _loanApiService.getLoanGuarantors(loanId);
      if (response.success) {
        return response.guarantors;
      }
      return [];
    } catch (e) {
      logger.e('Get guarantors error: $e');
      return [];
    }
  }

  /// Confirm guarantee
  Future<bool> confirmGuarantee({
    required String loanId,
    required String guarantorId,
    required String guarantorName,
    required String guarantorPhone,
    required double savingsBalance,
  }) async {
    try {
      final response = await _loanApiService.confirmGuarantee(
        loanId,
        GuarantorConfirmRequest(
          guarantorId: guarantorId,
          guarantorName: guarantorName,
          guarantorPhone: guarantorPhone,
          savingsBalance: savingsBalance,
        ),
      );
      return response.success;
    } catch (e) {
      logger.e('Confirm guarantee error: $e');
      return false;
    }
  }

  /// Decline guarantee
  Future<bool> declineGuarantee({
    required String loanId,
    required String guarantorId,
    required String reason,
  }) async {
    try {
      final response = await _loanApiService.declineGuarantee(
        loanId,
        GuarantorDeclineRequest(
          guarantorId: guarantorId,
          reason: reason,
        ),
      );
      return response.success;
    } catch (e) {
      logger.e('Decline guarantee error: $e');
      return false;
    }
  }

  /// Get repayment schedule
  Future<RepaymentScheduleData?> getRepaymentSchedule(String loanId) async {
    try {
      final response = await _loanApiService.getRepaymentSchedule(loanId);
      if (response.success && response.schedule != null) {
        return response.schedule;
      }
      return null;
    } catch (e) {
      logger.e('Get repayment schedule error: $e');
      return null;
    }
  }

  /// Make repayment
  Future<bool> makeRepayment({
    required String loanId,
    required double amount,
    required String paymentMethod,
  }) async {
    try {
      final userId = await _authRepository.getUserId();
      final response = await _loanApiService.makeRepayment(
        loanId,
        LoanRepayRequest(
          amount: amount,
          paymentMethod: paymentMethod,
        ),
      );
      if (response.success) {
        await getLoans(); // Refresh loans after repayment
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Make repayment error: $e');
      return false;
    }
  }

  /// Get loan types
  Future<List<LoanTypeData>> getLoanTypes() async {
    try {
      final response = await _loanApiService.getLoanTypes();
      if (response.success) {
        return response.loanTypes;
      }
      return [];
    } catch (e) {
      logger.e('Get loan types error: $e');
      return [];
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Calculate maximum loan amount based on savings.
  /// Uses the default 3x multiplier for generic estimates; product-specific
  /// limits (Premium 4x, Maxi 5x) are enforced by the backend at apply time.
  double calculateMaxLoanAmount(double totalSavings, {String? loanType}) {
    final multiplier = AppConfig.loanMultipliers[loanType] ?? AppConfig.loanMultiplier;
    return totalSavings * multiplier;
  }

  /// Check if member is eligible for loan based on membership duration
  /// Requirement: At least 6 months of membership
  bool isEligibleForLoan(int membershipMonths) {
    return membershipMonths >= AppConfig.loanEligibilityMonths;
  }

  /// Get eligibility message for the user
  String getEligibilityMessage({
    required int membershipMonths,
    required double totalSavings,
  }) {
    final isEligible = isEligibleForLoan(membershipMonths);
    
    if (!isEligible) {
      final monthsRemaining = AppConfig.loanEligibilityMonths - membershipMonths;
      return 'You will become eligible to apply for a loan after completing $monthsRemaining more month(s) of consistent contributions.';
    }
    
    final maxLoan = calculateMaxLoanAmount(totalSavings);
    return 'Based on your current savings of ₦${totalSavings.toStringAsFixed(0)}, you are eligible to apply for a loan of up to ₦${maxLoan.toStringAsFixed(0)}.';
  }

  /// Validate loan amount against maximum allowed
  bool validateLoanAmount(double amount, double totalSavings) {
    final maxLoan = calculateMaxLoanAmount(totalSavings);
    return amount > 0 && amount <= maxLoan;
  }
}