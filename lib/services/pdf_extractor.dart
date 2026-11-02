import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/pdf_line.dart';

/// Reads PDFs with Syncfusion and converts them to the pure [PdfPageLines]
/// model. Heavy work runs in a background isolate.
class PdfExtractor {
  static Future<int> pageCount(String pdfPath) => Isolate.run(() {
        final doc = PdfDocument(inputBytes: File(pdfPath).readAsBytesSync());
        try {
          return doc.pages.count;
        } finally {
          doc.dispose();
        }
      });

  /// Extracts positioned lines for the 1-based inclusive page range.
  static Future<List<PdfPageLines>> extractLines(
          String pdfPath, int startPage, int endPage) =>
      Isolate.run(() =>
          extractLinesSync(File(pdfPath).readAsBytesSync(), startPage, endPage));

  static List<PdfPageLines> extractLinesSync(
      Uint8List bytes, int startPage, int endPage) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(doc);
      final pages = <PdfPageLines>[];
      for (var n = startPage; n <= endPage && n <= doc.pages.count; n++) {
        final index = n - 1;
        List<TextLine> lines;
        try {
          lines = extractor.extractTextLines(
              startPageIndex: index, endPageIndex: index);
        } on Object {
          lines = const []; // A malformed page shouldn't sink the whole book.
        }
        pages.add(PdfPageLines(
          pageNumber: n,
          height: doc.pages[index].size.height,
          lines: [for (final l in lines) _toPdfLine(l)],
        ));
      }
      return pages;
    } finally {
      doc.dispose();
    }
  }

  static PdfLine _toPdfLine(TextLine l) {
    final words = l.wordCollection;
    // When Syncfusion reports spaces as their own glyph runs, rebuild the
    // text from the runs to undo its kerning splits ("A WS" -> "AWS").
    final hasSpaceRuns = words.any((w) => w.text.isNotEmpty && w.text.trim().isEmpty);
    final text = hasSpaceRuns
        ? joinGlyphRuns(
            [for (final w in words) GlyphRun(w.text, w.bounds.left, w.bounds.right)],
            l.fontSize)
        : l.text;
    return PdfLine(
      text: text,
      fontName: l.fontName,
      fontSize: l.fontSize,
      left: l.bounds.left,
      top: l.bounds.top,
      right: l.bounds.right,
      bottom: l.bounds.bottom,
    );
  }
}
