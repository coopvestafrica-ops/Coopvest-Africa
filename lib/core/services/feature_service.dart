import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Feature flags service for Flutter mobile app
/// Connects to admin backend to get feature configurations
class FeatureService {
  static final FeatureService _instance = FeatureService._internal();
  factory FeatureService() => _instance;
  FeatureService._internal();

  final String _baseUrl = 'https://coopvest-api.onrender.com/api';
  static const String _cacheKey = 'feature_flags_cache';
  // Short cache so admin toggles are reflected quickly. Previously 1 hour,
  // which meant a toggle made in the admin dashboard could take up to an
  // hour to affect the mobile app even after a refresh.
  static const Duration _cacheDuration = Duration(minutes: 2);
  
  final Map<String, FeatureFlag> _features = {};
  Timer? _refreshTimer;
  bool _isInitialized = false;

  // Feature flag definitions. Keys mirror the `id` values seeded by the
  // backend migration (backend/migrations/011_mobile_features.sql) and
  // returned as `name` by GET /api/features/platform/mobile, so toggles made
  // in the admin dashboard resolve to the same flag here.
  static const Map<String, String> featureNames = {
    'loan_requests': 'Loan Requests',
    'guarantor_system': 'Guarantor System',
    'qr_verification': 'QR Code Verification',
    'two_factor_auth': 'Two Factor Authentication',
    'advanced_analytics': 'Advanced Analytics',
    'push_notifications': 'Push Notifications',
    'email_notifications': 'Email Notifications',
    'referral_program': 'Referral Program',
    'investment_pool': 'Investment Pool',
    'offline_mode': 'Offline Mode',
    'biometric_login': 'Biometric Login',
    'salary_deduction': 'Salary Deduction',
    'rollover_requests': 'Rollover Requests',
    'direct_contribution': 'Direct Contribution',
    'wallet_transfers': 'Wallet Transfers',
    'withdrawals': 'Withdrawals',
    'kyc_verification': 'KYC Verification',
    'registration': 'Registration',
    'risk_scoring': 'Risk Scoring',
    'compliance_tools': 'Compliance Tools',
  };

  /// Initialize the feature service
  Future<void> init() async {
    if (_isInitialized) return;
    
    await _loadFromCache();
    await _fetchFeatures();
    _startAutoRefresh();
    _isInitialized = true;
  }

  /// Start auto-refresh timer
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      // Refresh frequently so admin-side toggles propagate to the app without
      // waiting for a full app restart.
      const Duration(minutes: 2),
      (_) => _fetchFeatures(),
    );
  }

  /// Stop auto-refresh
  void dispose() {
    _refreshTimer?.cancel();
  }

  /// Force a fresh fetch from the backend, bypassing the cache. Called on app
  /// resume so toggles made while the app was backgrounded take effect
  /// immediately. Safe to call repeatedly; never throws.
  Future<void> refreshOnResume() async {
    // Ignore the in-memory cache but keep using the last-known flags until the
    // fetch completes so the UI doesn't flicker to "disabled".
    await _fetchFeatures();
  }

  /// Load features from local cache
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_cacheKey);
      
      if (cacheData != null) {
        final Map<String, dynamic> cache = jsonDecode(cacheData);
        final timestamp = DateTime.tryParse(cache['timestamp'] ?? '');
        
        if (timestamp != null && 
            DateTime.now().difference(timestamp) < _cacheDuration) {
          final features = cache['features'] as Map<String, dynamic>;
          for (final entry in features.entries) {
            _features[entry.key] = FeatureFlag.fromJson(entry.value);
          }
        }
      }
    } catch (e) {
      // Cache load failed, continue with empty features
    }
  }

  /// Save features to local cache
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = {
        'timestamp': DateTime.now().toIso8601String(),
        'features': _features.map((k, v) => MapEntry(k, v.toJson())),
      };
      await prefs.setString(_cacheKey, jsonEncode(cache));
    } catch (e) {
      // Cache save failed
    }
  }

  /// Fetch features from backend
  Future<void> _fetchFeatures() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/features/platform/mobile'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10)); // Add 10 second timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final features = data['data'] as List;
          for (final feature in features) {
            final flag = FeatureFlag.fromJson(feature);
            _features[flag.name] = flag;
          }
          await _saveToCache();
        }
      }
    } catch (e) {
      // Network error or timeout, keep cached values or default to empty
      // App should still work even if feature service fails
    }
  }

  /// Check if a feature is enabled.
  ///
  /// Unknown features default to **enabled** (fail-open) so a transient
  /// backend failure never locks members out of core flows. The admin
  /// dashboard explicitly seeds the flags it wants disabled, so a missing
  /// flag almost always means "not fetched yet", not "intentionally off".
  bool isEnabled(String featureName) {
    final flag = _features[featureName];
    return flag?.enabled ?? true;
  }

  /// Get feature flag details
  FeatureFlag? getFeature(String featureName) => _features[featureName];

  /// Get all enabled features
  List<FeatureFlag> getEnabledFeatures() {
    final priorityOrder = {'high': 0, 'medium': 1, 'low': 2};
    return _features.values.where((f) => f.enabled).toList()
      ..sort((a, b) => (priorityOrder[a.priority] ?? 2).compareTo(priorityOrder[b.priority] ?? 2));
  }

  /// Get feature by category
  List<FeatureFlag> getFeaturesByCategory(String category) {
    return _features.values
        .where((f) => f.category == category)
        .toList();
  }

  /// Get all unique categories
  List<String> getAllCategories() {
    return _features.values.map((f) => f.category).toSet().toList();
  }

  /// Manually refresh features
  Future<void> refresh() async => _fetchFeatures();

  /// Get all features as a map
  Map<String, FeatureFlag> getAllFeatures() => Map.from(_features);
}

