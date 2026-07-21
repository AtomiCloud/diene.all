import 'package:diene_result/diene_result.dart';

void main() {
  final Result<int> parsed = Result<int>.ok(21)
      .map((int value) => value * 2)
      .andThen(
        (int value) => value == 42
            ? Result<int>.ok(value)
            : Result<int>.err(
                Problem(
                  type: 'about:blank',
                  title: 'Unexpected value',
                  status: 500,
                ),
              ),
      );

  parsed.match<void>(ok: (int value) {}, err: (Problem problem) {});
}
