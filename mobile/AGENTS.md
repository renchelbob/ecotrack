# mobile/AGENTS.md — Flutter Client & Offline Engine Playbook (Developer 2)

> **Workspace Scope**: `/mobile/**` (All Flutter client features, routing, BLoCs, and UI)
> **Pre-Delivered High-Complexity Modules (Authored by Developer 1)**:
> 1. `mobile/lib/features/mascot/presentation/widgets/mascot_vector_painter.dart` (fox mascot Canvas geometry & accessories)
> 2. `mobile/lib/core/database/outbox_dispatcher.dart` (offline mutation outbox FSM & causal barrier)
> 3. `mobile/lib/features/map/presentation/screens/map_activity_screen.dart` (dual-mode `flutter_map` with `LayerHitNotifier`)
> Developer 2 consumes these 3 pre-tested components as standalone building blocks and integrates them into the UI, BLoCs, and router.
> **Read-Only Contracts**: `/contracts/client_sqlite_schema.sql`, `/contracts/openapi.yaml`, `/contracts/error_catalog.json`
> **Relevant Specs & Skills**: `specs/01-product-and-ux-spec.md`, `specs/02-domain-math-and-algorithms.md`, `specs/05-mobile-flutter-architecture.md`, `specs/06-offline-sync-and-sensors.md`, `specs/08-verification-and-quality-gates.md`, `.agents/skills/`

---

## 1. Exact Feature-First Layered Layout (`mobile/lib/`)

Every file in `/mobile/lib/` MUST follow this exact directory hierarchy and static import boundary contract:

```text
mobile/
├── pubspec.yaml                              # Dart ^3.13.4, ZERO build_runner dependencies
├── analysis_options.yaml                     # fatal-infos, fatal-warnings, dart_code_linter, import_lint
├── assets/
│   ├── db/client_sqlite_schema.sql           # Symlink/copy of ../../contracts/client_sqlite_schema.sql
│   ├── errors/error_catalog.json             # Symlink/copy of ../../contracts/error_catalog.json
│   └── vectors/                              # Mascot accessory metadata & partner SVG/vector definitions
├── lib/
│   ├── main.dart                             # App bootstrap, SQLite WAL init, foreground task init
│   ├── app.dart                              # MaterialApp.router, Russian locale, BlocProviders
│   ├── core/
│   │   ├── error/
│   │   │   ├── app_error.dart                # Sealed AppError mapped 1:1 to contracts/error_catalog.json
│   │   │   └── result.dart                   # Sealed Result<T, AppError> (Ok / Err)
│   │   ├── database/
│   │   │   ├── sqlite_database.dart          # sqflite/sqlite3 WAL initializer & transaction runner
│   │   │   └── outbox_dispatcher.dart        # Exponential backoff worker for offline_mutation_outbox
│   │   ├── network/
│   │   │   ├── api_client.dart               # Dio ^5.x wrapper returning Future<Result<T, AppError>>
│   │   │   ├── auth_refresh_interceptor.dart # QueuedInterceptorsWrapper single-flight JWT refresh lock
│   │   │   └── idempotency_interceptor.dart  # Injects UUIDv7 Idempotency-Key header on mutations
│   │   ├── router/
│   │   │   └── app_router.dart               # Manual go_router ^15.x+ (5-tab StatefulShellRoute + guards)
│   │   ├── sensors/
│   │   │   ├── step_sensor_bridge.dart       # Reconciles health ^12.x+ & pedometer cumulative_steps
│   │   │   └── gps_foreground_service.dart   # geolocator ^14.x + flutter_foreground_task interval tracker
│   │   ├── push/
│   │   │   ├── push_provider.dart            # Abstract PushProvider interface
│   │   │   └── fcm_push_provider.dart        # firebase_messaging + flutter_local_notifications adapter
│   │   ├── theme/
│   │   │   └── eco_theme.dart                # EcoTrack color tokens, typography, banner presenter
│   │   └── utils/
│   │       └── uuid_v7.dart                  # Pure Dart RFC 9562 UUIDv7 generator
│   └── features/
│       ├── auth_fz152/                       # OAuth 2.1 PKCE, Google lab warning + phone modal, 152-FZ
│       │   ├── domain/
│       │   ├── data/
│       │   └── presentation/
│       ├── stats/                            # Tab 1: Emissions charts, history, equivalents, leaderboard, Shared Forest
│       │   ├── domain/
│       │   ├── data/
│       │   └── presentation/
│       ├── map_activity/                     # Tab 2: Unified flutter_map [ My Routes ] | [ Recycling Map ]
│       │   ├── domain/
│       │   ├── data/
│       │   └── presentation/
│       ├── home_mascot/                      # Tab 3: Balance, streak, interactive CustomPainter mascot, Today cards
│       │   ├── domain/
│       │   ├── data/
│       │   └── presentation/
│       ├── shop/                             # Tab 4: Fictional partner catalog, cart, QR/promo orders, virtual items
│       │   ├── domain/
│       │   ├── data/
│       │   └── presentation/
│       └── profile_social/                   # Tab 5: Profile, badges, Friends QR/nudge, My Vehicle, RSO shortcut, 152-FZ
│           ├── domain/
│           ├── data/
│           └── presentation/
└── test/
    ├── pbt/                                  # glados property-based tests (CO2 math, JSON codecs, outbox FSM)
    ├── database/                             # Real sqlite3 FFI tests against contracts/client_sqlite_schema.sql
    └── widgets/                              # Mascot CustomPainter & 5-tab navigation widget tests
```

