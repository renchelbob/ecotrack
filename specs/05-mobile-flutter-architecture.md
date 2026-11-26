# 05 — Mobile Flutter Architecture Specification (Dart `^3.13.4`, Zero `build_runner`)

> **Target Audience**: Developer 2 (Flutter Mobile Client & Offline Engine) & Mobile AI Coding Agents
> **Governing Contracts**: `contracts/openapi.yaml`, `contracts/client_sqlite_schema.sql`, `contracts/error_catalog.json`
> **Companion Specs**: `specs/01-product-and-ux-spec.md`, `specs/02-domain-math-and-algorithms.md`, `specs/06-offline-sync-and-sensors.md`, `mobile/AGENTS.md`

---

## 1. Locked `pubspec.yaml` Dependency Matrix & Zero-Codegen Policy

EcoTrack targets **Flutter `>=3.32.0`** and **Dart `^3.13.4`** (Impeller rendering engine enabled on both Android and iOS). Code generation (`build_runner`) is **strictly banned** to guarantee instant incremental compilation, zero generated-file merge conflicts, and 100% transparent Dart 3.13 pattern-matching models.

### 1.1 Canonical `mobile/pubspec.yaml`

```yaml
name: ecotrack_mobile
description: EcoTrack Mobile Client (RF 152-FZ, Hybrid Step+GPS CO2 Engine, Dual-Mode FlutterMap)
publish_to: "none"
version: 1.0.0+1

environment:
  sdk: "^3.13.4"
  flutter: ">=3.32.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # State Management (Zero Codegen)
  flutter_bloc: ^9.1.0

  # Local Offline Persistence & Secure Keystore
  sqflite: ^2.4.2
  sqlite3: ^2.7.5
  path: ^1.9.1
  flutter_secure_storage: ^9.2.4
  shared_preferences: ^2.5.2

  # Networking & OAuth 2.1 + PKCE
  dio: ^5.8.0+1
  flutter_appauth: ^9.0.0

  # Navigation & Deep Linking
  go_router: ^15.1.1

  # Unified Dual-Mode Map Engine (My Routes + Recycling Map)
  flutter_map: ^8.2.0
  latlong2: ^0.9.1
  flutter_map_marker_cluster: ^8.1.0
  flutter_map_cache: ^2.0.0
  dio_cache_interceptor: ^3.5.1

  # Hardware Sensors & Background Foreground Service
  pedometer: ^4.1.0
  health: ^12.1.0
  geolocator: ^14.0.0
  flutter_foreground_task: ^9.0.0

  # Charts, QR Codes & Camera Scanner
  fl_chart: ^1.0.0
  qr_flutter: ^4.1.0
  mobile_scanner: ^6.0.7

  # Push Notifications (Abstracted behind PushProvider)
  firebase_core: ^3.12.1
  firebase_messaging: ^15.2.4
  flutter_local_notifications: ^19.0.0

  # UI Icons, Typography, Motion & Utilities
  lucide_icons_flutter: ^3.0.0
  animations: ^2.0.11
  google_fonts: ^6.2.1
  uuid: ^4.5.1
  url_launcher: ^6.3.1
  share_plus: ^11.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  sqflite_common_ffi: ^2.3.5
  glados: ^1.1.7
  bloc_test: ^10.0.0
  dart_code_linter: ^4.4.1
  import_lint: ^2.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/db/client_sqlite_schema.sql
    - assets/errors/error_catalog.json
    - assets/vectors/
    - assets/fonts/
```

### 1.2 Explicitly Forbidden Packages (CI Rejection List)
Adding any of the following packages to `pubspec.yaml` causes `make verify-static` to fail immediately:
- **Codegen**: `build_runner`, `freezed`, `freezed_annotation`, `json_serializable`, `json_annotation`, `auto_route`, `auto_route_generator`, `retrofit`, `retrofit_generator`, `injectable`, `injectable_generator`.
- **Competing State/DI**: `riverpod`, `flutter_riverpod`, `hooks_riverpod`, `get`, `get_it`, `mobx`.
- **Competing Storage/Maps**: `hive`, `hive_flutter`, `isar`, `objectbox`, `drift`, `maplibre_gl`, `google_maps_flutter`, `yandex_mapkit`.
- **Mock Frameworks**: `mockito`, `mocktail` (all persistence and domain tests use real `sqflite_common_ffi` and `glados` property-based generators).

---

## 2. Feature-First Clean Architecture & Static Import Boundaries (`import_lint`)

### 2.1 Complete Directory Layout (`mobile/lib/`)

