import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'onboarding_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _preloaded = false;
  bool _finishing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_preloaded) {
      _preloaded = true;
      IntroAssets.preload(context);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await Hive.box<String>('settings_cache').put('onboarding_seen', '1');
      if (mounted) context.go('/auth/register');
    } catch (_) {
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de terminer. Réessaie.')),
        );
      }
    }
  }

  void _next() {
    if (_page == IntroAssets.pages.length - 1) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080808),
    body: Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: IntroAssets.pages.length,
          onPageChanged: (value) => setState(() => _page = value),
          itemBuilder: (context, index) => OnboardingPageWidget(
            page: IntroAssets.pages[index],
            active: index == _page,
            bottomInset: 190,
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEDE1CD),
                          foregroundColor: const Color(0xFF171717),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _finishing ? null : _next,
                        child: Text(_page == 2 ? 'Commencer' : 'Suivant'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE3DFD8),
                        minimumSize: const Size(80, 44),
                      ),
                      onPressed: _finishing ? null : _finish,
                      child: const Text('Passer'),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: 'Page ${_page + 1} sur 3',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          3,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == _page
                                  ? const Color(0xFFEDE1CD)
                                  : Colors.transparent,
                              border: Border.all(
                                color: index == _page
                                    ? const Color(0xFFEDE1CD)
                                    : const Color(0xFF92908B),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
