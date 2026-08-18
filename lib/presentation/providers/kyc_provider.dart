import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/utils.dart';
import '../../data/models/kyc_models.dart';
import '../../data/repositories/kyc_repository.dart';

/// KYC Provider
final kycProvider = StateNotifierProvider<KYCCubit, KYCState>((ref) {
  final kycRepository = ref.watch(kycRepositoryProvider);
  return KYCCubit(kycRepository);
});

/// KYC Cubit
class KYCCubit extends StateNotifier<KYCState> {
  final KYCRepository _repository;

  KYCCubit(this._repository) : super(const KYCState());

  /// Initialize KYC.
  ///
  /// Fetches the member's KYC status first and resolves the AuthGuard gate on
  /// that alone. The organizations list is loaded best-effort afterwards in a
  /// separate try/catch: the /organizations endpoint is optional (it is not a
  /// registered backend feature flag and can return 404 "Feature not found"),
  /// and its failure must never flip the KYC state to [KYCStatus.error] —
  /// previously a single try/catch bundled both calls, so a 404 on
  /// /organizations dead-ended the member on "Could not verify your KYC
  /// status" even though /kyc/status had succeeded.
  Future<void> initializeKYC() async {
    state = state.copyWith(status: KYCStatus.loading);

    KYCSubmission? submission;
    try {
      submission = await _repository.getKYCStatus();
    } catch (e) {
      logger.e('Get KYC status error: $e');
      state = state.copyWith(
        status: KYCStatus.error,
        error: e.toString(),
      );
      return;
    }

    // Best-effort: refresh the organizations list without letting its failure
    // affect the KYC submission status that AuthGuard gates on.
    List<Organization> organizations = const [];
    try {
      organizations = await _repository.getOrganizations();
    } catch (e) {
      logger.w('Get organizations failed (non-blocking): $e');
    }

    state = state.copyWith(
      status: KYCStatus.loaded,
      submission: submission,
      organizations: organizations,
    );
  }

  /// Update personal details
  void updatePersonalDetails({
    String? dateOfBirth,
    String? gender,
  }) {
    final current = state.submission;
    if (current == null) return;
    
    state = state.copyWith(
      submission: current.copyWith(
        dateOfBirth: dateOfBirth,
        gender: gender,
      ),
    );
  }

  /// Update employment details
  void updateEmploymentDetails({
    String? employmentType,
    String? organizationId,
    String? organizationName,
    String? jobTitle,
    String? monthlyIncomeRange,
    String? occupation,
    String? employerName,
    String? workAddress,
    String? yearsOfEmployment,
  }) {
    final current = state.submission;
    if (current == null) return;

    state = state.copyWith(
      submission: current.copyWith(
        employmentType: employmentType ?? current.employmentType,
        organizationId: organizationId,
        organizationName: organizationName,
        jobTitle: jobTitle ?? current.jobTitle,
        monthlyIncomeRange: monthlyIncomeRange ?? current.monthlyIncomeRange,
        occupation: occupation ?? current.occupation,
        employerName: employerName ?? current.employerName,
        workAddress: workAddress ?? current.workAddress,
        yearsOfEmployment: yearsOfEmployment ?? current.yearsOfEmployment,
      ),
    );
  }

  /// Update address
  void updateAddress({
    String? residentialAddress,
    String? city,
    String? stateValue,
    String? country,
    String? lga,
  }) {
    final current = state.submission;
    if (current == null) return;

    state = state.copyWith(
      submission: current.copyWith(
        residentialAddress: residentialAddress ?? current.residentialAddress,
        city: city,
        state: stateValue,
        country: country,
        lga: lga ?? current.lga,
      ),
    );
  }

  /// Update ID details
  void updateIDDetails({
    String? idType,
    String? idNumber,
    String? idPhotoPath,
    String? staffId,
  }) {
    final current = state.submission;
    if (current == null) return;

    state = state.copyWith(
      submission: current.copyWith(
        idType: idType ?? current.idType,
        idNumber: idNumber,
        idPhotoPath: idPhotoPath,
        staffId: staffId ?? current.staffId,
      ),
    );
  }

  /// Update next of kin details
  void updateNextOfKin({
    String? nokName,
    String? nokRelationship,
    String? nokPhone,
    String? nokAddress,
  }) {
    final current = state.submission;
    if (current == null) return;

    state = state.copyWith(
      submission: current.copyWith(
        nokName: nokName ?? current.nokName,
        nokRelationship: nokRelationship ?? current.nokRelationship,
        nokPhone: nokPhone ?? current.nokPhone,
        nokAddress: nokAddress ?? current.nokAddress,
      ),
    );
  }

