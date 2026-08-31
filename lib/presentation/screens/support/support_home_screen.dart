import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import 'ticket_list_screen.dart';
import 'ticket_creation_screen.dart';
import 'live_chat_screen.dart';

/// Support/Complaints Home Screen
class SupportHomeScreen extends ConsumerWidget {
  const SupportHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Help & Support', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [CoopvestColors.primary, CoopvestColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.support_agent, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('How can we help?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Submit a complaint and our team will assist you promptly.', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Quick Actions
              Text('Submit a Complaint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketCreationScreen())),
                  icon: const Icon(Icons.report_problem, color: Colors.white),
                  label: const Text('Submit New Complaint', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: CoopvestColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
              
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LiveChatScreen())),
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                  label: const Text('Live Chat with Support', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: CoopvestColors.secondary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity, height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketListScreen())),
                  icon: const Icon(Icons.inbox_outlined),
                  label: const Text('View My Complaints', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Common Help Topics
              Text('Common Issues', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
              const SizedBox(height: 16),
              
              _buildHelpTopic(
                context, 
                Icons.account_balance_wallet, 
                'Loan & Contribution Issues', 
                'Problems with loan applications, repayments, or savings',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketCreationScreen(preselectedCategory: 'loan_issue'))),
              ),
              
              _buildHelpTopic(
                context, 
                Icons.payments, 
                'Withdrawal Delays', 
                'Issues with fund withdrawals or transfer delays',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketCreationScreen(preselectedCategory: 'withdrawal'))),
              ),
              
              _buildHelpTopic(
                context, 
                Icons.person, 
                'Account & KYC', 
                'Profile updates, identity verification problems',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketCreationScreen(preselectedCategory: 'account_kyc'))),
              ),
              
              _buildHelpTopic(
                context, 
                Icons.bug_report, 
                'App Errors', 
                'Technical bugs or errors in the app',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketCreationScreen(preselectedCategory: 'technical_bug'))),
              ),
              
              _buildHelpTopic(
                context, 
                Icons.handshake, 
                'Guarantor Issues', 
                'Guarantor requests or consent problems',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TicketCreationScreen(preselectedCategory: 'guarantor_consent'))),
              ),
              
              const SizedBox(height: 32),
              
              // Response time info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: context.cardBackground, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.access_time, color: CoopvestColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Response Time', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                          Text('We typically respond within 24-48 hours on business days.', style: TextStyle(fontSize: 13, color: context.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Urgency notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CoopvestColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CoopvestColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.priority_high, color: CoopvestColors.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Urgent Issue?', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                          Text('Select "Urgent" priority when submitting if it requires immediate attention.', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpTopic(BuildContext context, IconData icon, String title, String description, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: context.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.dividerColor)),
          child: Row(
            children: [
              Icon(icon, color: CoopvestColors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                    Text(description, style: TextStyle(fontSize: 12, color: context.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}