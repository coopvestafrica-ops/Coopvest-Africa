import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../config/theme_config.dart';

/// Professional Coopvest Splash Screen with Animation and Sound
class SplashScreen extends StatefulWidget {
  final bool isReady;
  final Widget child;

  const SplashScreen({
    Key? key,
    required this.isReady,
    required this.child,
  }) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final AudioPlayer _audioPlayer;
  
  bool _showSplash = true;
  bool _dismissed = false;
  bool _soundPlayed = false;
  int _elapsedSeconds = 0;
  
  static const int splashDurationSeconds = 6;

  @override
  void initState() {
    super.initState();
    
    // Initialize audio player
    _audioPlayer = AudioPlayer();
    
    // The splash is intentionally static. Audio and timing remain active,
    // but the logo and interface do not move.
    
    // Play sound and start timer
    _playStartupSound();
    _startSplashTimer();
  }

  Future<void> _playStartupSound() async {
    if (_soundPlayed) return;
    _soundPlayed = true;

    try {
      // Play one short local branded cue. Keeping this local avoids network
      // delays and prevents multiple remote sounds from overlapping.
      await _audioPlayer.play(
        AssetSource('audio/coopvest_startup.mp3'),
        volume: 0.65,
      );
    } catch (e) {
      debugPrint('Error playing startup sound: $e');
    }
  }

  void _startSplashTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _dismissed) return false;
      
      setState(() {
        _elapsedSeconds++;
      });
      
      // Auto-dismiss after the configured maximum duration
      if (_elapsedSeconds >= splashDurationSeconds) {
        _dismissSplash();
        return false;
      }
      
      // Also dismiss if app is ready
      if (widget.isReady && !_dismissed) {
        _dismissSplash();
        return false;
      }
      
      return _showSplash;
    });
  }

  @override
  void didUpdateWidget(SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReady && !_dismissed) {
      _dismissSplash();
    }
  }

  Future<void> _dismissSplash() async {
    if (_dismissed) return;
    _dismissed = true;

    if (mounted) {
      setState(() => _showSplash = false);
    }
    await _audioPlayer.stop();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;

    final screenSize = MediaQuery.sizeOf(context);
    final compactLayout = screenSize.height < 500;
    final calculatedLogoSize = (screenSize.height *
            (compactLayout ? 0.62 : 0.55))
        .clamp(180.0, 320.0)
        .toDouble();
    final logoSize = calculatedLogoSize > screenSize.width * 0.86
        ? screenSize.width * 0.86
        : calculatedLogoSize;
    final verticalGap = compactLayout ? 20.0 : 40.0;

    return Container(
      decoration: const BoxDecoration(
        // Soft mint tones complement the supplied navy and green logo without
        // competing with the wordmark or tagline.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFC6DFC9),
            Color(0xFFA9CCB5),
            Color(0xFFB9D6C0),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: logoSize,
              height: logoSize,
              child: Image.asset(
                'assets/images/splash-logo-transparent.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const _LogoFallback();
                },
              ),
            ),
            SizedBox(height: verticalGap),
            // The timer updates once per second but has no visual animation.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0D3B66).withOpacity(0.08),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: const Color(0xFF0D3B66).withOpacity(0.82),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_elapsedSeconds}s / ${splashDurationSeconds}s',
                    style: TextStyle(
                      color: const Color(0xFF0D3B66).withOpacity(0.82),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
}

/// Branded fallback shown while the logo asset decodes or if it fails to load.
/// A gradient medallion with a savings glyph and the "CV" monogram — far more
/// polished than a bare white tile, so the splash never looks like "just a
/// green screen" even before the image is ready.
class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CoopvestColors.primary,
            CoopvestColors.primaryDark,
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.savings_outlined, color: Colors.white, size: 54),
          Positioned(
            bottom: 26,
            child: Text(
              'CV',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Branded fallback shown while the logo asset decodes or if it fails to load.
/// A gradient medallion with a savings glyph and the "CV" monogram — far more
/// polished than a bare white tile, so the splash never looks like "just a
/// green screen" even before the image is ready.
class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CoopvestColors.primary,
            CoopvestColors.primaryDark,
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.savings_outlined, color: Colors.white, size: 54),
          Positioned(
            bottom: 26,
            child: Text(
              'CV',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
