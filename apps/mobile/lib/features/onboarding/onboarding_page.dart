import 'package:flutter/material.dart';

class OnboardingPageModel {
  const OnboardingPageModel({
    required this.image,
    required this.title,
    required this.subtitle,
  });
  final String image;
  final String title;
  final String subtitle;
}

abstract final class IntroAssets {
  static const splash = 'packages/dressly_intro_assets/images/bording1.png';
  static const pages = [
    OnboardingPageModel(
      image: 'packages/dressly_intro_assets/images/boarding2.png',
      title: 'Une garde-robe intelligente',
      subtitle: 'Scanne, ajoute, organise et laisse l’IA créer tes tenues.',
    ),
    OnboardingPageModel(
      image: 'packages/dressly_intro_assets/images/boarding3.png',
      title: 'Des recommandations',
      subtitle: 'Adaptées à la météo, tes activités et ton style.',
    ),
    OnboardingPageModel(
      image: 'packages/dressly_intro_assets/images/boarding4.png',
      title: 'Partout dans le monde',
      subtitle: 'Ajoute une destination et obtiens des tenues adaptées.',
    ),
  ];
  static Future<void> preload(BuildContext context) => Future.wait([
    precacheImage(const AssetImage(splash), context),
    for (final page in pages) precacheImage(AssetImage(page.image), context),
  ]);
}

class IntroBackground extends StatelessWidget {
  const IntroBackground({super.key, required this.image});
  final String image;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(image, fit: BoxFit.cover, excludeFromSemantics: true),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x08000000),
              Color(0x33000000),
              Color(0xE8000000),
              Color(0xFF080808),
            ],
            stops: [0, 0.42, 0.78, 1],
          ),
        ),
      ),
    ],
  );
}

class OnboardingPageWidget extends StatefulWidget {
  const OnboardingPageWidget({
    super.key,
    required this.page,
    required this.active,
    required this.bottomInset,
  });
  final OnboardingPageModel page;
  final bool active;
  final double bottomInset;
  @override
  State<OnboardingPageWidget> createState() => _OnboardingPageWidgetState();
}

class _OnboardingPageWidgetState extends State<OnboardingPageWidget> {
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IntroBackground(image: widget.page.image),
      SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(28, 32, 28, widget.bottomInset),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        offset: _visible && widget.active
                            ? Offset.zero
                            : const Offset(0, 0.06),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: _visible && widget.active ? 1 : 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.page.title,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 28,
                                  height: 1.16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.8,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                widget.page.subtitle,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  height: 1.5,
                                  color: Color(0xFFE3DFD8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
