import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connectivity state
enum ConnectivityStatus { online, offline, checking }

/// Connectivity Service - monitors network status
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  ConnectivityStatus _status = ConnectivityStatus.checking;
  bool _showOfflineBanner = false;

  ConnectivityStatus get status => _status;
  bool get isOnline => _status == ConnectivityStatus.online;
  bool get showOfflineBanner => _showOfflineBanner;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // Check initial status
    final result = await _connectivity.checkConnectivity();
    _updateStatus(result);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final wasOffline = !isOnline;
    // Check if any result indicates connectivity is available
    final isNowOffline = results.isEmpty || 
                          results.every((r) => r == ConnectivityResult.none);

    if (isNowOffline) {
      _status = ConnectivityStatus.offline;
      _showOfflineBanner = true;
    } else {
      _status = ConnectivityStatus.online;
      // Hide banner after coming back online briefly
      if (wasOffline) {
        Future.delayed(const Duration(seconds: 3), () {
          if (isOnline) {
            _showOfflineBanner = false;
            notifyListeners();
          }
        });
      }
    }
    notifyListeners();
  }

  void hideOfflineBanner() {
    _showOfflineBanner = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Connectivity Provider
final connectivityProvider = ChangeNotifierProvider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Offline Banner Widget - shows when offline (updated for connectivity_plus v5+)
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    
    if (!connectivity.showOfflineBanner || connectivity.isOnline) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.orange.shade800,
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text(
              'No internet connection',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: () => connectivity.hideOfflineBanner(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}