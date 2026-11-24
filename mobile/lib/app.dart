import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/router/app_router.dart';
import 'package:ecotrack_mobile/core/sensors/gps_foreground_service.dart';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/data/auth_repository_impl.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/home_mascot/data/home_repository_impl.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_cubit.dart';
import 'package:ecotrack_mobile/features/map_activity/data/map_repository_impl.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_bloc.dart';
import 'package:ecotrack_mobile/features/profile_social/data/profile_repository_impl.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_cubit.dart';
import 'package:ecotrack_mobile/features/shop/data/shop_repository_impl.dart';
import 'package:ecotrack_mobile/features/shop/presentation/shop_bloc.dart';
import 'package:ecotrack_mobile/features/stats/data/stats_repository_impl.dart';
import 'package:ecotrack_mobile/features/stats/presentation/stats_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:go_router/go_router.dart';

class EcoTrackApp extends StatefulWidget {
  const EcoTrackApp({super.key, this.sqliteDb});

  final SqliteDatabase? sqliteDb;

  @override
  State<EcoTrackApp> createState() => _EcoTrackAppState();
}

class _EcoTrackAppState extends State<EcoTrackApp> {
  late final AuthCubit _authCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authCubit = AuthCubit(AuthRepositoryImpl())..checkSession();
    _router = AppRouter.createRouter(_authCubit);
  }

  @override
  void dispose() {
    _authCubit.close();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.sqliteDb ?? SqliteDatabase.instance;
    final gpsService = GpsForegroundService();

    final homeRepo = HomeRepositoryImpl(db: db);
    final statsRepo = StatsRepositoryImpl();
    final mapRepo = MapRepositoryImpl(db: db);
    final shopRepo = ShopRepositoryImpl();
    final profileRepo = ProfileRepositoryImpl(db: db);

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: _authCubit),
        BlocProvider<HomeCubit>(
          create: (_) => HomeCubit(homeRepo)..loadTodaySummary(),
        ),
        BlocProvider<StatsCubit>(
          create: (_) => StatsCubit(statsRepo)..loadStats(),
        ),
        BlocProvider<MapActivityCubit>(
          create: (_) =>
              MapActivityCubit(repository: mapRepo, gpsService: gpsService)
                ..loadMapData(),
        ),
        BlocProvider<ShopCubit>(
          create: (_) => ShopCubit(shopRepo)..loadShopData(),
        ),
        BlocProvider<ProfileCubit>(
          create: (_) => ProfileCubit(profileRepo)..loadProfile(),
        ),
      ],
      child: MaterialApp.router(
        title: 'EcoTrack',
        debugShowCheckedModeBanner: false,
        theme: EcoTheme.darkTheme,
        routerConfig: _router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
      ),
    );
  }
}
