import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../core/network/api_client.dart';
import '../models/loan_models.dart';
import '../api/loan_api_service.dart';
import '../../core/network/offline_support.dart';

/// Loan Repository - Connects loan screens to the API
class LoanRepository {
  final LoanApiService _apiService;
  final OfflineDataManager _offlineDataManager;

  LoanRepository({
    LoanApiService? apiService,
    OfflineDataManager? offlineDataManager,
  })  : _apiService = apiService ?? LoanApiService(ApiClient().getDio()),
        _offlineDataManager = offlineDataManager ?? OfflineDataManager();

  /// Apply for a new loan
  Future<ApiResult<Loan>> applyForLoan({
    required String userId,
    required String loanType,
    required double amount,
    required String purpose,
    required double monthlySavings,
    required bool isOnline,
  }) async {
    // If offline, save operation for later sync
    if (!isOnline) {
      final operation = {
        'type': 'loan_application',
        'userId': userId,
        'loanType': loanType,
        'amount': amount,
        'purpose': purpose,
        'monthlySavings': monthlySavings,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _offlineDataManager.savePendingOperation(operation);
      
      // Return mock loan for offline mode
      final tenure = _getTenure(loanType);
      final interestRate = _getInterestRate(loanType);
      final monthlyRepayment = _calculateMonthlyRepayment(amount, interestRate, tenure);
      final loan = Loan(
        id: 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: loanType,
        amount: amount,
        tenure: tenure,
        interestRate: interestRate,
        monthlyRepayment: monthlyRepayment,
        totalRepayment: _calculateTotalRepayment(amount, interestRate),
        status: 'pending_offline',
        purpose: purpose,
        guarantorsAccepted: 0,
        guarantorsRequired: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      return ApiResult.success(loan);
    }

    try {
      final result = await _apiService.applyForLoan(
        LoanApplicationRequest(
          loanType: loanType,
          loanAmount: amount,
          tenureMonths: _getTenure(loanType),
          purpose: purpose,
        ),
      );

      if (result.success && result.loan != null) {
        final loan = Loan(
          id: result.loan!.id,
          userId: result.loan!.userId,
          type: result.loan!.loanType,
          amount: result.loan!.amount,
          tenure: result.loan!.tenure,
          interestRate: result.loan!.interestRate,
          monthlyRepayment: result.loan!.monthlyRepayment,
          totalRepayment: result.loan!.totalRepayment > 0
              ? result.loan!.totalRepayment
              : result.loan!.monthlyRepayment * result.loan!.tenure,
          status: _mapLoanStatus(result.loan!.status),
          purpose: result.loan!.purpose,
          guarantorsAccepted: 0,
          guarantorsRequired: 3,
          createdAt: result.loan!.createdAt,
          updatedAt: result.loan!.createdAt,
        );
        
        return ApiResult.success(loan);
      } else {
        return ApiResult.error(result.message);
      }
    } catch (e) {
      return ApiResult.error('Failed to apply for loan: $e');
    }
  }

  /// Get user's loans
  Future<ApiResult<List<Loan>>> getUserLoans({
    required String userId,
    required bool isOnline,
  }) async {
    // Try to get from cache first if offline
    if (!isOnline) {
      final cachedData = await _offlineDataManager.getCachedData('user_loans_$userId');
      if (cachedData != null && cachedData['loans'] != null) {
        final List<dynamic> loanList = cachedData['loans'];
        final loans = loanList.map((e) => Loan.fromJson(e as Map<String, dynamic>)).toList();
        return ApiResult.success(loans);
      }
      // If no cache, return mock data for offline mode
      return ApiResult.success(_getMockLoans(userId));
    }

    try {
      final result = await _apiService.getUserLoans();

      if (result.success) {
        final loans = result.loans.map((e) {
          return Loan(
            id: e.id,
            userId: e.userId,
            type: e.loanType,
            amount: e.amount,
            tenure: e.tenure,
            interestRate: e.interestRate,
            monthlyRepayment: e.monthlyRepayment,
            totalRepayment: e.totalRepayment > 0
                ? e.totalRepayment
                : e.monthlyRepayment * e.tenure,
            status: _mapLoanStatus(e.status),
            purpose: e.purpose,
            guarantorsAccepted: 0,
            guarantorsRequired: 3,
            createdAt: e.createdAt,
            updatedAt: e.createdAt,
          );
        }).toList();

        // Cache the data for offline access when online
        await _offlineDataManager.cacheData('user_loans_$userId', {
          'loans': loans.map((l) => l.toJson()).toList(),
        });

        return ApiResult.success(loans);
      } else {
        return ApiResult.error('Failed to fetch loans');
      }
    } catch (e) {
      // Try to fallback to cache on network error
      final cachedData = await _offlineDataManager.getCachedData('user_loans_$userId');
      if (cachedData != null && cachedData['loans'] != null) {
        final List<dynamic> loanList = cachedData['loans'];
        final loans = loanList.map((e) => Loan.fromJson(e as Map<String, dynamic>)).toList();
        return ApiResult.success(loans);
      }
      return ApiResult.error('Network error and no cached data available: $e');
    }
  }

  /// Get loan details
  Future<ApiResult<LoanDetailsResponse>> getLoanDetails({
    required String loanId,
    required bool isOnline,
  }) async {
    try {
      final result = await _apiService.getLoanDetails(loanId);

      if (result.success) {
        return ApiResult.success(result);
      } else {
        return ApiResult.error('Failed to fetch loan details');
      }
    } catch (e) {
      return ApiResult.error('Failed to fetch loan details: $e');
    }
  }

  /// Confirm guarantee
  Future<ApiResult<GuarantorConfirmResponse>> confirmGuarantee({
    required String loanId,
    required String guarantorId,
    required String guarantorName,
    required String guarantorPhone,
    required double savingsBalance,
    required bool isOnline,
  }) async {
    // If offline, save operation for later sync
    if (!isOnline) {
      final operation = {
        'type': 'guarantor_confirmation',
        'loanId': loanId,
        'guarantorId': guarantorId,
        'guarantorName': guarantorName,
        'guarantorPhone': guarantorPhone,
        'savingsBalance': savingsBalance,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _offlineDataManager.savePendingOperation(operation);
      
      // Return mock success response for offline mode
      return ApiResult.success(GuarantorConfirmResponse(
        success: true,
        message: 'Guarantee confirmed (offline mode)',
        guarantorStatus: 'confirmed',
        guarantorsNowConfirmed: 1,
      ));
    }

    try {
      final result = await _apiService.confirmGuarantee(
        loanId,
        GuarantorConfirmRequest(
          guarantorId: guarantorId,
          guarantorName: guarantorName,
          guarantorPhone: guarantorPhone,
          savingsBalance: savingsBalance,
        ),
      );

      if (result.success) {
        return ApiResult.success(result);
      } else {
        return ApiResult.error(result.message);
      }
    } catch (e) {
      return ApiResult.error('Failed to confirm guarantee: $e');
    }
  }

  /// Decline guarantee
  Future<ApiResult<GuarantorDeclineResponse>> declineGuarantee({
    required String loanId,
    required String guarantorId,
    required String reason,
    required bool isOnline,
  }) async {
    if (!isOnline) {
      final operation = {
        'type': 'guarantor_decline',
        'loanId': loanId,
        'guarantorId': guarantorId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _offlineDataManager.savePendingOperation(operation);
      
      return ApiResult.success(GuarantorDeclineResponse(
        success: true,
        message: 'Guarantee declined (offline mode)',
      ));
    }

    try {
      final result = await _apiService.declineGuarantee(
        loanId,
        GuarantorDeclineRequest(
          guarantorId: guarantorId,
          reason: reason,
        ),
      );

      if (result.success) {
        return ApiResult.success(result);
      } else {
        return ApiResult.error(result.message);
      }
    } catch (e) {
      return ApiResult.error('Failed to decline guarantee: $e');
    }
  }

  /// Get loan types
  Future<ApiResult<List<LoanTypeData>>> getLoanTypes({required bool isOnline}) async {
    try {
      final result = await _apiService.getLoanTypes();

      if (result.success) {
        return ApiResult.success(result.loanTypes);
      } else {
        return ApiResult.error('Failed to fetch loan types');
      }
    } catch (e) {
      // Return hardcoded loan types on error
      return ApiResult.success(_getHardcodedLoanTypes());
    }
  }

  double _calculateMonthlyRepayment(double amount, double interestRate, int tenure) {
    final rate = interestRate / 100 / 12;
    final tenureDouble = tenure.toDouble();
    final numerator = amount * rate * pow(1 + rate, tenureDouble).toDouble();
    final denominator = (pow(1 + rate, tenureDouble).toDouble() - 1);
    final emi = numerator / denominator;
    return emi;
  }

  double _calculateTotalRepayment(double amount, double interestRate) {
    return amount + (amount * interestRate / 100);
  }

  String _mapLoanStatus(String apiStatus) {
    switch (apiStatus) {
      case 'pending_guarantors':
      case 'pending':
        return 'pending';
      case 'guarantors_confirmed':
      case 'under_review':
      case 'approved':
        return 'approved';
      case 'active':
        return 'active';
      case 'repaying':
        return 'repaying';
      case 'completed':
        return 'completed';
      case 'defaulted':
        return 'defaulted';
      case 'rejected':
        return 'rejected';
      default:
        // Preserve unknown statuses verbatim instead of collapsing to 'pending',
        // so screens that filter on 'active'/'repaying' keep working.
        return apiStatus.isEmpty ? 'pending' : apiStatus;
    }
  }

  List<LoanTypeData> _getHardcodedLoanTypes() {
    return [
      LoanTypeData(
        name: 'Quick Loan',
        minAmount: 5000,
        maxAmount: 50000,
        interestRate: 7.5,
        tenures: [4],
      ),
      LoanTypeData(
        name: 'Flexi Loan',
        minAmount: 10000,
        maxAmount: 100000,
        interestRate: 7.0,
        tenures: [6],
      ),
      LoanTypeData(
        name: 'Stable Loan (12 months)',
        minAmount: 20000,
        maxAmount: 200000,
        interestRate: 5.0,
        tenures: [12],
      ),
      LoanTypeData(
        name: 'Stable Loan (18 months)',
        minAmount: 30000,
        maxAmount: 300000,
        interestRate: 7.0,
        tenures: [18],
      ),
      LoanTypeData(
        name: 'Premium Loan',
        minAmount: 50000,
        maxAmount: 500000,
        interestRate: 14.0,
        tenures: [24],
      ),
      LoanTypeData(
        name: 'Maxi Loan',
        minAmount: 100000,
        maxAmount: 1000000,
        interestRate: 19.0,
        tenures: [36],
      ),
    ];
  }

  int _getTenure(String loanType) {
    final types = _getHardcodedLoanTypes();
    final type = types.firstWhere((e) => e.name == loanType, orElse: () => types.first);
    return type.tenures.isNotEmpty ? type.tenures.first : 12;
  }

  double _getInterestRate(String loanType) {
    final types = _getHardcodedLoanTypes();
    final type = types.firstWhere((e) => e.name == loanType, orElse: () => types.first);
    return type.interestRate;
  }

  List<Loan> _getMockLoans(String userId) {
    return [
      Loan(
        id: 'COOP-$userId-LOAN-001',
        userId: userId,
        type: 'Quick Loan',
        amount: 50000,
        tenure: 4,
        interestRate: 7.5,
        monthlyRepayment: 13125,
        totalRepayment: 52500,
        status: 'active',
        purpose: 'Business expansion',
        guarantorsAccepted: 3,
        guarantorsRequired: 3,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now(),
      ),
      Loan(
        id: 'COOP-$userId-LOAN-002',
        userId: userId,
        type: 'Flexi Loan',
        amount: 100000,
        tenure: 6,
        interestRate: 7.0,
        monthlyRepayment: 18333,
        totalRepayment: 110000,
        status: 'completed',
        purpose: 'Emergency expenses',
        guarantorsAccepted: 3,
        guarantorsRequired: 3,
        createdAt: DateTime.now().subtract(const Duration(days: 180)),
        updatedAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
    ];
  }
}

/// Loan Repository Provider
final loanRepositoryProvider = Provider<LoanRepository>((ref) {
  return LoanRepository();
});

/// Use pow from dart:math
double pow(double base, double exponent) => math.pow(base, exponent).toDouble();
