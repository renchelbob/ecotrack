import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DTO Round-Trip Serialization Tests', () {
    test('DailyActivitySummary fromJson / toJson parity', () {
      const summary = DailyActivitySummary(
        id: 'summary_001',
        activityDate: '2026-11-24',
        validatedSteps: 8520,
        totalStepDistanceM: 6304.8,
        allocatedGpsDistanceM: 1500.0,
        unallocatedStepDistanceM: 4804.8,
        allocatedCo2SavedGrams: 297,
        autoDefaultCo2SavedGrams: 220,
        totalCo2SavedGrams: 517,
        pointsBalance: 850,
        isAutoCalculated: false,
        streakDays: 7,
        mascotMood: MascotMood.thriving,
      );

      final json = summary.toJson();
      final parsed = DailyActivitySummary.fromJson(json);

      expect(parsed.isOk, isTrue);
      final value = parsed.okOrNull;
      expect(value, isNotNull);
      expect(value?.id, equals(summary.id));
      expect(value?.activityDate, equals(summary.activityDate));
      expect(value?.validatedSteps, equals(summary.validatedSteps));
      expect(value?.totalCo2SavedGrams, equals(summary.totalCo2SavedGrams));
      expect(value?.pointsBalance, equals(summary.pointsBalance));
      expect(value?.streakDays, equals(summary.streakDays));
      expect(value?.mascotMood, equals(summary.mascotMood));
    });

    test('UserVehicle fromJson / toJson parity', () {
      const vehicle = UserVehicle(
        name: 'Кроссовер 2.0',
        fuelType: 'Бензин АИ-95',
        litersPer100Km: 9.8,
      );

      final json = vehicle.toJson();
      final parsed = UserVehicle.fromJson(json);

      expect(parsed.name, equals(vehicle.name));
      expect(parsed.fuelType, equals(vehicle.fuelType));
      expect(parsed.litersPer100Km, closeTo(vehicle.litersPer100Km, 0.001));
    });

    test('UserProfile fromJson / toJson parity', () {
      final profile = UserProfile(
        id: 'usr_01935c10-0000-7000-8000-000000000001',
        displayName: 'Вадим Нопин',
        email: 'vadim@vyatsu.ru',
        phoneMasked: '+7 (***) ***-12-34',
        friendCode: 'ECO-VDM2-2026',
        pointsBalance: 450,
        dailyStepGoal: 10000,
        vehicle: UserVehicle.defaultVehicle(),
      );

      final json = profile.toJson();
      final parsed = UserProfile.fromJson(json);

      expect(parsed.isOk, isTrue);
      final value = parsed.okOrNull;
      expect(value, isNotNull);
      expect(value?.id, equals(profile.id));
      expect(value?.displayName, equals(profile.displayName));
      expect(value?.email, equals(profile.email));
      expect(value?.phoneMasked, equals(profile.phoneMasked));
      expect(value?.friendCode, equals(profile.friendCode));
      expect(value?.pointsBalance, equals(profile.pointsBalance));
      expect(value?.dailyStepGoal, equals(profile.dailyStepGoal));
      expect(value?.vehicle.name, equals(profile.vehicle.name));
    });

    test('WastePoint fromJson / toJson parity', () {
      const point = WastePoint(
        id: 'wp_kirov_01',
        title: 'Эко-пункт на Ленина',
        address: 'г. Киров, ул. Ленина, 105',
        latitude: 58.6035,
        longitude: 49.6680,
        wasteTypes: ['Пластик', 'Бумага', 'Стекло'],
        trustScore: 88.5,
      );

      final json = point.toJson();
      final parsed = WastePoint.fromJson(json);

      expect(parsed.isOk, isTrue);
      final value = parsed.okOrNull;
      expect(value, isNotNull);
      expect(value?.id, equals(point.id));
      expect(value?.title, equals(point.title));
      expect(value?.address, equals(point.address));
      expect(value?.latitude, closeTo(point.latitude, 0.0001));
      expect(value?.longitude, closeTo(point.longitude, 0.0001));
      expect(value?.wasteTypes, equals(point.wasteTypes));
      expect(value?.trustScore, closeTo(point.trustScore, 0.1));
    });

    test('ShopCoupon fromJson / toJson parity', () {
      const coupon = ShopCoupon(
        id: 'shop_coffee_01',
        title: 'Скидка 20% на кофе в свою кружку',
        partnerName: 'Бодрый День',
        costPoints: 150,
        discountPercent: 20,
        category: 'Напитки',
        description: 'Экологичная скидка для тех, кто бережет планету.',
      );

      final json = coupon.toJson();
      final parsed = ShopCoupon.fromJson(json);

      expect(parsed.isOk, isTrue);
      final value = parsed.okOrNull;
      expect(value, isNotNull);
      expect(value?.id, equals(coupon.id));
      expect(value?.title, equals(coupon.title));
      expect(value?.partnerName, equals(coupon.partnerName));
      expect(value?.costPoints, equals(coupon.costPoints));
      expect(value?.discountPercent, equals(coupon.discountPercent));
      expect(value?.category, equals(coupon.category));
    });

    test('AuthSession fromJson / toJson parity', () {
      const session = AuthSession(
        accessToken: 'jwt_mock_access_token_12345',
        refreshToken: 'jwt_mock_refresh_token_67890',
        userId: 'usr_01935c10-0000-7000-8000-000000000001',
        displayName: 'Вадим Нопин',
        email: 'vadim@vyatsu.ru',
        phoneMasked: '+7 (***) ***-12-34',
        hasFz152Consent: true,
      );

      final json = session.toJson();
      final parsed = AuthSession.fromJson(json);

      expect(parsed.isOk, isTrue);
      final value = parsed.okOrNull;
      expect(value, isNotNull);
      expect(value?.accessToken, equals(session.accessToken));
      expect(value?.refreshToken, equals(session.refreshToken));
      expect(value?.userId, equals(session.userId));
      expect(value?.displayName, equals(session.displayName));
      expect(value?.email, equals(session.email));
      expect(value?.phoneMasked, equals(session.phoneMasked));
      expect(value?.hasFz152Consent, isTrue);
    });
  });
}
