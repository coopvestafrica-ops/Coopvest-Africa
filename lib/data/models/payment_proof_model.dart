import 'package:equatable/equatable.dart';

/// Payment proof status
enum PaymentProofStatus {
  pending,
  underReview,
  approved,
  rejected,
}

/// Payment proof type
enum PaymentProofType {
  monthlyContribution,
  loanRepayment,
  registrationFee,
  investment,
  other,
}

/// Payment method
enum PaymentMethod {
  bankTransfer,
  ussd,
  pos,
  cashDeposit,
  card,
}

/// Extension for payment proof status display
extension PaymentProofStatusExtension on PaymentProofStatus {
  String get displayName {
    switch (this) {
      case PaymentProofStatus.pending:
        return 'Pending Verification';
      case PaymentProofStatus.underReview:
        return 'Under Review';
      case PaymentProofStatus.approved:
        return 'Verified';
      case PaymentProofStatus.rejected:
        return 'Rejected';
    }
  }

  String get apiValue {
    switch (this) {
      case PaymentProofStatus.pending:
        return 'pending';
      case PaymentProofStatus.underReview:
        return 'under_review';
      case PaymentProofStatus.approved:
        return 'approved';
      case PaymentProofStatus.rejected:
        return 'rejected';
    }
  }

  static PaymentProofStatus fromString(String? value) {
    switch (value) {
      case 'pending':
        return PaymentProofStatus.pending;
      case 'under_review':
        return PaymentProofStatus.underReview;
      case 'approved':
        return PaymentProofStatus.approved;
      case 'rejected':
        return PaymentProofStatus.rejected;
      default:
        return PaymentProofStatus.pending;
    }
  }
}

/// Extension for payment proof type display
extension PaymentProofTypeExtension on PaymentProofType {
  String get displayName {
    switch (this) {
      case PaymentProofType.monthlyContribution:
        return 'Monthly Contribution';
      case PaymentProofType.loanRepayment:
        return 'Loan Repayment';
      case PaymentProofType.registrationFee:
        return 'Registration Fee';
      case PaymentProofType.investment:
        return 'Investment';
      case PaymentProofType.other:
        return 'Other Payment';
    }
  }

  String get apiValue {
    switch (this) {
      case PaymentProofType.monthlyContribution:
        return 'monthly_contribution';
      case PaymentProofType.loanRepayment:
        return 'loan_repayment';
      case PaymentProofType.registrationFee:
        return 'registration_fee';
      case PaymentProofType.investment:
        return 'investment';
      case PaymentProofType.other:
        return 'other';
    }
  }

  static PaymentProofType fromString(String? value) {
    switch (value) {
      case 'monthly_contribution':
        return PaymentProofType.monthlyContribution;
      case 'loan_repayment':
        return PaymentProofType.loanRepayment;
      case 'registration_fee':
        return PaymentProofType.registrationFee;
      case 'investment':
        return PaymentProofType.investment;
      case 'other':
        return PaymentProofType.other;
      default:
        return PaymentProofType.other;
    }
  }
}

/// Extension for payment method display
extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.ussd:
        return 'USSD Transfer';
      case PaymentMethod.pos:
        return 'POS Terminal';
      case PaymentMethod.cashDeposit:
        return 'Cash Deposit';
      case PaymentMethod.card:
        return 'Card Payment';
    }
  }

  String get apiValue {
    switch (this) {
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      case PaymentMethod.ussd:
        return 'ussd';
      case PaymentMethod.pos:
        return 'pos';
      case PaymentMethod.cashDeposit:
        return 'cash_deposit';
      case PaymentMethod.card:
        return 'card';
    }
  }

  static PaymentMethod fromString(String? value) {
    switch (value) {
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      case 'ussd':
        return PaymentMethod.ussd;
      case 'pos':
        return PaymentMethod.pos;
      case 'cash_deposit':
        return PaymentMethod.cashDeposit;
      case 'card':
        return PaymentMethod.card;
      default:
        return PaymentMethod.bankTransfer;
    }
  }
}

