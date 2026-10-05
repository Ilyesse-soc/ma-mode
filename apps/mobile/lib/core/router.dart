import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/mannequin/mannequin_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/welcome_screen.dart';
import '../features/auth/screens/account_action_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/preferences/preferences_screen.dart';
import '../features/recommendation/outfit_flow_screen.dart';
import '../features/silhouette/silhouette_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/stats/statistics_screen.dart';
import '../features/settings/account_screens.dart';
import '../features/location/destination_screen.dart';
import '../features/wardrobe/screens/photo_screen.dart';
import '../features/wardrobe/screens/add_garment_screen.dart';
import '../features/wardrobe/screens/barcode_scan_screen.dart';
import '../features/wardrobe/screens/garment_detail_screen.dart';
import 'providers.dart';
import 'models.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => authListenable.value++);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final onAuthPage = location.startsWith('/auth');
      final isPublic =
          location == '/splash' || location == '/onboarding' || onAuthPage;
      if (auth.status == AuthStatus.unknown) {
        return isPublic ? null : '/splash';
      }
      if (auth.status == AuthStatus.guest && !isPublic) return '/auth/welcome';
      if (auth.status == AuthStatus.authenticated &&
          onAuthPage &&
          location != '/auth/action') {
        return location == '/auth/register'
            ? '/preferences?from=register'
            : '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/auth/action',
        builder: (_, state) => AccountActionScreen(
          action: state.uri.queryParameters['action'] == 'reset'
              ? 'reset'
              : 'verify',
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, state) => HomeShell(
          initialIndex: switch (state.uri.queryParameters['tab']) {
            'wardrobe' => 1,
            'explore' => 3,
            'profile' => 4,
            _ => 0,
          },
        ),
      ),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/privacy/export', builder: (_, _) => const ExportScreen()),
      GoRoute(
        path: '/account/delete',
        builder: (_, _) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/destinations',
        builder: (_, _) => const DestinationScreen(),
      ),
      GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
      GoRoute(
        path: '/wardrobe/photo',
        builder: (_, state) => PhotoScreen(
          labelMode: state.uri.queryParameters['mode'] == 'label',
        ),
      ),
      GoRoute(
        path: '/wardrobe/add',
        builder: (_, state) => AddGarmentScreen(
          initialGarment:
              (state.extra as Map<String, dynamic>?)?['garment'] as Garment?,
          initialCategorySlug:
              (state.extra as Map<String, dynamic>?)?['category_slug']
                  as String? ??
              state.uri.queryParameters['category'],
        ),
      ),
      GoRoute(
        path: '/wardrobe/scan',
        builder: (_, _) => const BarcodeScanScreen(),
      ),
      GoRoute(
        path: '/wardrobe/garment/:id',
        builder: (_, state) =>
            GarmentDetailScreen(garmentId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/silhouette', builder: (_, _) => const SilhouetteScreen()),
      GoRoute(
        path: '/mannequin',
        builder: (_, state) => MannequinScreen(
          initialGarmentIds: state.extra is List<String>
              ? state.extra as List<String>
              : const [],
        ),
      ),
      GoRoute(
        path: '/outfit-flow',
        builder: (_, state) => OutfitFlowScreen(
          initialRecommendation: state.extra is Recommendation
              ? state.extra as Recommendation
              : null,
        ),
      ),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/statistics', builder: (_, _) => const StatisticsScreen()),
      GoRoute(
        path: '/preferences',
        builder: (_, _) => const PreferencesScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authListenable.dispose();
  });
  return router;
});