```text
mobile/lib/
├── main.dart                                      # Bootstrap, SQLite WAL init, foreground task init
├── app.dart                                       # AppDependencies root, MultiBlocProvider, MaterialApp.router
├── core/
│   ├── di/
│   │   └── app_dependencies.dart                  # Manual Constructor DI Composition Root
│   ├── error/
│   │   ├── app_error.dart                         # Sealed AppError + ErrorCatalogRegistry
│   │   ├── result.dart                            # Sealed Result<T, AppError> (Ok / Err)
│   │   └── eco_error_banner_presenter.dart        # Deterministic UI presenter per client_action
│   ├── database/
│   │   ├── sqlite_database.dart                   # WAL mode sqflite/sqlite3 manager
│   │   └── outbox_dispatcher.dart                 # Offline mutation outbox worker (UUIDv7, CAS claim & causal barrier)
│   ├── network/
│   │   ├── dio_client.dart                        # Configured Dio ^5.x wrapper
│   │   ├── auth_header_interceptor.dart           # Injects Bearer access token
│   │   ├── idempotency_key_interceptor.dart       # Injects UUIDv7 Idempotency-Key on mutations
│   │   ├── token_refresh_interceptor.dart         # QueuedInterceptorsWrapper single-flight refresh lock
│   │   └── error_catalog_mapper_interceptor.dart  # Maps HTTP/Dio errors -> AppError via error_catalog.json
│   ├── router/
│   │   ├── app_router.dart                        # go_router ^15.x+ StatefulShellRoute (5 locked tabs)
│   │   └── floating_bottom_nav_bar.dart           # 5-tab wireframe bar with raised Home dome
│   ├── sensors/
│   │   ├── step_sensor_bridge.dart                # Health Connect/HealthKit + pedometer bridge
│   │   └── gps_foreground_service.dart            # geolocator ^14.x + flutter_foreground_task
│   ├── push/
│   │   ├── push_provider.dart                     # Abstract PushProvider interface
│   │   └── fcm_push_provider.dart                 # firebase_messaging + flutter_local_notifications
│   ├── theme/
│   │   ├── eco_colors.dart                        # Wireframe grayscale + 3 Eco-Equivalent accents
│   │   ├── eco_typography.dart                    # Inter tabular figures typography scale
│   │   └── eco_theme.dart                         # ThemeData configuration
│   └── utils/
│       ├── uuid_v7.dart                           # RFC 9562 UUIDv7 generator
│       └── polyline_simplifier.dart               # Ramer-Douglas-Peucker simplification for >2000 pts
└── features/
    ├── auth/
    │   ├── domain/                                # AuthSession, ConsentEntry, OAuthProviderType, AuthRepository
    │   ├── data/                                  # OAuthPkceClient, SecureTokenStore, AuthRepositoryImpl
    │   └── presentation/                          # AuthBloc, OnboardingScreen (in-place Step 3 OAuth),
    │                                              # GoogleLabModeBanner, GoogleFormalPhoneModal, Fz152ConsentResolutionModal
    ├── home_mascot/
    │   ├── domain/                                # MascotVisualState, MascotMoodState, TodayCardMetrics
    │   ├── data/                                  # HomeSummaryAggregator
    │   └── presentation/                          # HomeCubit, HomeScreen, FoxMascotWidget, MascotAccessoryLayerPainter
    │       └── widgets/
    │           └── mascot_vector_painter.dart     # Transparent wireframe fox mascot Canvas geometry & accessories (owned by Developer 2)
    ├── map_activity/
    │   ├── domain/                                # DailyActivityDetail, GpsTrackPointClassified,
    │   │                                          # RouteSegmentAllocationItem, WastePointMapItem, MapRepository
    │   ├── data/                                  # ActivitySqliteDao, WastePointSqliteDao, MapRepositoryImpl
    │   └── presentation/                          # MapActivityBloc, RoutePolylineOverlay, TransportAllocationBottomSheet,
    │       │                                      # WastePointDetailSheet, SuggestWastePointModal
    │       └── screens/
    │           └── map_activity_screen.dart         # Dual-mode FlutterMap + LayerHitNotifier (owned by Developer 2)
    ├── stats/
    │   ├── domain/                                # EmissionsStatistics, EcoEquivalentsMetrics,
    │   │                                          # SharedForestChallenge, LeaderboardEntry, StatsRepository
    │   ├── data/                                  # StatsSqliteDao, StatsRepositoryImpl
    │   └── presentation/                          # StatsCubit, StatsScreen, EmissionsDrilldownScreen,
    │                                              # ActivityHistoryDrilldownScreen, ForestDrilldownScreen,
    │                                              # GasolineDrilldownScreen, AirDrilldownScreen
    ├── shop/
    │   ├── domain/                                # ShopCatalogItem, CartLine, ShopOrderDetail,
    │   │                                          # PointLedgerItem, ShopRepository
    │   ├── data/                                  # ShopRepositoryImpl
    │   └── presentation/                          # ShopBloc, ShopScreen, CartScreen, OrdersQrScreen,
    │                                              # OrdersPromoScreen, ShopItemDetailModal
    ├── friends/
    │   ├── domain/                                # FriendProfileSummary, FriendshipRecord, FriendsRepository
    │   ├── data/                                  # FriendsSqliteDao, FriendsRepositoryImpl
    │   └── presentation/                          # FriendsCubit, FriendsScreen, FriendQrScannerModal
    ├── vehicles/
    │   ├── domain/                                # UserVehicle, FuelType, TransportPresetItem, VehicleRepository
    │   ├── data/                                  # VehicleSqliteDao, VehicleRepositoryImpl
    │   └── presentation/                          # VehicleCubit, MyVehicleScreen
    └── profile_settings/
        ├── domain/                                # UserProfile, BadgeCatalogProgressItem, MascotAccessoryItem,
        │                                          # AccountDeletionReceipt, ProfileRepository
        ├── data/                                  # ProfileSqliteDao, ProfileRepositoryImpl
        └── presentation/                          # ProfileSettingsCubit, SyncStatusCubit, ProfileSettingsScreen,
                                                   # BadgesAndAccessoriesScreen, Fz152DeleteAccountModal
```

