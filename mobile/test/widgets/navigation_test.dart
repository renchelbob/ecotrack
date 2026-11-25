import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/app.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/di/app_dependencies.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';
import 'package:ecotrack_mobile/core/push/push_provider.dart';
import 'package:ecotrack_mobile/core/router/app_router.dart';
import 'package:ecotrack_mobile/core/router/floating_bottom_nav_bar.dart';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/data/oauth_pkce_client.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/onboarding_screen.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

UserProfile _sampleProfile({
  bool requiresFormalPhone = false,
  bool is152fzConsentActive = true,
}) => UserProfile(
  id: 'usr-test-1',
  email: 'tester@vyatsu.ru',
  displayName: 'Тестовый Пользователь',
  friendCode: 'ECO-TEST-2026',
  requiresFormalPhone: requiresFormalPhone,
  pointsBalance: 150,
  lifetimePointsEarned: 300,
  lifetimeCo2SavedGrams: 1200,
  currentStreakDays: 3,
  longestStreakDays: 5,
  streakFreezeCount: 1,
  isGpsTrackingEnabled: false,
  isStatsVisibleToFriends: true,
  is152fzConsentActive: is152fzConsentActive,
  mascot: const MascotVisualState(
    mood: MascotMoodState.happy,
    dailyGoalProgressRatio: 0.6,
  ),
  createdAt: '2026-11-24T10:00:00Z',
);

final class _FakeDioAdapter() implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final Object body;
    if (path.contains('/users/me')) {
      body = _sampleProfile().toJson();
    } else if (path.contains('/activity/daily/')) {
      body = {
        'summary': {
          'id': 'sum-1',
          'activity_date': '2026-11-24',
          'raw_sensor_steps': 0,
          'validated_steps': 0,
          'stride_length_cm': 74,
          'total_step_distance_m': 0.0,
          'allocated_gps_distance_m': 0.0,
          'unallocated_step_distance_m': 0.0,
          'allocated_co2_saved_grams': 0,
          'auto_default_co2_saved_grams': 0,
          'total_co2_saved_grams': 0,
          'points_awarded_for_day': 0,
          'points_delta_applied': 0,
          'points_balance': 150,
          'is_auto_calculated': true,
          'antifraud_flagged': false,
        },
        'is_editable': true,
        'total_gps_walking_distance_m': 0.0,
        'track_points': const <Object?>[],
        'allocations': const <Object?>[],
        'co2_delta_applied_grams': 0,
      };
    } else {
      body = const <String, Object?>{'ok': true};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _StubAuthRepo() implements AuthRepository {
  @override
  Future<Result<AuthSession?, AppError>> restoreSession() async =>
      const Ok(null);

  @override
  Future<Result<AuthSession, AppError>> signInWithOAuth({
    required AuthProviderType provider,
    required ConsentScopeObject consentScope,
  }) async => Ok(
    AuthSession(
      accessToken: 'tok',
      refreshToken: 'ref',
      expiresInSeconds: 900,
      isForeignProviderLabMode: provider == AuthProviderType.google,
      user: _sampleProfile(
        requiresFormalPhone: provider == AuthProviderType.google,
      ),
    ),
  );

  @override
  Future<Result<AuthSession, AppError>> signInLocally({
    required ConsentScopeObject consentScope,
  }) async => Ok(
    AuthSession(
      accessToken: 'local-preview-access-token',
      refreshToken: 'local-preview-refresh-token-ecotrack',
      expiresInSeconds: 86400,
      isForeignProviderLabMode: false,
      user: _sampleProfile(),
    ),
  );

  @override
  Future<Result<UserProfile, AppError>> submitGoogleFormalPhone(
    String phoneE164,
  ) async => Ok(_sampleProfile());

  @override
  Future<Result<ConsentHistoryListResponse, AppError>>
  getConsentHistory() async => const Ok(
    ConsentHistoryListResponse(is152fzConsentActive: true, entries: []),
  );

  @override
  Future<Result<ConsentJournalEntry, AppError>> recordConsent({
    required String policyVersion,
    required String action,
    required ConsentScopeObject scope,
  }) async => const Ok(
    ConsentJournalEntry(
      id: 'c-1',
      policyVersion: '1.0.0-2026',
      action: ConsentActionType.granted,
      consentScope: ConsentScopeObject(
        personalData152fz: true,
        healthStepsSensor: true,
        backgroundGeolocation: false,
      ),
      recordedAt: '2026-11-24T10:00:00Z',
    ),
  );

  @override
  Future<Result<void, AppError>> logout() async => const Ok(null);

  @override
  Future<bool> hasCompletedOnboarding() async => true;

  @override
  Future<void> markOnboardingStepSeen() async {}
}

final class _StubPushProvider() implements PushProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<String?> getDevicePushToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushMessagePayload> get onForegroundMessage => const Stream.empty();

  @override
  Stream<String> get onNotificationTapDeepLink => const Stream.empty();

  @override
  Future<void> registerCurrentToken({
    required String deviceId,
    String platform = 'fcm_android',
  }) async {}

  @override
  Future<void> unregisterCurrentToken() async {}

  @override
  Future<void> dispose() async {}
}

