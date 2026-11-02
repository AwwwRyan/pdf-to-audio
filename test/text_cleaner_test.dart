import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/models/pdf_line.dart';
import 'package:pdf_listener/services/chunker.dart';
import 'package:pdf_listener/services/text_cleaner.dart';

/// Body text: 12pt, 12pt tall bounds, 18pt line pitch (6pt gap).
PdfLine line(String text, double top,
        {double size = 12, String font = 'Helvetica', double left = 50}) =>
    PdfLine(
      text: text,
      fontName: font,
      fontSize: size,
      left: left,
      top: top,
      right: left + text.length * size * 0.5,
      bottom: top + size,
    );

PdfPageLines page(int number, List<PdfLine> lines) =>
    PdfPageLines(pageNumber: number, height: 800, lines: lines);

String allText(List<TextBlock> blocks) => blocks.map((b) => b.text).join('\n');

void main() {
  group('headers and footers', () {
    test('repeated running title and "Page X of N" footer are removed', () {
      final pages = [
        for (var p = 1; p <= 4; p++)
          page(p, [
            line('AWS Study Guide', 20, size: 8),
            line('Body text on page $p is here.', 100),
            line('It continues on the next line.', 118),
            line('Page $p of 28', 775, size: 8, left: 500),
          ]),
      ];
      final blocks = cleanPages(pages);
      final text = allText(blocks);
      expect(text, isNot(contains('AWS Study Guide')));
      expect(text, isNot(contains('of 28')));
      expect(text, contains('Body text on page 3 is here.'));
      expect(blocks.map((b) => b.pageNumber).toSet(), {1, 2, 3, 4});
    });

    test('page numbers differing in digit count still match', () {
      expect(normalizeForRepeat('Page 9 of 28'), normalizeForRepeat('Page 10 of 28'));
    });

    test('a lone page-number footer is dropped even on a single page', () {
      final blocks = cleanPages([
        page(7, [line('Only page in range.', 100), line('- 7 -', 775)]),
      ]);
      expect(allText(blocks), 'Only page in range.');
    });

    test('text repeated in the body area is kept', () {
      final pages = [
        for (var p = 1; p <= 3; p++)
          page(p, [line('Summary', 300), line('Unique $p.', 340)]),
      ];
      expect(allText(cleanPages(pages)), contains('Summary'));
    });
  });

  group('headings', () {
    test('a large-font heading becomes its own sentence with a pause', () {
      final blocks = cleanPages([
        page(1, [
          line('Getting started', 60, size: 18),
          line('This is the first body line and it', 90),
          line('wraps onto a second line.', 108),
        ]),
      ]);
      expect(blocks.first.kind, BlockKind.heading);
      expect(blocks.first.text, 'Getting started.');
      expect(blocks[1].kind, BlockKind.paragraph);
      expect(blocks[1].text,
          'This is the first body line and it wraps onto a second line.');

      final chunks = chunkBlocks(blocks);
      expect(chunks.first.isHeading, isTrue);
      expect(chunks.first.text, 'Getting started.');
      expect(chunks[1].isHeading, isFalse);
    });

    test('a heading wrapped over two lines stays one heading', () {
      final blocks = cleanPages([
        page(1, [
          line('1. Cloud basics and global', 60, size: 18),
          line('infrastructure', 84, size: 18),
          line('Body text that is long enough to set the body size', 120),
          line('for the whole page, as real documents always do.', 138),
        ]),
      ]);
      expect(blocks.first.text, '1. Cloud basics and global infrastructure.');
      expect(chunkBlocks(blocks).first.text,
          '1. Cloud basics and global infrastructure.');
    });

    test('a short standalone body-size line is treated as a subheading', () {
      final blocks = cleanPages([
        page(1, [
          line('First paragraph wraps over', 60),
          line('two lines and ends here.', 78),
          line('Key terms', 104),
          line('Region — a geographic area that', 130),
          line('wraps onto another line.', 148),
        ]),
      ]);
      expect(blocks.map((b) => b.kind), [
        BlockKind.paragraph,
        BlockKind.heading,
        BlockKind.paragraph,
      ]);
      expect(blocks[1].text, 'Key terms.');
    });
  });

  group('code blocks', () {
    List<PdfPageLines> codePage() => [
          page(1, [
            line('A policy looks like this:', 60),
            line('{', 90, font: 'CourierNew', size: 10),
            line('"Effect": "Allow"', 104, font: 'CourierNew', size: 10),
            line('}', 118, font: 'CourierNew', size: 10),
            line('That grants access.', 145),
          ]),
        ];

    test('a multi-line monospace block becomes a spoken cue', () {
      final blocks = cleanPages(codePage());
      expect(blocks.map((b) => b.text), [
        'A policy looks like this:',
        'Code example skipped.',
        'That grants access.',
      ]);
      expect(blocks[1].kind, BlockKind.code);
    });

    test('with "Read code blocks" on, the block is kept raw', () {
      final blocks =
          cleanPages(codePage(), config: const CleanerConfig(readCodeBlocks: true));
      expect(blocks[1].text, '{\n"Effect": "Allow"\n}');
    });

    test('inline monospace inside a normal line is left alone', () {
      final blocks = cleanPages([
        page(1, [
          line('Run', 60, left: 50),
          line('df -h', 60, font: 'JetBrainsMono', left: 80),
          line('to check disk space.', 60, left: 120),
          line('Then carry on.', 78),
        ]),
      ]);
      expect(blocks.single.text, 'Run df -h to check disk space. Then carry on.');
    });

    test('a single monospace line on its own is read as text', () {
      final blocks = cleanPages([
        page(1, [
          line('Use this:', 60),
          line('docker ps', 90, font: 'Consolas'),
          line('Done.', 120),
        ]),
      ]);
      expect(allText(blocks), isNot(contains(codeSkippedCue)));
      expect(allText(blocks), contains('docker ps'));
    });
  });

  group('paragraphs', () {
    test('split by vertical gap without blank lines', () {
      final blocks = cleanPages([
        page(1, [
          line('First paragraph line one', 100),
          line('and line two.', 118),
          line('Second paragraph starts', 144),
          line('after a bigger gap.', 162),
        ]),
      ]);
      expect(blocks.map((b) => b.text), [
        'First paragraph line one and line two.',
        'Second paragraph starts after a bigger gap.',
      ]);
    });

    test('hyphenated words are joined across line breaks', () {
      final blocks = cleanPages([
        page(1, [line('This is an exam-', 100), line('ple of wrapping.', 118)]),
      ]);
      expect(blocks.single.text, 'This is an example of wrapping.');
    });

    test('lines out of reading order are sorted by position', () {
      final blocks = cleanPages([
        page(1, [line('second line.', 118), line('The first and', 100)]),
      ]);
      expect(blocks.single.text, 'The first and second line.');
    });
  });

  group('substitutions', () {
    test('symbols and abbreviations are spoken consistently', () {
      expect(applySpokenSubstitutions('Request → load balancer'),
          'Request to load balancer');
      expect(applySpokenSubstitutions('Oct 29 · Aryan'), 'Oct 29, Aryan');
      expect(applySpokenSubstitutions('Regions (e.g. Mumbai)'),
          'Regions (for example Mumbai)');
      expect(applySpokenSubstitutions('one AZ, i.e. one building'),
          'one AZ, that is one building');
      expect(applySpokenSubstitutions('HA vs fault tolerance'),
          'HA versus fault tolerance');
      expect(applySpokenSubstitutions('AWS & DevOps'), 'AWS and DevOps');
    });

    test('spacing before punctuation is tidied without gluing words', () {
      expect(normalizeSpacing('a balancer , then  done .'), 'a balancer, then done.');
      expect(normalizeSpacing('paste it into a .env file'), 'paste it into a .env file');
    });

    test('are applied by the cleaner but not to raw code', () {
      final blocks = cleanPages([
        page(1, [
          line('Client → server & back.', 60),
          line('a → b', 90, font: 'Courier'),
          line('c & d', 104, font: 'Courier'),
        ]),
      ], config: const CleanerConfig(readCodeBlocks: true));
      expect(blocks[0].text, 'Client to server and back.');
      expect(blocks[1].text, 'a → b\nc & d');
    });
  });

  group('glyph runs', () {
    test('kerned glyphs join and real spaces and column gaps are kept', () {
      const runs = [
        GlyphRun('A', 0, 8),
        GlyphRun('W', 7.5, 18),
        GlyphRun('S', 18, 25),
        GlyphRun(' ', 25, 27.5),
        GlyphRun('Y', 27.5, 35),
        GlyphRun('o', 34.2, 41),
        GlyphRun('u', 41, 48),
        GlyphRun('E', 120, 128), // next table column
        GlyphRun('C', 128, 136),
      ];
      expect(joinGlyphRuns(runs, 16), 'AWS You EC');
    });
  });

  test('scanned detection counts only spoken characters', () {
    expect(spokenAlnumCount(const [TextBlock(BlockKind.code, codeSkippedCue, 1)]), 0);
    expect(spokenAlnumCount(const [TextBlock(BlockKind.paragraph, 'Ab 12.', 1)]), 4);
  });
}
