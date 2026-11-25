import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:glados/glados.dart';

void main() {
  setUpAll(() {
    ErrorCatalogRegistry.instance.loadFromJsonString('''
{
  "errors": {
    "VALIDATION_ERROR": {
      "code": "VALIDATION_ERROR",
      "http_status": 422,
      "domain": "validation",
      "retryable": false,
      "client_action": "show_inline",
      "ui_message_ru": "Проверьте корректность данных"
    }
  }
}
''');
  });

  group('DTO Round-Trip Property-Based Serialization Tests', () {
    Glados3(
      any.intInRange(0, 100000),
      any.intInRange(40, 120),
      any.intInRange(0, 50000),
    ).test('DailyActivitySummary toJson / fromJson round-trip parity', (
      steps,
      strideCm,
      points,
    ) {
      final totalDist = (steps * strideCm) / 100.0;
      final summary = DailyActivitySummary(
        id: 'sum-$steps',
        activityDate: '2026-11-24',
        rawSensorSteps: steps,
        validatedSteps: steps,
        strideLengthCm: strideCm,
        totalStepDistanceM: totalDist,
        allocatedGpsDistanceM: 0.0,
        unallocatedStepDistanceM: totalDist,
        allocatedCo2SavedGrams: 0,
        autoDefaultCo2SavedGrams: (totalDist * 0.04592).round(),
        totalCo2SavedGrams: (totalDist * 0.04592).round(),
        pointsAwardedForDay: steps ~/ 100,
        pointsDeltaApplied: 0,
        pointsBalance: points,
        isAutoCalculated: true,
        antifraudFlagged: false,
      );

      final parsed = DailyActivitySummary.fromJson(summary.toJson());
      expect(parsed.isOk, isTrue);
      final value = parsed.valueOrNull;
      expect(value?.id, equals(summary.id));
      expect(value?.validatedSteps, equals(summary.validatedSteps));
      expect(value?.strideLengthCm, equals(summary.strideLengthCm));
      expect(value?.totalCo2SavedGrams, equals(summary.totalCo2SavedGrams));
      expect(value?.pointsBalance, equals(summary.pointsBalance));
    });

    Glados2(any.choose(FuelType.values), any.doubleInRange(1.0, 45.0)).test(
      'UserVehicle toJson / fromJson round-trip parity',
      (fuel, consumption) {
        final gKm = (fuel.emissionFactorGPerUnit * consumption) / 100.0;
        final vehicle = UserVehicle(
          id: 'veh-1',
          vehicleName: 'Eco Car',
          fuel: fuel,
          consumptionPer100km: consumption,
          fuelEmissionFactorGPerUnit: fuel.emissionFactorGPerUnit,
          computedCo2GPerKm: gKm,
          computedCo2GPerMeter: gKm / 1000.0,
          updatedAt: '2026-11-24T12:00:00Z',
        );

        final parsed = UserVehicle.fromJson(vehicle.toJson());
        expect(parsed.isOk, isTrue);
        final value = parsed.valueOrNull;
        expect(value?.fuel, equals(fuel));
        expect(value?.consumptionPer100km, closeTo(consumption, 0.0001));
        expect(value?.computedCo2GPerKm, closeTo(gKm, 0.0001));
      },
    );

    Glados2(
      any.intInRange(1000, 30000),
      any.choose(MascotMoodState.values),
    ).test('UserProfile toJson / fromJson round-trip parity', (stepGoal, mood) {
      final profile = UserProfile(
        id: 'usr-1',
        email: 'eco@vyatsu.ru',
        displayName: 'Иван',
        friendCode: 'ECO-1234-ABCD',
        requiresFormalPhone: false,
        pointsBalance: 250,
        lifetimePointsEarned: 500,
        lifetimeCo2SavedGrams: 12000,
        currentStreakDays: 4,
        longestStreakDays: 9,
        streakFreezeCount: 1,
        dailyStepGoal: stepGoal,
        dailyCo2GoalGrams: 1500,
        isGpsTrackingEnabled: true,
        isStatsVisibleToFriends: true,
        is152fzConsentActive: true,
        mascot: MascotVisualState(mood: mood, dailyGoalProgressRatio: 0.75),
        createdAt: '2026-11-24T12:00:00Z',
      );

      final parsed = UserProfile.fromJson(profile.toJson());
      expect(parsed.isOk, isTrue);
      final value = parsed.valueOrNull;
      expect(value?.dailyStepGoal, equals(stepGoal));
      expect(value?.mascot.mood, equals(mood));
      expect(value?.friendCode, equals('ECO-1234-ABCD'));
    });

    Glados3(
      any.doubleInRange(-89.0, 89.0),
      any.doubleInRange(-179.0, 179.0),
      any.choose(WastePointStatus.values),
    ).test('WastePointMapItem toJson / fromJson round-trip parity', (
      lat,
      lon,
      status,
    ) {
      final point = WastePointMapItem(
        id: 'wp-1',
        title: 'Пункт РСО',
        addressText: 'ул. Ленина, 10',
        acceptedFractions: const [
          WasteFractionCode.plastic,
          WasteFractionCode.glass,
        ],
        lat: lat,
        lon: lon,
        status: status,
        trustScore: 87.5,
        confirmationsCount: 5,
        issuesCount: 0,
      );

      final parsed = WastePointMapItem.fromJson(point.toJson());
      expect(parsed.isOk, isTrue);
      final value = parsed.valueOrNull;
      expect(value?.lat, closeTo(lat, 0.0001));
      expect(value?.lon, closeTo(lon, 0.0001));
      expect(value?.status, equals(status));
    });

    Glados2(any.intInRange(10, 5000), any.choose(ShopItemType.values)).test(
      'ShopCatalogItem & ShopOrderDetail round-trip parity',
      (price, itemType) {
        final item = ShopCatalogItem(
          id: 'item-1',
          sku: 'SKU-1',
          itemType: itemType,
          title: 'Купон',
          subtitle: 'Скидка',
          description: 'Описание',
          pricePoints: price,
          maxPerUserPerDay: 2,
          imageAssetKey: 'coupon_coffee',
        );
        final parsedItem = ShopCatalogItem.fromJson(item.toJson());
        expect(parsedItem.isOk, isTrue);
        expect(parsedItem.valueOrNull?.pricePoints, equals(price));
        expect(parsedItem.valueOrNull?.itemType, equals(itemType));

        final order = ShopOrderDetail(
          id: 'ord-1',
          idempotencyKey: '0195a1b2-c3d4-7000-8000-000000000001',
          status: OrderStatus.completed,
          totalPoints: price,
          remainingPointsBalance: 100,
          itemCount: 1,
          lineItems: [
            ShopOrderLineItem(
              id: 'line-1',
              shopItemId: 'item-1',
              title: 'Купон',
              itemType: itemType,
              quantity: 1,
              unitPricePoints: price,
              lineTotalPoints: price,
              couponCode: 'ECO-2026',
              qrPayload: 'ecotrack://qr/1',
            ),
          ],
          createdAt: '2026-11-24T12:00:00Z',
        );
        final parsedOrder = ShopOrderDetail.fromJson(order.toJson());
        expect(parsedOrder.isOk, isTrue);
        expect(
          parsedOrder.valueOrNull?.lineItems.single.couponCode,
          equals('ECO-2026'),
        );
      },
    );

    Glados3(any.bool, any.bool, any.intInRange(-500, 500)).test(
      'ConsentScopeObject & PointLedgerItem round-trip parity',
      (pdn, gps, delta) {
        final scope = ConsentScopeObject(
          personalData152fz: pdn,
          healthStepsSensor: true,
          backgroundGeolocation: gps,
        );
        final parsedScope = ConsentScopeObject.fromJson(scope.toJson());
        expect(parsedScope.isOk, isTrue);
        expect(parsedScope.valueOrNull?.personalData152fz, equals(pdn));
        expect(parsedScope.valueOrNull?.backgroundGeolocation, equals(gps));

        final ledger = PointLedgerItem(
          id: 'led-1',
          idempotencyKey: '0195a1b2-c3d4-7000-8000-000000000002',
          operationType: LedgerOperationType.dailyStepsReward,
          pointsDelta: delta,
          co2DeltaGrams: delta * 10,
          description: 'Награда',
          createdAt: '2026-11-24T12:00:00Z',
        );
        final parsedLedger = PointLedgerItem.fromJson(ledger.toJson());
        expect(parsedLedger.isOk, isTrue);
        expect(parsedLedger.valueOrNull?.pointsDelta, equals(delta));

        final eq = EcoEquivalentsMetrics(
          totalCo2SavedGrams: delta.abs() * 10,
          treesPlantedEquivalent: 0.5,
          carKmAvoided: 12.4,
          smartphoneChargesEquivalent: 100,
          plasticBottlesRecycledEquivalent: 40,
          ledBulbHoursEquivalent: 300,
        );
        final parsedEq = EcoEquivalentsMetrics.fromJson(eq.toJson());
        expect(parsedEq.isOk, isTrue);
        expect(
          parsedEq.valueOrNull?.totalCo2SavedGrams,
          equals(delta.abs() * 10),
        );
      },
    );
  });
}
