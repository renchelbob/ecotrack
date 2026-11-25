import 'dart:async';

import 'package:ecotrack_mobile/core/router/floating_bottom_nav_bar.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/fz152_consent_modal.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/onboarding_screen.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_screen.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/fox_mascot_widget.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_bloc.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/screens/map_activity_screen.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/badges_and_accessories_screen.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/friends_screen.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/my_vehicle_screen.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_settings_screen.dart';
import 'package:ecotrack_mobile/features/shop/presentation/shop_screen.dart';
import 'package:ecotrack_mobile/features/stats/presentation/stats_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

final class AuthRouterListenable(AuthBloc authBloc) extends ChangeNotifier {
  this {
    _subscription = authBloc.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

final class AppRouter._() {
  static GoRouter createRouter({
    required AuthBloc authBloc,
    required AuthRouterListenable refreshListenable,
    Future<bool> Function()? onRequestStepsPermission,
    Future<bool> Function()? onRequestGpsPermission,
    GlobalKey<NavigatorState>? navigatorKey,
  }) => GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/home',
    refreshListenable: refreshListenable,
    redirect: (context, state) => _handleRedirect(authBloc.state, state),
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) {
          final step =
              int.tryParse(state.uri.queryParameters['step'] ?? '') ?? 1;
          return OnboardingScreen(
            initialStep: step,
            mascotBuilder: _buildMascotWidget,
            onRequestStepsPermission: onRequestStepsPermission,
            onRequestGpsPermission: onRequestGpsPermission,
          );
        },
      ),
      GoRoute(path: '/auth/login', redirect: (_, _) => '/onboarding?step=3'),
      GoRoute(path: '/login', redirect: (_, _) => '/onboarding?step=3'),
      GoRoute(
        path: '/auth/google-phone',
        builder: (_, _) => const GoogleFormalPhoneModalScreen(),
      ),
      GoRoute(
        path: '/auth/consent',
        builder: (_, _) => const Fz152ConsentResolutionScreen(),
      ),
      GoRoute(path: '/ledger', builder: (_, _) => const PointLedgerScreen()),
      GoRoute(path: '/stats/challenge', redirect: (_, _) => '/stats'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _EcoShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (_, _) => const StatsScreen(),
                routes: [
                  GoRoute(
                    path: 'emissions',
                    builder: (_, _) => const EmissionsDrilldownScreen(),
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (_, _) => const ActivityHistoryDrilldownScreen(),
                  ),
                  GoRoute(
                    path: 'equivalents/:kind',
                    builder: (context, state) => EquivalentsDrilldownScreen(
                      kind: state.pathParameters['kind'] ?? 'forest',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) {
                  final modeParam = state.uri.queryParameters['mode'];
                  final mode = switch (modeParam) {
                    'rso' => MapScreenMode.recyclingMap,
                    'routes' => MapScreenMode.myRoutes,
                    _ => MapScreenMode.calculator,
                  };
                  return MapActivityScreen(
                    initialMode: mode,
                    initialDateIso: state.uri.queryParameters['date'],
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shop',
                builder: (_, _) => const ShopScreen(),
                routes: [
                  GoRoute(path: 'cart', builder: (_, _) => const CartScreen()),
                  GoRoute(
                    path: 'orders/qr',
                    builder: (_, _) => const OrdersQrScreen(),
                  ),
                  GoRoute(
                    path: 'orders/promo',
                    builder: (_, _) => const OrdersPromoScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileSettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'badges',
                    builder: (_, _) => const BadgesAndAccessoriesScreen(
                      mascotBuilder: _buildMascotWidget,
                    ),
                  ),
                  GoRoute(
                    path: 'friends',
                    builder: (context, state) => FriendsScreen(
                      initialInviteCode: state.uri.queryParameters['code'],
                    ),
                  ),
                  GoRoute(
                    path: 'vehicle',
                    builder: (_, _) => const MyVehicleScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static Widget _buildMascotWidget(String moodWire, {String? accessoryCode}) =>
      FoxMascotWidget(
        mood: MascotMoodState.fromWire(moodWire),
        equippedAccessoryCode: accessoryCode,
        size: const Size(156, 156),
      );

  static String? _handleRedirect(AuthState authState, GoRouterState state) {
    final loc = state.matchedLocation;
    return switch (authState) {
      AuthInitial() || AuthAuthenticating() => null,
      AuthOnboardingRequired() =>
        loc == '/onboarding' ? null : '/onboarding?step=1',
      AuthUnauthenticated() ||
      AuthError() => loc == '/onboarding' ? null : '/onboarding?step=3',
      AuthGooglePhoneRequired() =>
        loc == '/auth/google-phone' ? null : '/auth/google-phone',
      AuthConsentResolutionRequired() =>
        loc == '/auth/consent' ? null : '/auth/consent',
      AuthAuthenticated() => _isPreAuthLocation(loc) ? '/home' : null,
    };
  }

  static bool _isPreAuthLocation(String loc) =>
      loc == '/onboarding' ||
      loc == '/auth/login' ||
      loc == '/login' ||
      loc == '/auth/google-phone' ||
      loc == '/auth/consent';
}

final class const _EcoShellScaffold({
  required final StatefulNavigationShell navigationShell,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    extendBody: true,
    body: navigationShell,
    bottomNavigationBar: FloatingBottomNavBar(
      currentIndex: navigationShell.currentIndex,
      onTap: (idx) => navigationShell.goBranch(
        idx,
        initialLocation: idx == navigationShell.currentIndex,
      ),
    ),
  );
}
