import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../../data/models/wallet_models.dart';
import '../../../presentation/providers/wallet_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import '../savings/savings_goals_screen.dart';
import '../transactions/transactions_history_screen.dart';
import 'deposit_screen.dart';
import 'withdrawal_screen.dart';
import 'deposit_status_screen.dart';

/// Wallet Dashboard Screen
class WalletDashboardScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;

  const WalletDashboardScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  ConsumerState<WalletDashboardScreen> createState() => _WalletDashboardScreenState();
}

class _WalletDashboardScreenState extends ConsumerState<WalletDashboardScreen> {
  bool _isBalanceHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await ref.read(walletProvider.notifier).loadWallet();
    await ref.read(walletProvider.notifier).loadTransactions();
    await ref.read(walletProvider.notifier).loadSavingsGoals();
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final wallet = walletState.wallet;
    final savingsGoals = walletState.savingsGoals;
    final recentTransactions = walletState.transactions.take(5).toList();

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: context.scaffoldBackground,
        title: Text(
          'My Wallet',
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: CoopvestColors.primary),
            onPressed: () {
              _showReceiveQRDialog(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(context, walletState, wallet, savingsGoals, recentTransactions),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WalletState walletState,
    Wallet? wallet,
    List<SavingsGoal> savingsGoals,
    List<Transaction> recentTransactions,
  ) {
    // Show loading only if we have no data at all
    if (walletState.isLoading && wallet == null) {
      return const Center(
        child: CircularProgressIndicator(color: CoopvestColors.primary),
      );
    }

    // Show error only if we have no data at all
    if (walletState.status == WalletStatus.error && wallet == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: CoopvestColors.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load wallet data',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                walletState.error ?? 'An unexpected error occurred',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Retry',
                onPressed: _loadData,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance Card
            _buildBalanceCard(context, wallet),
            
            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActions(context),
            
            const SizedBox(height: 24),

            // Savings Goals Section
            _buildSavingsGoalsSection(context, ref, savingsGoals),
            
            const SizedBox(height: 24),

            // Recent Transactions
            _buildRecentTransactions(context, ref, recentTransactions),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, Wallet? wallet) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final displayBalance = _isBalanceHidden ? '••••••' : '₦${(wallet?.balance ?? 0).toStringAsFixed(2)}';
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode 
              ? [context.cardBackground, context.cardBackground.withOpacity(0.8)]
              : [CoopvestColors.primary, const Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : CoopvestColors.primary).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Balance',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? context.textSecondary : Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    displayBalance,
                    style: TextStyle(
                      fontSize: 28,
                      color: isDarkMode ? context.textPrimary : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isBalanceHidden = !_isBalanceHidden;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDarkMode ? CoopvestColors.primary.withOpacity(0.2) : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isBalanceHidden ? Icons.visibility_off : Icons.visibility,
                        color: isDarkMode ? CoopvestColors.primary : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isBalanceHidden ? 'Show' : 'Hide',
                        style: TextStyle(
                          color: isDarkMode ? CoopvestColors.primary : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? context.textSecondary : Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isBalanceHidden ? '••••••' : '₦${(wallet?.availableForWithdrawal ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isDarkMode ? context.textPrimary : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: isDarkMode ? context.dividerColor : Colors.white.withOpacity(0.2)),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? context.textSecondary : Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isBalanceHidden ? '••••••' : '₦${(wallet?.pendingContributions ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isDarkMode ? context.textPrimary : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildActionItem(
          context,
          'Deposit',
          Icons.add_circle_outline,
          () => Navigator.push(context, MaterialPageRoute(builder: (context) => DepositScreen(userId: widget.userId))),
        ),
        _buildActionItem(
          context,
          'Withdraw',
          Icons.file_upload_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (context) => WithdrawalScreen(userId: widget.userId))),
        ),
        _buildActionItem(
          context,
          'My Deposits',
          Icons.receipt_long_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DepositStatusScreen())),
        ),
        _buildActionItem(
          context,
          'History',
          Icons.history,
          () => Navigator.push(context, MaterialPageRoute(builder: (context) => TransactionsHistoryScreen(userId: widget.userId))),
        ),
      ],
    );
  }

  Widget _buildActionItem(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBackground,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: CoopvestColors.primary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsGoalsSection(BuildContext context, WidgetRef ref, List<SavingsGoal> goals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Savings Goals',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SavingsGoalsScreen(userId: widget.userId))),
              child: const Text('View All', style: TextStyle(color: CoopvestColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (goals.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.savings_outlined, size: 48, color: context.textSecondary.withOpacity(0.5)),
                const SizedBox(height: 12),
                Text(
                  'No savings goals yet',
                  style: TextStyle(color: context.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    // Create goal
                  },
                  child: const Text('Create Goal'),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: goals.length,
              itemBuilder: (context, index) {
                final goal = goals[index];
                final progress = goal.targetAmount > 0 ? goal.currentAmount / goal.targetAmount : 0.0;
                
                return Container(
                  width: 240,
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: context.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '₦${goal.currentAmount.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: CoopvestColors.primary),
                          ),
                          Text(
                            'of ₦${goal.targetAmount.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 12, color: context.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: context.dividerColor,
                        color: CoopvestColors.primary,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 10, color: context.textSecondary),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRecentTransactions(BuildContext context, WidgetRef ref, List<Transaction> transactions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Transactions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TransactionsHistoryScreen(userId: widget.userId))),
              child: const Text('See All', style: TextStyle(color: CoopvestColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (transactions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No recent transactions', style: TextStyle(color: context.textSecondary)),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: transactions.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isDeposit = tx.type == 'deposit';
              
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isDeposit ? Colors.green : Colors.orange).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDeposit ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isDeposit ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                ),
                title: Text(
                  tx.description ?? (isDeposit ? 'Deposit' : 'Withdrawal'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary),
                ),
                subtitle: Text(
                  DateFormat('MMM dd, yyyy').format(tx.createdAt),
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                trailing: Text(
                  '${isDeposit ? '+' : '-'}₦${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDeposit ? Colors.green : Colors.orange,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showReceiveQRDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receive Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scan this QR code to receive funds into your wallet'),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: widget.userId,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Wallet ID: ${widget.userId}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