final class _StubProfileRepo() implements ProfileRepository {
  @override
  Stream<UserProfile> watchUserProfile() => const Stream.empty();

  @override
  Future<Result<UserProfile, AppError>> getProfile({
    bool forceRefresh = false,
  }) async => Ok(_sampleProfile());

  @override
  Future<Result<UserProfile, AppError>> updateProfile(
    UpdateUserProfileRequest req,
  ) async => Ok(_sampleProfile());

  @override
  Future<Result<UserVehicle, AppError>> getMyVehicle() async =>
      Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<UserVehicle, AppError>> upsertVehicle(
    String vehicleName,
    FuelType fuel,
    double consumptionPer100km,
  ) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<void, AppError>> deleteVehicle() async => const Ok(null);

  @override
  Future<Result<List<TransportPresetItem>, AppError>>
  listTransportPresets() async => const Ok([]);

  @override
  Future<Result<BadgesListResponse, AppError>> listBadges() async =>
      const Ok(BadgesListResponse(unlockedCount: 0, totalCount: 0, badges: []));

  @override
  Future<Result<MascotInventoryResponse, AppError>>
  listMascotAccessories() async =>
      const Ok(MascotInventoryResponse(accessories: []));

  @override
  Future<Result<UserProfile, AppError>> equipMascotAccessory(
    String? accessoryCode,
  ) async => Ok(_sampleProfile());

  @override
  Future<Result<AccountDeletionReceipt, AppError>> deleteAccount(
    String reason,
    String confirmationPhrase,
  ) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<void> cacheProfile(
    UserProfile profile, {
    AuthProviderType? authProvider,
    bool? isForeignLabMode,
  }) async {}

  @override
  Future<UserProfile?> getCachedProfileSnapshot() async => _sampleProfile();

  @override
  Future<void> updateLocalConsentActive({required bool isActive}) async {}

  @override
  Future<void> clearAllLocalUserData() async {}
}

final class _StubMapActivityRepo() implements MapActivityRepository {
  @override
  Stream<DailyActivitySummary> watchDailySummary(String activityDate) =>
      const Stream.empty();

  @override
  Future<Result<DailyActivitySummary, AppError>> getTodaySummary() async =>
      Ok(DailyActivitySummary.emptyForDate('2026-11-24', pointsBalance: 150));

  @override
  Future<Result<DailyActivitySummary, AppError>> syncDailySteps({
    required String activityDate,
    required int rawSensorSteps,
    bool manualRefresh = false,
  }) async =>
      Ok(DailyActivitySummary.emptyForDate(activityDate, pointsBalance: 150));

  @override
  Future<Result<DailyActivityDetail, AppError>> getDailyActivityDetail(
    String activityDate,
  ) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<DailyActivityDetail, AppError>> saveRouteAllocations({
    required String activityDate,
    required List<RouteSegmentAllocationInput> allocations,
  }) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<DailyActivityDetail, AppError>> deleteRouteAllocation({
    required String activityDate,
    required String allocationId,
  }) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<WastePointsBboxResponse, AppError>> queryWastePoints({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    required int zoom,
    List<WasteFractionCode> fractions = const <WasteFractionCode>[],
  }) async => const Ok(
    WastePointsBboxResponse(
      attributionBannerRu: WastePointsBboxResponse.defaultAttributionBannerRu,
      totalReturned: 0,
      points: [],
    ),
  );

  @override
  Future<Result<WastePointDetail, AppError>> getWastePointDetail(
    String pointId,
  ) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<WastePointReportCreatedResponse, AppError>>
  submitWastePointReport({
    required String pointId,
    required ReportType reportType,
    String? comment,
    required double userLat,
    required double userLon,
  }) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<Result<WastePointDetail, AppError>> suggestWastePoint(
    SuggestWastePointRequest req,
  ) async => Err(AppError.fromCode('INTERNAL_SERVER_ERROR'));

