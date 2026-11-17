import 'package:test/test.dart';
import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart';

void main() {
  group('normalize', () {
    test('trims surrounding whitespace and lower-cases the text', () {
      expect(normalize('  Hello World '), 'hello world');
    });

    test('keeps inner whitespace', () {
      expect(normalize('\tA  B\n'), 'a  b');
    });

    test('lower-cases only ASCII letters', () {
      expect(normalize('ÉCOLE'), 'École');
    });

    test('throws BlankInputError on blank input', () {
      expect(
        () => normalize('   '),
        throwsA(isA<BlankInputError>().having((error) => error.message, 'message', 'input is blank')),
      );
    });

    test('throws an ArgumentError on empty input', () {
      expect(() => normalize(''), throwsArgumentError);
    });
  });
}
