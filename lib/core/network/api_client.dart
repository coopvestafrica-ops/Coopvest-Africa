import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/utils.dart';
import '../../config/app_config.dart';
import '../services/security_service.dart';
import '../../data/repositories/auth_repository.dart';

/// Secure token storage keys
const String _accessTokenKey = 'access_token';
const String _refreshTokenKey = 'refresh_token';

/// Secure storage instance for token persistence
final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

/// API Client Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

/// Session expired callback type
typedef SessionExpiredCallback = void Function();

/// API Client Implementation
class ApiClient {
  late final Dio _dio;
  bool _initialized = false;
  
  /// Static callback for session expiration (set from main.dart)
  static SessionExpiredCallback? _onSessionExpired;

  /// Set session expired callback
  static void setSessionExpiredCallback(SessionExpiredCallback callback) {
    _onSessionExpired = callback;
  }

  /// Trigger session expired
  static void triggerSessionExpired() {
    _onSessionExpired?.call();
  }

  ApiClient() {
    _initialize();
  }

  void _initialize() {
    if (_initialized) return;

    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Apply SSL Pinning
    SecurityService().applySSLPinning(_dio);

    // Auth interceptor first, then logging, then error handler
    _dio.interceptors.add(AuthInterceptor());
    _dio.interceptors.add(LoggingInterceptor());
    _dio.interceptors.add(ErrorInterceptor(this));

    _initialized = true;
  }

  Dio get dio => getDio();

  /// Get the Dio HTTP client instance
  Dio getDio() {
    _initialize();
    return _dio;
  }

  /// GET request
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// POST request
  Future<dynamic> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// PUT request
  Future<dynamic> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// PATCH request
  Future<dynamic> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// DELETE request
  Future<dynamic> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Retry with exponential backoff for transient failures
  Future<dynamic> retryRequest({
    required Future<dynamic> Function() request,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempts = 0;
    Duration delay = initialDelay;
    
    while (true) {
      try {
        return await request();
      } catch (e) {
        attempts++;
        
        // Don't retry for client errors (4xx) except 429 (rate limit)
        if (e is ServerException && e.statusCode != null && e.statusCode! < 500 && e.statusCode != 429) {
          rethrow;
        }
        
        // Don't retry for auth errors
        if (e is AuthException) {
          rethrow;
        }
        
        if (attempts >= maxRetries) {
          rethrow;
        }
        
        // Exponential backoff: 1s, 2s, 4s...
        await Future.delayed(delay);
        delay *= 2;
        
        logger.w('Retry attempt $attempts/$maxRetries after ${delay.inMilliseconds}ms');
      }
    }
  }

  /// GET with retry
  Future<dynamic> getWithRetry(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    int maxRetries = 3,
  }) async {
    return retryRequest(
      request: () => get(path, queryParameters: queryParameters, options: options),
      maxRetries: maxRetries,
    );
  }

  /// POST with retry
  Future<dynamic> postWithRetry(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    int maxRetries = 3,
  }) async {
    return retryRequest(
      request: () => post(path, data: data, queryParameters: queryParameters, options: options),
      maxRetries: maxRetries,
    );
  }

  /// Handle errors
  Exception _handleError(DioException error) {
    logger.e('API Error: ${error.message}', error: error, stackTrace: error.stackTrace);

    if (error.response != null) {
      final statusCode = error.response!.statusCode;
      final data = error.response!.data;

      // Safely coerce a dynamic value to String without throwing on Maps/Lists.
      String? safeStr(dynamic v) {
        if (v == null) return null;
        if (v is String) return v;
        return null; // Maps/Lists are not useful as error strings
      }

      String? errorMessage;
      if (data is Map<String, dynamic>) {
        // Check for single error field first
        errorMessage = safeStr(data['error']) ?? safeStr(data['message']) ?? safeStr(data['msg']);
        // If no single error, check for validation errors array
        if (errorMessage == null && data['errors'] != null) {
          final errors = data['errors'] as List?;
          if (errors != null && errors.isNotEmpty) {
            final firstError = errors.first as Map<String, dynamic>?;
            errorMessage = safeStr(firstError?['msg']) ?? safeStr(firstError?['message']);
          }
        }
      }

      switch (statusCode) {
        case 400:
          return ValidationException(errorMessage ?? 'Bad request');
        case 401:
          // Trigger session expired callback for proper navigation
          ApiClient.triggerSessionExpired();
          return AuthException(errorMessage ?? 'Session expired. Please login again.');
        case 403:
          return AuthException(errorMessage ?? 'Access forbidden');
        case 404:
          return ServerException(errorMessage ?? 'Resource not found', statusCode: statusCode);
        case 500:
          return ServerException(errorMessage ?? 'Server error. Please try again later.', statusCode: statusCode);
        default:
          return ServerException(errorMessage ?? 'An error occurred', statusCode: statusCode);
      }
    } else if (error.type == DioExceptionType.connectionTimeout) {
      return NetworkException('Connection timeout. Please check your internet.');
    } else if (error.type == DioExceptionType.receiveTimeout) {
      return NetworkException('Request timeout. Please try again.');
    } else if (error.type == DioExceptionType.connectionError) {
      return NetworkException(
          'Unable to connect to the server. Please check your internet connection.');
    } else if (error.type == DioExceptionType.unknown) {
      return NetworkException('Network error. Please check your connection.');
    }

    return NetworkException(error.message ?? 'An error occurred');
  }

  /// Set authorization token
  void setAuthToken(String token) {
    _initialize();
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear authorization token
  void clearAuthToken() {
    _initialize();
    _dio.options.headers.remove('Authorization');
  }

  /// Set custom headers
  void setHeaders(Map<String, String> headers) {
    _initialize();
    _dio.options.headers.addAll(headers);
  }

  /// Reset client state
  void reset() {
    _dio.close();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.add(AuthInterceptor());
    _dio.interceptors.add(LoggingInterceptor());
    _dio.interceptors.add(ErrorInterceptor(this));
  }

  dynamic getLoanApiService() => _dio;
  dynamic getRolloverApiService() => _dio;
  dynamic getReferralApiService() => _dio;
}