> **Core Mobile Module Canonical Paths (Owned by Developer 2)**: `mobile/lib/features/home_mascot/presentation/widgets/mascot_vector_painter.dart`, `mobile/lib/core/database/outbox_dispatcher.dart`, and `mobile/lib/features/map_activity/presentation/screens/map_activity_screen.dart`.

### 2.2 Manual Dependency Injection Composition Root (`AppDependencies`)
Zero service-locator singletons (`get_it`) are permitted. `AppDependencies` constructs all infrastructure adapters, SQLite DAOs, and repositories once during `main()` bootstrap and injects them into the widget tree via `MultiRepositoryProvider` and `MultiBlocProvider`:

```dart
final class AppDependencies(
  this.sqliteDb,
  this.errorCatalog,
  this.outboxDispatcher,
  this.stepSensorBridge,
  this.gpsForegroundService,
  this.pushProvider,
  this.authRepository,
  this.profileRepository,
  this.vehicleRepository,
  this.mapActivityRepository,
  this.statsRepository,
  this.shopRepository,
  this.friendsRepository,
) {
  final SqliteDatabase sqliteDb;
  final ErrorCatalogRegistry errorCatalog;
  final OutboxDispatcher outboxDispatcher;
  final StepSensorBridge stepSensorBridge;
  final GpsForegroundService gpsForegroundService;
  final PushProvider pushProvider;
  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final VehicleRepository vehicleRepository;
  final MapActivityRepository mapActivityRepository;
  final StatsRepository statsRepository;
  final ShopRepository shopRepository;
  final FriendsRepository friendsRepository;
}
```

### 2.3 Static Import Boundary Configuration (`mobile/analysis_options.yaml`)

```yaml
plugins:
  dart_code_linter:
    version: ^4.4.1
    diagnostics:
      always-remove-listener: error
      avoid-dynamic: error
      avoid-non-null-assertion: error
      no-empty-block: error
  import_lint:
    version: ^2.0.0
    diagnostics:
      import_lint: error

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    missing_required_param: error
    missing_return: error
    deprecated_member_use: error
    deprecated_member_use_from_same_package: error
    todo: error

import_lint:
  severity: error
  rules:
    presentation_no_dio:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:dio/**/*.dart"
      except: []
    presentation_no_sqflite:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:sqflite/**/*.dart"
      except: []
    presentation_no_sqlite3:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:sqlite3/**/*.dart"
      except: []
    presentation_no_geolocator:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:geolocator/**/*.dart"
      except: []
    presentation_no_health:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:health/**/*.dart"
      except: []
    presentation_no_pedometer:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:pedometer/**/*.dart"
      except: []
    presentation_no_firebase_messaging:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:firebase_messaging/**/*.dart"
      except: []
    presentation_no_secure_storage:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:flutter_secure_storage/**/*.dart"
      except: []
    presentation_no_core_network:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:ecotrack_mobile/core/network/**/*.dart"
      except: []
    presentation_no_core_database:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:ecotrack_mobile/core/database/**/*.dart"
      except: []
    presentation_no_core_sensors:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:ecotrack_mobile/core/sensors/**/*.dart"
      except: []
    presentation_no_feature_data:
      target: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      from: "package:ecotrack_mobile/features/*/data/**/*.dart"
      except: []
    domain_no_flutter:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:flutter/**/*.dart"
      except: []
    domain_no_dio:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:dio/**/*.dart"
      except: []
    domain_no_sqflite:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:sqflite/**/*.dart"
      except: []
    domain_no_sqlite3:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:sqlite3/**/*.dart"
      except: []
    domain_no_core_network:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:ecotrack_mobile/core/network/**/*.dart"
      except: []
    domain_no_core_database:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:ecotrack_mobile/core/database/**/*.dart"
      except: []
    domain_no_feature_data:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:ecotrack_mobile/features/*/data/**/*.dart"
      except: []
    domain_no_feature_presentation:
      target: "package:ecotrack_mobile/features/*/domain/**/*.dart"
      from: "package:ecotrack_mobile/features/*/presentation/**/*.dart"
      except: []
```

---

## 3. BLoC / Cubit State Machine Catalog (`flutter_bloc ^9.x`)

