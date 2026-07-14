import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/utils.dart';
import '../../data/models/wallet_models.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class DepositHistoryState {
  final List<DepositRequest> requests;
  final bool isLoading;
  final String? error;

  const DepositHistoryState({
    this.requests = const [],
    this.isLoading = false,
    this.error,
  });

  DepositHistoryState copyWith({
    List<DepositRequest>? requests,
    bool? isLoading,
    String? error,
  }) {
    return DepositHistoryState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  int get pendingCount   => requests.where((r) => r.isPending).length;
  int get verifiedCount  => requests.where((r) => r.isVerified).length;
  int get rejectedCount  => requests.where((r) => r.isRejected).length;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DepositHistoryNotifier extends StateNotifier<DepositHistoryState> {
  final ApiClient _apiClient;

  DepositHistoryNotifier(this._apiClient) : super(const DepositHistoryState());

  Future<void> load({int page = 1, int limit = 50}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _apiClient.get(
        '/wallet/deposit-requests',
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = response as Map<String, dynamic>;
      final list = (data['deposit_requests'] as List? ?? [])
          .map((e) => DepositRequest.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(requests: list, isLoading: false);
    } catch (e) {
      logger.e('DepositHistoryNotifier.load error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Optimistically update a single request's status (called after realtime event)
  void updateStatus(String id, String newStatus, {String? adminNotes}) {
    final updated = state.requests.map((r) {
      if (r.id != id) return r;
      return DepositRequest(
        id: r.id,
        profileId: r.profileId,
        amount: r.amount,
        currency: r.currency,
        status: newStatus,
        paymentMethod: r.paymentMethod,
        paymentProofUrl: r.paymentProofUrl,
        paymentReference: r.paymentReference,
        paymentDate: r.paymentDate,
        bankName: r.bankName,
        senderAccountName: r.senderAccountName,
        senderAccountNumber: r.senderAccountNumber,
        adminNotes: adminNotes ?? r.adminNotes,
        verifiedBy: r.verifiedBy,
        verifiedAt: newStatus == 'verified' || newStatus == 'rejected'
            ? DateTime.now()
            : r.verifiedAt,
        createdAt: r.createdAt,
        updatedAt: DateTime.now(),
      );
    }).toList();
    state = state.copyWith(requests: updated);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final depositHistoryProvider =
    StateNotifierProvider<DepositHistoryNotifier, DepositHistoryState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return DepositHistoryNotifier(apiClient);
});

/// Convenience: count of pending deposit requests
final pendingDepositCountProvider = Provider<int>((ref) {
  return ref.watch(depositHistoryProvider).pendingCount;
});
