import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/utils.dart';
import '../../models/contributions/monthly_contribution.dart';

/// API Service for Contribution Operations
/// Handles all monthly contributions related API calls
class ContributionApiService {
  final Dio _dio;

  ContributionApiService(this._dio);

  /// Get contributions list with pagination and filters
  Future<ContributionsListResponse> getContributions({
    int page = 1,
    int pageSize = 20,
    ContributionFilter? filter,
  }) async {
    try {
      final queryParams = {
        'page': page,
        'page_size': pageSize,
        ...?filter?.toQueryParameters(),
      };

      final response = await _dio.get(
        '/contributions',
        queryParameters: queryParams,
      );

      return ContributionsListResponse.fromJson(response.data);
    } catch (e) {
      logger.e('getContributions failed — surfacing error instead of mock data: $e');
      rethrow;
    }
  }

  /// Get contribution details by ID
  Future<ContributionDetail> getContributionDetail(String contributionId) async {
    try {
      final response = await _dio.get('/contributions/$contributionId');
      return ContributionDetail.fromJson(response.data);
    } catch (e) {
      logger.e('getContributionDetail failed — surfacing error instead of mock data: $e');
      rethrow;
    }
  }

  /// Get contribution summary
  Future<ContributionSummary> getContributionSummary() async {
    try {
      final response = await _dio.get('/contributions/summary');
      return ContributionSummary.fromJson(response.data);
    } catch (e) {
      logger.e('getContributionSummary failed — surfacing error instead of mock data: $e');
      rethrow;
    }
  }

  /// Get contribution receipt
  Future<String> getContributionReceipt(String contributionId) async {
    try {
      final response = await _dio.get('/contributions/$contributionId/receipt');
      return response.data['receipt_url'] as String? ?? '';
    } catch (e) {
      rethrow;
    }
  }

}

/// Response model for contributions list
class ContributionsListResponse {
  final bool success;
  final List<MonthlyContribution> contributions;
  final int totalCount;
  final int page;
  final int pageSize;

  ContributionsListResponse({
    required this.success,
    required this.contributions,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  factory ContributionsListResponse.fromJson(Map<String, dynamic> json) {
    return ContributionsListResponse(
      success: json['success'] as bool,
      contributions: (json['data'] as List? ?? [])
          .map((e) => MonthlyContribution.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: json['total_count'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }

  bool get hasMore => page * pageSize < totalCount;
}
