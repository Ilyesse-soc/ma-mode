import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/providers.dart';
import '../onboarding/onboarding_page.dart';

/// Splash premium: titre éditorial et baseline — puis onboarding
/// (premier lancement) ou auth/home selon la session.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _animationDone = false;
  bool _imagesReady = false;
  bool _preloading = false;

  void _navigate() {
    if (!_animationDone || !_imagesReady || !mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.unknown) return;
    final seen =
        Hive.box<String>('settings_cache').get('onboarding_seen') == '1';
    context.go(
      auth.status == AuthStatus.authenticated
          ? '/'
          : seen
          ? '/auth/welcome'
          : '/onboarding',
    );
  }

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          _animationDone = true;
          _navigate();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloading) return;
    _preloading = true;
    IntroAssets.preload(context).then((_) {
      if (!mounted) return;
      _imagesReady = true;
      _navigate();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, _) => _navigate());
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const IntroBackground(image: IntroAssets.splash),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingXl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 3),
                  FadeTransition(
                    opacity: _controller,
                    child: Column(
                      children: [
                        Text(
                          'Dressly',
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                            fontSize: 52,
                            height: 1.1,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.spacingM),
                        Text(
                          'Ta garde-robe,\ndes tenues parfaites.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFE3DFD8),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
