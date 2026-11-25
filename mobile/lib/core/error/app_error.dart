import 'dart:convert';

import 'package:flutter/services.dart';

enum ClientErrorAction(final String wireName) {
  none('none'),
  refreshToken('refresh_token'),
  forceLogout('force_logout'),
  showInline('show_inline'),
  showBanner('show_banner'),
  queueRetry('queue_retry'),
  openPhoneModal('open_phone_modal'),
  openConsentScreen('open_consent_screen');

  static ClientErrorAction fromWire(String raw) => switch (raw) {
    'none' => ClientErrorAction.none,
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

final class const ErrorFieldIssue(final String field, final String issue);

final class const _CatalogEntry({
  required final String code,
  required final int httpStatus,
  required final String domain,
  required final bool retryable,
  required final ClientErrorAction clientAction,
  required final String uiMessageRu,
});

final class const AppError({
  required final String code,
  required final int httpStatus,
  required final String domain,
  required final bool retryable,
  required final ClientErrorAction clientAction,
  required final String uiMessageRu,
  final String? traceId,
  final List<ErrorFieldIssue> details = const [],
}) implements Exception {
  factory fromCode(
    String code, {
    String? traceId,
    List<ErrorFieldIssue> details = const [],
  }) => ErrorCatalogRegistry.instance.resolve(
    code,
    traceId: traceId,
    details: details,
  );

  @override
  String toString() =>
      'AppError($code, status: $httpStatus, action: ${clientAction.wireName})';
}

final class ErrorCatalogRegistry._() {
  static final ErrorCatalogRegistry instance = ErrorCatalogRegistry._();

  static const _CatalogEntry _defaultInternal = _CatalogEntry(
    code: 'INTERNAL_SERVER_ERROR',
    httpStatus: 500,
    domain: 'infrastructure',
    retryable: true,
    clientAction: ClientErrorAction.showBanner,
    uiMessageRu: 'Внутренняя ошибка сервера. Мы уже записали сбой — попробуйте повторить позже.',
  );

  static const _CatalogEntry _defaultDatabaseUnavailable = _CatalogEntry(
    code: 'DATABASE_UNAVAILABLE',
    httpStatus: 503,
    domain: 'infrastructure',
    retryable: true,
    clientAction: ClientErrorAction.queueRetry,
    uiMessageRu: 'Сервис временно перегружен. Изменения сохранены локально и синхронизируются автоматически.',
  );

  final Map<String, _CatalogEntry> _entries = <String, _CatalogEntry>{};

  Future<void> loadFromAsset([
    String assetPath = 'assets/errors/error_catalog.json',
  ]) async {
    final rawJson = await rootBundle.loadString(assetPath);
    loadFromJsonString(rawJson);
  }

  void loadFromJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, Object?>) {
      return;
    }
    final errorsNode = decoded['errors'];
    if (errorsNode is! Map<String, Object?>) {
      return;
    }

    _entries.clear();
    for (final entry in errorsNode.entries) {
      final rawItem = entry.value;
      if (rawItem is! Map<String, Object?>) {
        continue;
      }
      final code = rawItem['code'] as String? ?? entry.key;
      final httpStatus = (rawItem['http_status'] as num?)?.toInt() ?? 500;
      final domain = rawItem['domain'] as String? ?? 'infrastructure';
      final retryable = rawItem['retryable'] as bool? ?? false;
      final rawAction = rawItem['client_action'] as String? ?? 'none';
      final uiMessageRu = rawItem['ui_message_ru'] as String? ?? '';

      _entries[entry.key] = _CatalogEntry(
        code: code,
        httpStatus: httpStatus,
        domain: domain,
        retryable: retryable,
        clientAction: ClientErrorAction.fromWire(rawAction),
        uiMessageRu: uiMessageRu,
      );
    }
  }

  AppError resolve(
    String code, {
    String? traceId,
    List<ErrorFieldIssue> details = const [],
  }) {
    final entry =
        _entries[code] ??
        _entries['INTERNAL_SERVER_ERROR'] ??
        (code == 'DATABASE_UNAVAILABLE'
            ? _defaultDatabaseUnavailable
            : _defaultInternal);
    return AppError(
      code: entry.code,
      httpStatus: entry.httpStatus,
      domain: entry.domain,
      retryable: entry.retryable,
      clientAction: entry.clientAction,
      uiMessageRu: entry.uiMessageRu,
      traceId: traceId,
      details: details,
    );
  }

  AppError fromResponseMap(
    Map<String, Object?> json, {
    int? fallbackHttpStatus,
  }) {
    final errorCode = json['error_code'];
    final traceId = json['trace_id'] as String?;
    final rawDetails = json['details'];
    final parsedDetails = <ErrorFieldIssue>[];

    if (rawDetails is List<Object?>) {
      for (final item in rawDetails) {
        if (item is Map<String, Object?>) {
          final field = item['field'] as String? ?? '';
          final issue = item['issue'] as String? ?? '';
          parsedDetails.add(ErrorFieldIssue(field, issue));
        }
      }
    }

    if (errorCode is String && errorCode.isNotEmpty) {
      return resolve(errorCode, traceId: traceId, details: parsedDetails);
    }

    final fallbackCode = switch (fallbackHttpStatus) {
      401 => 'AUTH_TOKEN_INVALID',
      403 => 'FZ152_CONSENT_REQUIRED',
      422 => 'VALIDATION_ERROR',
      429 => 'RATE_LIMIT_EXCEEDED',
      503 => 'DATABASE_UNAVAILABLE',
      _ => 'INTERNAL_SERVER_ERROR',
    };

    return resolve(fallbackCode, traceId: traceId, details: parsedDetails);
  }
}