### 3.1 Complete State Machine Inventory

| Bloc / Cubit Class | Scope / Lifecycle | Consumed Repositories | Emitted Sealed States |
| :--- | :--- | :--- | :--- |
| `AuthBloc` | Global App-Scope | `AuthRepository`, `ProfileRepository`, `PushProvider` | `AuthInitial`, `AuthOnboardingRequired`, `AuthUnauthenticated`, `AuthAuthenticating`, `AuthGooglePhoneRequired(UserProfile, String? warningBanner)`, `AuthConsentResolutionRequired(UserProfile, bool isRevoked)`, `AuthAuthenticated(UserProfile, bool isForeignLabMode, String? warningBanner)`, `AuthError(AppError)` |
| `SyncStatusCubit` | Global App-Scope | `OutboxDispatcher`, `StepSensorBridge` | `SyncStatusState(int pendingOutboxCount, bool isOnline, bool isSyncingSensors, int? lastSyncedEpochMs)` |
| `HomeCubit` | Tab 3 (`Home`) | `ProfileRepository`, `MapActivityRepository` | `HomeLoading`, `HomeReady(UserProfile profile, DailyActivitySummary todaySummary, MascotVisualState mascot, bool isPointerSquinting, AppError? bannerError)` |
| `MapActivityBloc` | Tab 2 (`Map & Activity`) | `MapActivityRepository`, `VehicleRepository`, `ProfileRepository` | `MapActivityState` (composite immutable state holding `activeMode`, `selectedDate`, `routeDetail`, `selectedSegmentRange`, `transportPresets`, `wastePoints`, `selectedFractions`, `activeWastePointDetail`, `isSubmitting`, `activeError`) |
| `StatsCubit` | Tab 1 (`Stats`) | `StatsRepository`, `FriendsRepository` | `StatsLoading`, `StatsLoaded(EmissionsStatistics emissions, PaginatedActivityHistory history, EcoEquivalentsResponse equivalents, FriendsLeaderboardResponse leaderboard, SharedForestChallengeResponse sharedForest, String selectedPeriod, AppError? bannerError)` |
| `ShopBloc` | Tab 4 (`Shop`) | `ShopRepository`, `ProfileRepository` | `ShopState` (holding `catalogItems`, `categories`, `selectedCategory`, `searchQuery`, `cartLines`, `pointsBalance`, `orders`, `isCheckingOut`, `lastCompletedOrder`, `activeError`) |
| `FriendsCubit` | Tab 5 Sub-route (`FriendsScreen`) | `FriendsRepository` | `FriendsLoading`, `FriendsLoaded(FriendsOverviewResponse overview, bool isSendingRequest, Set<String> nudgingUserIds, AppError? activeError)` |
| `VehicleCubit` | Tab 5 Sub-route (`MyVehicleScreen`) | `VehicleRepository` | `VehicleLoading`, `VehicleConfigured(UserVehicle vehicle, double previewCo2GPerKm, bool isSaving, AppError? activeError)`, `VehicleUnconfigured(FuelType draftFuel, double draftConsumption, double previewCo2GPerKm, AppError? activeError)` |
| `ProfileSettingsCubit` | Tab 5 (`Profile & Settings`) | `ProfileRepository`, `AuthRepository` | `ProfileSettingsLoaded(UserProfile profile, BadgesListResponse badges, MascotInventoryResponse accessories, ConsentHistoryListResponse consents, AccountDeletionReceipt? deletionReceipt, bool isSaving, AppError? activeError)` |

### 3.2 Cross-Feature Reactive Propagation Architecture
Widgets and Blocs **MUST NEVER** reference or call methods on another Bloc directly. All cross-feature state updates propagate reactively through broadcast streams exposed by domain repositories:
1. **`ProfileRepository.watchUserProfile()` (`Stream<UserProfile>`)**:
   - Whenever `ShopBloc` completes an order (`remaining_points_balance`), `MapActivityBloc` saves daily steps or route segment allocations (`points_balance`, `lifetime_co2_saved_grams`), or `ProfileSettingsCubit` updates goals/accessories/consent, the repository writes the updated row to SQLite `local_user_profile` and emits on `watchUserProfile()`.
   - `HomeCubit`, `ShopBloc`, `ProfileSettingsCubit`, and `AuthBloc` subscribe to `watchUserProfile()` and immediately reflect the new balance, streak, goal, or mascot accessory without manual polling.
2. **`MapActivityRepository.watchDailySummary(String activityDate)` (`Stream<DailyActivitySummary>`)**:
   - Emits whenever `StepSensorBridge` flushes new validated steps or `MapActivityBloc` saves/deletes a route segment allocation.
   - `HomeCubit` and `StatsCubit` listen to this stream so the Home Today cards and 7-day bar chart update instantaneously.

---

## 4. Navigation Architecture (`go_router ^15.x+`)

### 4.1 Route Tree & 5-Tab `StatefulShellRoute.indexedStack`

