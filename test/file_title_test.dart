import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/services/file_title.dart';

void main() {
  test('underscores become spaces and the extension is dropped', () {
    expect(titleFromFileName('AWS_DevOps_Interview_Study_Guide.pdf'),
        'AWS DevOps Interview Study Guide');
    expect(titleFromFileName('Report__2026_final.PDF'), 'Report 2026 final');
  });

  test('hyphens and other dots are kept', () {
    expect(titleFromFileName('SpotCare-style notes v1.2.pdf'), 'SpotCare-style notes v1.2');
  });

  test('URL escapes are decoded, stray percent signs survive', () {
    expect(titleFromFileName('My%20Book.pdf'), 'My Book');
    expect(titleFromFileName('100% guide.pdf'), '100% guide');
  });

  test('empty names fall back to Untitled', () {
    expect(titleFromFileName('_.pdf'), 'Untitled');
    expect(titleFromFileName('.pdf'), '.pdf');
  });
}
