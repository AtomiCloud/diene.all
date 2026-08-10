/// Journey drivers — reusable, ordered sequences of async steps a consumer
/// runs to exercise a user flow end-to-end against stubbed backends.
///
/// A journey is `diene_e2e`'s own harness glue: it turns the "arrange a stub,
/// act through the client, assert the outcome" pattern into a named, replayable
/// script so int/e2e tiers do not hand-roll the same orchestration.
library;

/// The outcome of running one [JourneyStep].
class JourneyStepResult {
  const JourneyStepResult({required this.name, required this.ok, this.detail});

  final String name;
  final bool ok;
  final String? detail;
}

/// One named step in a journey. Returns `true` when the step succeeded.
class JourneyStep {
  const JourneyStep(this.name, this.run);

  final String name;
  final Future<bool> Function() run;
}

/// The result of running a whole [Journey].
class JourneyResult {
  const JourneyResult(this.steps);

  final List<JourneyStepResult> steps;

  /// Whether every step succeeded.
  bool get ok => steps.every((JourneyStepResult s) => s.ok);

  /// The first failing step, or `null` when the journey passed.
  JourneyStepResult? get firstFailure {
    for (final JourneyStepResult s in steps) {
      if (!s.ok) return s;
    }
    return null;
  }
}

/// An ordered set of steps. Runs them in sequence and stops at the first
/// failure (later steps are not recorded), modelling a real user flow where a
/// broken step aborts the journey.
class Journey {
  Journey(this.name, this.steps);

  final String name;
  final List<JourneyStep> steps;

  Future<JourneyResult> run() async {
    final List<JourneyStepResult> results = <JourneyStepResult>[];
    for (final JourneyStep step in steps) {
      bool ok;
      String? detail;
      try {
        ok = await step.run();
      } on Object catch (error) {
        ok = false;
        detail = error.toString();
      }
      results.add(JourneyStepResult(name: step.name, ok: ok, detail: detail));
      if (!ok) break;
    }
    return JourneyResult(results);
  }
}
