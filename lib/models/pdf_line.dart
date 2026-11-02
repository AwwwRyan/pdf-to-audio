/// Pure-Dart representation of a line fragment extracted from a PDF.
///
/// Coordinates are in PDF points with the origin at the top-left of the page.
class PdfLine {
  const PdfLine({
    required this.text,
    required this.fontName,
    required this.fontSize,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final String fontName;
  final double fontSize;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

class PdfPageLines {
  const PdfPageLines({
    required this.pageNumber,
    required this.height,
    required this.lines,
  });

  /// 1-based page number in the original PDF.
  final int pageNumber;
  final double height;
  final List<PdfLine> lines;
}

/// A run of glyphs as reported by the extractor (one "word" in Syncfusion's
/// terms, which is often a single glyph or a single space).
class GlyphRun {
  const GlyphRun(this.text, this.left, this.right);

  final String text;
  final double left;
  final double right;
}

/// Rebuilds a line's text from its glyph runs.
///
/// Syncfusion's `TextLine.text` inserts spaces between kerned glyphs
/// ("A WS", "Y ou"), while explicit space glyphs carry the real word breaks.
/// Concatenating the runs fixes the kerning splits; a horizontal gap wider
/// than [gapFactor] × [fontSize] (e.g. between table columns) still gets a
/// space.
String joinGlyphRuns(List<GlyphRun> runs, double fontSize,
    {double gapFactor = 0.25}) {
  final buf = StringBuffer();
  double? prevRight;
  for (final run in runs) {
    if (run.text.isEmpty) continue;
    final isSpace = run.text.trim().isEmpty;
    if (prevRight != null &&
        !isSpace &&
        run.left - prevRight > fontSize * gapFactor) {
      final s = buf.toString();
      if (s.isNotEmpty && !s.endsWith(' ')) buf.write(' ');
    }
    buf.write(isSpace ? ' ' : run.text);
    prevRight = run.right;
  }
  return buf.toString();
}
