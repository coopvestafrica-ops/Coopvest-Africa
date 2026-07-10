import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/utils.dart';
import '../../data/models/wallet_models.dart';

/// Wallet Repository Provider
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return WalletRepository(apiClient);
});

/// Wallet Repository
class WalletRepository {
  final ApiClient _apiClient;

  WalletRepository(this._apiClient);

  /// Get wallet
  Future<Wallet> getWallet() async {
    try {
      final response = await _apiClient.get('/wallet/balance');
      // Backend returns { success: true, balance: ..., recentTransactions: ... }
      // We need to map this to the Wallet model
      if (response is Map<String, dynamic>) {
        return Wallet(
          id: response['id']?.toString() ?? 'mock_wallet_id',
          userId: response['user_id']?.toString() ?? 'mock_user_id',
          balance: (response['balance'] as num?)?.toDouble() ?? 0.0,
          totalContributions: (response['total_contributions'] as num?)?.toDouble() ?? 0.0,
          totalSavings: (response['total_savings'] as num?)?.toDouble() ?? 0.0,
          pendingContributions: (response['pending_contributions'] as num?)?.toDouble() ?? 0.0,
          availableForWithdrawal: (response['available_for_withdrawal'] as num?)?.toDouble() ?? (response['balance'] as num?)?.toDouble() ?? 0.0,
          updatedAt: response['lastUpdated'] != null ? DateTime.parse(response['lastUpdated'] as String) : DateTime.now(),
        );
      }
      return Wallet.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      logger.e('Get wallet error: $e');
      // Return empty wallet with zero values when backend fails
      return Wallet(
        id: '',
        userId: '',
        balance: 0.0,
        totalContributions: 0.0,
        totalSavings: 0.0,
        pendingContributions: 0.0,
        availableForWithdrawal: 0.0,
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Get savings goals
  Future<List<SavingsGoal>> getSavingsGoals({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/savings/goals',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
      );

      final data = response as Map<String, dynamic>;
      final goals = (data['goals'] as List? ?? [])
          .map((item) => SavingsGoal.fromJson(item as Map<String, dynamic>))
          .toList();

      return goals;
    } catch (e) {
      logger.e('Get savings goals error: $e');
      return [];
    }
  }

  /// Get transactions
  Future<List<Transaction>> getTransactions({
    int page = 1,
    int pageSize = 20,
    String? type,
    String? status,
  }) async {
    try {
      final response = await _apiClient.get(
        '/wallet/transactions',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          if (type != null) 'type': type,
          if (status != null) 'status': status,
        },
      );

      final data = response as Map<String, dynamic>;
      final transactions = (data['transactions'] as List? ?? [])
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList();

      return transactions;
    } catch (e) {
      logger.e('Get transactions error: $e');
      // Return empty list when backend fails - no placeholders
      return [];
    }
  }

  /// Make contribution - returns Map with transaction and message
  Future<Map<String, dynamic>> makeContribution(double amount, {String? description}) async {
    try {
      final Map<String, dynamic> requestData = {
        'amount': amount,
      };
      if (description != null) {
        requestData['description'] = description;
      }
      
      final response = await _apiClient.post(
        '/wallet/contribute',
        data: requestData,
      );

      final data = response as Map<String, dynamic>;
      
      // Return the full response including message
      return {
        'transaction': data['transaction'],
        'deposit_request': data['deposit_request'],
        'message': data['message'] ?? 'Your deposit is pending verification.',
        'success': data['success'] == true,
      };
    } catch (e) {
      logger.e('Make contribution error: $e');
      rethrow;
    }
  }

  /// Get contributions
  Future<List<Contribution>> getContributions({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/wallet/contributions',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
      );

      final data = response as Map<String, dynamic>;
      final contributions = (data['data'] as List? ?? [])
          .map((item) => Contribution.fromJson(item as Map<String, dynamic>))
          .toList();

      return contributions;
    } catch (e) {
      logger.e('Get contributions error: $e');
      return [];
    }
  }

  /// Make withdrawal
  Future<void> makeWithdrawal(double amount, {String? description}) async {
    try {
      final response = await _apiClient.post(
        '/wallet/withdraw',
        data: {'amount': amount, if (description != null) 'description': description},
      );
      return;
    } catch (e) {
      logger.e('Make withdrawal error: $e');
      rethrow;
    }
  }

  /// Create a savings goal
  Future<void> createSavingsGoal({
    required String name,
    required double targetAmount,
    required DateTime targetDate,
    String? description,
  }) async {
    try {
      await _apiClient.post(
        '/savings/goals',
        data: {
          'name': name,
          'targetAmount': targetAmount,
          'targetDate': targetDate.toIso8601String(),
          if (description != null) 'description': description,
        },
      );
    } catch (e) {
      logger.e('Create savings goal error: $e');
      rethrow;
    }
  }

  /// Generate statement
  Future<String> generateStatement({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _apiClient.post(
        '/wallet/statement',
        data: {
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
        },
      );

      return response['statement_url'] as String? ?? '';
    } catch (e) {
      logger.e('Generate statement error: $e');
      rethrow;
    }
  }

