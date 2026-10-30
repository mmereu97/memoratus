import 'package:flutter_test/flutter_test.dart';

import 'package:memoratus/main.dart';

void main() {
  group('rich text tags', () {
    test('plain text is one token', () {
      final t = parseRich('Doamne miluiește');
      expect(t.length, 1);
      expect(t.first.text, 'Doamne miluiește');
      expect(t.first.bold || t.first.italic || t.first.red, isFalse);
    });

    test('bold, italic and red (rubric) tags', () {
      final t = parseRich('Sfinte [b]Dumnezeule[/b], [i]Sfinte[/i] [r]Tare[/r]');
      expect(t.where((x) => x.bold).single.text, 'Dumnezeule');
      expect(t.where((x) => x.italic).single.text, 'Sfinte');
      expect(t.where((x) => x.red).single.text, 'Tare');
    });

    test('stripTags removes only the formatting', () {
      expect(stripTags('[r]Slavă[/r] Tatălui și [b]Fiului[/b]'), 'Slavă Tatălui și Fiului');
    });
  });

  group('wrapping by characters', () {
    test('short line stays on one row', () {
      expect(wrapLineByChars(parseRich('Tatăl nostru'), 40).length, 1);
    });

    test('long line wraps into several rows', () {
      final line = List.filled(20, 'cuvânt').join(' '); // 20 × 6 letters + spaces
      expect(wrapLineByChars(parseRich(line), 30).length, greaterThan(3));
    });

    test('empty line gives one empty row', () {
      final rows = wrapLineByChars(parseRich(''), 30);
      expect(rows.length, 1);
      expect(rows.first, isEmpty);
    });
  });
}
