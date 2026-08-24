/**
 * Member Detail Admin API Routes
 * 
 * Comprehensive endpoints for viewing complete member profiles in the Admin Dashboard.
 * Returns all member information including:
 * - Personal Information
 * - Identity Verification
 * - Bank Information
 * - Next of Kin
 * - Employment Information
 * - Contribution/Savings Information
 * - Loan Information
 * - Guarantor Information
 * - Documents
 * - Audit Information
 */

const express = require('express');
const { param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate, requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

// Use authenticate middleware to verify Supabase JWT
router.use(authenticate);

function paging(req) {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 20));
  return { page, limit, from: (page - 1) * limit, to: page * limit - 1 };
}

/**
 * GET /api/v1/admin/members/:profileId/profile
 * Get complete member profile with all details
 */
router.get('/:profileId/profile', async (req, res) => {
  try {
    const { profileId } = req.params;

    // Get base profile
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', profileId)
      .maybeSingle();
    if (profileError) throw profileError;
    if (!profile) return res.status(404).json({ success: false, error: 'Member not found' });

    // Fetch all related data in parallel
    const [
      wallet,
      savings,
      kyc,
      kycDocuments,
      memberDocuments,
      bankAccounts,
      nextOfKin,
      loans,
      loanGuarantors,
      contributions,
      transactions,
      referrals,
      auditLogs,
      adminNotes,
      activityTimeline,
      tickets,
    ] = await Promise.all([
      // Wallet
      supabase.from('wallets').select('*').eq('profile_id', profileId).maybeSingle(),
      // Savings/Contributions
      supabase.from('savings').select('*').eq('profile_id', profileId).maybeSingle(),
      // KYC
      supabase.from('kyc').select('*').eq('profile_id', profileId).maybeSingle(),
      // KYC Documents
      supabase.from('kyc_documents').select('*').eq('profile_id', profileId).order('created_at', { ascending: false }),
      // Member Documents
      supabase.from('member_documents').select('*').eq('profile_id', profileId).order('uploaded_at', { ascending: false }),
      // Bank Accounts
      supabase.from('bank_accounts').select('*').eq('profile_id', profileId),
      // Next of Kin
      supabase.from('next_of_kin').select('*').eq('profile_id', profileId).maybeSingle(),
      // Loans
      supabase.from('loans').select('*').eq('profile_id', profileId).order('created_at', { ascending: false }),
      // Loan Guarantors (as guarantor)
      supabase.from('loan_guarantors').select('*, loan:loans(id, status, profile_id)').eq('guarantor_id', profileId).order('created_at', { ascending: false }),
      // Recent Transactions (contributions)
      supabase.from('transactions')
        .select('*')
        .eq('profile_id', profileId)
        .in('type', ['savings', 'contribution', 'deposit'])
        .order('created_at', { ascending: false })
        .limit(20),
      // All Transactions
      supabase.from('transactions').select('id, type, amount, status, created_at').eq('profile_id', profileId).order('created_at', { ascending: false }).limit(100),
      // Referrals
      supabase.from('referrals').select('*').eq('profile_id', profileId).maybeSingle(),
      // Recent Audit Logs
      supabase.from('audit_logs')
        .select('*')
        .eq('target_profile_id', profileId)
        .order('created_at', { ascending: false })
        .limit(50),
      // Admin Notes
      supabase.from('admin_notes')
        .select('*, admin:profiles!admin_id(id, name, email)')
        .eq('profile_id', profileId)
        .order('created_at', { ascending: false }),
      // Activity Timeline
      supabase.from('member_activity_timeline')
        .select('*')
        .eq('profile_id', profileId)
        .order('created_at', { ascending: false })
        .limit(100),
      // Support Tickets
      supabase.from('tickets')
        .select('*')
        .eq('profile_id', profileId)
        .order('created_at', { ascending: false }),
    ]);

    // Process loan data to get statistics
    const loanData = loans.data || [];
    const activeLoans = loanData.filter(l => ['active', 'approved', 'disbursed'].includes(l.status));
    const problemLoans = loanData.filter(l => ['overdue', 'defaulted', 'in_recovery'].includes(l.status));
    const completedLoans = loanData.filter(l => l.status === 'completed');
    const rejectedLoans = loanData.filter(l => l.status === 'rejected');
    
    // Calculate total outstanding balance
    const totalOutstandingBalance = activeLoans.reduce((sum, loan) => {
      return sum + parseFloat(loan.outstanding_amount || loan.amount || 0);
    }, 0);

    // Process guarantor data
    const guarantorData = loanGuarantors.data || [];
    const pendingGuarantees = guarantorData.filter(g => g.request_status === 'pending');
    const approvedGuarantees = guarantorData.filter(g => g.request_status === 'approved');
    const rejectedGuarantees = guarantorData.filter(g => g.request_status === 'rejected');

    // Calculate missed contributions (simplified - based on consecutive months)
    const savingsData = savings.data;
    const missedContributions = Math.max(0, (savingsData?.consecutive_months === 0 ? 1 : 0));

    // Get contribution history from transactions
    const contributionHistory = (contributions.data || []).map(t => ({
      id: t.id,
      amount: t.amount,
      date: t.created_at,
      status: t.status,
      type: t.type,
    }));

    // Build comprehensive response
    const memberProfile = {
      // Personal Information
      personalInfo: {
        fullName: profile.name,
        memberId: profile.member_id,
        profilePhoto: profile.profile_photo_url,
        gender: profile.gender,
        dateOfBirth: profile.date_of_birth,
        maritalStatus: profile.marital_status,
        nationality: profile.nationality,
        residentialAddress: profile.residential_address,
        state: profile.state,
        lga: profile.lga,
        city: profile.city,
        occupation: profile.occupation,
        employerName: profile.employer_name,
        employmentStatus: profile.employment_status,
        monthlyIncome: profile.monthly_income,
        phoneNumber: profile.phone,
        emailAddress: profile.email,
        registrationDate: profile.created_at,
        accountStatus: deriveAccountStatus(profile),
        kycVerificationStatus: profile.kyc_verified ? 'Verified' : 'Pending',
        selfieUrl: profile.selfie_url,
      },

      // Identity Verification
      identityVerification: {
        meansOfIdentification: kyc.data?.id_type || null,
        idType: kyc.data?.id_type || null,
        idNumber: kyc.data?.id_number || null,
        dateOfIssue: kyc.data?.id_issue_date || null,
        expiryDate: kyc.data?.id_expiry_date || null,
        uploadedFrontImage: kyc.data?.id_front_image_url || null,
        uploadedBackImage: kyc.data?.id_back_image_url || null,
        selfieVerificationImage: kyc.data?.selfie_url || null,
        passportPhoto: kyc.data?.passport_photo_url || null,
        signature: kyc.data?.signature_url || null,
        kycStatus: kyc.data?.status || 'pending',
        kycVerified: kyc.data?.verified || false,
        bvn: kyc.data?.bvn ? '********' + kyc.data?.bvn.slice(-4) : null,
        nin: kyc.data?.nin ? '********' + kyc.data?.nin.slice(-4) : null,
      },

      // Bank Information
      bankInfo: {
        accounts: (bankAccounts.data || []).map(acc => ({
          bankName: acc.bank_name,
          accountName: acc.account_name,
          accountNumber: maskAccountNumber(acc.account_number),
          bankVerificationStatus: acc.bank_verification_status,
          isPrimary: acc.is_primary,
        })),
      },

      // Next of Kin
      nextOfKin: nextOfKin.data ? {
        fullName: nextOfKin.data.full_name,
        relationship: nextOfKin.data.relationship,
        phone: nextOfKin.data.phone,
        email: nextOfKin.data.email,
        residentialAddress: nextOfKin.data.residential_address,
      } : null,

      // Employment Information
      employmentInfo: {
        employerName: profile.employer_name,
        employerAddress: profile.employer_address || null,
        staffId: profile.staff_id || null,
        employmentType: profile.employment_status,
        salaryPaymentFrequency: profile.salary_frequency || null,
        payrollDeductionConsentStatus: profile.payroll_consent || 'pending',
        occupation: profile.occupation,
        monthlyIncome: profile.monthly_income,
      },

      // Contribution Information
      contributionInfo: {
        totalSavings: savingsData?.total_saved || 0,
        monthlyContributionAmount: savingsData?.monthly_savings || 0,
        firstSavingsDate: savingsData?.first_savings_date || null,
        consecutiveMonths: savingsData?.consecutive_months || 0,
        lastSavingsDate: savingsData?.last_savings_date || null,
        missedContributions: missedContributions,
        contributionHistory: contributionHistory,
      },

      // Loan Information
      loanInfo: {
        loanEligibilityStatus: determineLoanEligibility(problemLoans.length, activeLoans.length),
        monthsCompleted: savingsData?.consecutive_months || 0,
        loanCategoryEligible: determineLoanCategory(),
        maximumLoanAmount: calculateMaxLoanAmount(savingsData?.total_saved || 0, activeLoans.length),
        outstandingObligations: problemLoans.map(loan => ({
          id: loan.id,
          type: loan.loan_type,
          amount: loan.amount,
          outstandingBalance: loan.outstanding_amount || loan.remaining_balance || loan.amount,
          status: loan.status,
        })),
        activeLoans: activeLoans.map(loan => ({
          id: loan.id,
          type: loan.loan_type,
          amount: loan.amount,
          outstandingBalance: loan.outstanding_amount || loan.amount,
          status: loan.status,
          disbursedAt: loan.disbursed_at,
          maturityDate: loan.maturity_date,
          monthlyRepayment: loan.monthly_repayment,
        })),
        totalActiveLoans: activeLoans.length,
        totalOutstandingBalance: totalOutstandingBalance,
        completedLoans: completedLoans.length,
        rejectedLoans: rejectedLoans.length,
        repaymentHistory: loanData
          .filter(l => l.status === 'completed')
          .map(l => ({
            id: l.id,
            type: l.loan_type,
            amount: l.amount,
            completedAt: l.completed_at,
          })),
      },

      // Guarantor Information
      guarantorInfo: {
        guaranteesGiven: {
          total: guarantorData.length,
          pending: pendingGuarantees.length,
          approved: approvedGuarantees.length,
          rejected: rejectedGuarantees.length,
          requests: guarantorData.map(g => ({
            loanId: g.loan_id,
            status: g.request_status,
            approvedAt: g.approved_at,
            rejectedAt: g.rejected_at,
          })),
        },
        guaranteesReceived: {
          // This would need additional query to get loans where this profile is the borrower
          total: loanData.reduce((sum, loan) => sum + (loan.guarantee_count || 0), 0),
          pending: 0, // Would need additional query
          approved: 0, // Would need additional query
        },
      },

      // Documents
      documents: {
        kycDocuments: (kycDocuments.data || []).map(doc => ({
          id: doc.id,
          type: doc.type,
          documentNumber: doc.document_number,
          expiryDate: doc.expiry_date,
          frontImageUrl: doc.front_image_url,
          backImageUrl: doc.back_image_url,
          status: doc.status,
          uploadedAt: doc.uploaded_at,
        })),
        memberDocuments: (memberDocuments.data || []).map(doc => ({
          id: doc.id,
          type: doc.document_type,
          fileUrl: doc.file_url,
          fileName: doc.file_name,
          status: doc.status,
          uploadedAt: doc.uploaded_at,
        })),
      },

      // Audit Information
      auditInfo: {
        registrationDate: profile.created_at,
        lastLogin: profile.last_login,
        deviceUsed: profile.last_device,
        ipAddress: profile.last_ip_address,
        registrationChannel: profile.registration_channel,
        lastProfileUpdate: profile.updated_at,
        lastPasswordChange: profile.last_password_change_at,
        recentActivity: (activityTimeline.data || []).slice(0, 20).map(a => ({
          type: a.activity_type,
          description: a.description,
          date: a.created_at,
          ipAddress: a.ip_address,
          deviceInfo: a.device_info,
        })),
        adminNotes: (adminNotes.data || []).map(n => ({
          id: n.id,
          note: n.note,
          createdAt: n.created_at,
          adminName: n.admin?.name || 'Unknown',
        })),
      },

      // Wallet
      wallet: wallet.data ? {
        balance: wallet.data.balance,
        currency: wallet.data.currency,
        isActive: wallet.data.is_active,
        lastUpdated: wallet.data.last_updated,
      } : null,

      // Referrals
      referrals: referrals.data ? {
        referralCode: referrals.data.my_referral_code,
        referredBy: referrals.data.referred_by_code,
        referralCount: referrals.data.referral_count,
        confirmedReferrals: referrals.data.confirmed_referral_count,
      } : null,

      // Support Tickets
      supportTickets: (tickets.data || []).map(t => ({
        id: t.id,
        ticketId: t.ticket_id,
        subject: t.subject,
        status: t.status,
        priority: t.priority,
        createdAt: t.created_at,
      })),
    };

    res.json({
      success: true,
      member: memberProfile,
      metadata: {
        profileId: profile.id,
        userId: profile.user_id,
        email: profile.email,
        role: profile.role,
        isActive: profile.is_active,
        isFlagged: profile.is_flagged,
        flaggedReason: profile.flagged_reason,
        createdAt: profile.created_at,
        updatedAt: profile.updated_at,
      },
    });
  } catch (err) {
    logger.error('admin member profile error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/members/:profileId/activity
 * Get member activity timeline with pagination
 */
router.get('/:profileId/activity', async (req, res) => {
  try {
    const { profileId } = req.params;
    const { page, limit, from, to } = paging(req);

    const { data, error, count } = await supabase
      .from('member_activity_timeline')
      .select('*', { count: 'exact' })
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    res.json({
      success: true,
      activities: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('admin member activity error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/members/:profileId/transactions
 * Get member transactions with pagination
 */
router.get('/:profileId/transactions', async (req, res) => {
  try {
    const { profileId } = req.params;
    const { page, limit, from, to } = paging(req);

    let q = supabase
      .from('transactions')
      .select('*', { count: 'exact' })
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (req.query.type) q = q.eq('type', req.query.type);
    if (req.query.status) q = q.eq('status', req.query.status);

    const { data, error, count } = await q;
    if (error) throw error;

    res.json({
      success: true,
      transactions: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('admin member transactions error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Helper functions
function deriveAccountStatus(profile) {
  if (profile.is_flagged) return 'Suspended';
  if (!profile.is_active) return 'Inactive';
  if (profile.kyc_verified) return 'Active';
  return 'Pending';
}

function maskAccountNumber(accountNumber) {
  if (!accountNumber || accountNumber.length < 4) return accountNumber;
  return '****' + accountNumber.slice(-4);
}

function determineLoanEligibility(problemLoans, activeLoans) {
  if (problemLoans > 0) return 'Restricted (overdue/defaulted loan)';
  if (activeLoans > 0) return 'Has Active Loan';
  return 'Eligible';
}

function determineLoanCategory() {
  return 'Quick/Flexi/Stable (3x savings), Premium (4x), Maxi (5x)';
}

function calculateMaxLoanAmount(totalSavings, activeLoans) {
  if (activeLoans > 0) return 0;
  // Theoretical ceiling: the highest product multiplier (Maxi Loan, 5x).
  return totalSavings * 5;
}

module.exports = router;
