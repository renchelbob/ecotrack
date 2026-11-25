import 'dart:async';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';
import 'package:ecotrack_mobile/core/push/fcm_push_provider.dart';
import 'package:ecotrack_mobile/core/push/push_provider.dart';
import 'package:ecotrack_mobile/core/sensors/gps_foreground_service.dart';
import 'package:ecotrack_mobile/core/sensors/step_sensor_bridge.dart';
import 'package:ecotrack_mobile/features/auth_fz152/data/auth_repository_impl.dart';
import 'package:ecotrack_mobile/features/auth_fz152/data/oauth_pkce_client.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/map_activity/data/map_repository_impl.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/data/friends_repository_impl.dart';
import 'package:ecotrack_mobile/features/profile_social/data/profile_repository_impl.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/shop/data/shop_repository_impl.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:ecotrack_mobile/features/stats/data/stats_repository_impl.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';

final class AppSessionCallbacks() {
  void Function()? onForceLogout;
  void Function(AppError error)? onGateError;
  void Function(AppError error)? onPermanentError;
}

final class const CoreDependencies({
  required final SqliteDatabase sqliteDb,
  required final ErrorCatalogRegistry errorCatalog,
  required final TokenStore tokenStore,
  required final DioClient dioClient,
  required final OutboxDispatcher outboxDispatcher,
});

final class const SensorAndPushDependencies({
  required final StepSensorBridge stepSensorBridge,
  required final GpsForegroundService gpsForegroundService,
  required final PushProvider pushProvider,
  required final AppSessionCallbacks sessionCallbacks,
});

final class const RepositoryDependencies({
  required final AuthRepository authRepository,
  required final ProfileRepository profileRepository,
  required final FriendsRepository friendsRepository,
  required final MapActivityRepository mapActivityRepository,
  required final StatsRepository statsRepository,
  required final ShopRepository shopRepository,
});

final class const AppDependencies({
  required final CoreDependencies core,
  required final SensorAndPushDependencies platform,
  required final RepositoryDependencies repositories,
}) {
  SqliteDatabase get sqliteDb => core.sqliteDb;
  ErrorCatalogRegistry get errorCatalog => core.errorCatalog;
  TokenStore get tokenStore => core.tokenStore;
  DioClient get dioClient => core.dioClient;
  OutboxDispatcher get outboxDispatcher => core.outboxDispatcher;
  StepSensorBridge get stepSensorBridge => platform.stepSensorBridge;
  GpsForegroundService get gpsForegroundService =>
      platform.gpsForegroundService;
  PushProvider get pushProvider => platform.pushProvider;
  AppSessionCallbacks get sessionCallbacks => platform.sessionCallbacks;

  AuthRepository get authRepository => repositories.authRepository;
  ProfileRepository get profileRepository => repositories.profileRepository;
  FriendsRepository get friendsRepository => repositories.friendsRepository;
  MapActivityRepository get mapActivityRepository =>
      repositories.mapActivityRepository;
  StatsRepository get statsRepository => repositories.statsRepository;
  ShopRepository get shopRepository => repositories.shopRepository;

  int? get lastStatsOfflineCachedAtMs {
    final repo = statsRepository;
    if (repo is StatsRepositoryImpl) {
      return repo.lastOfflineCachedAtMs;
    }
    return null;
  }

  static Future<AppDependencies> create({
    SqliteDatabase? overrideDb,
    TokenStore? overrideTokenStore,
    DioClient? overrideDioClient,
    OAuthPkceClient? overridePkceClient,
    PushProvider? overridePushProvider,
  }) async {
    final db = overrideDb ?? SqliteDatabase.instance;
    if (!db.isInitialized) {
      await db.initialize();
    }

    final catalog = ErrorCatalogRegistry.instance;
    final tokenStore = overrideTokenStore ?? SecureTokenStore();
    final callbacks = AppSessionCallbacks();

    final dioClient =
        overrideDioClient ??
        DioClient(
          tokenStore: tokenStore,
          onForceLogout: () => callbacks.onForceLogout?.call(),
          onGateError: (err) => callbacks.onGateError?.call(err),
        );

    final outbox = OutboxDispatcher(
      db: db,
      networkSender: OutboxDispatcher.senderFromDioClient(dioClient),
      onForceLogout: () => callbacks.onForceLogout?.call(),
      onGateError: (err) => callbacks.onGateError?.call(err),
      onPermanentError: (err) => callbacks.onPermanentError?.call(err),
    );

    final stepBridge = StepSensorBridge(db: db);
    final gpsService = GpsForegroundService(
      db: db,
      outboxDispatcher: outbox,
      stepBridge: stepBridge,
    );
    final pushProvider =
        overridePushProvider ?? FcmPushProvider(dioClient: dioClient);

    final profileRepo = ProfileRepositoryImpl(
      dioClient,
      db,
      tokenStore,
      outbox,
    );
    final friendsRepo = FriendsRepositoryImpl(dioClient, db, outbox);
    final authRepo = AuthRepositoryImpl(
      dioClient,
      tokenStore,
      profileRepo,
      overridePkceClient ?? OAuthPkceClient(),
      pushProvider,
    );
    final mapRepo = MapRepositoryImpl(
      dioClient,
      db,
      outbox,
      stepBridge,
      gpsService,
    );
    final statsRepo = StatsRepositoryImpl(dioClient, null, db);
    final shopRepo = ShopRepositoryImpl(dioClient);

    return AppDependencies(
      core: CoreDependencies(
        sqliteDb: db,
        errorCatalog: catalog,
        tokenStore: tokenStore,
        dioClient: dioClient,
        outboxDispatcher: outbox,
      ),
      platform: SensorAndPushDependencies(
        stepSensorBridge: stepBridge,
        gpsForegroundService: gpsService,
        pushProvider: pushProvider,
        sessionCallbacks: callbacks,
      ),
      repositories: RepositoryDependencies(
        authRepository: authRepo,
        profileRepository: profileRepo,
        friendsRepository: friendsRepo,
        mapActivityRepository: mapRepo,
        statsRepository: statsRepo,
        shopRepository: shopRepo,
      ),
    );
  }

  Future<void> dispose() async {
    outboxDispatcher.dispose();
    await gpsForegroundService.dispose();
    await stepSensorBridge.dispose();
    await pushProvider.dispose();
    if (profileRepository case final ProfileRepositoryImpl p) {
      await p.dispose();
    }
    if (authRepository case final AuthRepositoryImpl a) {
      await a.dispose();
    }
    if (mapActivityRepository case final MapRepositoryImpl m) {
      await m.dispose();
    }
    await sqliteDb.close();
  }
}