```dart
final class AppRouter {
  AppRouter({
    required AuthBloc authBloc,
    required GlobalKey<NavigatorState> rootNavigatorKey,
  }) : _authBloc = authBloc,
       _rootNavigatorKey = rootNavigatorKey;

  final AuthBloc _authBloc;
  final GlobalKey<NavigatorState> _rootNavigatorKey;

  late final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: BlocListenable(_authBloc),
    redirect: _handleRedirect,
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (context, state) {
          final stepParam = int.tryParse(state.uri.queryParameters['step'] ?? '');
          final initialStep = switch (stepParam) {
            final int step when step >= 1 && step <= 3 => step,
            _ => 1,
          };
          return OnboardingScreen(initialStep: initialStep);
        },
      ),
      GoRoute(
        path: '/auth/login',
        redirect: (context, state) => '/onboarding?step=3',
      ),
      GoRoute(
        path: '/auth/google-phone',
        builder: (context, state) => const GoogleFormalPhoneModalScreen(),
      ),
      GoRoute(
        path: '/auth/consent-resolution',
        builder: (context, state) => const Fz152ConsentResolutionScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainNavigationShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          // Branch 0: Tab 1 — Statistics & Social Challenges
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'emissions',
                    builder: (context, state) => const EmissionsDrilldownScreen(),
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => const ActivityHistoryDrilldownScreen(),
                  ),
                  GoRoute(
                    path: 'equivalents/forest',
                    builder: (context, state) => const ForestDrilldownScreen(),
                  ),
                  GoRoute(
                    path: 'equivalents/gasoline',
                    builder: (context, state) => const GasolineDrilldownScreen(),
                  ),
                  GoRoute(
                    path: 'equivalents/air',
                    builder: (context, state) => const AirDrilldownScreen(),
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: Tab 2 — Unified Dual-Mode Map & Activity
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/map',
                builder: (context, state) {
                  final modeParam = state.uri.queryParameters['mode'];
                  final dateParam = state.uri.queryParameters['date'];
                  return MapActivityScreen(
                    initialMode: modeParam == 'rso'
                        ? MapScreenMode.recyclingMap
                        : MapScreenMode.myRoutes,
                    initialDateIso: dateParam,
                  );
                },
              ),
            ],
          ),
          // Branch 2: Tab 3 — Home (Mascot + Today Cards)
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Branch 3: Tab 4 — Shop, Cart & Orders
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/shop',
                builder: (context, state) => const ShopScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'cart',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const CartScreen(),
                  ),
                  GoRoute(
                    path: 'orders/qr',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const OrdersQrScreen(),
                  ),
                  GoRoute(
                    path: 'orders/promo',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const OrdersPromoScreen(),
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Tab 5 — Profile, Friends, Vehicle & 152-FZ Settings
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileSettingsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'friends',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => FriendsScreen(
                      initialInviteCode: state.uri.queryParameters['code'],
                    ),
                  ),
                  GoRoute(
                    path: 'badges',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const BadgesAndAccessoriesScreen(),
                  ),
                  GoRoute(
                    path: 'vehicle',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const MyVehicleScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  String? _handleRedirect(BuildContext context, GoRouterState state) {
    final authState = _authBloc.state;
    final path = state.matchedLocation;

    switch (authState) {
      case AuthInitial() || AuthAuthenticating():
        return null;
      case AuthOnboardingRequired():
        return path == '/onboarding' ? null : '/onboarding';
      case AuthUnauthenticated() || AuthError():
        return path == '/onboarding' ? null : '/onboarding?step=3';
      case AuthGooglePhoneRequired():
        return path == '/auth/google-phone' ? null : '/auth/google-phone';
      case AuthConsentResolutionRequired():
        return path == '/auth/consent-resolution' ? null : '/auth/consent-resolution';
      case AuthAuthenticated():
        if (path == '/onboarding' ||
            path == '/auth/login' ||
            path == '/auth/google-phone' ||
            path == '/auth/consent-resolution') {
          return '/home';
        }
        return null;
    }
  }
}
```

### 4.2 Deep-Link & Push Notification URI Routing Table

| Incoming URI / Push Deep Link | Target `go_router` Location | Triggering Scenario |
| :--- | :--- | :--- |
| `ecotrack://auth/callback?code=...` | Handled by `flutter_appauth` native receiver | OAuth 2.1 PKCE redirect from Yandex ID, VK ID, or Google |
| `ecotrack://friend/{friend_code}` | `/profile/friends?code={friend_code}` | Scanning a friend's QR code or tapping a shared invite link |
| `ecotrack://map?mode=rso` | `/map?mode=rso` | Tapping the Recycling Map shortcut card in Profile or RSO push |
| `ecotrack://map?mode=routes&date={YYYY-MM-DD}` | `/map?mode=routes&date={YYYY-MM-DD}` | Tapping `"Уточнить транспорт на карте →"` on Home or History |
| `ecotrack://stats/challenge` | `/stats` (scrolls to Shared Forest card) | Push notification for cooperative "Shared Forest" milestone |
| `ecotrack://home` | `/home` (triggers mascot wake-up bounce animation) | Tapping a friend's `"Разбудить зверька 🔔"` push notification |

