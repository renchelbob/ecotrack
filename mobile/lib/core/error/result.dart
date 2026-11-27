sealed class const Result<T, E>() {
  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T? get valueOrNull => switch (this) {
    Ok(value: final v) => v,
    Err() => null,
  };

  E? get errorOrNull => switch (this) {
    Ok() => null,
    Err(error: final e) => e,
  };

  R when<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) => switch (this) {
    Ok(value: final v) => ok(v),
    Err(error: final e) => err(e),
  };
}

final class const Ok<T, E>(final T value) extends Result<T, E>;

final class const Err<T, E>(final E error) extends Result<T, E>;
