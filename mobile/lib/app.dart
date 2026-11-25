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
  @override
  State<EcoTrackApp> createState() => _EcoTrackAppState();
}

final class _EcoTrackAppState()
    extends State<EcoTrackApp>
    with WidgetsBindingObserver {
  late final AuthBloc _authBloc;
  late final bool _ownsAuthBloc;
  late final AuthRouterListenable _routerListenable;
  late final GoRouter _router;
  late final SyncStatusCubit _syncStatusCubit;
  StreamSubscription<String>? _deepLinkSub;

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

    deps.sessionCallbacks.onForceLogout = () {
      _authBloc.add(const AuthForceLogoutRequested());
    };
    deps.sessionCallbacks.onGateError = (error) {
      if (error.clientAction == ClientErrorAction.openConsentScreen ||
          error.clientAction == ClientErrorAction.openPhoneModal) {
        _authBloc.add(const AuthSessionChecked());
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
      final parsed = Uri.tryParse(uri);
      if (parsed != null && parsed.path.isNotEmpty) {
        _router.go(parsed.path);
      }
    });

    if (_ownsAuthBloc) {
      _authBloc.add(const AuthSessionChecked());
    }
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