### Static Layer Import Rules (Enforced by `import_lint`)
1. `features/*/presentation/**` **MUST NOT** import `package:dio/dio.dart`, `package:sqflite/sqflite.dart`, `package:sqlite3/sqlite3.dart`, `package:geolocator/geolocator.dart`, `package:health/health.dart`, `package:pedometer/pedometer.dart`, `package:flutter_secure_storage/flutter_secure_storage.dart`, or any file in `features/*/data/**`.
2. `features/*/domain/**` **MUST NOT** import `package:flutter/material.dart`, `package:flutter/widgets.dart`, `core/network/**`, `core/database/**`, `features/*/data/**`, or `features/*/presentation/**`.
3. Cross-feature imports are allowed ONLY between `domain/` layers or via `core/router/app_router.dart`.

---

## 2. Mandatory Tech Stack & Zero-`build_runner` Rules (Dart `^3.13.4`)

1. **Zero Code Generation (`build_runner` is BANNED)**:
   - Write native Dart `^3.13.4` classes using **Primary Constructors**, `sealed class` hierarchies, `final class` domain entities, and exhaustive `switch` expressions with pattern matching for JSON deserialization.
2. **State Management (`flutter_bloc ^9.x`)**:
   - Every screen or sub-feature uses a `Cubit<State>` or `Bloc<Event, State>` where `State` is a `sealed class`.
   - Side effects (navigation, opening the Google formal phone dialog, opening the 152-FZ consent sheet, or showing a unified error banner) are driven by `BlocListener` inspecting `AppError.clientAction` from `contracts/error_catalog.json`.
3. **Unified Map Engine (`flutter_map ^8.2+`)**:
   - Both Tab 2 modes (`[ My Routes ]` and `[ Recycling Map ]`) and the Profile RSO shortcut render using a single `FlutterMap` widget infrastructure backed by `latlong2`, `flutter_map_marker_cluster`, and `flutter_map_cache` (OpenFreeMap tiles + SQLite tile cache).
4. **Interactive Schematic Vector Mascot**:
   - Rendered on Tab 3 (`Home`) via a dedicated `CustomPainter` (`MascotVectorPainter`) with `RepaintBoundary` and `TickerProvider` driving breathing scale, press-squint eye morphing, mood transitions (`sleepy`, `neutral`, `happy`, `thriving`, `squinting`), and layered vector accessories (`head`, `neck`, `glasses`, `aura`, `companion`).

---

## 3. Canonical Dart 3.13.4 Syntax (Primary Constructors, Pattern Matching & Cubit)

All Dart code MUST follow this exact zero-`build_runner` pattern:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/error/app_error.dart';
import '../../core/error/result.dart';

enum TransportModeCode {
  bus('bus', 0.08200),
  metro('metro', 0.02800),
  tram('tram', 0.03500),
  personalCar('personal_car', 0.19200),
  carCompact('car_compact', 0.14500),
  carSedan('car_sedan', 0.19200),
  carSuv('car_suv', 0.25500),
  carEv('car_ev', 0.05800);

  const TransportModeCode(this.wireName, this.defaultCo2GramsPerMeter);
  final String wireName;
  final double defaultCo2GramsPerMeter;

  static TransportModeCode fromWire(String raw) =>
      TransportModeCode.values.firstWhere(
        ( m) => m.wireName == raw,
        orElse: () => TransportModeCode.bus,
      );
}

