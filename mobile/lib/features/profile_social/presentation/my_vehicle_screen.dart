import 'dart:async';

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/vehicle_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

final class const MyVehicleScreen({super.key}) extends StatefulWidget {
  @override
  State<MyVehicleScreen> createState() => _MyVehicleScreenState();
}

final class _MyVehicleScreenState() extends State<MyVehicleScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _consumptionController = TextEditingController();
  bool _syncedControllers = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<VehicleCubit>();
    if (cubit.state is VehicleLoading) {
      unawaited(cubit.load());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _consumptionController.dispose();
    super.dispose();
  }

  void _syncControllersIfNeeded(VehicleState state) {
    if (_syncedControllers) return;
    final (String name, double cons) = switch (state) {
      VehicleConfigured(:final draftName, :final draftConsumption) => (
        draftName,
        draftConsumption,
      ),
      VehicleUnconfigured(:final draftName, :final draftConsumption) => (
        draftName,
        draftConsumption,
      ),
      VehicleLoading() => ('', 0.0),
    };
    if (name.isNotEmpty) {
      _nameController.text = name;
      _consumptionController.text = cons.toStringAsFixed(1);
      _syncedControllers = true;
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<VehicleCubit, VehicleState>(
        listener: (context, state) {
          final err = switch (state) {
            VehicleConfigured(:final activeError) => activeError,
            VehicleUnconfigured(:final activeError) => activeError,
            VehicleLoading() => null,
          };
          final feedback = switch (state) {
            VehicleConfigured(:final feedbackMessage) => feedbackMessage,
            VehicleUnconfigured(:final feedbackMessage) => feedbackMessage,
            VehicleLoading() => null,
          };
          if (err != null) {
            EcoErrorBannerPresenter.show(context, err);
          } else if (feedback != null) {
            EcoTopBannerOverlay.instance.showMessage(feedback);
          }
        },
        builder: (context, state) {
          _syncControllersIfNeeded(state);
          return Scaffold(
            backgroundColor: EcoColors.surfacePrimary,
            appBar: AppBar(title: const Text('Мой автомобиль')),
            body: switch (state) {
              VehicleLoading() => const Center(
                child: CircularProgressIndicator(color: EcoColors.inkPrimary),
              ),
              VehicleConfigured() => _VehicleFormBody(
                isConfigured: true,
                draftFuel: state.draftFuel,
                draftConsumption: state.draftConsumption,
                previewGPerKm: state.previewCo2GPerKm,
                previewGPerM: state.previewCo2GPerMeter,
                isSaving: state.isSaving,
                nameController: _nameController,
                consumptionController: _consumptionController,
              ),
              VehicleUnconfigured() => _VehicleFormBody(
                isConfigured: false,
                draftFuel: state.draftFuel,
                draftConsumption: state.draftConsumption,
                previewGPerKm: state.previewCo2GPerKm,
                previewGPerM: state.previewCo2GPerMeter,
                isSaving: state.isSaving,
                nameController: _nameController,
                consumptionController: _consumptionController,
              ),
            },
          );
        },
      );
}

final class const _VehicleFormBody({
  required final bool isConfigured,
  required final FuelType draftFuel,
  required final double draftConsumption,
  required final double previewGPerKm,
  required final double previewGPerM,
  required final bool isSaving,
  required final TextEditingController nameController,
  required final TextEditingController consumptionController,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VehicleCubit>();
    return ListView(
      padding: const .all(16),
      children: [
        TextField(
          controller: nameController,
          onChanged: (val) =>
              cubit.selectDraft(draftFuel, draftConsumption, val),
          decoration: const InputDecoration(
            labelText: 'Название авто',
            prefixIcon: Icon(LucideIcons.car),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Тип топлива / двигателя', style: EcoTypography.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FuelType.values
              .map(
                (fuel) => ChoiceChip(
                  label: Text(fuel.displayNameRu),
                  selected: fuel == draftFuel,
                  onSelected: (_) => cubit.selectDraft(
                    fuel,
                    draftConsumption,
                    nameController.text,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Средний расход на 100 км: ${draftConsumption.toStringAsFixed(1)}',
          style: EcoTypography.bodyLarge,
        ),
        Slider(
          value: draftConsumption.clamp(0.5, 50.0),
          min: 0.5,
          max: 50.0,
          divisions: 99,
          activeColor: EcoColors.inkPrimary,
          onChanged: (v) {
            consumptionController.text = v.toStringAsFixed(1);
            cubit.selectDraft(draftFuel, v, nameController.text);
          },
        ),
        TextField(
          controller: consumptionController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (raw) {
            final parsed = double.tryParse(raw.replaceAll(',', '.'));
            if (parsed != null && parsed > 0 && parsed <= 50.0) {
              cubit.selectDraft(draftFuel, parsed, nameController.text);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Точный расход (л или кВт·ч / 100 км)',
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: EcoColors.surfaceCard,
            borderRadius: .all(.circular(20)),
            border: .fromBorderSide(
              BorderSide(color: EcoColors.borderMuted, width: 1.5),
            ),
          ),
          child: Padding(
            padding: const .all(14),
            child: Text(
              'Расчётный выброс вашего авто: ${previewGPerKm.toStringAsFixed(2)} г CO₂ / км (${previewGPerM.toStringAsFixed(5)} г / м)',
              style: EcoTypography.tabularMetric,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: isSaving
              ? null
              : () => unawaited(
                  cubit.saveVehicle(
                    nameController.text,
                    draftFuel,
                    draftConsumption,
                  ),
                ),
          child: const Text('Сохранить автомобиль'),
        ),
        if (isConfigured) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: isSaving ? null : () => unawaited(cubit.deleteVehicle()),
            child: const Text('Удалить авто'),
          ),
        ],
      ],
    );
  }
}
