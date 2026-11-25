import 'dart:async';

import 'package:ecotrack_mobile/app.dart';
import 'package:ecotrack_mobile/core/di/app_dependencies.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:material_ui/material_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('EcoTrack FlutterError: ${details.exceptionAsString()}');
  };

  await ErrorCatalogRegistry.instance.loadFromAsset();
  final dependencies = await AppDependencies.create();
  unawaited(dependencies.pushProvider.initialize());

  runApp(EcoTrackApp(dependencies: dependencies));
}
