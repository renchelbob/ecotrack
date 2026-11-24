import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

final class UserVehicle {
  const UserVehicle({
    required this.name,
    required this.fuelType,
    required this.litersPer100Km,
  });

  factory UserVehicle.fromJson(Map<String, Object?> json) => UserVehicle(
    name: json['name'] as String? ?? 'Автомобиль',
    fuelType: json['fuel_type'] as String? ?? 'Бензин',
    litersPer100Km: (json['liters_per_100km'] as num?)?.toDouble() ?? 8.5,
  );

  factory UserVehicle.defaultVehicle() => const UserVehicle(
    name: 'Городской седан',
    fuelType: 'Бензин АИ-95',
    litersPer100Km: 8.5,
  );

  final String name;
  final String fuelType;
  final double litersPer100Km;

  Map<String, Object?> toJson() => {
    'name': name,
    'fuel_type': fuelType,
    'liters_per_100km': litersPer100Km,
  };
}

final class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.phoneMasked,
    required this.friendCode,
    required this.pointsBalance,
    required this.dailyStepGoal,
    required this.vehicle,
  });

  final String id;
  final String displayName;
  final String email;
  final String phoneMasked;
  final String friendCode;
  final int pointsBalance;
  final int dailyStepGoal;
  final UserVehicle vehicle;

  static Result<UserProfile, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'display_name': final String name,
      'friend_code': final String friendCode,
    }) {
      return Ok(
        UserProfile(
          id: id,
          displayName: name,
          email: json['email'] as String? ?? '',
          phoneMasked: json['phone_masked'] as String? ?? '+7 (9**) ***-**-**',
          friendCode: friendCode,
          pointsBalance: (json['points_balance'] as num?)?.toInt() ?? 0,
          dailyStepGoal: (json['daily_step_goal'] as num?)?.toInt() ?? 10000,
          vehicle: json['vehicle'] is Map<String, Object?>
              ? UserVehicle.fromJson(json['vehicle']! as Map<String, Object?>)
              : UserVehicle.defaultVehicle(),
        ),
      );
    }
    return Err(
      AppError.fromCode('VALIDATION_ERROR', 'Неверный формат профиля'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'email': email,
    'phone_masked': phoneMasked,
    'friend_code': friendCode,
    'points_balance': pointsBalance,
    'daily_step_goal': dailyStepGoal,
    'vehicle': vehicle.toJson(),
  };
}

abstract interface class ProfileRepository {
  Future<Result<UserProfile, AppError>> getProfile();
  Future<Result<void, AppError>> exportPersonalData152Fz();
  Future<Result<void, AppError>> deleteAccount152Fz();
}
