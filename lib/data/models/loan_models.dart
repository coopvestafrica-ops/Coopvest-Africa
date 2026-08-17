import 'package:equatable/equatable.dart';
import '../../config/app_config.dart';

/// Loan Model
class Loan extends Equatable {
  final String id;
  final String userId;
  final String type;
  final double amount;
  final int tenure; // months
  final double interestRate;
  final double monthlyRepayment;
  final double totalRepayment;
  final String status; // draft, pending_guarantors, guarantors_confirmed, under_review, approved, rejected, active, repaying, completed, defaulted
  final String? purpose;
  final int guarantorsAccepted;
  final int guarantorsRequired;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? approvedAt;
  final DateTime? disbursedAt;
  final double remainingBalance;

  const Loan({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.tenure,
    required this.interestRate,
    required this.monthlyRepayment,
    required this.totalRepayment,
    required this.status,
    this.purpose,
    required this.guarantorsAccepted,
    required this.guarantorsRequired,
    required this.createdAt,
    required this.updatedAt,
    this.approvedAt,
    this.disbursedAt,
    this.remainingBalance = 0.0,
  });

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      type: json['type'] as String? ?? json['loanType'] as String? ?? 'Personal Loan',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      tenure: json['tenure'] as int? ?? 12,
      interestRate: (json['interest_rate'] as num?)?.toDouble() ?? 0.0,
      monthlyRepayment: (json['monthly_repayment'] as num?)?.toDouble() ?? 0.0,
      totalRepayment: (json['total_repayment'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      purpose: json['purpose'] as String?,
      guarantorsAccepted: json['guarantors_accepted'] as int? ?? 0,
      guarantorsRequired: json['guarantors_required'] as int? ?? AppConfig.guarantorsRequired,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : DateTime.now(),
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      disbursedAt: json['disbursed_at'] != null
          ? DateTime.parse(json['disbursed_at'] as String)
          : null,
      remainingBalance: (json['remaining_balance'] as num?)?.toDouble() ??
          (json['remainingBalance'] as num?)?.toDouble() ??
          0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'amount': amount,
      'tenure': tenure,
      'interest_rate': interestRate,
      'monthly_repayment': monthlyRepayment,
      'total_repayment': totalRepayment,
      'status': status,
      'purpose': purpose,
      'guarantors_accepted': guarantorsAccepted,
      'guarantors_required': guarantorsRequired,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'approved_at': approvedAt?.toIso8601String(),
      'disbursed_at': disbursedAt?.toIso8601String(),
      'remaining_balance': remainingBalance,
    };
  }

  Loan copyWith({
    String? id,
    String? userId,
    String? type,
    double? amount,
    int? tenure,
    double? interestRate,
    double? monthlyRepayment,
    double? totalRepayment,
    String? status,
    String? purpose,
    int? guarantorsAccepted,
    int? guarantorsRequired,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? approvedAt,
    DateTime? disbursedAt,
    double? remainingBalance,
  }) {
    return Loan(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      tenure: tenure ?? this.tenure,
      interestRate: interestRate ?? this.interestRate,
      monthlyRepayment: monthlyRepayment ?? this.monthlyRepayment,
      totalRepayment: totalRepayment ?? this.totalRepayment,
      status: status ?? this.status,
      purpose: purpose ?? this.purpose,
      guarantorsAccepted: guarantorsAccepted ?? this.guarantorsAccepted,
      guarantorsRequired: guarantorsRequired ?? this.guarantorsRequired,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      disbursedAt: disbursedAt ?? this.disbursedAt,
      remainingBalance: remainingBalance ?? this.remainingBalance,
    );
  }

  DateTime? get nextRepaymentDate {
    if (disbursedAt == null) return null;
    final nextPayment = disbursedAt!.add(Duration(days: 30 * 1));
    return nextPayment;
  }

  /// True for loans the member is actively repaying or has been approved and
  /// disbursed. The backend marks disbursed loans as 'approved' (not 'active'),
  /// so we treat 'approved' as active for display purposes.
  bool get isActive =>
      status == 'active' ||
      status == 'repaying' ||
      status == 'approved';

  /// Amount repaid so far on this loan.
  double get amountRepaid {
    final repaid = totalRepayment - remainingBalance;
    if (repaid.isNaN || repaid < 0) return 0.0;
    return repaid > totalRepayment ? totalRepayment : repaid;
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    type,
    amount,
    tenure,
    interestRate,
    monthlyRepayment,
    totalRepayment,
    status,
    purpose,
    guarantorsAccepted,
    guarantorsRequired,
    createdAt,
    updatedAt,
    approvedAt,
    disbursedAt,
    remainingBalance,
  ];
}

