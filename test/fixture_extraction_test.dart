import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/services/chunker.dart';
import 'package:pdf_listener/services/pdf_extractor.dart';
import 'package:pdf_listener/services/text_cleaner.dart';

const fixture = 'test/fixtures/study_guide.pdf';

void main() {
  final file = File(fixture);

  group('study_guide.pdf', () {
    late List<TextBlock> blocks;
    late List<ChunkDraft> chunks;

    setUpAll(() {
      final pages = PdfExtractor.extractLinesSync(file.readAsBytesSync(), 1, 28);
      blocks = cleanPages(pages);
      chunks = chunkBlocks(blocks);
    });

    test('"Page # of 28" footer never appears', () {
      final pattern = RegExp(r'page\s*\d+\s*of\s*28', caseSensitive: false);
      expect(blocks.where((b) => pattern.hasMatch(b.text)), isEmpty);
      expect(chunks.where((c) => pattern.hasMatch(c.text)), isEmpty);
    });

    test('running title is not read on every page', () {
      final title = blocks
          .where((b) => b.text.contains('Junior DevOps Interview Study Guide'))
          .length;
      expect(title, lessThanOrEqualTo(1));
    });

    test('code blocks are skipped, kerning splits are repaired', () {
      expect(blocks.where((b) => b.kind == BlockKind.code), isNotEmpty);
      final text = blocks.map((b) => b.text).join(' ');
      expect(text, isNot(contains('"Effect": "Allow"')));
      expect(text, isNot(contains('A WS')));
      expect(text, contains('AWS'));
      expect(text, isNot(contains('→')));
    });

    test('headings are detected and chunks stay small and on one page', () {
      expect(chunks.where((c) => c.isHeading).map((c) => c.text),
          contains('1. Cloud basics and global infrastructure.'));
      expect(chunks.length, greaterThan(150));
      expect(chunks.every((c) => c.text.length <= 600), isTrue);
      expect(chunks.every((c) => c.pageNumber >= 1 && c.pageNumber <= 28), isTrue);
    });
  }, skip: file.existsSync() ? false : 'Fixture $fixture not present');
}
