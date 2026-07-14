import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/services/contribution_reminder_service.dart';
// contributionReminderService is a singleton, no Provider needed
import '../../../data/models/wallet_models.dart';
import '../../../data/models/loan_models.dart';
import '../../../data/models/announcement_models.dart';
import '../../../data/models/guarantor_models.dart';
import '../../../data/models/document_models.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/wallet_provider.dart';
import '../../../presentation/providers/loan_provider.dart';
import '../../../presentation/providers/contributions/contribution_provider.dart';
import '../../../presentation/providers/insights_provider.dart';
import '../../../presentation/providers/notifications_provider.dart';
import '../../../core/services/realtime_notification_service.dart';
import '../../../data/models/notification_models.dart';
import '../../../presentation/providers/deposit_history_provider.dart';
import '../../../presentation/providers/announcement_provider.dart';
import '../../../presentation/providers/guarantor_provider.dart';
import '../../../presentation/providers/document_provider.dart';
import '../../../presentation/screens/wallet/deposit_screen.dart';
import '../../../presentation/screens/loan/loan_dashboard_screen.dart';
import '../../../presentation/screens/wallet/wallet_dashboard_screen.dart';
import '../../../presentation/screens/referral/referral_dashboard_screen.dart';
import '../../../presentation/screens/contributions/monthly_contributions_screen.dart';
import '../../../presentation/screens/transactions/transactions_history_screen.dart';
import '../../../presentation/screens/announcements/announcements_screen.dart';
import '../../../presentation/screens/guarantor/guarantor_dashboard_screen.dart';
import '../../../presentation/screens/documents/document_upload_screen.dart';
import '../../../presentation/screens/profile/profile_settings_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../presentation/widgets/loan/loan_eligibility_card.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen>
    with WidgetsBindingObserver {
  late Future<void> _refreshFuture;
  Timer? _refreshTimer;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshFuture = _loadData();
    _startPeriodicRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeToNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPeriodicRefresh();
    RealtimeNotificationService().unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _startPeriodicRefresh();
      _loadData();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _appInForeground = false;
      _stopPeriodicRefresh();
    }
  }

  void _startPeriodicRefresh() {
    _stopPeriodicRefresh();
    // Refresh every 60 seconds only while the app is in the foreground
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _appInForeground) {
        _loadData();
      }
    });
  }

  void _stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _subscribeToNotifications() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final service = RealtimeNotificationService();
    service.onNewNotification = (Map<String, dynamic> row) {
      if (!mounted) return;
      try {
        final notification = AppNotification.fromJson(row);
        ref.read(notificationsProvider.notifier).addNotification(notification);
        // Refresh deposit history for wallet events so status screen stays current
        final type = row['type'] as String? ?? '';
        if (type == 'wallet_credited' || type == 'deposit_rejected') {
          ref.read(depositHistoryProvider.notifier).load();
        }
      } catch (e) {
        // ignore parse errors
      }
    };

    service.subscribe(user.id);
  }

  Future<void> _loadData() async {
    try {
      // Load all required data in parallel
      final results = await Future.wait([
        ref.read(walletProvider.notifier).loadWallet(),
        ref.read(loanProvider.notifier).getLoans(),
        ref.read(contributionProvider.notifier).loadContributions(),
      ]);

      // Check and send contribution reminders after data is loaded
      _checkContributionReminders();
    } catch (e) {
      if (mounted) {
        debugPrint('Error loading dashboard data: $e');
      }
    }
  }

  void _checkContributionReminders() {
    final user = ref.read(currentUserProvider);
    final walletState = ref.read(walletProvider);
    final contributionState = ref.read(contributionProvider);

    if (user == null) return;

    // Get user's contribution method from settings
    // Default to 'manual' if not set (assume manual until proven payroll)
    const contributionMethod = 'manual';
    
    // Use defaults - backend will have accurate user preferences
    const preferredDay = 5; // Default to 5th of month
    const monthlyAmount = 5000.0; // Minimum contribution

    // Use singleton service
    contributionReminderService.checkAndSendReminders(
      contributions: contributionState.contributions,
      monthlyAmount: monthlyAmount,
      preferredDay: preferredDay,
      totalSavings: walletState.wallet?.totalContributions ?? 0.0,
    );

    // Sync status with backend for cron job processing
    contributionReminderService.syncContributionStatus(
      userId: user.id,
      contributions: contributionState.contributions,
      monthlyAmount: monthlyAmount,
      preferredDay: preferredDay,
      contributionMethod: contributionMethod,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final walletState = ref.watch(walletProvider);
    final wallet = walletState.wallet;
    final loansState = ref.watch(loanProvider);
    
    final userName = user?.name.split(' ').first ?? 'User';
    final membershipId = user?.id.substring(0, 6) ?? 'N/A';
    
    final walletBalance = wallet?.balance ?? 0.0;
    final totalContributions = wallet?.totalContributions ?? 0.0;
    final activeLoans = loansState.loans
        .where((l) => l.status == 'active' || l.status == 'repaying')
        .fold(0.0, (sum, l) => sum + l.amount);

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: CoopvestColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(context, userName, membershipId, user?.name ?? 'User'),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stat Cards - Overlapping
                    Transform.translate(
                      offset: const Offset(0, -30),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildCompactStatCard(
                              context,
                              'Wallet Balance',
                              '₦${walletBalance.formatNumber()}',
                              Icons.account_balance_wallet_outlined,
                              () => Navigator.push(context, MaterialPageRoute(builder: (context) => WalletDashboardScreen(userId: user?.id ?? '', userName: user?.name ?? ''))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCompactStatCard(
                              context,
                              'Contributions',
                              '₦${totalContributions.formatNumber()}',
                              Icons.savings_outlined,
                              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MonthlyContributionsScreen())),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCompactStatCard(
                              context,
                              'Loans',
                              '₦${activeLoans.formatNumber()}',
                              Icons.monetization_on_outlined,
                              () => Navigator.push(context, MaterialPageRoute(builder: (context) => LoanDashboardScreen(userId: user?.id ?? '', userName: user?.name ?? '', userPhone: user?.phone ?? ''))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Action Buttons Grid
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                      children: [
                        _buildActionButton(
                          context,
                          'Make Contribution',
                          Icons.payments_outlined,
                          () => Navigator.push(context, MaterialPageRoute(builder: (context) => DepositScreen(userId: user?.id ?? ''))),
                        ),
                        _buildActionButton(
                          context,
                          'Apply for Loan',
                          Icons.description_outlined,
                          () => Navigator.push(context, MaterialPageRoute(builder: (context) => LoanDashboardScreen(userId: user?.id ?? '', userName: user?.name ?? '', userPhone: user?.phone ?? ''))),
                        ),
                        _buildActionButton(
                          context,
                          'Investment Pool',
                          Icons.trending_up_outlined,
                          () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Investment Pool coming soon'),
                              backgroundColor: CoopvestColors.primary,
                            ),
                          ),
                        ),
                        _buildActionButton(
                          context,
                          'Download Statements',
                          Icons.assignment_outlined,
                          () => Navigator.push(context, MaterialPageRoute(builder: (context) => TransactionsHistoryScreen(userId: user?.id ?? ''))),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 28),

                    // Loan Eligibility Progress
                    LoanEligibilityCard(
                      onApplyTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoanDashboardScreen(
                            userId: user?.id ?? '',
                            userName: user?.name ?? '',
                            userPhone: user?.phone ?? '',
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    
                    // Insights & Loan Status
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildInsightsCard(context, walletState),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildLoanStatusCard(context, loansState),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 28),
                    
                    // Notifications Section - Real-time from provider
                    _buildNotificationsSection(context, user?.id ?? ''),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String name, String membershipId, String fullName) {
    final walletState = ref.watch(walletProvider);
    final wallet = walletState.wallet;
    final totalBalance = (wallet?.balance ?? 0.0) + (wallet?.totalContributions ?? 0.0);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 60),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1B5E20),
            const Color(0xFF2E7D32),
            const Color(0xFF388E3C),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row with greeting and avatar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // Notification bell
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Avatar
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileSettingsScreen())),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                      ),
                      child: ref.watch(currentUserProvider)?.profilePicture != null && ref.watch(currentUserProvider)!.profilePicture!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                ref.watch(currentUserProvider)!.profilePicture!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.white.withOpacity(0.2),
                                    child: Text(
                                      _getInitials(fullName),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              child: Text(
                                _getInitials(fullName),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 28),
          
          // Total Balance Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Balance',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            color: Colors.white.withOpacity(0.9),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'ID: $membershipId',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '₦${totalBalance.formatNumber()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                // Growth indicator - only show if there's actual data
                if (totalBalance > 0)
                  Text(
                    'Updated just now',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    'Make your first contribution',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Widget _buildCompactStatCard(BuildContext context, String title, String value, IconData icon, VoidCallback onTap, {Color? accentColor}) {
    final cardColor = accentColor ?? CoopvestColors.primary;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: cardColor.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: cardColor.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cardColor.withOpacity(0.15),
                    cardColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cardColor, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: context.textSecondary,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: CoopvestColors.primary.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      CoopvestColors.primary.withOpacity(0.15),
                      CoopvestColors.primary.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: CoopvestColors.primary, size: 24),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsCard(BuildContext context, WalletState walletState) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => WalletDashboardScreen(userId: ref.read(currentUserProvider)?.id ?? '', userName: ref.read(currentUserProvider)?.name ?? ''))),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: CoopvestColors.primary.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: CoopvestColors.primary.withOpacity(0.06),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Insights',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: CoopvestColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 11,
                      color: CoopvestColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Contributions Trend',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const titles = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                          if (value.toInt() < titles.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(titles[value.toInt()], style: TextStyle(fontSize: 10, color: context.textSecondary, fontWeight: FontWeight.w500)),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 24,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: const [
                        FlSpot(0, 20),
                        FlSpot(1, 35),
                        FlSpot(2, 28),
                        FlSpot(3, 45),
                        FlSpot(4, 40),
                        FlSpot(5, 60),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: CoopvestColors.primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: index == 5 ? 5 : 0,
                            color: CoopvestColors.primary,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            CoopvestColors.primary.withOpacity(0.2),
                            CoopvestColors.primary.withOpacity(0.02),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanStatusCard(BuildContext context, LoansState loansState) {
    final pendingLoan = loansState.loans.any((l) => l.status == 'under_review' || l.status == 'pending_guarantors');
    final activeLoan = loansState.loans.any((l) => l.status == 'active' || l.status == 'repaying');
    
    final statusColor = pendingLoan 
        ? CoopvestColors.warning 
        : (activeLoan ? CoopvestColors.primary : context.textSecondary);
    final statusText = pendingLoan 
        ? 'Pending Approval' 
        : (activeLoan ? 'Active Loan' : 'No Applications');
    final statusIcon = pendingLoan 
        ? Icons.hourglass_empty_rounded 
        : (activeLoan ? Icons.check_circle_outline : Icons.info_outline_rounded);
    
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LoanDashboardScreen(userId: ref.read(currentUserProvider)?.id ?? '', userName: ref.read(currentUserProvider)?.name ?? '', userPhone: ref.read(currentUserProvider)?.phone ?? ''))),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              statusColor.withOpacity(0.08),
              statusColor.withOpacity(0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: statusColor.withOpacity(0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Loan Status',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textPrimary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 18,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: statusColor,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'View Details',
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationItem(BuildContext context, String title, String time, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: Colors.grey.withOpacity(0.06),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.15),
                      color.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (time.isNotEmpty) ...[ 
                      const SizedBox(height: 4),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.textSecondary.withOpacity(0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsSection(BuildContext context, String userId) {
    final notificationsState = ref.watch(notificationsProvider);
    final notifications = notificationsState.notifications.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notifications',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (notifications.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.dividerColor.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CoopvestColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.notifications_none_outlined,
                    color: CoopvestColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your notifications will appear here',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ...notifications.map((notification) {
            final isLoan = notification.type.contains('loan');
            final isContribution = notification.type.contains('contribution');
            final icon = isLoan 
                ? Icons.monetization_on_outlined 
                : (isContribution ? Icons.savings_outlined : Icons.notifications_outlined);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildNotificationItem(
                context,
                notification.title,
                _formatTimeAgo(notification.timestamp),
                icon,
                CoopvestColors.primary,
                () {},
              ),
            );
          }),
      ],
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }
}
