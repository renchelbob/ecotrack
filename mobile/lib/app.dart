import 'dart:async';

import 'package:ecotrack_mobile/core/di/app_dependencies.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/router/app_router.dart';
import 'package:ecotrack_mobile/core/sync/sync_status_cubit.dart';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_cubit.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_bloc.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/friends_cubit.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_settings_cubit.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/vehicle_cubit.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:ecotrack_mobile/features/shop/presentation/shop_bloc.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:ecotrack_mobile/features/stats/presentation/stats_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

final class const EcoTrackApp({
  required final AppDependencies dependencies,
  final AuthBloc? overrideAuthBloc,
  super.key,
}) extends StatefulWidget {
  static String? resolveDeepLinkLocation(String rawUri) {
    final trimmed = rawUri.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      return null;
    }
    if (parsed.scheme.isNotEmpty && parsed.scheme != 'ecotrack') {
      return null;
    }
    if (parsed.host.isNotEmpty) {
      return _resolveHostBasedUri(parsed);
    }
    if (parsed.path.isEmpty) {
      return null;
    }
    final normalizedPath = parsed.path.startsWith('/')
        ? parsed.path
        : '/${parsed.path}';
    if (normalizedPath.startsWith('/friend/')) {
      final code = normalizedPath.substring('/friend/'.length);
      return _buildFriendsLocation(code, parsed.queryParameters);
    }
    return _appendQuery(normalizedPath, parsed.query);
  }

  static String? _resolveHostBasedUri(Uri parsed) {
    final host = parsed.host;
    final segments = parsed.pathSegments;
    return switch (host) {
      'friend' => _buildFriendsLocation(
        segments.isNotEmpty ? segments.first : parsed.queryParameters['code'],
        parsed.queryParameters,
      ),
      'home' ||
      'map' ||
      'stats' ||
      'shop' ||
      'profile' ||
      'ledger' => _appendQuery(
        segments.isEmpty ? '/$host' : '/$host/${segments.join('/')}',
        parsed.query,
      ),
      _ => null,
    };
  }

  static String _buildFriendsLocation(
    String? code,
    Map<String, String> existingQuery,
  ) {
    final merged = Map<String, String>.of(existingQuery);
    if (code != null && code.isNotEmpty) {
      merged['code'] = code;
    }
    if (merged.isEmpty) {
      return '/profile/friends';
    }
    return Uri(path: '/profile/friends', queryParameters: merged).toString();
  }

  static String _appendQuery(String path, String query) =>
      query.isEmpty ? path : '$path?$query';

  @override
  State<EcoTrackApp> createState() => _EcoTrackAppState();
}