/// True for loans the member is actively repaying or has been approved and
/// disbursed. Kept as a top-level helper so list filters read naturally:
/// `loans.where(isLoanActive)`.
bool isLoanActive(String status) =>
    status == 'active' || status == 'repaying' || status == 'approved';

/// Guarantor Model
class Guarantor extends Equatable {
  final String id;
  final String loanId;
  final String guarantorId;
  final String guarantorName;
  final String? guarantorPhone;
  final String status; // pending, accepted, declined, expired, released
  final DateTime? acceptedAt;
  final DateTime createdAt;

  const Guarantor({
    required this.id,
    required this.loanId,
    required this.guarantorId,
    required this.guarantorName,
    this.guarantorPhone,
    required this.status,
    this.acceptedAt,
    required this.createdAt,
  });

  factory Guarantor.fromJson(Map<String, dynamic> json) {
    return Guarantor(
      id: json['id'] as String,
      loanId: json['loan_id'] as String,
      guarantorId: json['guarantor_id'] as String,
      guarantorName: json['guarantor_name'] as String,
      guarantorPhone: json['guarantor_phone'] as String?,
      status: json['status'] as String,
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'loan_id': loanId,
      'guarantor_id': guarantorId,
      'guarantor_name': guarantorName,
      'guarantor_phone': guarantorPhone,
      'status': status,
      'accepted_at': acceptedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    loanId,
    guarantorId,
    guarantorName,
    guarantorPhone,
    status,
    acceptedAt,
    createdAt,
  ];
}

/// Loan Application Model
class LoanApplication extends Equatable {
  final double amount;
  final int tenure;
  final String? purpose;

  const LoanApplication({
    required this.amount,
    required this.tenure,
    this.purpose,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'tenure': tenure,
      'purpose': purpose,
    };
  }

  @override
  List<Object?> get props => [amount, tenure, purpose];
}

/// Loan State
enum LoanStatus {
  initial,
  loading,
  loaded,
  error,
}

class LoansState extends Equatable {
  final LoanStatus status;
  final List<Loan> loans;
  final Loan? selectedLoan;
  final List<Guarantor> guarantors;
  final String? error;

  const LoansState({
    this.status = LoanStatus.initial,
    this.loans = const [],
    this.selectedLoan,
    this.guarantors = const [],
    this.error,
  });

  bool get isLoading => status == LoanStatus.loading;
  bool get isLoaded => status == LoanStatus.loaded;

  LoansState copyWith({
    LoanStatus? status,
    List<Loan>? loans,
    Loan? selectedLoan,
    List<Guarantor>? guarantors,
    String? error,
  }) {
    return LoansState(
      status: status ?? this.status,
      loans: loans ?? this.loans,
      selectedLoan: selectedLoan ?? this.selectedLoan,
      guarantors: guarantors ?? this.guarantors,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, loans, selectedLoan, guarantors, error];
}

/// Loan Type Info for displaying available loan types
class LoanTypeInfo extends Equatable {
  final String name;
  final double minAmount;
  final double maxAmount;
  final int tenure;
  final double interestRate;
  final String? description;
  final List<int>? tenures;

  const LoanTypeInfo({
    required this.name,
    required this.minAmount,
    required this.maxAmount,
    required this.tenure,
    required this.interestRate,
    this.description,
    this.tenures,
  });

  factory LoanTypeInfo.fromJson(Map<String, dynamic> json) {
    return LoanTypeInfo(
      name: json['name'] as String? ?? '',
      minAmount: (json['minAmount'] as num?)?.toDouble() ?? 
                  (json['min_amount'] as num?)?.toDouble() ?? 0.0,
      maxAmount: (json['maxAmount'] as num?)?.toDouble() ?? 
                 (json['max_amount'] as num?)?.toDouble() ?? 0.0,
      tenure: json['tenure'] as int? ?? 
              json['duration'] as int? ?? 12,
      interestRate: (json['interestRate'] as num?)?.toDouble() ?? 
                     (json['interest_rate'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String?,
      tenures: json['tenures'] != null 
          ? (json['tenures'] as List).cast<int>() 
          : null,
    );
  }

  @override
  List<Object?> get props => [name, minAmount, maxAmount, tenure, interestRate, description, tenures];
}
