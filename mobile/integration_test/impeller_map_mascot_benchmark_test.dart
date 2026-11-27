import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_cubit.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_screen.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/fox_mascot_widget.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_bloc.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/screens/map_activity_screen.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const List<int> _transparentPngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
];

String _todayIso() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

UserProfile _benchmarkProfile() => const UserProfile(
  id: '01935c10-0000-7000-8000-00000000b001',
  email: 'bench@vyatsu.ru',
  displayName: 'Бенчмарк',
  friendCode: 'ECO-BNCH-0001',
  requiresFormalPhone: false,
  pointsBalance: 850,
  lifetimePointsEarned: 1500,
  lifetimeCo2SavedGrams: 12400,
  currentStreakDays: 14,
  longestStreakDays: 14,
  streakFreezeCount: 2,
  isGpsTrackingEnabled: false,
  isStatsVisibleToFriends: true,
  is152fzConsentActive: true,
  mascot: .new(
    mood: .thriving,
    dailyGoalProgressRatio: 0.95,
    equippedAccessoryCode: 'firefly_aura',
    unlockedAccessoryCodes: ['firefly_aura'],
  ),
  createdAt: '2026-11-24T10:00:00Z',
);

final class _OfflineTileHttpOverrides() extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OfflineTileHttpClient();
}

final class _OfflineTileHttpClient() implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _OfflineTileRequest(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _OfflineTileRequest(url);

  @override
  void close({bool force = false}) {
    return;
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('HttpClient.${invocation.memberName}');
}

final class _OfflineTileRequest(final Uri _uri) implements HttpClientRequest {
  @override
  final HttpHeaders headers = _EmptyHttpHeaders();

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = 0;

  @override
  bool bufferOutput = true;

  @override
  String get method => 'GET';

  @override
  Uri get uri => _uri;

  @override
  Future<HttpClientResponse> close() async => _OfflineTileResponse();

  @override
  void add(List<int> data) {
    return;
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('HttpClientRequest.${invocation.memberName}');
}

final class _OfflineTileResponse()
    extends Stream<List<int>>
    implements HttpClientResponse {
  final Uint8List _bytes = .fromList(_transparentPngBytes);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers => _EmptyHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpClientResponseCompressionState get compressionState => .notCompressed;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('HttpClientResponse.${invocation.memberName}');
}

final class _EmptyHttpHeaders() implements HttpHeaders {
  @override
  DateTime? date;

  @override
  DateTime? expires;

  @override
  DateTime? ifModifiedSince;

  @override
  String? host;

  @override
  int? port;

  @override
  ContentType? contentType;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = false;

  @override
  bool chunkedTransferEncoding = false;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    return;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    return;
  }

  @override
  void remove(String name, Object value) {
    return;
  }

  @override
  void removeAll(String name) {
    return;
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    return;
  }

  @override
  void noFolding(String name) {
    return;
  }

  @override
  void clear() {
    return;
  }

  @override
  String? value(String name) => null;

  @override
  List<String>? operator [](String name) => null;
}

final class _BenchmarkProfileRepo() implements ProfileRepository {
  @override
  Stream<UserProfile> watchUserProfile() => const Stream.empty();

  @override
  Future<Result<UserProfile, AppError>> getProfile({
    bool forceRefresh = false,
  }) async => Ok(_benchmarkProfile());

  @override
  Future<Result<UserProfile, AppError>> updateProfile(
    UpdateUserProfileRequest req,
  ) async => Ok(_benchmarkProfile());

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
  listTransportPresets() async => const Ok([
    TransportPresetItem(
      modeCode: .bus,
      displayNameRu: 'Автобус / электробус',
      displayNameEn: 'Bus',
      co2GramsPerKm: 82.0,
      co2GramsPerMeter: 0.082,
      isPersonalVehicleSlot: false,
    ),
    TransportPresetItem(
      modeCode: .carSedan,
      displayNameRu: 'Авто (седан C/D-класс)',
      displayNameEn: 'Car (Sedan C/D)',
      co2GramsPerKm: 192.0,
      co2GramsPerMeter: 0.192,
      isPersonalVehicleSlot: false,
    ),
  ]);

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
  ) async => Ok(_benchmarkProfile());

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
  }) => Future<void>.value();

  @override
  Future<UserProfile?> getCachedProfileSnapshot() async => _benchmarkProfile();

  @override
  Future<void> updateLocalConsentActive({required bool isActive}) =>
      Future<void>.value();

  @override
  Future<void> clearAllLocalUserData() => Future<void>.value();
}