---

## 5. Networking Layer (`dio ^5.x`) & Error Mapping

### 5.1 Sealed `Result<T, AppError>` and `AppError` Contract

```dart
enum ClientErrorAction {
  none,
  refreshToken,
  forceLogout,
  showInline,
  showBanner,
  queueRetry,
  openPhoneModal,
  openConsentScreen;

  static ClientErrorAction fromWire(String raw) => switch (raw) {
    'refresh_token' => ClientErrorAction.refreshToken,
    'force_logout' => ClientErrorAction.forceLogout,
    'show_inline' => ClientErrorAction.showInline,
    'show_banner' => ClientErrorAction.showBanner,
    'queue_retry' => ClientErrorAction.queueRetry,
    'open_phone_modal' => ClientErrorAction.openPhoneModal,
    'open_consent_screen' => ClientErrorAction.openConsentScreen,
    _ => ClientErrorAction.none,
  };
}

final class AppError(
  final String code,
  final int httpStatus,
  final String domain,
  final bool retryable,
  final ClientErrorAction clientAction,
  final String uiMessageRu, [
  final Map<String, String> fieldIssues = const {},
]);

sealed class Result<T, E>;

final class Ok<T, E>(final T value) extends Result<T, E>;

final class Err<T, E>(final E error) extends Result<T, E>;
```

### 5.2 Exact Dio Interceptor Pipeline Order
`DioClient` registers 4 interceptors in strict sequence:
1. **`AuthHeaderInterceptor`**: Reads the active JWT access token from memory/secure storage and attaches `Authorization: Bearer <access_token>` to all requests except `/api/v1/auth/oauth/exchange`, `/api/v1/auth/refresh`, `/healthz`, and `/readyz`.
2. **`IdempotencyKeyInterceptor`**: For every request where `options.method` is `'POST'`, `'PUT'`, `'PATCH'`, or `'DELETE'`, checks if `options.headers['Idempotency-Key']` is already set (e.g., replayed from `offline_mutation_outbox`). If absent, generates a fresh RFC 9562 UUIDv7 via `UuidV7.generate()` and sets `options.headers['Idempotency-Key']`.
3. **`TokenRefreshInterceptor` (`QueuedInterceptorsWrapper`)**:
   - Intercepts `401` responses where `response.data['error_code'] == 'AUTH_TOKEN_EXPIRED'`.
   - Because it extends `QueuedInterceptorsWrapper`, concurrent requests hitting `401` queue behind a single refresh execution (preventing parallel refresh storms).
   - Calls `POST /api/v1/auth/refresh` with `{refresh_token, device_fingerprint}` using a separate bare `Dio` instance.
   - On `200 OK`: persists the rotated token pair to `FlutterSecureStorage` and retries the original request with the preserved `Idempotency-Key`.
   - On `401 REFRESH_TOKEN_EXPIRED_OR_REVOKED` or `DEVICE_FINGERPRINT_MISMATCH`: clears session and dispatches `AuthForceLogoutRequested` to `AuthBloc`.
4. **`ErrorCatalogMapperInterceptor`**:
   - Extracts `error_code` and `details` from the backend unified `ErrorResponse` JSON envelope and looks up the exact entry in `ErrorCatalogRegistry` (loaded at startup from `assets/errors/error_catalog.json`).
   - For network timeouts or socket errors (`DioExceptionType.connectionError`, `connectionTimeout`, `receiveTimeout`), maps to `DATABASE_UNAVAILABLE` (`retryable: true, client_action: queue_retry`).
   - Automatically triggers global modal guards if `client_action == openPhoneModal` (`GOOGLE_FORMAL_PHONE_REQUIRED`) or `client_action == openConsentScreen` (`FZ152_CONSENT_REQUIRED`, `FZ152_CONSENT_REVOKED`).

---

## 6. Unified Dual-Mode Map (`flutter_map ^8.2+`) Architecture

Both `[ Мои маршруты ]` and `[ Пункты РСО ]` share a single `FlutterMap` instance inside `MapActivityScreen` wrapped in a `RepaintBoundary` so switching modes never destroys the underlying GL/Impeller canvas or tile cache.

### 6.1 Shared Tile Layer & Offline Tile Cache
- **Tile Source**: OpenFreeMap / OSM Bright raster-vector compatible tile endpoint (`https://tiles.openfreemap.org/planet/{z}/{x}/{y}.png` or configured self-hosted tile mirror).
- **Tile Provider**: `CachedTileProvider` from `flutter_map_cache` backed by a SQLite store (`maxStale: const Duration(days: 14)`), allowing full offline map viewing of previously visited districts.
- **Legal Attribution Layer**: Pinned `RichAttributionWidget` at bottom of map viewport displaying `attribution_banner_ru` (`"© Участники OpenStreetMap (ODbL 1.0) · data.mos.ru · Муниципальные реестры"`).