final class DailyActivitySummary(
  this.id,
  this.activityDate,
  this.validatedSteps,
  this.totalStepDistanceM,
  this.allocatedGpsDistanceM,
  this.unallocatedStepDistanceM,
  this.allocatedCo2SavedGrams,
  this.autoDefaultCo2SavedGrams,
  this.totalCo2SavedGrams,
  this.pointsBalance,
  this.isAutoCalculated,
) {
  final String id;
  final String activityDate;
  final int validatedSteps;
  final double totalStepDistanceM;
  final double allocatedGpsDistanceM;
  final double unallocatedStepDistanceM;
  final int allocatedCo2SavedGrams;
  final int autoDefaultCo2SavedGrams;
  final int totalCo2SavedGrams;
  final int pointsBalance;
  final bool isAutoCalculated;

  static Result<DailyActivitySummary, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'activity_date': final String activityDate,
      'validated_steps': final int validatedSteps,
      'total_step_distance_m': final num totalDist,
      'allocated_gps_distance_m': final num allocDist,
      'unallocated_step_distance_m': final num unallocDist,
      'allocated_co2_saved_grams': final int allocCo2,
      'auto_default_co2_saved_grams': final int autoCo2,
      'total_co2_saved_grams': final int totalCo2,
      'points_balance': final int balance,
      'is_auto_calculated': final bool isAuto,
    }) {
      return Ok(
        DailyActivitySummary(
          id,
          activityDate,
          validatedSteps,
          totalDist.toDouble(),
          allocDist.toDouble(),
          unallocDist.toDouble(),
          allocCo2,
          autoCo2,
          totalCo2,
          balance,
          isAuto,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }
}

sealed class DailyActivityState {
  const DailyActivityState();
}

final class DailyActivityLoading extends DailyActivityState {
  const DailyActivityLoading();
}

final class DailyActivityLoaded(this.summary) extends DailyActivityState {
  final DailyActivitySummary summary;
}

final class DailyActivityFailure(this.error) extends DailyActivityState {
  final AppError error;
}

abstract interface class ActivityRepository {
  Future<Result<DailyActivitySummary, AppError>> syncDailySteps({
    required String activityDate,
    required int rawSensorSteps,
  });
}

final class DailyActivityCubit extends Cubit<DailyActivityState> {
  DailyActivityCubit(this._repository) : super(const DailyActivityLoading());
  final ActivityRepository _repository;

  Future<void> syncSteps(String activityDate, int rawSensorSteps) async {
    emit(const DailyActivityLoading());
    final result = await _repository.syncDailySteps(
      activityDate: activityDate,
      rawSensorSteps: rawSensorSteps,
    );
    switch (result) {
      case Ok(value: final summary):
        emit(DailyActivityLoaded(summary));
      case Err(error: final appError):
        emit(DailyActivityFailure(appError));
    }
  }
}
```

---

## 4. Strict Negative Constraints (Mobile Bans)

1. **FORBIDDEN**: Adding `build_runner`, `freezed`, `json_serializable`, `auto_route`, `retrofit`, `injectable`, `riverpod`, `flutter_riverpod`, `get`, `hive`, `isar`, `maplibre_gl`, or `google_maps_flutter` to `pubspec.yaml`.
2. **FORBIDDEN**: Using `dynamic` anywhere in `lib/` or `test/`. Use `Object?` and Dart 3 type promotion / pattern matching (`if (value case final String s)`).
3. **FORBIDDEN**: Using the null-assertion bang operator (`!`) in `lib/` (enforced by `analysis_options.yaml` rule `avoid_non_null_assertion`).
4. **FORBIDDEN**: Calling `ScaffoldMessenger.of(context).showSnackBar(...)` directly inside widgets with raw exception text. All errors must route through `EcoErrorBannerPresenter` using `AppError.clientAction` and `AppError.uiMessageRu`.
5. **FORBIDDEN**: Leaving any `StreamSubscription`, `AnimationController`, `TextEditingController`, or `MapController` undisposed in `close()` / `dispose()`.
6. **FORBIDDEN**: Computing authoritative point balances or unlocking shop coupons on the client without recording an outbox mutation and receiving server `point_ledger` confirmation.
7. **FORBIDDEN**: Mocking `Database` (`sqflite`/`sqlite3`) or domain calculators with `mockito`/`mocktail`. Run `sqlite3` FFI tests against the real `contracts/client_sqlite_schema.sql`.

---

## 5. Local Verification Commands (Developer 2)

Run all checks from `/mobile/`:

```bash
# 1. Formatting & Zero-Warning Static Analysis
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings

# 2. Complexity, Cyclomatic Metrics & Layer Import Boundaries
dart run dart_code_linter:metrics analyze lib --fatal-style --fatal-performance --fatal-warnings
dart run import_lint

# 3. Property-Based Testing (glados) & Real SQLite 3 Schema Tests
flutter test test/pbt/ test/database/ test/widgets/ --coverage

# 4. Impeller 60fps Frame Budget Benchmark (Vector Mascot + FlutterMap Pan/Zoom)
flutter test integration_test/impeller_map_mascot_benchmark_test.dart
```
