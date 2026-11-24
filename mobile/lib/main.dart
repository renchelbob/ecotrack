import 'package:ecotrack_mobile/app.dart';
import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load machine-readable error catalog
  await AppError.loadCatalog();

  // Initialize SQLite with WAL mode & foreign keys
  try {
    await SqliteDatabase.instance.initialize();
  } catch (_) {
    // Database fallback handles memory/unsupported environments
  }

  // Start background outbox sync worker
  OutboxDispatcher().startWorker();

  runApp(const EcoTrackApp());
}