### 6.2 Mode A: `[ Мои маршруты ]` Layer Stack & Segment Hit-Testing
1. **Motion-Class Polyline Layer (`PolylineLayer<int>`)**:
   - Uses a `LayerHitNotifier<int>()` (`_segmentHitNotifier`) where each `Polyline<int>` carries `hitValue: segmentIndex`.
   - Visual styling per `TrackPointMotionClass`:
     - **Unallocated `walking`**: `color: Color(0xFF1E1E1E)`, `strokeWidth: 4.5`, `pattern: StrokePattern.dashed(segments: [10, 6])`.
     - **Allocated `route_segment_allocations`**: `color: Color(0xFF1E1E1E)`, `strokeWidth: 6.5`, solid stroke with border `borderColor: Color(0xFFFFFFFF)`, `borderStrokeWidth: 2.0`.
     - **`indoor_pacing`**: `color: Color(0xFF868686)`, `strokeWidth: 3.0`, `pattern: StrokePattern.dotted()`.
     - **`vehicle_suspected`**: `color: Color(0xFFC4C4C4)`, `strokeWidth: 2.5` (tapping triggers inline `SEGMENT_CONTAINS_VEHICLE_MOTION` message).
2. **Waypoint & Transport Badge Marker Layer (`MarkerLayer`)**:
   - Renders start (`A`) and end (`B`) draggable sequence handles when selecting a segment (`start_seq_no` .. `end_seq_no`) plus floating pill badges (`"🚌 -142 г"`) at the midpoint of each saved allocation.
3. **Interactive `TransportAllocationBottomSheet`**:
   - Computes real-time client preview of $C_k = \text{round}(D_k \times K_{\text{mode}} \times 1.0)$ vs default fallback $\text{round}(D_k \times 0.80 \times 0.08200 \times 0.70)$ as the user taps transport chips (`bus`, `metro`, `tram`, `personal_car`, `car_compact`, `car_sedan`, `car_suv`, `car_ev`).
   - Submitting dispatches `MapRouteAllocationsSaved` to `MapActivityBloc`, which calls `PUT /api/v1/activity/daily/{activity_date}/allocations` (or queues in `offline_mutation_outbox` if offline).

### 6.3 Mode B: `[ Пункты РСО ]` Layer Stack, Clustering & External Navigation
1. **Debounced BBox Query (`300 ms`)**:
   - `MapController.mapEventStream` listens for `MapEventMoveEnd` and `MapEventRotateEnd`, debounces by `300 ms`, extracts `camera.visibleBounds` (`min_lat`, `min_lon`, `max_lat`, `max_lon`) and `camera.zoom.round()`, and calls `GET /api/v1/map/waste-points`.
2. **Zoom-Adaptive Clustering**:
   - At zoom `>= 13`, `MarkerClusterLayerWidget` (`flutter_map_marker_cluster`) groups nearby pins within a `45 dp` radius into monochrome circular count badges (`#1E1E1E` fill, `#FFFFFF` tabular count) with smooth spiderfy/zoom-on-tap animation.
   - At zoom `<= 12`, increases cluster radius to `80 dp` and disables individual label rendering to maintain `< 16.6 ms` frame raster time.
3. **External Navigator Deep Links**:
   - Inside `WastePointDetailSheet`, tapping `"Построить маршрут во внешнем навигаторе"` checks installed schemes via `url_launcher` in order:
     1. Yandex Maps: `yandexmaps://maps.yandex.ru/?rtext=~{lat},{lon}&rtt=pd`
     2. 2GIS: `dgis://2gis.ru/routeSearch/rsType/pedestrian/to/{lon},{lat}`
     3. Universal Geo URI fallback: `geo:{lat},{lon}?q={lat},{lon}({encodedTitle})`

### 6.4 Impeller 60fps Map Performance Invariants
- **Polyline Simplification**: If `track_points.length > 2000`, `PolylineSimplifier.simplifyRdp(points, epsilonMeters: 1.5)` reduces visual vertices before building `PolylineLayer` while keeping exact server `seq_no` indices intact.
- **Zero Widget Rebuild on Pan**: `MapActivityScreen` never calls `setState()` on continuous `MapEventMove` frames; camera position updates are isolated to `MapController`.

---

## 7. Interactive Schematic Vector Mascot (`FoxMascotWidget`) & Accessories Architecture

### 7.1 `FoxMascotWidget` & `MascotVectorPainter`
Located on Tab 3 (`Home`), `FoxMascotWidget` is a stateful widget mixing in `SingleTickerProviderStateMixin`:
1. **Breathing Controller**:
   - `AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true)` drives `breathingPhase` $\in [0.0, 1.0]$.
   - `MascotVectorPainter` applies a vertical scale transform $S_y = 0.985 + 0.030 \times \sin(\pi \cdot \text{breathingPhase})$ anchored at the mascot's paws and rotates the schematic tail by $\pm 4.5^\circ$.
