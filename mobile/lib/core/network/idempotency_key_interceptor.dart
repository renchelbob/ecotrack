import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';

final class const IdempotencyKeyInterceptor() extends Interceptor {
  static const Set<String> _mutatingMethods = {
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_mutatingMethods.contains(options.method.toUpperCase())) {
      final hasKey = _hasNonEmptyHeader(options.headers, 'Idempotency-Key');
      if (!hasKey) {
        options.headers['Idempotency-Key'] = UuidV7.generate();
      }
    }
    handler.next(options);
  }

  static bool _hasNonEmptyHeader(Map<String, Object?> headers, String target) {
    final lowerTarget = target.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerTarget) {
        final value = entry.value;
        return value is String && value.isNotEmpty;
      }
    }
    return false;
  }
}
