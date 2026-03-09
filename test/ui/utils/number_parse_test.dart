import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/utils/number_parse.dart';

void main() {
  group('parseDoubleFlexible', () {
    test('parses locale variants and grouped values', () {
      expect(parseDoubleFlexible('1,79'), 1.79);
      expect(parseDoubleFlexible('1.790'), 1790);
      expect(parseDoubleFlexible('1,790'), 1790);
      expect(parseDoubleFlexible('1 790,25'), 1790.25);
      expect(parseDoubleFlexible('1.790,25'), 1790.25);
      expect(parseDoubleFlexible('1,790.25'), 1790.25);
    });

    test('returns null for empty and incomplete values', () {
      expect(parseDoubleFlexible(''), isNull);
      expect(parseDoubleFlexible('   '), isNull);
      expect(parseDoubleFlexible('-'), isNull);
      expect(parseDoubleFlexible('1,'), isNull);
      expect(parseDoubleFlexible('1.'), isNull);
      expect(parseDoubleFlexible('abc'), isNull);
    });
  });

  group('parseIntFlexible', () {
    test('parses grouped integer values', () {
      expect(parseIntFlexible('1.790'), 1790);
      expect(parseIntFlexible('1,790'), 1790);
      expect(parseIntFlexible('1790'), 1790);
    });

    test('returns null for decimal and invalid values', () {
      expect(parseIntFlexible('1790,5'), isNull);
      expect(parseIntFlexible('1790.5'), isNull);
      expect(parseIntFlexible(''), isNull);
      expect(parseIntFlexible('foo'), isNull);
    });
  });
}
