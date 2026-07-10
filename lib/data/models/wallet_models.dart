import 'package:equatable/equatable.dart';

/// Wallet Model
class Wallet extends Equatable {
  final String id;
  final String userId;
  final double balance;
  final double totalContributions;
  final double totalSavings; // Total savings used for loan eligibility calculation
  final double pendingContributions;
  final double availableForWithdrawal;
  final DateTime updatedAt;

  const Wallet({
    required this.id,
    required this.userId,
    required this.balance,
    required this.totalContributions,
    required this.totalSavings,
    required this.pendingContributions,
    required this.availableForWithdrawal,
    required this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      balance: (json['balance'] as num).toDouble(),
      totalContributions: (json['total_contributions'] as num).toDouble(),
      totalSavings: (json['total_savings'] as num).toDouble(),
      pendingContributions: (json['pending_contributions'] as num).toDouble(),
      availableForWithdrawal: (json['available_for_withdrawal'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'balance': balance,
      'total_contributions': totalContributions,
      'total_savings': totalSavings,
      'pending_contributions': pendingContributions,
      'available_for_withdrawal': availableForWithdrawal,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Wallet copyWith({
    String? id,
    String? userId,
    double? balance,
    double? totalContributions,
    double? totalSavings,
    double? pendingContributions,
    double? availableForWithdrawal,
    DateTime? updatedAt,
  }) {
    return Wallet(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      balance: balance ?? this.balance,
      totalContributions: totalContributions ?? this.totalContributions,
      totalSavings: totalSavings ?? this.totalSavings,
      pendingContributions: pendingContributions ?? this.pendingContributions,
      availableForWithdrawal: availableForWithdrawal ?? this.availableForWithdrawal,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    balance,
    totalContributions,
    totalSavings,
    pendingContributions,
    availableForWithdrawal,
    updatedAt,
  ];
}

/// Transaction Model
class Transaction extends Equatable {
  final String id;
  final String walletId;
  final String type; // deposit, withdrawal, transfer_in, transfer_out, interest, loan_repayment
  final String? category; // credit, debit
  final double amount;
  final String status; // pending, completed, failed
  final String? description;
  final String? referenceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Transaction({
    required this.id,
    required this.walletId,
    required this.type,
    this.category,
    required this.amount,
    required this.status,
    this.description,
    this.referenceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True when the transaction increases the wallet balance.
  /// Prefers the backend `category` field, falling back to known credit types.
  bool get isCredit {
    if (category != null) return category == 'credit';
    return const ['deposit', 'transfer_in', 'contribution', 'loan_disbursement', 'refund', 'interest']
        .contains(type);
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Helper to safely extract string values, handling nested objects
    String? safeString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is Map) return value.toString();
      return value.toString();
    }
    
    return Transaction(
      id: safeString(json['id']) ?? '',
      walletId: safeString(json['wallet_id']) ?? safeString(json['profile_id']) ?? '',
      type: safeString(json['type']) ?? 'deposit',
      category: safeString(json['category']),
      amount: _safeDouble(json['amount']),
      status: safeString(json['status']) ?? 'completed',
      description: safeString(json['description']),
      referenceId: safeString(json['reference_id']) ?? safeString(json['reference']),
      createdAt: _safeDateTime(json['created_at']),
      updatedAt: _safeDateTime(json['updated_at']),
    );
  }
  
  static double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  
  static DateTime _safeDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'wallet_id': walletId,
      'type': type,
      'category': category,
      'amount': amount,
      'status': status,
      'description': description,
      'reference_id': referenceId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    walletId,
    type,
    category,
    amount,
    status,
    description,
    referenceId,
    createdAt,
    updatedAt,
  ];
}

/// Contribution Model
class Contribution extends Equatable {
  final String id;
  final String walletId;
  final double amount;
  final String status; // pending, completed, failed
  final String? paymentMethod;
  final DateTime dueDate;
  final DateTime? completedAt;
  final DateTime createdAt;

  const Contribution({
    required this.id,
    required this.walletId,
    required this.amount,
    required this.status,
    this.paymentMethod,
    required this.dueDate,
    this.completedAt,
    required this.createdAt,
  });

  factory Contribution.fromJson(Map<String, dynamic> json) {
    return Contribution(
      id: json['id'] as String,
      walletId: json['wallet_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      status: json['status'] as String,
      paymentMethod: json['payment_method'] as String?,
      dueDate: DateTime.parse(json['due_date'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'wallet_id': walletId,
      'amount': amount,
      'status': status,
      'payment_method': paymentMethod,
      'due_date': dueDate.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    walletId,
    amount,
    status,
    paymentMethod,
    dueDate,
    completedAt,
    createdAt,
  ];
}

/// Wallet State
enum WalletStatus {
  initial,
  loading,
  loaded,
  error,
}

class WalletState extends Equatable {
  final WalletStatus status;
  final Wallet? wallet;
  final List<Transaction> transactions;
  final List<Contribution> contributions;
  final List<SavingsGoal> savingsGoals;
  final String? error;

  const WalletState({
    this.status = WalletStatus.initial,
    this.wallet,
    this.transactions = const [],
    this.contributions = const [],
    this.savingsGoals = const [],
    this.error,
  });

  bool get isLoading => status == WalletStatus.loading;
  bool get isLoaded => status == WalletStatus.loaded;

  WalletState copyWith({
    WalletStatus? status,
    Wallet? wallet,
    List<Transaction>? transactions,
    List<Contribution>? contributions,
    List<SavingsGoal>? savingsGoals,
    String? error,
  }) {
    return WalletState(
      status: status ?? this.status,
      wallet: wallet ?? this.wallet,
      transactions: transactions ?? this.transactions,
      contributions: contributions ?? this.contributions,
      savingsGoals: savingsGoals ?? this.savingsGoals,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, wallet, transactions, contributions, savingsGoals, error];
}

/// Savings Goal Model
class SavingsGoal extends Equatable {
  final String id;
  final String userId;
  final String walletId;
  final String name;
  final String? description;
  final double targetAmount;
  final double currentAmount;
  final double monthlyContribution;
  final DateTime targetDate;
  final DateTime createdAt;
  final String status; // active, completed, cancelled

  const SavingsGoal({
    required this.id,
    required this.userId,
    required this.walletId,
    required this.name,
    this.description,
    required this.targetAmount,
    required this.currentAmount,
    required this.monthlyContribution,
    required this.targetDate,
    required this.createdAt,
    this.status = 'active',
  });

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      walletId: json['wallet_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      targetAmount: (json['target_amount'] as num).toDouble(),
      currentAmount: (json['current_amount'] as num).toDouble(),
      monthlyContribution: (json['monthly_contribution'] as num).toDouble(),
      targetDate: DateTime.parse(json['target_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'wallet_id': walletId,
      'name': name,
      'description': description,
      'target_amount': targetAmount,
      'current_amount': currentAmount,
      'monthly_contribution': monthlyContribution,
      'target_date': targetDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'status': status,
    };
  }

  SavingsGoal copyWith({
    String? id,
    String? userId,
    String? walletId,
    String? name,
    String? description,
    double? targetAmount,
    double? currentAmount,
    double? monthlyContribution,
    DateTime? targetDate,
    DateTime? createdAt,
    String? status,
  }) {
    return SavingsGoal(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      walletId: walletId ?? this.walletId,
      name: name ?? this.name,
      description: description ?? this.description,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      monthlyContribution: monthlyContribution ?? this.monthlyContribution,
      targetDate: targetDate ?? this.targetDate,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }

  double get progressPercentage {
    if (targetAmount <= 0) return 0;
    return (currentAmount / targetAmount).clamp(0, 1) * 100;
  }

  double get remainingAmount => targetAmount - currentAmount;

  int get monthsRemaining {
    final now = DateTime.now();
    if (targetDate.isBefore(now)) return 0;
    return (targetDate.difference(now).inDays / 30).ceil();
  }

  bool get isCompleted => currentAmount >= targetAmount;

  @override
  List<Object?> get props => [
        id,
        userId,
        walletId,
        name,
        description,
        targetAmount,
        currentAmount,
        monthlyContribution,
        targetDate,
        createdAt,
        status,
      ];
}