/// Bank Account Model
class BankAccount extends Equatable {
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String? bankCode;

  const BankAccount({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    this.bankCode,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      bankName: json['bank_name'] as String,
      accountName: json['account_name'] as String,
      accountNumber: json['account_number'] as String,
      bankCode: json['bank_code'] as String?,
    );
  }

  @override
  List<Object?> get props => [bankName, accountName, accountNumber, bankCode];
}

/// Payment Proof Model
class PaymentProof extends Equatable {
  final String id;
  final String profileId;
  final PaymentProofType paymentType;
  final double amount;
  final String currency;
  final DateTime paymentDate;
  final PaymentMethod? paymentMethod;
  final String? receivingBank;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? transactionReference;
  final String? proofUrl;
  final String? proofType;
  final String? originalFilename;
  final int? fileSize;
  final PaymentProofStatus status;
  final String? rejectionReason;
  final DateTime? rejectedAt;
  final String? reviewedBy;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? adminNotes;
  final String? contributionId;
  final String? memberNote;
  final DigitalReceipt? receipt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentProof({
    required this.id,
    required this.profileId,
    required this.paymentType,
    required this.amount,
    this.currency = 'NGN',
    required this.paymentDate,
    this.paymentMethod,
    this.receivingBank,
    this.bankAccountName,
    this.bankAccountNumber,
    this.transactionReference,
    this.proofUrl,
    this.proofType,
    this.originalFilename,
    this.fileSize,
    this.status = PaymentProofStatus.pending,
    this.rejectionReason,
    this.rejectedAt,
    this.reviewedBy,
    this.approvedAt,
    this.approvedBy,
    this.adminNotes,
    this.contributionId,
    this.memberNote,
    this.receipt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentProof.fromJson(Map<String, dynamic> json) {
    return PaymentProof(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      paymentType: PaymentProofTypeExtension.fromString(json['payment_type'] as String?),
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'NGN',
      paymentDate: DateTime.parse(json['payment_date'] as String),
      paymentMethod: json['payment_method'] != null
          ? PaymentMethodExtension.fromString(json['payment_method'] as String)
          : null,
      receivingBank: json['receiving_bank'] as String?,
      bankAccountName: json['bank_account_name'] as String?,
      bankAccountNumber: json['bank_account_number'] as String?,
      transactionReference: json['transaction_reference'] as String?,
      proofUrl: json['proof_url'] as String?,
      proofType: json['proof_type'] as String?,
      originalFilename: json['original_filename'] as String?,
      fileSize: json['file_size'] as int?,
      status: PaymentProofStatusExtension.fromString(json['status'] as String?),
      rejectionReason: json['rejection_reason'] as String?,
      rejectedAt: json['rejected_at'] != null
          ? DateTime.parse(json['rejected_at'] as String)
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      adminNotes: json['admin_notes'] as String?,
      contributionId: json['contribution_id'] as String?,
      memberNote: json['member_note'] as String?,
      receipt: json['receipt'] != null
          ? DigitalReceipt.fromJson(json['receipt'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_id': profileId,
      'payment_type': paymentType.apiValue,
      'amount': amount,
      'currency': currency,
      'payment_date': paymentDate.toIso8601String(),
      'payment_method': paymentMethod?.apiValue,
      'receiving_bank': receivingBank,
      'bank_account_name': bankAccountName,
      'bank_account_number': bankAccountNumber,
      'transaction_reference': transactionReference,
      'proof_url': proofUrl,
      'proof_type': proofType,
      'original_filename': originalFilename,
      'file_size': fileSize,
      'status': status.apiValue,
      'rejection_reason': rejectionReason,
      'rejected_at': rejectedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by': approvedBy,
      'admin_notes': adminNotes,
      'contribution_id': contributionId,
      'member_note': memberNote,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        profileId,
        paymentType,
        amount,
        currency,
        paymentDate,
        paymentMethod,
        receivingBank,
        transactionReference,
        proofUrl,
        status,
        rejectionReason,
        createdAt,
        updatedAt,
      ];
}

/// Digital Receipt Model
class DigitalReceipt extends Equatable {
  final String id;
  final String receiptNumber;
  final String? receiptId;
  final String? paymentProofId;
  final String profileId;
  final String? memberName;
  final String? membershipId;
  final String? paymentType;
  final double amount;
  final String currency;
  final String? transactionReference;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? receivingBank;
  final String? approvedBy;
  final String? approvedByName;
  final DateTime? approvedAt;
  final String? qrCodeUrl;
  final String? verificationHash;
  final String? organizationName;
  final DateTime createdAt;

  const DigitalReceipt({
    required this.id,
    required this.receiptNumber,
    this.receiptId,
    this.paymentProofId,
    required this.profileId,
    this.memberName,
    this.membershipId,
    this.paymentType,
    required this.amount,
    this.currency = 'NGN',
    this.transactionReference,
    this.paymentDate,
    this.paymentMethod,
    this.receivingBank,
    this.approvedBy,
    this.approvedByName,
    this.approvedAt,
    this.qrCodeUrl,
    this.verificationHash,
    this.organizationName,
    required this.createdAt,
  });

  factory DigitalReceipt.fromJson(Map<String, dynamic> json) {
    return DigitalReceipt(
      id: json['id'] as String,
      receiptNumber: json['receipt_number'] as String,
      receiptId: json['receipt_id'] as String?,
      paymentProofId: json['payment_proof_id'] as String?,
      profileId: json['profile_id'] as String,
      memberName: json['member_name'] as String?,
      membershipId: json['membership_id'] as String?,
      paymentType: json['payment_type'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'NGN',
      transactionReference: json['transaction_reference'] as String?,
      paymentDate: json['payment_date'] != null
          ? DateTime.parse(json['payment_date'] as String)
          : null,
      paymentMethod: json['payment_method'] as String?,
      receivingBank: json['receiving_bank'] as String?,
      approvedBy: json['approved_by'] as String?,
      approvedByName: json['approved_by_name'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      qrCodeUrl: json['qr_code_url'] as String?,
      verificationHash: json['verification_hash'] as String?,
      organizationName: json['organization_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        receiptNumber,
        receiptId,
        paymentProofId,
        profileId,
        amount,
        createdAt,
      ];
}

/// Payment Proof Summary
class PaymentProofSummary extends Equatable {
  final int total;
  final int pending;
  final int underReview;
  final int approved;
  final int rejected;
  final double totalAmount;
  final double approvedAmount;

  const PaymentProofSummary({
    required this.total,
    required this.pending,
    required this.underReview,
    required this.approved,
    required this.rejected,
    required this.totalAmount,
    required this.approvedAmount,
  });

  factory PaymentProofSummary.fromJson(Map<String, dynamic> json) {
    return PaymentProofSummary(
      total: json['total'] as int? ?? 0,
      pending: json['pending'] as int? ?? 0,
      underReview: json['under_review'] as int? ?? 0,
      approved: json['approved'] as int? ?? 0,
      rejected: json['rejected'] as int? ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      approvedAmount: (json['approved_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [
        total,
        pending,
        underReview,
        approved,
        rejected,
        totalAmount,
        approvedAmount,
      ];
}

/// Payment Proof List Response
class PaymentProofListResponse {
  final bool success;
  final List<PaymentProof> paymentProofs;
  final int totalCount;
  final int page;
  final int pageSize;
  final int totalPages;

  PaymentProofListResponse({
    required this.success,
    required this.paymentProofs,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory PaymentProofListResponse.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    return PaymentProofListResponse(
      success: json['success'] as bool,
      paymentProofs: (json['payment_proofs'] as List? ?? [])
          .map((e) => PaymentProof.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: pagination['total'] as int? ?? 0,
      page: pagination['page'] as int? ?? 1,
      pageSize: pagination['limit'] as int? ?? 20,
      totalPages: pagination['total_pages'] as int? ?? 1,
    );
  }

  bool get hasMore => page < totalPages;
}
