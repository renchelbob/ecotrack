import 'dart:convert';
import 'package:flutter/services.dart';

/// Sealed error model mapped directly to `contracts/error_catalog.json`.
sealed class AppError implements Exception {
  const AppError({
    required this.code,
    required this.httpStatus,
    required this.domain,
    required this.retryable,
    required this.clientAction,
    required this.descriptionEn,
    required this.uiMessageRu,
  });

  factory AppError.fromCode(String code, [String? customMessageRu]) {
    final entry = _staticCatalog[code] ?? _fallbackError;
    return GenericAppError(
      code: code,
      httpStatus: entry.httpStatus,
      domain: entry.domain,
      retryable: entry.retryable,
      clientAction: entry.clientAction,
      descriptionEn: entry.descriptionEn,
      uiMessageRu: customMessageRu ?? entry.uiMessageRu,
    );
  }

  factory AppError.fromJson(Map<String, Object?> json) {
    if (json case {
      'code': final String code,
      'http_status': final int httpStatus,
      'domain': final String domain,
      'retryable': final bool retryable,
      'client_action': final String clientAction,
      'description_en': final String descriptionEn,
      'ui_message_ru': final String uiMessageRu,
    }) {
      return GenericAppError(
        code: code,
        httpStatus: httpStatus,
        domain: domain,
        retryable: retryable,
        clientAction: clientAction,
        descriptionEn: descriptionEn,
        uiMessageRu: uiMessageRu,
      );
    }
    return AppError.fromCode('VALIDATION_ERROR');
  }

  final String code;
  final int httpStatus;
  final String domain;
  final bool retryable;
  final String clientAction;
  final String descriptionEn;
  final String uiMessageRu;

  static Future<void> loadCatalog() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/errors/error_catalog.json',
      );
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded case {'errors': final Map<String, Object?> errors}) {
        for (final entry in errors.entries) {
          if (entry.value case final Map<String, Object?> map) {
            _staticCatalog[entry.key] = GenericAppError(
              code: map['code'] as String? ?? entry.key,
              httpStatus: (map['http_status'] as num?)?.toInt() ?? 500,
              domain: map['domain'] as String? ?? 'general',
              retryable: map['retryable'] as bool? ?? false,
              clientAction: map['client_action'] as String? ?? 'show_banner',
              descriptionEn: map['description_en'] as String? ?? '',
              uiMessageRu: map['ui_message_ru'] as String? ?? 'Ошибка сервиса',
            );
          }
        }
      }
    } catch (_) {
      // Fallback in-memory catalog will serve requests
    }
  }

  static final Map<String, AppError> _staticCatalog = {
    'INTERNAL_SERVER_ERROR': const GenericAppError(
      code: 'INTERNAL_SERVER_ERROR',
      httpStatus: 500,
      domain: 'infrastructure',
      retryable: true,
      clientAction: 'show_banner',
      descriptionEn: 'Unhandled server exception.',
      uiMessageRu: 'Внутренняя ошибка сервера. Попробуйте повторить позже.',
    ),
    'DATABASE_UNAVAILABLE': const GenericAppError(
      code: 'DATABASE_UNAVAILABLE',
      httpStatus: 503,
      domain: 'infrastructure',
      retryable: true,
      clientAction: 'queue_retry',
      descriptionEn: 'Database unreachable.',
      uiMessageRu: 'Сервис временно перегружен. Изменения сохранены локально.',
    ),
    'NETWORK_UNAVAILABLE': const GenericAppError(
      code: 'NETWORK_UNAVAILABLE',
      httpStatus: 0,
      domain: 'network',
      retryable: true,
      clientAction: 'queue_retry',
      descriptionEn: 'Network unreachable or connection timed out.',
      uiMessageRu: 'Нет соединения с интернетом. Работаем в офлайн-режиме.',
    ),
    'AUTH_TOKEN_EXPIRED': const GenericAppError(
      code: 'AUTH_TOKEN_EXPIRED',
      httpStatus: 401,
      domain: 'auth',
      retryable: false,
      clientAction: 'refresh_auth',
      descriptionEn: 'Access token expired.',
      uiMessageRu: 'Сессия истекла. Обновляем доступ...',
    ),
    'AUTH_REQUIRED': const GenericAppError(
      code: 'AUTH_REQUIRED',
      httpStatus: 401,
      domain: 'auth',
      retryable: false,
      clientAction: 'navigate_login',
      descriptionEn: 'Authentication required.',
      uiMessageRu: 'Пожалуйста, выполните вход в аккаунт.',
    ),
    'VALIDATION_ERROR': const GenericAppError(
      code: 'VALIDATION_ERROR',
      httpStatus: 422,
      domain: 'validation',
      retryable: false,
      clientAction: 'show_banner',
      descriptionEn: 'Validation error.',
      uiMessageRu: 'Проверьте правильность введенных данных.',
    ),
    'INSUFFICIENT_POINTS': const GenericAppError(
      code: 'INSUFFICIENT_POINTS',
      httpStatus: 400,
      domain: 'points',
      retryable: false,
      clientAction: 'show_banner',
      descriptionEn: 'Insufficient points balance.',
      uiMessageRu: 'Недостаточно эко-баллов на счете.',
    ),
    'FZ152_CONSENT_REQUIRED': const GenericAppError(
      code: 'FZ152_CONSENT_REQUIRED',
      httpStatus: 403,
      domain: 'auth',
      retryable: false,
      clientAction: 'show_consent_modal',
      descriptionEn: 'User consent under 152-FZ is required.',
      uiMessageRu:
          'Требуется подтверждение согласия на обработку персональных данных (152-ФЗ).',
    ),
    'FZ152_GOOGLE_PHONE_REQUIRED': const GenericAppError(
      code: 'FZ152_GOOGLE_PHONE_REQUIRED',
      httpStatus: 403,
      domain: 'auth',
      retryable: false,
      clientAction: 'show_phone_modal',
      descriptionEn: 'Phone number is mandatory under 152-FZ.',
      uiMessageRu:
          'По закону 152-ФЗ для авторизации через Google требуется указать номер телефона РФ (+7).',
    ),
  };

  static const _fallbackError = GenericAppError(
    code: 'UNKNOWN_ERROR',
    httpStatus: 500,
    domain: 'general',
    retryable: true,
    clientAction: 'show_banner',
    descriptionEn: 'An unexpected error occurred.',
    uiMessageRu: 'Произошла непредвиденная ошибка. Попробуйте позже.',
  );
}

final class GenericAppError extends AppError {
  const GenericAppError({
    required super.code,
    required super.httpStatus,
    required super.domain,
    required super.retryable,
    required super.clientAction,
    required super.descriptionEn,
    required super.uiMessageRu,
  });

  @override
  String toString() =>
      'AppError($code, status: $httpStatus, action: $clientAction)';
}
