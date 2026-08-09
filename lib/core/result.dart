sealed class Result<T> {
  const Result();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Problem failure) onFailure,
  }) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Failure<T>(:final problem) => onFailure(problem),
  };

  bool get isSuccess => this is Success<T>;
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.problem);

  final Problem problem;
}

class Problem {
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.recoverable = false,
    this.data = const <String, Object?>{},
  });

  factory Problem.fromJson(Map<String, Object?> json) => Problem(
    type: json['type'] as String? ?? 'about:blank',
    title: json['title'] as String? ?? 'Unexpected problem',
    status: json['status'] as int? ?? 500,
    detail: json['detail'] as String?,
    instance: json['instance'] as String?,
    recoverable: json['recoverable'] as bool? ?? false,
    data: (json['data'] as Map<Object?, Object?>? ?? const <Object?, Object?>{})
        .map((Object? key, Object? value) => MapEntry(key.toString(), value)),
  );

  final String type;
  final String title;
  final int status;
  final String? detail;
  final String? instance;
  final bool recoverable;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'title': title,
    'status': status,
    if (detail != null) 'detail': detail,
    if (instance != null) 'instance': instance,
    'recoverable': recoverable,
    'data': data,
  };
}