final class _BenchmarkMapRepo(final SqliteDatabase _db)
    implements MapActivityRepository {
  @override
  Stream<DailyActivitySummary> watchDailySummary(String activityDate) =>
      const Stream.empty();

  @override
  Future<Result<DailyActivitySummary, AppError>> getTodaySummary() async {
    final rows = await _db.database.query(
      'local_daily_step_summaries',
      where: 'activity_date = ?',
      whereArgs: [_todayIso()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return Ok(
        DailyActivitySummary.emptyForDate(_todayIso(), pointsBalance: 850),
      );
    }
    return DailyActivitySummary.fromSqliteRow(rows.first, pointsBalance: 850);
  }

  @override
  Future<Result<DailyActivitySummary, AppError>> syncDailySteps({
    required String activityDate,
    required int rawSensorSteps,
    bool manualRefresh = false,
  }) => getTodaySummary();

  @override
  Future<Result<DailyActivityDetail, AppError>> getDailyActivityDetail(
    String activityDate,
  ) async {
    final summaryRes = await getTodaySummary();
    final summary =
        summaryRes.valueOrNull ??
        DailyActivitySummary.emptyForDate(activityDate, pointsBalance: 850);
    final ptRows = await _db.database.query(
      'local_gps_track_points',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      orderBy: 'seq_no ASC',
    );
    final trackPoints = ptRows
        .map((r) => GpsTrackPointClassified.fromSqliteRow(r).valueOrNull)
        .whereType<GpsTrackPointClassified>()
        .toList();
    final allocRows = await _db.database.query(
      'local_route_segment_allocations',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      orderBy: 'start_seq_no ASC',
    );
    final allocations = allocRows
        .map((r) => RouteSegmentAllocationItem.fromSqliteRow(r).valueOrNull)
        .whereType<RouteSegmentAllocationItem>()
        .toList();
    return Ok(
      DailyActivityDetail(
        summary: summary,
        isEditable: true,
        totalGpsWalkingDistanceM: 7600.0,
        trackPoints: trackPoints,
        allocations: allocations,
        co2DeltaAppliedGrams: 0,
      ),
    );
  }

  @override
  Future<Result<DailyActivityDetail, AppError>> saveRouteAllocations({
    required String activityDate,
    required List<RouteSegmentAllocationInput> allocations,
  }) => getDailyActivityDetail(activityDate);

  @override
  Future<Result<DailyActivityDetail, AppError>> deleteRouteAllocation({
    required String activityDate,
    required String allocationId,
  }) => getDailyActivityDetail(activityDate);

  @override
  Future<Result<WastePointsBboxResponse, AppError>> queryWastePoints({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    required int zoom,
    List<WasteFractionCode> fractions = const [],
  }) async {
    final rows = await _db.database.query(
      'cached_waste_points',
      where: 'lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
      whereArgs: [minLat, maxLat, minLon, maxLon],
    );
    final points = rows
        .map((r) => WastePointMapItem.fromSqliteRow(r).valueOrNull)
        .whereType<WastePointMapItem>()
        .toList();
    return Ok(
      WastePointsBboxResponse(
        attributionBannerRu: WastePointsBboxResponse.defaultAttributionBannerRu,
        totalReturned: points.length,
        points: points,
      ),
    );
  }

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
  Future<void> setGpsTrackingEnabled(bool enabled, {int? intervalSeconds}) =>
      Future<void>.value();

  @override
  Stream<({double lat, double lon, double accuracy})>
  get currentPositionStream => const Stream.empty();

  @override
  Future<({double lat, double lon, double accuracy})?>
  getLastKnownOrCurrentPosition() async =>
      (lat: 58.6035, lon: 49.6680, accuracy: 6.0);
}

Future<void> _seedBenchmarkSqlite(SqliteDatabase sqliteDb) async {
  final db = sqliteDb.database;
  final date = _todayIso();
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  await db.transaction((txn) async {
    await txn.insert('local_user_profile', {
      'user_id': '01935c10-0000-7000-8000-00000000b001',
      'display_name': 'Бенчмарк',
      'friend_code': 'ECO-BNCH-0001',
      'auth_provider': 'yandex',
      'points_balance': 850,
      'equipped_accessory_code': 'firefly_aura',
      'updated_at_ms': nowMs,
    });
    await txn.insert('local_daily_step_summaries', {
      'activity_date': date,
      'user_id': '01935c10-0000-7000-8000-00000000b001',
      'raw_sensor_steps': 10200,
      'validated_steps': 10200,
      'total_step_distance_m': 7600.0,
      'allocated_gps_distance_m': 3000.0,
      'unallocated_step_distance_m': 4600.0,
      'allocated_co2_saved_grams': 246,
      'auto_default_co2_saved_grams': 377,
      'total_co2_saved_grams': 623,
      'points_awarded_for_day': 102,
      'last_sensor_read_at_ms': nowMs,
    });
    await _seedGpsAndAllocations(txn, date, nowMs);
    await _seedWastePoints(txn, nowMs);
  });
}

Future<void> _seedGpsAndAllocations(
  Transaction txn,
  String date,
  int nowMs,
) async {
  const classes = ['walking', 'indoor_pacing', 'vehicle_suspected'];
  final batch = txn.batch();
  for (var i = 0; i < 10000; i++) {
    final lat = 58.5900 + (i % 200) * 0.00015;
    final lon = 49.6400 + (i ~/ 200) * 0.00055;
    batch.insert('local_gps_track_points', {
      'activity_date': date,
      'seq_no': i,
      'recorded_at_ms': nowMs - (10000 - i) * 1000,
      'lat': lat,
      'lon': lon,
      'accuracy_m': 5.0,
      'speed_mps': i % 3 == 2 ? 11.2 : 1.35,
      'cumulative_steps': i,
      'delta_steps': 1,
      'delta_distance_m': 0.76,
      'motion_class': classes[i % 3],
      'sync_status': 'synced',
    });
  }
  for (var a = 0; a < 15; a++) {
    final s = a * 600;
    final e = s + 200;
    final poly = jsonEncode([
      [58.5900 + (s % 200) * 0.00015, 49.6400 + (s ~/ 200) * 0.00055],
      [58.5900 + (e % 200) * 0.00015, 49.6400 + (e ~/ 200) * 0.00055],
    ]);
    batch.insert('local_route_segment_allocations', {
      'id': 'alloc-$a',
      'idempotency_key': 'idem-alloc-$a',
      'activity_date': date,
      'start_seq_no': s,
      'end_seq_no': e,
      'polyline_json': poly,
      'segment_distance_m': 200.0,
      'segment_steps': 260,
      'replaced_transport_mode': a.isEven ? 'bus' : 'car_sedan',
      'applied_co2_g_per_meter': a.isEven ? 0.082 : 0.192,
      'confidence_factor': 1.0,
      'co2_saved_grams': a.isEven ? 16 : 38,
      'created_at_ms': nowMs,
      'updated_at_ms': nowMs,
    });
  }
  await batch.commit(noResult: true);
}

Future<void> _seedWastePoints(Transaction txn, int nowMs) async {
  final batch = txn.batch();
  for (var i = 0; i < 5000; i++) {
    final row = i ~/ 100;
    final col = i % 100;
    final lat = 58.55 + row * 0.0022;
    final lon = 49.58 + col * 0.0018;
    batch.insert('cached_waste_points', {
      'id': 'wp-bench-$i',
      'title': 'Пункт РСО #$i',
      'accepted_fractions_csv': 'plastic,glass,paper',
      'lat': lat,
      'lon': lon,
      'status': i % 10 == 0 ? 'unverified' : 'active',
      'trust_score': 82.0,
      'attribution_text': 'OpenStreetMap',
      'cached_at_ms': nowMs,
    });
  }
  await batch.commit(noResult: true);
}

double _percentileMs(List<double> sortedMs, double pct) {
  if (sortedMs.isEmpty) return 0.0;
  final idx = ((sortedMs.length - 1) * pct).ceil().clamp(
    0,
    sortedMs.length - 1,
  );
  return sortedMs[idx];
}

Future<List<double>> _pumpFrames(WidgetTester tester, int count) async {
  final pumpMs = <double>[];
  final watch = Stopwatch();
  for (var i = 0; i < count; i++) {
    watch
      ..reset()
      ..start();
    await tester.pump(const Duration(milliseconds: 16));
    watch.stop();
    pumpMs.add(watch.elapsedMicroseconds / 1000.0);
  }
  return pumpMs;
}

Future<void> _exerciseMascotStage(WidgetTester tester) async {
  final homeCubit = HomeCubit(
    _BenchmarkProfileRepo(),
    _BenchmarkMapRepo(.instance),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: EcoTheme.lightTheme,
      home: BlocProvider<HomeCubit>.value(
        value: homeCubit,
        child: const HomeScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.byType(FoxMascotWidget), findsOneWidget);

  await _pumpFrames(tester, 90);
  final mascotCenter = tester.getCenter(find.byType(FoxMascotWidget));
  final gesture = await tester.startGesture(mascotCenter);
  await _pumpFrames(tester, 45);
  await gesture.up();
  await _pumpFrames(tester, 45);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(homeCubit.close);
}

Future<void> _exerciseMapStage(WidgetTester tester) async {
  final mapBloc = MapActivityBloc(
    _BenchmarkMapRepo(.instance),
    _BenchmarkProfileRepo(),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: EcoTheme.lightTheme,
      home: BlocProvider<MapActivityBloc>.value(
        value: mapBloc,
        child: const MapActivityScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 80));
  expect(find.byType(FlutterMap), findsOneWidget);

  final mapFinder = find.byType(FlutterMap);
  for (var i = 0; i < 5; i++) {
    await tester.drag(mapFinder, const Offset(40, -25));
    await _pumpFrames(tester, 30);
  }

  await tester.tap(find.text('Пункты РСО'));
  await tester.pump(const Duration(milliseconds: 60));
  for (var i = 0; i < 5; i++) {
    await tester.drag(mapFinder, const Offset(-35, 25));
    await _pumpFrames(tester, 30);
  }

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(mapBloc.close);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late HttpOverrides? previousHttpOverrides;

  setUpAll(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _OfflineTileHttpOverrides();
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final schemaSql = File('assets/db/client_sqlite_schema.sql')
          .readAsStringSync();
      final rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await SqliteDatabase.instance.initialize(
        overrideDb: rawDb,
        schemaSqlOverride: schemaSql,
      );
    } else {
      await SqliteDatabase.instance.initialize();
    }
    await _seedBenchmarkSqlite(.instance);
  });

  tearDownAll(() async {
    HttpOverrides.global = previousHttpOverrides;
    await SqliteDatabase.instance.close();
  });

  testWidgets('Gate 4.4 Impeller mascot + 10k GPS + 5k RSO benchmark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final recordedTimings = <FrameTiming>[];
    void onTimings(List<FrameTiming> timings) {
      recordedTimings.addAll(timings);
    }

    WidgetsBinding.instance.addTimingsCallback(onTimings);
    addTearDown(() => WidgetsBinding.instance.removeTimingsCallback(onTimings));

    await _exerciseMascotStage(tester);
    await _exerciseMapStage(tester);

    for (var attempt = 0; attempt < 10 && recordedTimings.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final ptCount = await SqliteDatabase.instance.database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM local_gps_track_points',
    );
    final wpCount = await SqliteDatabase.instance.database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM cached_waste_points',
    );
    expect((ptCount.first['cnt'] as num?)?.toInt(), equals(10000));
    expect((wpCount.first['cnt'] as num?)?.toInt(), equals(5000));

    expect(
      recordedTimings,
      isNotEmpty,
      reason:
          'Expected FrameTiming entries from WidgetsBinding.addTimingsCallback; '
          'zero timings were recorded (cannot verify 60fps p99 <= 16.6 ms budget).',
    );

    final buildMs =
        recordedTimings
            .map((t) => t.buildDuration.inMicroseconds / 1000.0)
            .toList()
          ..sort();
    final rasterMs =
        recordedTimings
            .map((t) => t.rasterDuration.inMicroseconds / 1000.0)
            .toList()
          ..sort();
    final totalMs =
        recordedTimings.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList()
          ..sort();
    debugPrint(
      'Impeller timings n=${recordedTimings.length} '
      'build(p50=${_percentileMs(buildMs, 0.50).toStringAsFixed(2)}, '
      'p95=${_percentileMs(buildMs, 0.95).toStringAsFixed(2)}, '
      'p99=${_percentileMs(buildMs, 0.99).toStringAsFixed(2)}) '
      'raster(p99=${_percentileMs(rasterMs, 0.99).toStringAsFixed(2)}) '
      'total(p99=${_percentileMs(totalMs, 0.99).toStringAsFixed(2)})',
    );
    expect(_percentileMs(buildMs, 0.99), lessThanOrEqualTo(16.6));
    expect(_percentileMs(rasterMs, 0.99), lessThanOrEqualTo(16.6));
  });
}
