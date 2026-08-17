import 'package:equatable/equatable.dart';

/// Contribution payment method (how member contributes)
enum ContributionMethod {
  manual,
  payroll,
}

/// Extension for contribution method display
extension ContributionMethodExtension on ContributionMethod {
  String get displayName {
    switch (this) {
      case ContributionMethod.manual:
        return 'Monthly Self Contribution';
      case ContributionMethod.payroll:
        return 'Salary Deduction';
    }
  }

  String get shortName {
    switch (this) {
      case ContributionMethod.manual:
        return 'Manual';
      case ContributionMethod.payroll:
        return 'Payroll';
    }
  }
}

/// Status types for contributions
enum ContributionStatus {
  successful,
  pending,
  failed,
  processing,
  reversed,
  adjusted,
  disputed,
}

/// Types of contributions
enum ContributionType {
  monthly,
  voluntary,
  special,
  arrears,
  topup,
}

/// Contribution status helper
extension ContributionStatusExtension on ContributionStatus {
  String get displayName {
    switch (this) {
      case ContributionStatus.successful:
        return 'Successful';
      case ContributionStatus.pending:
        return 'Pending';
      case ContributionStatus.failed:
        return 'Failed';
      case ContributionStatus.processing:
        return 'Processing';
      case ContributionStatus.reversed:
        return 'Reversed';
      case ContributionStatus.adjusted:
        return 'Adjusted';
      case ContributionStatus.disputed:
        return 'Disputed';
    }
  }

  String get color {
    switch (this) {
      case ContributionStatus.successful:
        return 'success';
      case ContributionStatus.pending:
        return 'warning';
      case ContributionStatus.failed:
        return 'error';
      case ContributionStatus.processing:
        return 'info';
      case ContributionStatus.reversed:
        return 'warning';
      case ContributionStatus.adjusted:
        return 'info';
      case ContributionStatus.disputed:
        return 'error';
    }
  }
}

/// Contribution type helper
extension ContributionTypeExtension on ContributionType {
  String get displayName {
    switch (this) {
      case ContributionType.monthly:
        return 'Monthly Contribution';
      case ContributionType.voluntary:
        return 'Voluntary Contribution';
      case ContributionType.special:
        return 'Special Contribution';
      case ContributionType.arrears:
        return 'Arrears Payment';
      case ContributionType.topup:
        return 'Top-up';
    }
  }
}

/// Monthly Contribution Model
/// Represents a single monthly contribution record
class MonthlyContribution extends Equatable {
  final String id;
  final String userId;
  final String contributionMonth; // Format: '2024-01' for January 2024
  final double amount;
  final ContributionType type;
  final ContributionStatus status;
  final String? transactionReference;
  final String? paymentMethod;
  final String? sourceWallet;
  final String? sourceBank;
  final DateTime? postedDate;
  final DateTime? processedDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;
  final List<StatusHistory>? statusHistory;

  const MonthlyContribution({
    required this.id,
    required this.userId,
    required this.contributionMonth,
    required this.amount,
    required this.type,
    required this.status,
    this.transactionReference,
    this.paymentMethod,
    this.sourceWallet,
    this.sourceBank,
    this.postedDate,
    this.processedDate,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.statusHistory,
  });

