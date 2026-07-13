import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';


/// API Service for Loan Operations - Uses official ApiClient
class LoanApiService {
  final Dio _dio;

  LoanApiService(this._dio);

  /// Apply for a new loan
  Future<LoanResponse> applyForLoan(LoanApplicationRequest request) {
    return _dio.post('/loans/apply', data: request.toJson()).then((response) => LoanResponse.fromJson(response.data));
  }

  /// Get all loans for a user
  Future<LoansListResponse> getUserLoans() {
    return _dio.get('/loans').then((response) => LoansListResponse.fromJson(response.data));
  }

  /// Get loan details by ID
  Future<LoanDetailsResponse> getLoanDetails(String loanId) {
    return _dio.get('/loans/$loanId').then((response) => LoanDetailsResponse.fromJson(response.data));
  }

  /// Get loan status
  Future<LoanStatusResponse> getLoanStatus(String loanId) {
    return _dio.get('/loans/$loanId/status').then((response) => LoanStatusResponse.fromJson(response.data));
  }

  /// Get guarantors for a loan
  Future<GuarantorsListResponse> getLoanGuarantors(String loanId) {
    return _dio.get('/loans/$loanId/guarantors').then((response) => GuarantorsListResponse.fromJson(response.data));
  }

  /// Confirm guarantee (guarantor accepts)
  /// Calls the /guarantor/requests/:loanId/accept endpoint.
  /// The loanId is used as the path param so the backend resolves the record
  /// by loan_id + guarantor_id (from the JWT token).
  Future<GuarantorConfirmResponse> confirmGuarantee(String loanId, GuarantorConfirmRequest request) {
    return _dio.post('/guarantor/requests/$loanId/accept', data: request.toJson()).then((response) {
      // Map the backend response to GuarantorConfirmResponse
      return GuarantorConfirmResponse(
        success: response.data['success'] as bool? ?? true,
        message: response.data['message'] as String? ?? 'Guarantee confirmed',
        guarantorStatus: 'accepted',
        guarantorsNowConfirmed: 0,
      );
    });
  }

  /// Decline guarantee (guarantor rejects)
  /// Calls the /guarantor/requests/:loanId/decline endpoint.
  /// The loanId is used as the path param so the backend resolves the record
  /// by loan_id + guarantor_id (from the JWT token).
  Future<GuarantorDeclineResponse> declineGuarantee(String loanId, GuarantorDeclineRequest request) {
    return _dio.post('/guarantor/requests/$loanId/decline', data: request.toJson()).then((response) {
      // Map the backend response to GuarantorDeclineResponse
      return GuarantorDeclineResponse(
        success: response.data['success'] as bool? ?? true,
        message: response.data['message'] as String? ?? 'Guarantee declined',
      );
    });
  }

  /// Cancel loan application
  Future<LoanCancelResponse> cancelLoan(String loanId, LoanCancelRequest request) {
    return _dio.post('/loans/$loanId/cancel', data: request.toJson()).then((response) => LoanCancelResponse.fromJson(response.data));
  }

  /// Get loan repayment schedule
  Future<RepaymentScheduleResponse> getRepaymentSchedule(String loanId) {
    return _dio.get('/loans/$loanId/repayment-schedule').then((response) => RepaymentScheduleResponse.fromJson(response.data));
  }

  /// Make loan repayment
  Future<LoanRepayResponse> makeRepayment(String loanId, LoanRepayRequest request) {
    return _dio.post('/loans/$loanId/repay', data: request.toJson()).then((response) => LoanRepayResponse.fromJson(response.data));
  }

  /// Get available loan types
  Future<LoanTypesResponse> getLoanTypes() {
    return _dio.get('/loans/types').then((response) => LoanTypesResponse.fromJson(response.data));
  }
}

/// Loan API Service Provider
final loanApiServiceProvider = Provider<LoanApiService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return LoanApiService(apiClient.dio);
});

/// Request/Response Models

class LoanApplicationRequest {
  final String loanType;
  final double loanAmount;
  final int tenureMonths;
  final String purpose;

  LoanApplicationRequest({
    required this.loanType,
    required this.loanAmount,
    required this.tenureMonths,
    required this.purpose,
  });

  Map<String, dynamic> toJson() => {
        'loanType': loanType,
        'amount': loanAmount,
        'tenureMonths': tenureMonths,
        'purpose': purpose,
      };
}

class LoanResponse {
  final bool success;
  final String message;
  final LoanData? loan;

  LoanResponse({
    required this.success,
    required this.message,
    this.loan,
  });

  factory LoanResponse.fromJson(Map<String, dynamic> json) {
    return LoanResponse(
      success: json['success'] as bool,
      message: json['message'] as String? ?? '',
      loan: json['loan'] != null ? LoanData.fromJson(json['loan']) : null,
    );
  }
}