final class _EcoTrackAppState()
    extends State<EcoTrackApp>
    with WidgetsBindingObserver {
  static const Duration _gateCheckCooldown = Duration(seconds: 5);

  late final AuthBloc _authBloc;
  late final bool _ownsAuthBloc;
  late final AuthRouterListenable _routerListenable;
  late final GoRouter _router;
  late final SyncStatusCubit _syncStatusCubit;
  StreamSubscription<String>? _deepLinkSub;
  StreamSubscription<AuthState>? _authStateSub;
  bool _isCheckingGateSession = false;
  DateTime? _lastGateCheckAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final deps = widget.dependencies;
    final overrideAuth = widget.overrideAuthBloc;
    _ownsAuthBloc = overrideAuth == null;
    _authBloc =
        overrideAuth ??
        AuthBloc(
          deps.authRepository,
          deps.profileRepository,
          onSessionActivated: () => _onSessionActivated(deps),
          onSessionCleared: () => _onSessionCleared(deps),
        );

    _authStateSub = _authBloc.stream.listen((_) {
      _isCheckingGateSession = false;
    });

    deps.sessionCallbacks.onForceLogout = () {
      _authBloc.add(const AuthForceLogoutRequested());
    };
    deps.sessionCallbacks.onGateError = (error) {
      if (error.clientAction == ClientErrorAction.openConsentScreen ||
          error.clientAction == ClientErrorAction.openPhoneModal) {
        _handleGateResolutionError(error);
      } else {
        EcoTopBannerOverlay.instance.show(error);
      }
    };
    deps.sessionCallbacks.onPermanentError = EcoTopBannerOverlay.instance.show;

    _syncStatusCubit = SyncStatusCubit(
      deps.outboxDispatcher,
      deps.stepSensorBridge,
    );

    _routerListenable = AuthRouterListenable(_authBloc);
    _router = AppRouter.createRouter(
      authBloc: _authBloc,
      refreshListenable: _routerListenable,
      onRequestStepsPermission: deps.stepSensorBridge.requestPermissions,
      onRequestGpsPermission:
          deps.gpsForegroundService.checkAndRequestPermission,
    );

    _deepLinkSub = deps.pushProvider.onNotificationTapDeepLink.listen((uri) {
      final target = EcoTrackApp.resolveDeepLinkLocation(uri);
      if (target != null) {
        _router.go(target);
      }
    });

    if (_ownsAuthBloc) {
      _authBloc.add(const AuthSessionChecked());
    }
  }

  void _handleGateResolutionError(AppError error) {
    final currentState = _authBloc.state;
    if (currentState is AuthConsentResolutionRequired ||
        currentState is AuthGooglePhoneRequired ||
        currentState is AuthAuthenticating ||
        currentState is AuthUnauthenticated ||
        currentState is AuthOnboardingRequired) {
      return;
    }
    if (currentState is! AuthAuthenticated) {
      EcoTopBannerOverlay.instance.show(error);
      return;
    }
    final now = DateTime.now();
    final lastCheck = _lastGateCheckAt;
    final inCooldown =
        lastCheck != null && now.difference(lastCheck) < _gateCheckCooldown;
    if (_isCheckingGateSession || inCooldown) {
      return;
    }
    _isCheckingGateSession = true;
    _lastGateCheckAt = now;
    _authBloc.add(const AuthSessionChecked());
  }

  Future<void> _onSessionActivated(AppDependencies deps) {
    deps.outboxDispatcher.resumeQueue();
    deps.outboxDispatcher.startWorker();
    deps.stepSensorBridge.startLivePedometer();
    return Future<void>.value();
  }

  Future<void> _onSessionCleared(AppDependencies deps) async {
    deps.outboxDispatcher.stopWorker();
    await deps.gpsForegroundService.stopTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _authBloc.state is AuthAuthenticated) {
      unawaited(_syncStatusCubit.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_deepLinkSub?.cancel());
    unawaited(_authStateSub?.cancel());
    unawaited(_syncStatusCubit.close());
    _router.dispose();
    _routerListenable.dispose();
    if (_ownsAuthBloc) {
      unawaited(_authBloc.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = widget.dependencies;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: deps.authRepository),
        RepositoryProvider<ProfileRepository>.value(
          value: deps.profileRepository,
        ),
        RepositoryProvider<FriendsRepository>.value(
          value: deps.friendsRepository,
        ),
        RepositoryProvider<MapActivityRepository>.value(
          value: deps.mapActivityRepository,
        ),
        RepositoryProvider<StatsRepository>.value(value: deps.statsRepository),
        RepositoryProvider<ShopRepository>.value(value: deps.shopRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: _authBloc),
          BlocProvider<SyncStatusCubit>.value(value: _syncStatusCubit),
          BlocProvider<HomeCubit>(
            create: (_) =>
                HomeCubit(deps.profileRepository, deps.mapActivityRepository),
          ),
          BlocProvider<StatsCubit>(
            create: (_) => StatsCubit(
              deps.statsRepository,
              deps.friendsRepository,
              deps.mapActivityRepository,
              () => deps.lastStatsOfflineCachedAtMs,
            ),
          ),
          BlocProvider<MapActivityBloc>(
            create: (_) => MapActivityBloc(
              deps.mapActivityRepository,
              deps.profileRepository,
            ),
          ),
          BlocProvider<ShopBloc>(
            create: (_) =>
                ShopBloc(deps.shopRepository, deps.profileRepository),
          ),
          BlocProvider<ProfileSettingsCubit>(
            create: (_) => ProfileSettingsCubit(
              deps.profileRepository,
              deps.authRepository,
            ),
          ),
          BlocProvider<FriendsCubit>(
            create: (_) => FriendsCubit(deps.friendsRepository),
          ),
          BlocProvider<VehicleCubit>(
            create: (_) => VehicleCubit(deps.profileRepository),
          ),
        ],
        child: MaterialApp.router(
          title: 'EcoTrack',
          debugShowCheckedModeBanner: false,
          theme: EcoTheme.lightTheme,
          routerConfig: _router,
          locale: const Locale('ru', 'RU'),
          supportedLocales: const [Locale('ru', 'RU')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) =>
              EcoTopBannerHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