  /// Get transaction receipt
  Future<String> getTransactionReceipt(String transactionId) async {
    try {
      final response = await _apiClient.get(
        '/wallet/transactions/$transactionId/receipt',
      );

      return response['receipt_url'] as String? ?? '';
    } catch (e) {
      logger.e('Get transaction receipt error: $e');
      rethrow;
    }
  }
}

/// Wallet Notifier
class WalletNotifier extends StateNotifier<WalletState> {
  final WalletRepository _walletRepository;

  WalletNotifier(this._walletRepository) : super(const WalletState());

  /// Load wallet
  Future<void> loadWallet() async {
    state = state.copyWith(status: WalletStatus.loading);
    try {
      final wallet = await _walletRepository.getWallet();
      state = state.copyWith(
        status: WalletStatus.loaded,
        wallet: wallet,
      );
    } catch (e) {
      logger.e('Load wallet error: $e');
      state = state.copyWith(
        status: WalletStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Load transactions
  Future<void> loadTransactions({
    int page = 1,
    int pageSize = 20,
    String? type,
    String? status,
  }) async {
    state = state.copyWith(status: WalletStatus.loading);
    try {
      final transactions = await _walletRepository.getTransactions(
        page: page,
        pageSize: pageSize,
        type: type,
        status: status,
      );

      state = state.copyWith(
        status: WalletStatus.loaded,
        transactions: transactions,
      );
    } catch (e) {
      logger.e('Load transactions error: $e');
      state = state.copyWith(
        status: WalletStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Load savings goals
  Future<void> loadSavingsGoals({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final goals = await _walletRepository.getSavingsGoals(
        page: page,
        pageSize: pageSize,
      );

      state = state.copyWith(
        status: WalletStatus.loaded,
        savingsGoals: goals,
      );
    } catch (e) {
      logger.e('Load savings goals error: $e');
      state = state.copyWith(
        status: WalletStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Make contribution - returns Map with transaction and message
  Future<Map<String, dynamic>> makeContribution({
    required double amount,
    String? description,
  }) async {
    state = state.copyWith(status: WalletStatus.loading);
    try {
      final result = await _walletRepository.makeContribution(amount, description: description);

      // Note: We don't reload wallet immediately since deposit is pending verification
      // The wallet will be updated after admin verification
      // Instead, add the pending transaction to the list

      if (result['transaction'] != null && result['transaction'] is Map<String, dynamic>) {
        try {
          final pendingTxn = Transaction.fromJson(result['transaction'] as Map<String, dynamic>);
          state = state.copyWith(
            status: WalletStatus.loaded,
            transactions: [pendingTxn, ...state.transactions],
          );
        } catch (txnError) {
          logger.w('Failed to parse pending transaction: $txnError');
          state = state.copyWith(status: WalletStatus.loaded);
        }
      } else {
        state = state.copyWith(status: WalletStatus.loaded);
      }

      return result;
    } catch (e) {
      logger.e('Make contribution error: $e');
      state = state.copyWith(
        status: WalletStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Make withdrawal
  Future<void> makeWithdrawal({
    required double amount,
    String? description,
  }) async {
    state = state.copyWith(status: WalletStatus.loading);
    try {
      await _walletRepository.makeWithdrawal(amount, description: description);
      await loadWallet();
      state = state.copyWith(status: WalletStatus.loaded);
    } catch (e) {
      logger.e('Make withdrawal error: $e');
      state = state.copyWith(
        status: WalletStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Create a savings goal
  Future<bool> createSavingsGoal({
    required String goalName,
    required double targetAmount,
    required DateTime targetDate,
    String? description,
  }) async {
    state = state.copyWith(status: WalletStatus.loading);
    try {
      await _walletRepository.createSavingsGoal(
        name: goalName,
        targetAmount: targetAmount,
        targetDate: targetDate,
        description: description,
      );
      await loadSavingsGoals();
      state = state.copyWith(status: WalletStatus.loaded);
      return true;
    } catch (e) {
      logger.e('Create savings goal error: $e');
      state = state.copyWith(
        status: WalletStatus.error,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Wallet Provider
final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  final walletRepository = ref.watch(walletRepositoryProvider);
  return WalletNotifier(walletRepository);
});

/// Wallet balance provider
final walletBalanceProvider = Provider<double>((ref) {
  final walletState = ref.watch(walletProvider);
  return walletState.wallet?.balance ?? 0.0;
});

/// Total contributions provider
final totalContributionsProvider = Provider<double>((ref) {
  final walletState = ref.watch(walletProvider);
  return walletState.wallet?.totalContributions ?? 0.0;
});

/// Transactions provider
final transactionsProvider = Provider<List<Transaction>>((ref) {
  final walletState = ref.watch(walletProvider);
  return walletState.transactions;
});

/// Wallet error provider
final walletErrorProvider = Provider<String?>((ref) {
  final walletState = ref.watch(walletProvider);
  return walletState.error;
});
