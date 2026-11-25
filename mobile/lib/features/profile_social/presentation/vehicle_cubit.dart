import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class const VehicleState();

final class const VehicleLoading() extends VehicleState;

final class const VehicleConfigured({
  required final UserVehicle vehicle,
  required final FuelType draftFuel,
  required final double draftConsumption,
  required final String draftName,
  required final double previewCo2GPerKm,
  required final double previewCo2GPerMeter,
  final bool isSaving = false,
  final AppError? activeError,
  final String? feedbackMessage,
}) extends VehicleState;

final class const VehicleUnconfigured({
  required final FuelType draftFuel,
  required final double draftConsumption,
  required final String draftName,
  required final double previewCo2GPerKm,
  required final double previewCo2GPerMeter,
  final bool isSaving = false,
  final AppError? activeError,
  final String? feedbackMessage,
}) extends VehicleState;

final class VehicleCubit(final ProfileRepository _profileRepo)
    extends Cubit<VehicleState> {
  this : super(const VehicleLoading());

  Future<void> load() async {
    emit(const VehicleLoading());
    final res = await _profileRepo.getMyVehicle();
    if (isClosed) {
      return;
    }
    switch (res) {
      case Ok(value: final vehicle):
        emit(
          VehicleConfigured(
            vehicle: vehicle,
            draftFuel: vehicle.fuel,
            draftConsumption: vehicle.consumptionPer100km,
            draftName: vehicle.vehicleName,
            previewCo2GPerKm: vehicle.computedCo2GPerKm,
            previewCo2GPerMeter: vehicle.computedCo2GPerMeter,
          ),
        );
      case Err(:final error):
        final factors = _safeFactors(.petrol95, 8.5);
        emit(
          VehicleUnconfigured(
            draftFuel: .petrol95,
            draftConsumption: 8.5,
            draftName: 'Мой автомобиль',
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            activeError: error.code == 'VEHICLE_NOT_CONFIGURED' ? null : error,
          ),
        );
    }
  }

  void selectDraft(FuelType fuel, double consumption, [String? name]) {
    final clamped = consumption.clamp(0.5, 50.0);
    final factors = _safeFactors(fuel, clamped);
    switch (state) {
      case VehicleConfigured(:final vehicle, :final draftName, :final isSaving):
        emit(
          VehicleConfigured(
            vehicle: vehicle,
            draftFuel: fuel,
            draftConsumption: clamped,
            draftName: name ?? draftName,
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            isSaving: isSaving,
          ),
        );
      case VehicleUnconfigured(:final draftName, :final isSaving):
        emit(
          VehicleUnconfigured(
            draftFuel: fuel,
            draftConsumption: clamped,
            draftName: name ?? draftName,
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            isSaving: isSaving,
          ),
        );
      case VehicleLoading():
        emit(
          VehicleUnconfigured(
            draftFuel: fuel,
            draftConsumption: clamped,
            draftName: name ?? 'Мой автомобиль',
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
          ),
        );
    }
  }

  Future<void> saveVehicle(
    String name,
    FuelType fuel,
    double consumption,
  ) async {
    final resolvedName = name.trim().isEmpty ? 'Мой автомобиль' : name.trim();
    if (consumption <= 0.0 || consumption > 50.0) {
      _emitError(AppError.fromCode('INVALID_VEHICLE_CONSUMPTION'));
      return;
    }
    final factors = _safeFactors(fuel, consumption);
    _emitSaving(resolvedName, fuel, consumption, factors);

    final res = await _profileRepo.upsertVehicle(
      resolvedName,
      fuel,
      consumption,
    );
    if (isClosed) {
      return;
    }
    switch (res) {
      case Ok(value: final vehicle):
        emit(
          VehicleConfigured(
            vehicle: vehicle,
            draftFuel: vehicle.fuel,
            draftConsumption: vehicle.consumptionPer100km,
            draftName: vehicle.vehicleName,
            previewCo2GPerKm: vehicle.computedCo2GPerKm,
            previewCo2GPerMeter: vehicle.computedCo2GPerMeter,
            feedbackMessage: 'Параметры автомобиля сохранены',
          ),
        );
      case Err(:final error):
        _emitError(error);
    }
  }

  Future<void> deleteVehicle() async {
    final res = await _profileRepo.deleteVehicle();
    if (isClosed) {
      return;
    }
    switch (res) {
      case Ok():
        final factors = _safeFactors(.petrol95, 8.5);
        emit(
          VehicleUnconfigured(
            draftFuel: .petrol95,
            draftConsumption: 8.5,
            draftName: 'Мой автомобиль',
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            feedbackMessage:
                'Автомобиль удалён (применяется стандарт 192 г/км)',
          ),
        );
      case Err(:final error):
        _emitError(error);
    }
  }

  ({double gPerKm, double gPerMeter, double factor}) _safeFactors(
    FuelType fuel,
    double consumption,
  ) => Co2Math.computeVehicleCo2Factors(
    fuel.wireName,
    consumption.clamp(0.1, 50.0),
  );

  void _emitSaving(
    String name,
    FuelType fuel,
    double consumption,
    ({double gPerKm, double gPerMeter, double factor}) factors,
  ) {
    switch (state) {
      case VehicleConfigured(:final vehicle):
        emit(
          VehicleConfigured(
            vehicle: vehicle,
            draftFuel: fuel,
            draftConsumption: consumption,
            draftName: name,
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            isSaving: true,
          ),
        );
      default:
        emit(
          VehicleUnconfigured(
            draftFuel: fuel,
            draftConsumption: consumption,
            draftName: name,
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            isSaving: true,
          ),
        );
    }
  }

  void _emitError(AppError error) {
    switch (state) {
      case VehicleConfigured(
        :final vehicle,
        :final draftFuel,
        :final draftConsumption,
        :final draftName,
        :final previewCo2GPerKm,
        :final previewCo2GPerMeter,
      ):
        emit(
          VehicleConfigured(
            vehicle: vehicle,
            draftFuel: draftFuel,
            draftConsumption: draftConsumption,
            draftName: draftName,
            previewCo2GPerKm: previewCo2GPerKm,
            previewCo2GPerMeter: previewCo2GPerMeter,
            activeError: error,
          ),
        );
      case VehicleUnconfigured(
        :final draftFuel,
        :final draftConsumption,
        :final draftName,
        :final previewCo2GPerKm,
        :final previewCo2GPerMeter,
      ):
        emit(
          VehicleUnconfigured(
            draftFuel: draftFuel,
            draftConsumption: draftConsumption,
            draftName: draftName,
            previewCo2GPerKm: previewCo2GPerKm,
            previewCo2GPerMeter: previewCo2GPerMeter,
            activeError: error,
          ),
        );
      case VehicleLoading():
        final factors = _safeFactors(.petrol95, 8.5);
        emit(
          VehicleUnconfigured(
            draftFuel: .petrol95,
            draftConsumption: 8.5,
            draftName: 'Мой автомобиль',
            previewCo2GPerKm: factors.gPerKm,
            previewCo2GPerMeter: factors.gPerMeter,
            activeError: error,
          ),
        );
    }
  }
}