  /// Update selfie
  void updateSelfie(String selfiePath) {
    final current = state.submission;
    if (current == null) return;
    
    state = state.copyWith(
      submission: current.copyWith(selfiePhotoPath: selfiePath),
    );
  }
  
  /// Update bank details
  void updateBankDetails({
    String? bankName,
    String? bankCode,
    String? accountNumber,
    String? accountName,
    String? accountType,
    String? bvn,
  }) {
    final current = state.submission;
    if (current == null) return;
    
    state = state.copyWith(
      submission: current.copyWith(
        bankName: bankName ?? current.bankName,
        bankCode: bankCode ?? current.bankCode,
        accountNumber: accountNumber,
        accountName: accountName,
        accountType: accountType ?? current.accountType,
        bvn: bvn,
      ),
    );
  }

  /// Search organizations
  Future<void> searchOrganizations(String query) async {
    try {
      final organizations = await _repository.getOrganizations(search: query);
      state = state.copyWith(organizations: organizations);
    } catch (e) {
      logger.e('Search organizations error: $e');
    }
  }

  /// Request organization approval
  Future<void> requestOrganizationApproval(String organizationName) async {
    try {
      await _repository.requestOrganizationApproval(organizationName);
    } catch (e) {
      logger.e('Request organization approval error: $e');
      rethrow;
    }
  }

  /// Upload ID document
  Future<void> uploadIDDocument(String filePath) async {
    try {
      final path = await _repository.uploadIDDocument(filePath);
      updateIDDetails(idPhotoPath: path);
    } catch (e) {
      logger.e('Upload ID document error: $e');
      rethrow;
    }
  }

  /// Upload selfie
  Future<void> uploadSelfie(String filePath) async {
    try {
      final path = await _repository.uploadSelfie(filePath);
      updateSelfie(path);
    } catch (e) {
      logger.e('Upload selfie error: $e');
      rethrow;
    }
  }

  /// Submit KYC
  Future<void> submitKYC() async {
    final submission = state.submission;
    if (submission == null) {
      state = state.copyWith(error: 'No submission data');
      return;
    }

    if (!submission.isComplete) {
      state = state.copyWith(
        error: 'Please complete all required fields',
      );
      return;
    }

    state = state.copyWith(status: KYCStatus.submitting);
    
    try {
      await _repository.submitKYC(submission);
      
      state = state.copyWith(
        status: KYCStatus.loaded,
        submission: submission.copyWith(
          status: 'submitted',
          submittedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      logger.e('Submit KYC error: $e');
      state = state.copyWith(
        status: KYCStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Navigate to next step
  void nextStep() {
    if (state.currentStep < state.totalSteps - 1) {
      state = state.copyWith(
        currentStep: state.currentStep + 1,
      );
    }
  }

  /// Navigate to previous step
  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(
        currentStep: state.currentStep - 1,
      );
    }
  }

  /// Go to specific step
  void goToStep(int step) {
    if (step >= 0 && step < state.totalSteps) {
      state = state.copyWith(currentStep: step);
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Reset KYC
  void resetKYC() {
    state = const KYCState();
  }
}

/// KYC Status Provider
final kycStatusProvider = Provider<KYCStatus>((ref) {
  final kycState = ref.watch(kycProvider);
  return kycState.status;
});

/// KYC Submission Provider
final kycSubmissionProvider = Provider<KYCSubmission?>((ref) {
  final kycState = ref.watch(kycProvider);
  return kycState.submission;
});

/// KYC Progress Provider
final kycProgressProvider = Provider<double>((ref) {
  final kycState = ref.watch(kycProvider);
  return kycState.progress;
});

/// Is KYC Complete Provider
final isKYCCompleteProvider = Provider<bool>((ref) {
  final kycState = ref.watch(kycProvider);
  return kycState.isComplete;
});

/// Whether the member has submitted their KYC (status submitted or verified).
/// Used to gate features (e.g. loan applications) and to decide whether the
/// "Complete KYC" prompt should be shown.
final isKycSubmittedProvider = Provider<bool>((ref) {
  final kycState = ref.watch(kycProvider);
  final status = kycState.submission?.status ?? 'pending';
  return status == 'submitted' ||
      status == 'verified' ||
      status == 'in_review' ||
      status == 'approved';
});

/// KYC Error Provider
final kycErrorProvider = Provider<String?>((ref) {
  final kycState = ref.watch(kycProvider);
  return kycState.error;
});
