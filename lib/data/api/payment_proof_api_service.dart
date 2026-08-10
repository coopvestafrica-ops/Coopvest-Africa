import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../models/payment_proof_model.dart';

/// API Service for Payment Proof Operations
/// Handles submission and tracking of proof of payment submissions
class PaymentProofApiService {
  final Dio _dio;

  PaymentProofApiService(this._dio);

  /// Submit a new payment proof
  Future<PaymentProof> submitPaymentProof({
    required PaymentProofType paymentType,
    required double amount,
    required DateTime paymentDate,
    PaymentMethod? paymentMethod,
    String? receivingBank,
    String? bankAccountName,
    String? bankAccountNumber,
    String? transactionReference,
    String? proofUrl,
    String? proofType,
    String? originalFilename,
    int? fileSize,
    String? memberNote,
  }) async {
    try {
      final response = await _dio.post(
        '/payment-proofs',
        data: {
          'payment_type': paymentType.apiValue,
          'amount': amount,
          'payment_date': paymentDate.toIso8601String().split('T')[0],
          if (paymentMethod != null) 'payment_method': paymentMethod.apiValue,
          if (receivingBank != null) 'receiving_bank': receivingBank,
          if (bankAccountName != null) 'bank_account_name': bankAccountName,
          if (bankAccountNumber != null) 'bank_account_number': bankAccountNumber,
          if (transactionReference != null) 'transaction_reference': transactionReference,
          if (proofUrl != null) 'proof_url': proofUrl,
          if (proofType != null) 'proof_type': proofType,
          if (originalFilename != null) 'original_filename': originalFilename,
          if (fileSize != null) 'file_size': fileSize,
          if (memberNote != null) 'member_note': memberNote,
        },
      );

      return PaymentProof.fromJson(response.data['payment_proof'] as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }

  /// Upload proof file and get URL
  Future<Map<String, dynamic>> uploadProofFile({
    required String filename,
    required String mimeType,
    required List<int> fileBytes,
  }) async {
    try {
      final base64Data = base64Encode(fileBytes);
      
      final response = await _dio.post(
        '/payment-proofs/upload',
        data: {
          'filename': filename,
          'mime_type': mimeType,
          'file_data': base64Data,
        },
      );

      return {
        'proof_url': response.data['proof_url'] as String,
        'filename': response.data['filename'] as String,
        'file_size': response.data['file_size'] as int,
        'proof_type': response.data['proof_type'] as String,
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Get all payment proofs for the current user
  Future<PaymentProofListResponse> getPaymentProofs({
    int page = 1,
    int limit = 20,
    PaymentProofStatus? status,
    PaymentProofType? paymentType,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };

      if (status != null) {
        queryParams['status'] = status.apiValue;
      }
      if (paymentType != null) {
        queryParams['payment_type'] = paymentType.apiValue;
      }

      final response = await _dio.get(
        '/payment-proofs',
        queryParameters: queryParams,
      );

      return PaymentProofListResponse.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  /// Get payment proof summary
  Future<PaymentProofSummary> getPaymentProofSummary() async {
    try {
      final response = await _dio.get('/payment-proofs/summary');
      return PaymentProofSummary.fromJson(response.data['summary'] as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }

  /// Get a specific payment proof by ID
  Future<PaymentProof> getPaymentProof(String id) async {
    try {
      final response = await _dio.get('/payment-proofs/$id');
      return PaymentProof.fromJson(response.data['payment_proof'] as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }

  /// Get digital receipt for an approved payment proof
  Future<DigitalReceipt> getReceipt(String paymentProofId) async {
    try {
      final response = await _dio.get('/payment-proofs/$paymentProofId/receipt');
      return DigitalReceipt.fromJson(response.data['receipt'] as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel/delete a pending payment proof
  Future<void> cancelPaymentProof(String id) async {
    try {
      await _dio.delete('/payment-proofs/$id');
    } catch (e) {
      rethrow;
    }
  }

  /// Get available Coopvest bank accounts for payment
  Future<List<BankAccount>> getAvailableBankAccounts() async {
    try {
      final response = await _dio.get('/payment-proofs/bank-accounts/available');
      return (response.data['bank_accounts'] as List)
          .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Return default bank accounts if API fails
      return [
        const BankAccount(
          bankName: 'First Bank of Nigeria',
          accountName: 'Coopvest Africa Savings',
          accountNumber: '3085749012',
          bankCode: '011',
        ),
        const BankAccount(
          bankName: 'Guaranty Trust Bank',
          accountName: 'Coopvest Africa Microfinance',
          accountNumber: '0145689231',
          bankCode: '058',
        ),
      ];
    }
  }
}