/// Feature flag model
class FeatureFlag {
  final String name;
  final String displayName;
  final String description;
  final String category;
  final List<String> platforms;
  final bool enabled;
  final int rolloutPercentage;
  final String targetAudience;
  final List<String> targetRegions;
  final String priority;
  final String status;
  final Map<String, dynamic> config;
  final DateTime? startDate;
  final DateTime? endDate;

  FeatureFlag({
    required this.name,
    required this.displayName,
    required this.description,
    required this.category,
    required this.platforms,
    required this.enabled,
    required this.rolloutPercentage,
    required this.targetAudience,
    required this.targetRegions,
    required this.priority,
    required this.status,
    required this.config,
    this.startDate,
    this.endDate,
  });

  factory FeatureFlag.fromJson(Map<String, dynamic> json) {
    return FeatureFlag(
      name: json['name'] ?? '',
      displayName: json['displayName'] ?? json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? 'other',
      platforms: List<String>.from(json['platforms'] ?? []),
      enabled: json['enabled'] ?? false,
      rolloutPercentage: json['rolloutPercentage'] ?? 0,
      targetAudience: json['targetAudience'] ?? 'all',
      targetRegions: List<String>.from(json['targetRegions'] ?? []),
      priority: json['priority'] ?? 'medium',
      status: json['status'] ?? 'planning',
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      startDate: json['startDate'] != null 
          ? DateTime.tryParse(json['startDate']) 
          : null,
      endDate: json['endDate'] != null 
          ? DateTime.tryParse(json['endDate']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'description': description,
    'category': category,
    'platforms': platforms,
    'enabled': enabled,
    'rolloutPercentage': rolloutPercentage,
    'targetAudience': targetAudience,
    'targetRegions': targetRegions,
    'priority': priority,
    'status': status,
    'config': config,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
  };

  /// Check if feature is currently active based on dates
  bool get isActive {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return status == 'active';
  }
}

/// Extension methods for common feature checks
extension FeatureExtensions on FeatureService {
  bool get loansEnabled => isEnabled('loan_requests');
  bool get guarantorEnabled => isEnabled('guarantor_system');
  bool get qrEnabled => isEnabled('qr_verification');
  bool get biometricEnabled => isEnabled('biometric_login');
  bool get referralEnabled => isEnabled('referral_program');
  bool get investmentEnabled => isEnabled('investment_pool');
  bool get offlineEnabled => isEnabled('offline_mode');
  bool get rolloverEnabled => isEnabled('rollover_requests');
  bool get pushEnabled => isEnabled('push_notifications');
  bool get emailEnabled => isEnabled('email_notifications');
  bool get withdrawalsEnabled => isEnabled('withdrawals');
  bool get directContributionEnabled => isEnabled('direct_contribution');
  bool get walletTransfersEnabled => isEnabled('wallet_transfers');
  bool get registrationEnabled => isEnabled('registration');
}
