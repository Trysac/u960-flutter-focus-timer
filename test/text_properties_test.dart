// Property tests: invariants checked by kiri_check on generated inputs from a fixed seed, so every run checks the same
// cases (and shrinks a failure to its smallest input).
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';
import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart';

const _seed = 20260101;

/// Text that is never blank: an `x` between generated runs of letters, digits, whitespace and accented letters.
final _inputs = string(
  minLength: 0,
  maxLength: 12,
  characterSet: CharacterSet.fromCharacters('abzABZ09 \t\n-_éÄ'),
).map((core) => ' x$core\t');

void main() {
  property('normalize is idempotent', () {
    forAll(_inputs, (input) {
      final once = normalize(input);
      expect(normalize(once), once);
    }, seed: _seed);
  });

  property('normalize leaves no surrounding whitespace', () {
    forAll(_inputs, (input) {
      final result = normalize(input);
      expect(result, result.trim());
    }, seed: _seed);
  });

  property('normalize leaves no ASCII upper-case letters', () {
    forAll(_inputs, (input) {
      expect(normalize(input), isNot(matches(RegExp('[A-Z]'))));
    }, seed: _seed);
  });
}
