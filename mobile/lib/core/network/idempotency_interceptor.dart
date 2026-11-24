import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';

final class IdempotencyInterceptor extends Interceptor {
  const IdempotencyInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    if (['POST', 'PUT', 'PATCH', 'DELETE'].contains(method)) {
      if (!options.headers.containsKey('Idempotency-Key')) {
        options.headers['Idempotency-Key'] = UuidV7.generate();
      }
    }
    handler.next(options);
  }
}