/// API Error Handling
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;

  ApiException({
    required this.message,
    this.statusCode,
    this.errorCode,
  });

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

/// Result wrapper for API responses
class ApiResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  ApiResult({
    this.data,
    this.error,
    required this.isSuccess,
  });

  factory ApiResult.success(T data) => ApiResult(data: data, isSuccess: true);
  factory ApiResult.error(String error) => ApiResult(error: error, isSuccess: false);

  bool get hasData => data != null;
  bool get hasError => error != null;
}

/// Extension for handling Dio errors
extension DioErrorExtension on DioException {
  ApiException toApiException() {
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return ApiException(message: 'Connection timed out. Please try again.', statusCode: 408);
      case DioExceptionType.sendTimeout:
        return ApiException(message: 'Send timed out. Please try again.', statusCode: 408);
      case DioExceptionType.receiveTimeout:
        return ApiException(message: 'Receive timed out. Please try again.', statusCode: 408);
      case DioExceptionType.badCertificate:
        return ApiException(message: 'Security certificate error.', statusCode: 495);
      case DioExceptionType.badResponse:
        return ApiException(
          message: (response?.data?['message'] is String ? response!.data['message'] as String : null) ?? 'Request failed',
          statusCode: response?.statusCode,
        );
      case DioExceptionType.cancel:
        return ApiException(message: 'Request cancelled', statusCode: -1);
      case DioExceptionType.connectionError:
        return ApiException(
          message: 'Unable to connect to the server. Please check your internet connection.',
          statusCode: -1,
        );
      case DioExceptionType.unknown:
        return ApiException(message: 'An unexpected error occurred. Please try again.');
    }
  }
}

/// Logging Interceptor
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (AppConfig.enableRequestLogging) {
      logger.i('API Request: ${options.method} ${options.path}');
      if (options.data != null) {
        logger.i('Request Data: ${options.data}');
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (AppConfig.enableResponseLogging) {
      logger.i('API Response: ${response.statusCode} ${response.requestOptions.path}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e('API Error: ${err.message}', error: err.response?.data, stackTrace: err.stackTrace);
    handler.next(err);
  }
}

/// Auth Interceptor — reads token from secure storage and attaches it
class AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await _secureStorage.read(key: _accessTokenKey);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      logger.e('AuthInterceptor: Failed to read token: $e');
    }
    handler.next(options);
  }
}

/// Error Interceptor — handles 401 responses via Supabase token refresh
class ErrorInterceptor extends Interceptor {
  final ApiClient _apiClient;
  bool _isRefreshing = false;

  ErrorInterceptor(this._apiClient);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final authRepo = AuthRepository(_apiClient);
        final response = await authRepo.refreshToken('');

        await TokenStorage.saveTokens(
          accessToken: response.accessToken,
          refreshToken: response.refreshToken,
        );
        _apiClient.setAuthToken(response.accessToken);

        final options = err.requestOptions;
        options.headers['Authorization'] = 'Bearer ${response.accessToken}';

        final retryResponse = await _apiClient.dio.fetch(options);
        _isRefreshing = false;
        return handler.resolve(retryResponse);
      } catch (e) {
        logger.e('Auto-refresh failed: $e');
        await TokenStorage.clearTokens();
        _apiClient.clearAuthToken();
      } finally {
        _isRefreshing = false;
      }
    }
    handler.next(err);
  }
}

/// Helper functions for token persistence
class TokenStorage {
  static Future<void> saveTokens(
      {required String accessToken, String? refreshToken}) async {
    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  static Future<String?> getAccessToken() async =>
      _secureStorage.read(key: _accessTokenKey);

  static Future<String?> getRefreshToken() async =>
      _secureStorage.read(key: _refreshTokenKey);

  static Future<void> clearTokens() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
  }

  static Future<bool> hasToken() async {
    final token = await _secureStorage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }
}
