import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../data/models/notification_models.dart';
import '../../../presentation/providers/notifications_provider.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../widgets/common/cards.dart';
import '../loan/loan_dashboard_screen.dart';
import '../transactions/transactions_history_screen.dart';
import '../support/support_home_screen.dart';
import '../contributions/monthly_contributions_screen.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notificationsState = ref.watch(notificationsProvider);
    final notifications = notificationsState.notifications;

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (notifications.isNotEmpty)
            TextButton(
              onPressed: () {
                // Mark all as read
                for (final notif in notifications.where((n) => !n.isRead)) {
                  ref.read(notificationsProvider.notifier).markAsRead(notif.id);
                }
              },
              child: const Text('Mark all as read'),
            ),
        ],
      ),
      body: notificationsState.isLoading && notifications.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: CoopvestColors.primary),
            )
          : notifications.isEmpty
              ? _buildEmptyState(context)
              : RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(notificationsProvider.notifier).loadNotifications();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _buildNotificationCard(context, notification, ref);
                    },
                  ),
                ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    AppNotification notification,
    WidgetRef ref,
  ) {
    final color = _getColorFromHex(notification.color);
    final icon = _getIconFromString(notification.icon);

    return GestureDetector(
      onTap: () {
        if (!notification.isRead) {
          ref.read(notificationsProvider.notifier).markAsRead(notification.id);
        }
        _openNotificationDestination(context, notification, ref);
      },
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha((255 * 0.1).toInt()),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: CoopvestColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(notification.timestamp),
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      PopupMenuButton(
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: const Text('Delete'),
                            onTap: () {
                              ref
                                  .read(notificationsProvider.notifier)
                                  .deleteNotification(notification.id);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Route a tapped notification to the most relevant screen based on its type.
  void _openNotificationDestination(
    BuildContext context,
    AppNotification notification,
    WidgetRef ref,
  ) {
    final user = ref.read(currentUserProvider);
    final userId = user?.id ?? '';
    final t = notification.type.toLowerCase();

    Widget? destination;
    if (t.contains('loan') || t.contains('guarantor') || t.contains('rollover')) {
      destination = LoanDashboardScreen(
        userId: userId,
        userName: user?.name ?? '',
        userPhone: user?.phone ?? '',
      );
    } else if (t.contains('chat') ||
        t.contains('support') ||
        t.contains('ticket') ||
        t.contains('message')) {
      destination = const SupportHomeScreen();
    } else if (t.contains('saving') || t.contains('invest') || t.contains('contribution')) {
      destination = const MonthlyContributionsScreen();
    } else if (t.contains('transaction') || t.contains('payment') || t.contains('wallet')) {
      destination = TransactionsHistoryScreen(userId: userId);
    }

    if (destination != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => destination!));
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 64,
            color: context.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
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
      return DateFormat('MMM dd, yyyy').format(dateTime);
    }
  }

  Color _getColorFromHex(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xff')));
    } catch (e) {
      return CoopvestColors.primary;
    }
  }

  IconData _getIconFromString(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'celebration':
        return Icons.celebration;
      case 'verified':
        return Icons.verified;
      case 'new_releases':
        return Icons.new_releases;
      case 'savings':
        return Icons.savings;
      case 'person_add':
        return Icons.person_add;
      case 'payment':
        return Icons.payment;
      default:
        return Icons.notifications;
    }
  }
}