class LoanData {
  final String id;
  final String userId;
  final String loanType;
  final double amount;
  final int tenure;
  final double interestRate;
  final double monthlyRepayment;
  final String status;
  final String purpose;
  final String? qrCode;
  final DateTime createdAt;

  LoanData({
    required this.id,
    required this.userId,
    required this.loanType,
    required this.amount,
    required this.tenure,
    required this.interestRate,
    required this.monthlyRepayment,
    required this.status,
    required this.purpose,
    this.qrCode,
    required this.createdAt,
  });

  factory LoanData.fromJson(Map<String, dynamic> json) {
    return LoanData(
      id: json['loanId'] as String? ?? json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      loanType: json['loanType'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      tenure: json['tenureMonths'] as int? ?? json['tenure'] as int? ?? 0,
      interestRate: (json['effectiveInterestRate'] as num?)?.toDouble() ?? (json['interest_rate'] as num?)?.toDouble() ?? 0.0,
      monthlyRepayment: (json['monthlyRepayment'] as num?)?.toDouble() ?? (json['monthly_repayment'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? '',
      purpose: json['purpose'] as String? ?? '',
      qrCode: json['qr_code'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now(),
    );
  }
}

class LoansListResponse {
  final bool success;
  final List<LoanData> loans;

  LoansListResponse({
    required this.success,
    required this.loans,
  });

  factory LoansListResponse.fromJson(Map<String, dynamic> json) {
    return LoansListResponse(
      success: json['success'] as bool,
      loans: (json['loans'] as List? ?? [])
          .map((e) => LoanData.fromJson(e))
          .toList(),
    );
  }
}

class LoanDetailsResponse {
  final bool success;
  final LoanData loan;
  final List<GuarantorData> guarantors;
  final RepaymentScheduleData? repaymentSchedule;

  LoanDetailsResponse({
    required this.success,
    required this.loan,
    required this.guarantors,
    this.repaymentSchedule,
  });

  factory LoanDetailsResponse.fromJson(Map<String, dynamic> json) {
    return LoanDetailsResponse(
      success: json['success'] as bool,
      loan: LoanData.fromJson(json['loan']),
      guarantors: (json['guarantors'] as List? ?? [])
          .map((e) => GuarantorData.fromJson(e))
          .toList(),
      repaymentSchedule: json['repayment_schedule'] != null
          ? RepaymentScheduleData.fromJson(json['repayment_schedule'])
          : null,
    );
  }
}

class LoanStatusResponse {
  final bool success;
  final String status;
  final int guarantorsConfirmed;
  final int guarantorsRequired;
  final DateTime? lastUpdated;

  LoanStatusResponse({
    required this.success,
    required this.status,
    required this.guarantorsConfirmed,
    required this.guarantorsRequired,
    this.lastUpdated,
  });

  factory LoanStatusResponse.fromJson(Map<String, dynamic> json) {
    return LoanStatusResponse(
      success: json['success'] as bool,
      status: json['status'] as String? ?? '',
      guarantorsConfirmed: json['guarantors_confirmed'] as int? ?? 0,
      guarantorsRequired: json['guarantors_required'] as int? ?? 3,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : null,
    );
  }
}

class GuarantorData {
  final String id;
  final String name;
  final String phone;
  final String status;
  final DateTime? confirmedAt;

  GuarantorData({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    this.confirmedAt,
  });

  factory GuarantorData.fromJson(Map<String, dynamic> json) {
    return GuarantorData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      status: json['status'] as String? ?? '',
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String)
          : null,
    );
  }
}

class GuarantorsListResponse {
  final bool success;
  final List<GuarantorData> guarantors;

  GuarantorsListResponse({
    required this.success,
    required this.guarantors,
  });

  factory GuarantorsListResponse.fromJson(Map<String, dynamic> json) {
    return GuarantorsListResponse(
      success: json['success'] as bool,
      guarantors: (json['guarantors'] as List? ?? [])
          .map((e) => GuarantorData.fromJson(e))
          .toList(),
    );
  }
}

class GuarantorConfirmRequest {
  final String guarantorId;
  final String guarantorName;
  final String guarantorPhone;
  final double savingsBalance;

  GuarantorConfirmRequest({
    required this.guarantorId,
    required this.guarantorName,
    required this.guarantorPhone,
    required this.savingsBalance,
  });

  Map<String, dynamic> toJson() => {
        'guarantor_id': guarantorId,
        'guarantor_name': guarantorName,
        'guarantor_phone': guarantorPhone,
        'savings_balance': savingsBalance,
      };
}

class GuarantorConfirmResponse {
  final bool success;
  final String message;
  final String guarantorStatus;
  final int guarantorsNowConfirmed;

  GuarantorConfirmResponse({
    required this.success,
    required this.message,
    required this.guarantorStatus,
    required this.guarantorsNowConfirmed,
  });

  factory GuarantorConfirmResponse.fromJson(Map<String, dynamic> json) {
    return GuarantorConfirmResponse(
      success: json['success'] as bool,
      message: json['message'] as String? ?? '',
      guarantorStatus: json['guarantor_status'] as String? ?? '',
      guarantorsNowConfirmed: json['guarantors_now_confirmed'] as int? ?? 0,
    );
  }
}

class GuarantorDeclineRequest {
  final String guarantorId;
  final String reason;

  GuarantorDeclineRequest({
    required this.guarantorId,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'guarantor_id': guarantorId,
        'reason': reason,
      };
}

class GuarantorDeclineResponse {
  final bool success;
  final String message;

  GuarantorDeclineResponse({
    required this.success,
    required this.message,
  });

  factory GuarantorDeclineResponse.fromJson(Map<String, dynamic> json) {
    return GuarantorDeclineResponse(
      success: json['success'] as bool,
      message: json['message'] as String? ?? '',
    );
  }
}

class LoanCancelRequest {
  final String reason;

  LoanCancelRequest({required this.reason});

  Map<String, dynamic> toJson() => {'reason': reason};
}

class LoanCancelResponse {
  final bool success;
  final String message;

  LoanCancelResponse({required this.success, required this.message});

  factory LoanCancelResponse.fromJson(Map<String, dynamic> json) {
    return LoanCancelResponse(
      success: json['success'] as bool,
      message: json['message'] as String? ?? '',
    );
  }
}

class RepaymentScheduleData {
  final List<RepaymentInstallment> installments;
  final double totalInterest;
  final double totalPrincipal;

  RepaymentScheduleData({
    required this.installments,
    required this.totalInterest,
    required this.totalPrincipal,
  });

  factory RepaymentScheduleData.fromJson(Map<String, dynamic> json) {
    return RepaymentScheduleData(
      installments: (json['installments'] as List? ?? [])
          .map((e) => RepaymentInstallment.fromJson(e))
          .toList(),
      totalInterest: (json['total_interest'] as num?)?.toDouble() ?? 0.0,
      totalPrincipal: (json['total_principal'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RepaymentInstallment {
  final int installmentNumber;
  final double amount;
  final DateTime dueDate;
  final String status;

  RepaymentInstallment({
    required this.installmentNumber,
    required this.amount,
    required this.dueDate,
    required this.status,
  });

  factory RepaymentInstallment.fromJson(Map<String, dynamic> json) {
    return RepaymentInstallment(
      installmentNumber: json['installment_number'] as int? ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: DateTime.parse(json['due_date'] as String),
      status: json['status'] as String? ?? '',
    );
  }
}

class RepaymentScheduleResponse {
  final bool success;
  final RepaymentScheduleData schedule;

  RepaymentScheduleResponse({required this.success, required this.schedule});

  factory RepaymentScheduleResponse.fromJson(Map<String, dynamic> json) {
    return RepaymentScheduleResponse(
      success: json['success'] as bool,
      schedule: RepaymentScheduleData.fromJson(json['schedule']),
    );
  }
}

class LoanRepayRequest {
  final double amount;
  final String paymentMethod;

  LoanRepayRequest({required this.amount, required this.paymentMethod});

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'payment_method': paymentMethod,
      };
}

class LoanRepayResponse {
  final bool success;
  final String message;
  final String transactionId;

  LoanRepayResponse({
    required this.success,
    required this.message,
    required this.transactionId,
  });

  factory LoanRepayResponse.fromJson(Map<String, dynamic> json) {
    return LoanRepayResponse(
      success: json['success'] as bool,
      message: json['message'] as String? ?? '',
      transactionId: json['transaction_id'] as String? ?? '',
    );
  }
}

class LoanTypesResponse {
  final bool success;
  final List<LoanTypeData> loanTypes;

  LoanTypesResponse({required this.success, required this.loanTypes});

  factory LoanTypesResponse.fromJson(Map<String, dynamic> json) {
    return LoanTypesResponse(
      success: json['success'] as bool,
      loanTypes: (json['loan_types'] as List? ?? [])
          .map((e) => LoanTypeData.fromJson(e))
          .toList(),
    );
  }
}

class LoanTypeData {
  final String name;
  final double minAmount;
  final double maxAmount;
  final double interestRate;
  final List<int> tenures;

  LoanTypeData({
    required this.name,
    required this.minAmount,
    required this.maxAmount,
    required this.interestRate,
    required this.tenures,
  });

  factory LoanTypeData.fromJson(Map<String, dynamic> json) {
    return LoanTypeData(
      name: json['name'] as String? ?? '',
      minAmount: (json['min_amount'] as num?)?.toDouble() ?? 0.0,
      maxAmount: (json['max_amount'] as num?)?.toDouble() ?? 0.0,
      interestRate: (json['interest_rate'] as num?)?.toDouble() ?? 0.0,
      tenures: (json['tenures'] as List? ?? []).cast<int>(),
    );
  }
}
