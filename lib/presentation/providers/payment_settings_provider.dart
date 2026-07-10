import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/utils.dart';

class PaymentAccountDetails {
  final String bank;
  final String accountName;
  final String accountNumber;

  const PaymentAccountDetails({
    required this.bank,
    required this.accountName,
    required this.accountNumber,
  });

  PaymentAccountDetails copyWith({
    String? bank,
    String? accountName,
    String? accountNumber,
  }) {
    return PaymentAccountDetails(
      bank: bank ?? this.bank,
      accountName: accountName ?? this.accountName,
      accountNumber: accountNumber ?? this.accountNumber,
    );
  }

  factory PaymentAccountDetails.fromJson(Map<String, dynamic> json) {
    return PaymentAccountDetails(
      bank: json['bank'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
    );
  }
}

const _defaultPaymentAccount = PaymentAccountDetails(
  bank: 'Opay',
  accountName: 'Coopvest Africa',
  accountNumber: '',
);

class PaymentSettingsNotifier extends StateNotifier<PaymentAccountDetails> {
  final ApiClient _apiClient;

  PaymentSettingsNotifier(this._apiClient) : super(_defaultPaymentAccount);

  Future<void> loadFromApi() async {
    try {
      final resp = await _apiClient.get('/wallet/payment-settings');
      if (resp is Map<String, dynamic> && resp['success'] == true) {
        // Backend returns the settings directly in the response
        // Handle both direct field access and nested value field
        Map<String, dynamic> settingsData;
        
        // Check if settings are nested under 'value' field (common in Supabase)
        if (resp['value'] is Map<String, dynamic>) {
          settingsData = resp['value'] as Map<String, dynamic>;
        } else {
          // Settings are at the root level of the response
          settingsData = resp;
        }
        
        state = PaymentAccountDetails.fromJson(settingsData);
      }
    } catch (e) {
      logger.w('PaymentSettings: API unavailable, using defaults: $e');
    }
  }

  void update({String? bank, String? accountName, String? accountNumber}) {
    state = state.copyWith(
      bank: bank,
      accountName: accountName,
      accountNumber: accountNumber,
    );
  }
}

final paymentSettingsProvider =
    StateNotifierProvider<PaymentSettingsNotifier, PaymentAccountDetails>(
  (ref) {
    final apiClient = ref.watch(apiClientProvider);
    return PaymentSettingsNotifier(apiClient);
  },
);
