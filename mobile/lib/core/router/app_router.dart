import 'dart:async';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/data/auth_repository_impl.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/login_screen.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/onboarding_screen.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/register_screen.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_screen.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_screen.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_settings_screen.dart';
import 'package:ecotrack_mobile/features/shop/presentation/shop_screen.dart';
import 'package:ecotrack_mobile/features/stats/presentation/stats_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final class AuthRouterListenable extends ChangeNotifier {
  AuthRouterListenable(AuthCubit authCubit) {
    _subscription = authCubit.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final class AppRouter {
  AppRouter._();

  static GoRouter get router => createRouter(AuthCubit(AuthRepositoryImpl()));

  static GoRouter createRouter(AuthCubit authCubit) => GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: AuthRouterListenable(authCubit),
    redirect: (context, state) {
      final authState = authCubit.state;
      final isAuthenticated = authState is AuthAuthenticated;
      final loc = state.matchedLocation;
      final isAuthRoute =
          loc == '/login' || loc == '/register' || loc == '/onboarding';

      // If user is authenticated and is on an auth screen -> open profile screen directly
      if (isAuthenticated && isAuthRoute) {
        return '/profile';
      }

      // If user is unauthenticated and tries to access app content -> redirect to login
      if (!isAuthenticated && !isAuthRoute) {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          // Tab 1: Stats
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
          // Tab 2: Map & Activity
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapActivityScreen(),
              ),
            ],
          ),
          // Tab 3: Home & Mascot (Raised Center)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Tab 4: Shop
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shop',
                builder: (context, state) => const ShopScreen(),
              ),
            ],
          ),
          // Tab 5: Profile & 152-FZ
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileSettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onDestinationSelected,
      backgroundColor: EcoColors.surface,
      indicatorColor: EcoColors.primaryGreen.withValues(alpha: 0.25),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart, color: EcoColors.primaryGreen),
          label: 'Статистика',
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map, color: EcoColors.primaryGreen),
          label: 'Маршруты',
        ),
        NavigationDestination(
          icon: Icon(Icons.eco_outlined),
          selectedIcon: Icon(Icons.eco, color: EcoColors.primaryGreen),
          label: 'Главная',
        ),
        NavigationDestination(
          icon: Icon(Icons.card_giftcard_outlined),
          selectedIcon: Icon(
            Icons.card_giftcard,
            color: EcoColors.primaryGreen,
          ),
          label: 'Награды',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person, color: EcoColors.primaryGreen),
          label: 'Профиль',
        ),
      ],
    ),
  );
}
