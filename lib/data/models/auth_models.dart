import 'package:equatable/equatable.dart';

/// User Model
class User extends Equatable {
  final String id;
  final String email;
  final String? phone;
  final String name;
  final String? dateOfBirth;
  final String? gender;
  final String? occupation;
  final String kycStatus; // pending, approved, rejected
  final String membershipStatus; // active, pending_termination, suspended, terminated, inactive
  final String? idType;
  final String? idNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? profilePicture; // URL to user's profile picture
  final String? referralCode;
  final bool isEmailVerified;
  final bool registrationCompleted; // true if user completed registration flow
  final DateTime createdAt;
  final DateTime? updatedAt;

  const User({
    required this.id,
    required this.email,
    this.phone,
    required this.name,
    this.dateOfBirth,
    this.gender,
    this.occupation,
    required this.kycStatus,
    this.membershipStatus = 'active',
    this.idType,
    this.idNumber,
    this.address,
    this.city,
    this.state,
    this.country,
    this.profilePicture,
    this.referralCode,
    this.isEmailVerified = false,
    this.registrationCompleted = false,
    required this.createdAt,
    this.updatedAt,
  });

  /// Check if user can request termination
  bool get canRequestTermination {
    return membershipStatus == 'active' ||
           membershipStatus == 'suspended' ||
           membershipStatus == 'inactive';
  }

  /// Check if user is terminated
  bool get isTerminated {
    return membershipStatus == 'terminated';
  }

  /// Check if termination is pending approval
  bool get isTerminationPending {
    return membershipStatus == 'pending_termination';
  }

  /// Get membership duration in months
  int get membershipDurationMonths {
    final now = DateTime.now();
    return ((now.difference(createdAt).inDays) / 30).floor();
  }

  /// Check if member is eligible for loan based on membership duration
  bool isEligibleForLoan(int requiredMonths) {
    return membershipDurationMonths >= requiredMonths;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['userId'] as String? ?? json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      name: json['name'] as String? ?? '',
      dateOfBirth: json['date_of_birth'] as String?,
      gender: json['gender'] as String?,
      occupation: json['occupation'] as String?,
      kycStatus: json['kycVerified'] == true ? 'approved' : (json['kyc_status'] as String? ?? 'pending'),
      membershipStatus: json['membershipStatus'] as String? ?? json['membership_status'] as String? ?? 'active',
      idType: json['id_type'] as String?,
      idNumber: json['id_number'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      profilePicture: json['profile_picture'] as String? ?? json['profilePicture'] as String?,
      referralCode: json['referral_code'] as String? ?? json['referralCode'] as String?,
      isEmailVerified: json['isEmailVerified'] as bool? ?? json['is_email_verified'] as bool? ?? json['emailVerified'] as bool? ?? false,
      registrationCompleted: json['registration_completed'] as bool? ?? json['registrationCompleted'] as bool? ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : (json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now()),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : (json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'phone': phone,
      'name': name,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'occupation': occupation,
      'kyc_status': kycStatus,
      'id_type': idType,
      'id_number': idNumber,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'is_email_verified': isEmailVerified,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? phone,
    String? name,
    String? dateOfBirth,
    String? gender,
    String? occupation,
    String? kycStatus,
    String? membershipStatus,
    String? idType,
    String? idNumber,
    String? address,
    String? city,
    String? state,
    String? country,
    String? profilePicture,
    bool? isEmailVerified,
    bool? registrationCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      kycStatus: kycStatus ?? this.kycStatus,
      membershipStatus: membershipStatus ?? this.membershipStatus,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      profilePicture: profilePicture ?? this.profilePicture,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      registrationCompleted: registrationCompleted ?? this.registrationCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    email,
    phone,
    name,
    dateOfBirth,
    gender,
    occupation,
    kycStatus,
    idType,
    idNumber,
    address,
    city,
    state,
    country,
    isEmailVerified,
    createdAt,
    updatedAt,
  ];
}

/// Auth Response Model
class AuthResponse extends Equatable {
  final String accessToken;
  final String refreshToken;
  final User user;
  final DateTime expiresAt;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.expiresAt,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['token'] as String? ?? json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : DateTime.now().add(const Duration(days: 7)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'user': user.toJson(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, user, expiresAt];
}

/// Login Request Model
class LoginRequest extends Equatable {
  final String email;
  final String password;
  final String? deviceId;

  const LoginRequest({
    required this.email,
    required this.password,
    this.deviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'device_id': deviceId,
    };
  }

  @override
  List<Object?> get props => [email, password, deviceId];
}

/// Register Request Model
class RegisterRequest extends Equatable {
  final String email;
  final String password;
  final String name;
  final String? phone;
  final String? deviceId;

  const RegisterRequest({
    required this.email,
    required this.password,
    required this.name,
    this.phone,
    this.deviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'name': name,
      'phone': phone,
      'device_id': deviceId,
    };
  }

  @override
  List<Object?> get props => [email, password, name, phone, deviceId];
}

/// KYC Submission Model
/// NOTE: The comprehensive KYCSubmission model is now defined in kyc_models.dart
/// and includes all fields: employment details, bank info, ID documents, selfie, etc.
/// Use `import '../models/kyc_models.dart'` for the full KYC submission model.

/// Auth State
enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  kycPending,
  kycRejected,
  error,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final User? user;
  final String? error;
  final String? accessToken;
  final String? refreshToken;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.accessToken,
    this.refreshToken,
  });

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;
  bool get isKycPending => status == AuthStatus.kycPending;
  bool get isKycRejected => status == AuthStatus.kycRejected;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? error,
    String? accessToken,
    String? refreshToken,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  @override
  List<Object?> get props => [status, user, error, accessToken, refreshToken];
}
