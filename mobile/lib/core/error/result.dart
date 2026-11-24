import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:flutter/foundation.dart';

/// Sealed Result type representing either a successful [Ok] value or a failure [Err].
@immutable
sealed class Result<T, E extends AppError> {
  const Result();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T? get okOrNull => switch (this) {
    Ok(value: final v) => v,
    Err() => null,
  };

  E? get errOrNull => switch (this) {
    Ok() => null,
    Err(error: final e) => e,
  };

  R fold<R>(R Function(T value) onOk, R Function(E error) onErr) =>
      switch (this) {
        Ok(value: final v) => onOk(v),
        Err(error: final e) => onErr(e),
      };

  Result<R, E> map<R>(R Function(T value) transform) => switch (this) {
    Ok(value: final v) => Ok(transform(v)),
    Err(error: final e) => Err(e),
  };
}

@immutable
final class Ok<T, E extends AppError> extends Result<T, E> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T, E> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

@immutable
final class Err<T, E extends AppError> extends Result<T, E> {
  const Err(this.error);
  final E error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T, E> && other.error == error);

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Err($error)';
}