2. **Press / Hold Squinting Interaction**:
   - Wrapped in `GestureDetector(onTapDown: ..., onTapUp: ..., onTapCancel: ..., onLongPressStart: ..., onLongPressEnd: ...)`.
   - Pressing sets `isPointerSquinting = true`, morphing the eye paths from open circles/arcs into schematic `^ ^` squinting chevrons and flattening the ear triangles by $12^\circ$.
3. **Deterministic Mood Expression Rendering (`MascotMoodState`)**:
   - `sleepy` (`0%` of `daily_co2_goal_grams`): Closed horizontal eyelid lines, curled posture, animated floating `"Zzz"` vector paths.
   - `neutral` (`1%–49%` of goal): Standard schematic geometric fox head/body posture, calm upright ears.
   - `happy` (`50%–99%` of goal): cheerful curved eye arcs, faster tail wag frequency ($1.5\times$).
   - `thriving` (`100%+` of goal): Wide celebratory `^ ^` eyes, upright ears, geometric star sparkles orbiting the silhouette.

### 7.2 Modular Vector Accessory Overlay Painters (`MascotAccessoryLayerPainter`)
Each `accessory_code` in `mascot_accessories` maps to a dedicated pure-vector painting routine anchored to deterministic socket coordinates (`headAnchor`, `neckAnchor`, `eyesAnchor`, `auraCenter`) on the `240x240` mascot canvas:

| `accessory_code` | `slot` | Vector Drawing Specification |
| :--- | :--- | :--- |
| `leaf_sprout_hat` | `head` | Two-leaf clover stem path anchored at `headAnchor(120, 42)` swaying with `breathingPhase`. |
| `knit_green_scarf` | `neck` | Ribbed geometric collar + hanging fringe path anchored at `neckAnchor(120, 138)`. |
| `solar_shades` | `glasses` | Angular wireframe aviator polygons with diagonal reflection strokes over `eyesAnchor(120, 96)`. |
| `moss_crown` | `head` | Geometric woodland crown ring with botanical nodes around `headAnchor(120, 46)`. |
| `firefly_aura` | `aura` | 6 orbiting glowing wireframe circles around `auraCenter(120, 120)` phase-shifted by $2\pi / 6$. |

---

## 8. OAuth PKCE (`flutter_appauth`) & `PushProvider` Abstraction

### 8.1 OAuth 2.1 + PKCE Client (`OAuthPkceClient`)
All three providers (**Яндекс ID**, **VK ID**, **Google**) use `FlutterAppAuth.authorize()` with `S256` PKCE challenge generation (`codeVerifier` generated on device, **token exchange executed on the EcoTrack backend** via `POST /api/v1/auth/oauth/exchange` so client secrets never ship in the mobile binary):
1. Call `appAuth.authorize(AuthorizationRequest(clientId, redirectUrl: 'ecotrack://auth/callback', serviceConfiguration: providerConfig, scopes: scopes))`.
2. Extract `authorizationCode` and `codeVerifier` from `AuthorizationResponse`.
3. Send `OAuthExchangeRequest` (`provider`, `authorization_code`, `code_verifier`, `redirect_uri`, `device_fingerprint`, `policy_version: "1.0.0-2026"`, `consent_scope`) to `POST /api/v1/auth/oauth/exchange`.
4. If `AuthSessionResponse.is_foreign_provider_lab_mode == true` (`provider == 'google'`), `AuthBloc` displays `GoogleLabModeBanner` and transitions to `AuthGooglePhoneRequired` until `POST /api/v1/auth/google-phone` succeeds.

### 8.2 `PushProvider` Interface & `FcmPushProvider`
To guarantee a 2-line swap between Firebase Cloud Messaging (`firebase_messaging`) and Russian domestic push gateways (`RuStore Push` / `APNs`), all push operations depend strictly on `PushProvider`:

```dart
final class PushMessagePayload(
  this.title,
  this.body,
  this.deepLinkUri,
  this.data,
) {
  final String title;
  final String body;
  final String? deepLinkUri;
  final Map<String, Object?> data;
}

abstract interface class PushProvider {
  Future<void> initialize();
  Future<String?> getDevicePushToken();
  Stream<String> get onTokenRefresh;
  Stream<PushMessagePayload> get onForegroundMessage;
  Stream<String> get onNotificationTapDeepLink;
}
```
- `FcmPushProvider` implements `PushProvider` using `FirebaseMessaging.instance` and `FlutterLocalNotificationsPlugin` (Android high-importance channel `'ecotrack_social_nudges'`, title `"Эко-уведомления и друзья"`).
- When a foreground message arrives (e.g., `"Друг {name} будит вашего зверька! 🔔"`), `FcmPushProvider` displays a local notification and emits on `onForegroundMessage`. Tapping the notification emits `deepLinkUri` (`ecotrack://home` or `ecotrack://stats/challenge`) on `onNotificationTapDeepLink`, which `AppRouter` routes to the target screen.