  @override
  Future<void> setGpsTrackingEnabled(
    bool enabled, {
    int? intervalSeconds,
  }) async {}

  @override
  Stream<({double lat, double lon, double accuracy})>
  get currentPositionStream => const Stream.empty();

  @override
  Future<({double lat, double lon, double accuracy})?>
  getLastKnownOrCurrentPosition() async => null;
}

void main() {
  late AppDependencies deps;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ErrorCatalogRegistry.instance.loadFromJsonString('''
{
  "errors": {
    "INTERNAL_SERVER_ERROR": {
      "code": "INTERNAL_SERVER_ERROR",
      "http_status": 500,
      "domain": "infrastructure",
      "retryable": true,
      "client_action": "show_banner",
      "ui_message_ru": "Ошибка сервера"
    }
  }
}
''');
    final tokenStore = InMemoryTokenStore();
    final schemaSql = File('assets/db/client_sqlite_schema.sql')
        .readAsStringSync();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteDatabase.instance.initialize(
      overrideDb: db,
      schemaSqlOverride: schemaSql,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'))
      ..httpClientAdapter = _FakeDioAdapter();
    deps = await AppDependencies.create(
      overrideDb: SqliteDatabase.instance,
      overrideTokenStore: tokenStore,
      overrideDioClient: DioClient(tokenStore: tokenStore, dio: dio),
      overridePkceClient: OAuthPkceClient(),
      overridePushProvider: _StubPushProvider(),
    );
  });

  tearDownAll(() async {
    await deps.dispose();
  });

  group('AppRouter & 5-Tab Shell Navigation Tests', () {
    testWidgets(
      'Onboarding Step 3 renders 152-FZ consent gate, enables Начать when checked, and shows OAuth sheet',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final authBloc = AuthBloc(_StubAuthRepo(), _StubProfileRepo());

        await tester.pumpWidget(
          MaterialApp(
            theme: EcoTheme.lightTheme,
            home: BlocProvider<AuthBloc>.value(
              value: authBloc,
              child: const OnboardingScreen(initialStep: 3),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Я согласен на обработку персональных данных'),
          findsOneWidget,
        );
        final checkboxFinder = find.byType(Checkbox);
        expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

        final startBtnFinder = find.widgetWithText(OutlinedButton, 'Начать');
        expect(tester.widget<OutlinedButton>(startBtnFinder).onPressed, isNull);

        await tester.tap(checkboxFinder);
        await tester.pump();
        expect(
          tester.widget<OutlinedButton>(startBtnFinder).onPressed,
          isNotNull,
        );

        await tester.tap(find.text('Другие способы входа (OAuth)'));
        await tester.pumpAndSettle();

        expect(find.text('Войти через Яндекс ID'), findsOneWidget);
        expect(find.text('Войти через VK ID'), findsOneWidget);
        expect(find.text('Войти через Google (Лаб. режим)'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(authBloc.close);
      },
    );

    testWidgets(
      'AppRouter redirects AuthAuthenticated to /home and renders 5-tab FloatingBottomNavBar',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final stubProfileRepo = _StubProfileRepo();
        final testDeps = AppDependencies(
          core: deps.core,
          platform: deps.platform,
          repositories: RepositoryDependencies(
            authRepository: _StubAuthRepo(),
            profileRepository: stubProfileRepo,
            friendsRepository: deps.friendsRepository,
            mapActivityRepository: _StubMapActivityRepo(),
            statsRepository: deps.statsRepository,
            shopRepository: deps.shopRepository,
          ),
        );
        final authBloc = AuthBloc(_StubAuthRepo(), stubProfileRepo)
          ..emit(AuthAuthenticated(_sampleProfile(), false));

        await tester.pumpWidget(
          EcoTrackApp(dependencies: testDeps, overrideAuthBloc: authBloc),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(FloatingBottomNavBar), findsOneWidget);
        expect(find.byTooltip('Статистика'), findsOneWidget);
        expect(find.byTooltip('Калькулятор'), findsOneWidget);
        expect(find.byTooltip('Главная'), findsOneWidget);
        expect(find.byTooltip('Магазин'), findsOneWidget);
        expect(find.byTooltip('Профиль'), findsOneWidget);

        final listenable = AuthRouterListenable(authBloc);
        final router = AppRouter.createRouter(
          authBloc: authBloc,
          refreshListenable: listenable,
        );
        expect(router.routeInformationProvider.value.uri.path, equals('/home'));

        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        listenable.dispose();
        await tester.runAsync(authBloc.close);
      },
    );
  });
}
