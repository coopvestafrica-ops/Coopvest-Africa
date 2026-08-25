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

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _particleController;
  late final AudioPlayer _audioPlayer;
  
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _logoSlideAnimation;
  late final Animation<double> _rotateAnimation;
  late final Animation<double> _particleAnimation;
  
  bool _showSplash = true;
  bool _dismissed = false;
  bool _soundPlayed = false;
  int _elapsedSeconds = 0;
  
  static const int splashDurationSeconds = 30;

  @override
  void initState() {
    super.initState();
    
    // Initialize audio player
    _audioPlayer = AudioPlayer();
    
    // Fade controller for logo appearance
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Pulse controller for logo breathing effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Rotate controller for subtle rotation
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // Particle controller for background particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _logoSlideAnimation = Tween<double>(begin: 18.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _rotateAnimation = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(
        parent: _rotateController,
        curve: Curves.easeInOut,
      ),
    );

    _particleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _particleController,
        curve: Curves.linear,
      ),
    );

    // Start all animations
    _fadeController.forward();
    _pulseController.repeat(reverse: true);
    _rotateController.repeat(reverse: true);
    
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

    // Wait for minimum display time, then dismiss
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      await _fadeController.reverse();
      if (mounted) {
        setState(() => _showSplash = false);
        await _audioPlayer.stop();
        await _audioPlayer.dispose();
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    _particleController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _fadeController,
        _pulseController,
        _particleController,
        _rotateController,
      ]),
      builder: (context, child) {
        final pulseScale = 1.0 + (_pulseController.value * 0.025);
        
        return Container(
          decoration: const BoxDecoration(
            // These colors are sampled from the approved splash artwork so the
            // image and the Flutter surface read as one continuous composition.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF062D0A),
                Color(0xFF0A4A13),
                Color(0xFF062C0A),
              ],
              stops: [0.0, 0.52, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Animated background particles - rising bubbles
              ...List.generate(30, (index) {
                final delay = index * 0.08;
                final progress = (_particleAnimation.value + delay) % 1.0;
                final startX = (index * 37) % MediaQuery.of(context).size.width;
                // Slight horizontal drift
                final drift = (index % 2 == 0 ? 1 : -1) * (progress * 20);
                
                return Positioned(
                  left: startX + drift,
                  bottom: -20 + (progress * (MediaQuery.of(context).size.height + 40)),
                  child: Opacity(
                    opacity: 0.4 + 0.4 * (1 - (progress * 2 - 1).abs()), // Fade in middle, dim at ends
                    child: Container(
                      width: 6 + (index % 4) * 2,
                      height: 6 + (index % 4) * 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              
              // Main content
              Opacity(
                opacity: _fadeAnimation.value,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated Logo with pulse and glow effect
                      Transform.scale(
                        scale: _scaleAnimation.value * pulseScale,
                        child: Transform.rotate(
                          angle: _rotateAnimation.value,
                          child: Transform.translate(
                            offset: Offset(0, _logoSlideAnimation.value),
                            child: SizedBox(
                            width: 320,
                            height: 320,
                            child: Image.asset(
                              'assets/images/splash-logo-transparent.png',
                              fit: BoxFit.contain,
                              // The cleaned transparent asset sits directly on the matched
                              // dark-emerald surface without a visible image rectangle.
                              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded || frame != null) {
                                  return AnimatedOpacity(
                                    opacity: frame != null ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 350),
                                    child: child,
                                  );
                                }
                                return const _LogoFallback();
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const _LogoFallback();
                              },
                            ),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // The splash-logo asset already contains the wordmark
                      // and the exact brand tagline, so no duplicate text is added.
                      const SizedBox(height: 24),
                      
                      // Animated loading indicator
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Timer display
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: Colors.white.withOpacity(0.9),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_elapsedSeconds}s / ${splashDurationSeconds}s',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Loading dots animation - sequential bouncing
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (index) {
                          // Create a sequential animation where each dot bounces in turn
                          final phaseOffset = index * 0.33;
                          final bounceValue = (_particleController.value + phaseOffset) % 1.0;
                          // Use sine wave for smooth bounce effect
                          final bounceHeight = (bounceValue < 0.5 
                              ? bounceValue * 2 
                              : 2 - bounceValue * 2);
                          final opacity = 0.4 + (bounceValue * 0.6);
                          
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 10,
                            height: 10 + (bounceHeight * 6), // Bouncing height
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(opacity),
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(opacity * 0.5),
                                  blurRadius: 4 + bounceHeight * 4,
                                  spreadRadius: bounceHeight * 2,
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
