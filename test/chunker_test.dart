import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/services/chunk_lookup.dart';
import 'package:pdf_listener/services/chunker.dart';
import 'package:pdf_listener/services/text_cleaner.dart';

void main() {
  group('splitSentences', () {
    test('splits on terminal punctuation', () {
      expect(splitSentences('One. Two? Three! "Four." Five'),
          ['One.', 'Two?', 'Three!', '"Four."', 'Five']);
    });

    test('keeps abbreviations, initials and section numbers together', () {
      expect(splitSentences('Ask Dr. Rao about J. Smith. Then go.'),
          ['Ask Dr. Rao about J. Smith.', 'Then go.']);
      expect(splitSentences('1. Cloud basics.'), ['1. Cloud basics.']);
    });

    test('does not split decimals or lowercase continuations', () {
      expect(splitSentences('Version 2.5 is out. it works.'),
          ['Version 2.5 is out. it works.']);
    });
  });

  group('chunkBlocks', () {
    final rng = Random(42);
    String sentence() {
      final words = List.generate(
          3 + rng.nextInt(25), (_) => 'word${rng.nextInt(1000)}');
      return '${words.join(' ')}.'.replaceFirst('w', 'W');
    }

    test('no chunk exceeds 600 chars, 4 sentences, or crosses a page', () {
      final blocks = [
        for (var p = 1; p <= 30; p++)
          for (var k = 0; k < 4; k++)
            TextBlock(BlockKind.paragraph,
                List.generate(1 + rng.nextInt(12), (_) => sentence()).join(' '), p),
      ];
      final chunks = chunkBlocks(blocks);
      expect(chunks.length, greaterThan(150));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(600));
        expect(splitSentences(c.text).length, lessThanOrEqualTo(4));
      }
      // Each chunk's text comes from exactly one block, on that block's page.
      for (final c in chunks) {
        final owners = blocks.where((b) => b.text.contains(c.text));
        expect(owners, isNotEmpty);
        expect(owners.every((b) => b.pageNumber == c.pageNumber), isTrue);
      }
    });

    test('never merges two paragraphs into one chunk', () {
      final chunks = chunkBlocks(const [
        TextBlock(BlockKind.paragraph, 'Short one.', 1),
        TextBlock(BlockKind.paragraph, 'Short two.', 1),
      ]);
      expect(chunks.map((c) => c.text), ['Short one.', 'Short two.']);
    });

    test('an oversized sentence is split at clause boundaries', () {
      final long = '${List.generate(80, (i) => 'clause $i, more text').join(' ')}.';
      final chunks = chunkBlocks([TextBlock(BlockKind.paragraph, long, 3)]);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.text.length <= 600 && c.pageNumber == 3), isTrue);
      expect(chunks.map((c) => c.text).join(' '), long);
    });

    test('raw code without sentences is split at line breaks', () {
      final code = List.generate(60, (i) => '"key$i": "value$i",').join('\n');
      final chunks = chunkBlocks([TextBlock(BlockKind.code, code, 1)]);
      expect(chunks.every((c) => c.text.length <= 600), isTrue);
      expect(chunks.first.text.endsWith(','), isTrue);
    });

    test('carries the heading flag', () {
      final chunks = chunkBlocks(const [
        TextBlock(BlockKind.heading, 'Networking.', 2),
        TextBlock(BlockKind.paragraph, 'VPCs are private networks.', 2),
      ]);
      expect(chunks.map((c) => c.isHeading), [true, false]);
    });
  });

  group('chunkIndexAt', () {
    final starts = [
      for (var i = 0; i < 1000; i++) Duration(milliseconds: i * 1500),
    ];

    test('finds the chunk containing a position', () {
      expect(chunkIndexAt(starts, Duration.zero), 0);
      expect(chunkIndexAt(starts, const Duration(milliseconds: 1499)), 0);
      expect(chunkIndexAt(starts, const Duration(milliseconds: 1500)), 1);
      expect(chunkIndexAt(starts, const Duration(seconds: 300)), 200);
      expect(chunkIndexAt(starts, const Duration(hours: 9)), 999);
    });

    test('handles empty lists and zero-length chunks', () {
      expect(chunkIndexAt(const [], Duration.zero), -1);
      final dupes = [Duration.zero, const Duration(seconds: 2), const Duration(seconds: 2)];
      expect(chunkIndexAt(dupes, const Duration(seconds: 2)), 2);
      expect(chunkIndexAt(dupes, const Duration(seconds: 1)), 0);
    });
  });
}