  factory MonthlyContribution.fromJson(Map<String, dynamic> json) {
    return MonthlyContribution(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      contributionMonth: json['contribution_month'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: ContributionType.values.firstWhere(
        (e) => e.name == (json['contribution_type'] as String? ?? 'monthly'),
        orElse: () => ContributionType.monthly,
      ),
      status: ContributionStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'pending'),
        orElse: () => ContributionStatus.pending,
      ),
      transactionReference: json['transaction_reference'] as String?,
      paymentMethod: json['payment_method'] as String?,
      sourceWallet: json['source_wallet'] as String?,
      sourceBank: json['source_bank'] as String?,
      postedDate: json['posted_date'] != null
          ? DateTime.parse(json['posted_date'] as String)
          : null,
      processedDate: json['processed_date'] != null
          ? DateTime.parse(json['processed_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      notes: json['notes'] as String?,
      statusHistory: json['status_history'] != null
          ? (json['status_history'] as List)
              .map((e) => StatusHistory.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'contribution_month': contributionMonth,
      'amount': amount,
      'contribution_type': type.name,
      'status': status.name,
      'transaction_reference': transactionReference,
      'payment_method': paymentMethod,
      'source_wallet': sourceWallet,
      'source_bank': sourceBank,
      'posted_date': postedDate?.toIso8601String(),
      'processed_date': processedDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'notes': notes,
      'status_history': statusHistory?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        contributionMonth,
        amount,
        type,
        status,
        transactionReference,
        paymentMethod,
        sourceWallet,
        sourceBank,
        postedDate,
        processedDate,
        createdAt,
        updatedAt,
        notes,
        statusHistory,
      ];
}

/// Status History for tracking contribution status changes
class StatusHistory extends Equatable {
  final ContributionStatus status;
  final String? description;
  final DateTime timestamp;

  const StatusHistory({
    required this.status,
    this.description,
    required this.timestamp,
  });

  factory StatusHistory.fromJson(Map<String, dynamic> json) {
    return StatusHistory(
      status: ContributionStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'pending'),
        orElse: () => ContributionStatus.pending,
      ),
      description: json['description'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [status, description, timestamp];
}

/// Contribution Summary Model
/// Provides aggregated contribution data
class ContributionSummary extends Equatable {
  final double totalThisMonth;
  final double totalThisYear;
  final double lifetimeContributions;
  final double expectedMonthlyAmount;
  final String contributionStatus; // 'up_to_date', 'overdue', 'pending'
  final int monthsContributed;
  final int totalContributionsCount;
  final double? pendingAmount;
  final double? overdueAmount;

  const ContributionSummary({
    required this.totalThisMonth,
    required this.totalThisYear,
    required this.lifetimeContributions,
    required this.expectedMonthlyAmount,
    required this.contributionStatus,
    required this.monthsContributed,
    required this.totalContributionsCount,
    this.pendingAmount,
    this.overdueAmount,
  });

  factory ContributionSummary.fromJson(Map<String, dynamic> json) {
    // The backend /contributions/summary returns camelCase keys
    // (totalThisMonth, totalThisYear, lifetimeContributions,
    // expectedMonthlyAmount, contributionStatus). Support both camelCase and
    // snake_case so a mismatched case never silently falls back to mock data.
    double _asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return ContributionSummary(
      totalThisMonth: _asDouble(json['totalThisMonth'] ?? json['total_this_month']),
      totalThisYear: _asDouble(json['totalThisYear'] ?? json['total_this_year']),
      lifetimeContributions: _asDouble(json['lifetimeContributions'] ?? json['lifetime_contributions']),
      expectedMonthlyAmount: _asDouble(json['expectedMonthlyAmount'] ?? json['expected_monthly_amount']),
      contributionStatus: (json['contributionStatus'] ?? json['contribution_status'] ?? 'pending') as String,
      monthsContributed: (json['monthsContributed'] ?? json['months_contributed'] ?? 0) as int,
      totalContributionsCount: (json['totalContributionsCount'] ?? json['total_contributions_count'] ?? 0) as int,
      pendingAmount: json['pendingAmount'] != null || json['pending_amount'] != null
          ? _asDouble(json['pendingAmount'] ?? json['pending_amount'])
          : null,
      overdueAmount: json['overdueAmount'] != null || json['overdue_amount'] != null
          ? _asDouble(json['overdueAmount'] ?? json['overdue_amount'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_this_month': totalThisMonth,
      'total_this_year': totalThisYear,
      'lifetime_contributions': lifetimeContributions,
      'expected_monthly_amount': expectedMonthlyAmount,
      'contribution_status': contributionStatus,
      'months_contributed': monthsContributed,
      'total_contributions_count': totalContributionsCount,
      'pending_amount': pendingAmount,
      'overdue_amount': overdueAmount,
    };
  }

  @override
  List<Object?> get props => [
        totalThisMonth,
        totalThisYear,
        lifetimeContributions,
        expectedMonthlyAmount,
        contributionStatus,
        monthsContributed,
        totalContributionsCount,
        pendingAmount,
        overdueAmount,
      ];
}

/// Contribution Detail Model
/// Extended information for a single contribution
class ContributionDetail extends Equatable {
  final MonthlyContribution contribution;
  final String? receiptUrl;
  final String? auditTrailId;
  final List<ProcessingLog>? processingLogs;

  const ContributionDetail({
    required this.contribution,
    this.receiptUrl,
    this.auditTrailId,
    this.processingLogs,
  });

  factory ContributionDetail.fromJson(Map<String, dynamic> json) {
    return ContributionDetail(
      contribution: MonthlyContribution.fromJson(
          json['contribution'] as Map<String, dynamic>),
      receiptUrl: json['receipt_url'] as String?,
      auditTrailId: json['audit_trail_id'] as String?,
      processingLogs: json['processing_logs'] != null
          ? (json['processing_logs'] as List)
              .map((e) => ProcessingLog.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contribution': contribution.toJson(),
      'receipt_url': receiptUrl,
      'audit_trail_id': auditTrailId,
      'processing_logs': processingLogs?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [contribution, receiptUrl, auditTrailId, processingLogs];
}

/// Processing Log for tracking contribution processing steps
class ProcessingLog extends Equatable {
  final String step;
  final String? description;
  final DateTime timestamp;
  final bool success;
  final String? errorMessage;

  const ProcessingLog({
    required this.step,
    this.description,
    required this.timestamp,
    required this.success,
    this.errorMessage,
  });

  factory ProcessingLog.fromJson(Map<String, dynamic> json) {
    return ProcessingLog(
      step: json['step'] as String,
      description: json['description'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'step': step,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'error_message': errorMessage,
    };
  }

  @override
  List<Object?> get props => [step, description, timestamp, success, errorMessage];
}

/// Filter options for contributions list
class ContributionFilter {
  final int? year;
  final int? month;
  final ContributionStatus? status;
  final ContributionType? type;
  final String? searchQuery;
  final DateTime? startDate;
  final DateTime? endDate;

  const ContributionFilter({
    this.year,
    this.month,
    this.status,
    this.type,
    this.searchQuery,
    this.startDate,
    this.endDate,
  });

  ContributionFilter copyWith({
    int? year,
    int? month,
    ContributionStatus? status,
    ContributionType? type,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return ContributionFilter(
      year: year ?? this.year,
      month: month ?? this.month,
      status: status ?? this.status,
      type: type ?? this.type,
      searchQuery: searchQuery ?? this.searchQuery,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (status != null) 'status': status!.name,
      if (type != null) 'type': type!.name,
      if (searchQuery != null && searchQuery!.isNotEmpty) 'search': searchQuery,
      if (startDate != null) 'start_date': startDate!.toIso8601String(),
      if (endDate != null) 'end_date': endDate!.toIso8601String(),
    };
  }

  ContributionFilter thisMonth() {
    final now = DateTime.now();
    return copyWith(
      year: now.year,
      month: now.month,
      startDate: DateTime(now.year, now.month, 1),
      endDate: DateTime(now.year, now.month + 1, 0),
    );
  }

  ContributionFilter last3Months() {
    final now = DateTime.now();
    return copyWith(
      startDate: DateTime(now.year, now.month - 3, 1),
      endDate: DateTime(now.year, now.month + 1, 0),
    );
  }

  ContributionFilter last6Months() {
    final now = DateTime.now();
    return copyWith(
      startDate: DateTime(now.year, now.month - 6, 1),
      endDate: DateTime(now.year, now.month + 1, 0),
    );
  }

  ContributionFilter thisYear() {
    final now = DateTime.now();
    return copyWith(
      year: now.year,
      startDate: DateTime(now.year, 1, 1),
      endDate: DateTime(now.year, 12, 31),
    );
  }

  ContributionFilter allTime() {
    return copyWith(year: null, month: null, startDate: null, endDate: null);
  }
}

/// Monthly Deductions Breakdown Model
/// Provides a breakdown of deductions for a single month
class MonthlyDeductionsBreakdown extends Equatable {
  final String month; // Format: '2024-01' for January 2024
  final double totalDeductions;
  final List<DeductionItem> items;

  const MonthlyDeductionsBreakdown({
    required this.month,
    required this.totalDeductions,
    required this.items,
  });

  factory MonthlyDeductionsBreakdown.fromJson(Map<String, dynamic> json) {
    return MonthlyDeductionsBreakdown(
      month: json['month'] as String,
      totalDeductions: (json['total_deductions'] as num).toDouble(),
      items: (json['items'] as List)
          .map((e) => DeductionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'month': month,
      'total_deductions': totalDeductions,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [month, totalDeductions, items];
}

/// Deduction Item Model
/// Represents a single deduction item in the breakdown
class DeductionItem extends Equatable {
  final String name;
  final double amount;
  final String? description;

  const DeductionItem({
    required this.name,
    required this.amount,
    this.description,
  });

  factory DeductionItem.fromJson(Map<String, dynamic> json) {
    return DeductionItem(
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': amount,
      'description': description,
    };
  }

  @override
  List<Object?> get props => [name, amount, description];
}