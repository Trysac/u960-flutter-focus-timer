import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';
import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart';

/// Command action generated for property testing.
final class _CommandStep {
  const _CommandStep(this.kind, this.deltaSeconds, this.tag);

  final int kind;
  final int deltaSeconds;
  final String? tag;

  @override
  String toString() => '_CommandStep(kind: $kind, deltaSeconds: $deltaSeconds, tag: $tag)';
}

Arbitrary<_CommandStep> _stepArbitrary() => combine3(
  integer(min: 0, max: 5),
  integer(min: 0, max: 1800),
  oneOf(<Arbitrary<String?>>[constant(null), constant('code'), constant('write'), constant('review')]),
).map((tuple) => _CommandStep(tuple.$1, tuple.$2, tuple.$3 as String?));

void main() {
  group('Acceptance Criterion 4: Replay property tests', () {
    property(
      'FocusTimer.fromLog(log) rebuilds a state equal to the live timer state and round-trips through LogCodec',
      () {
        forAll(
          list(_stepArbitrary(), minLength: 1, maxLength: 25),
          (steps) {
            final config = TimerConfig(
              focus: const Duration(minutes: 25),
              shortBreak: const Duration(minutes: 5),
              longBreak: const Duration(minutes: 15),
              longBreakEvery: 4,
              autoStartBreaks: true,
              autoStartFocus: false,
            );
            final store = MemoryEventStore();
            final live = FocusTimer(config, store);

            var now = DateTime.utc(2026, 1, 5, 9, 0, 0);

            for (final step in steps) {
              now = now.add(Duration(seconds: step.deltaSeconds));
              try {
                switch (step.kind) {
                  case 0:
                    live.startFocus(now, tag: step.tag);
                  case 1:
                    live.pause(now);
                  case 2:
                    live.resume(now);
                  case 3:
                    live.skip(now);
                  case 4:
                    live.reset(now);
                  default:
                    live.tick(now);
                }
              } on FocusTimerException catch (e) {
                expect(e.code, 'invalid_transition');
              }
            }

            // Settle up to `now` so the log contains all elapsed transitions
            // and the live timer's state is anchored at `now`.
            live.tick(now);
            // Record an explicit terminal event at `now` if running so that
            // `fromLog` (which only sees persisted events) knows the exact
            // elapsed time within the current running phase.
            if (live.state.phase != Phase.idle && !live.state.paused) {
              live.pause(now);
              live.resume(now);
            }

            final log = store.load();
            final replayed = FocusTimer.fromLog(config, log);
            expect(replayed.state, equals(live.state));

            final encoded = LogCodec.encode(log);
            final decoded = LogCodec.decode(encoded);
            expect(decoded, equals(log));
            expect(FocusTimer.fromLog(config, decoded).state, equals(live.state));
          },
          seed: 960,
          maxExamples: 500,
        );
      },
    );
  });
}
