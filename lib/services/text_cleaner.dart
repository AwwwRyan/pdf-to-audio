import '../models/pdf_line.dart';

enum BlockKind { heading, paragraph, code }

/// A unit of cleaned, speakable text that never spans a page.
class TextBlock {
  const TextBlock(this.kind, this.text, this.pageNumber);

  final BlockKind kind;
  final String text;
  final int pageNumber;

  bool get isHeading => kind == BlockKind.heading;

  @override
  String toString() => 'TextBlock(${kind.name}, p$pageNumber, "$text")';
}

const codeSkippedCue = 'Code example skipped.';

/// Symbols and abbreviations Android TTS reads inconsistently, applied in
/// order to headings and paragraphs (never to raw code). Extend here.
final List<(RegExp, String)> spokenSubstitutions = [
  (RegExp('→'), ' to '),
  (RegExp('·'), ', '),
  (RegExp(r'\be\.g\.', caseSensitive: false), 'for example'),
  (RegExp(r'\bi\.e\.', caseSensitive: false), 'that is'),
  (RegExp(r'(?<=\s)vs\.?(?=\s)'), 'versus'),
  (RegExp('&'), ' and '),
];

class CleanerConfig {
  const CleanerConfig({
    this.readCodeBlocks = false,
    this.marginFraction = 0.08,
    this.repeatPageFraction = 0.5,
    this.headingSizeRatio = 1.25,
    this.paragraphGapFactor = 1.4,
  });

  /// Read code blocks verbatim instead of replacing them with [codeSkippedCue].
  final bool readCodeBlocks;

  /// Top/bottom share of the page where running headers/footers live.
  final double marginFraction;

  /// A margin line repeated on at least this share of pages is dropped.
  final double repeatPageFraction;

  /// Lines at least this many times the body font size are headings.
  final double headingSizeRatio;

  /// A vertical gap this many times the typical line gap starts a paragraph.
  final double paragraphGapFactor;
}

final _monoFont = RegExp(r'mono|courier|code|consol', caseSensitive: false);
final _pageNumberOnly =
    RegExp(r'^(page\s*)?[-–—\s]*#[-–—\s]*((of|/)\s*#)?$');
final _sentenceEnd = RegExp(r'[.,;:!?"”]$');
final _startsUpperOrDigit = RegExp(r'^[A-Z0-9]');

/// Normalises a line for header/footer comparison: digit runs become "#",
/// so "Page 9 of 28" and "Page 10 of 28" match.
String normalizeForRepeat(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Applies [spokenSubstitutions] and tidies spacing.
String applySpokenSubstitutions(String s) {
  var out = s;
  for (final (pattern, replacement) in spokenSubstitutions) {
    out = out.replaceAll(pattern, replacement);
  }
  return normalizeSpacing(out);
}

String normalizeSpacing(String s) => s
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s+([,.;:!?)\]])(?=\s|$|[,.;:!?)\]])'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'([(\[])\s+'), (m) => m[1]!)
    .replaceAll(RegExp(r',\s*,'), ',')
    .trim();

/// Joins wrapped lines of one paragraph, undoing end-of-line hyphenation.
String joinWrappedLines(List<String> lines) {
  var out = '';
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (out.isEmpty) {
      out = line;
    } else if (RegExp(r'[A-Za-z]-$').hasMatch(out) &&
        RegExp(r'^[a-z]').hasMatch(line)) {
      out = out.substring(0, out.length - 1) + line;
    } else {
      out = '$out $line';
    }
  }
  return out;
}

/// Number of letters and digits in spoken (non-code) blocks; used to detect
/// scanned PDFs.
int spokenAlnumCount(List<TextBlock> blocks) => blocks
    .where((b) => b.kind != BlockKind.code)
    .fold(0, (n, b) => n + RegExp(r'[\p{L}\p{N}]', unicode: true).allMatches(b.text).length);

/// One visual row: the line fragments sharing a baseline band on a page.
class _Row {
  _Row(PdfLine first)
      : top = first.top,
        bottom = first.bottom {
    frags.add(first);
  }

  final List<PdfLine> frags = [];
  double top;
  double bottom;
  late String text;
  late double fontSize;
  late bool isMono;
  bool isCode = false;

  double get centerY => (top + bottom) / 2;

  bool accepts(PdfLine f) =>
      (f.centerY >= top && f.centerY <= bottom) ||
      (centerY >= f.top && centerY <= f.bottom);

  void add(PdfLine f) {
    frags.add(f);
    if (f.top < top) top = f.top;
    if (f.bottom > bottom) bottom = f.bottom;
  }

  void finish() {
    frags.sort((a, b) => a.left.compareTo(b.left));
    text = frags.map((f) => f.text.trim()).join(' ');
    var best = frags.first;
    for (final f in frags) {
      if (f.text.trim().length > best.text.trim().length) best = f;
    }
    fontSize = best.fontSize;
    isMono = frags.every((f) => _monoFont.hasMatch(f.fontName));
  }
}

List<_Row> _buildRows(PdfPageLines page) {
  final frags = page.lines.where((l) => l.text.trim().isNotEmpty).toList()
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <_Row>[];
  for (final f in frags) {
    if (rows.isNotEmpty && rows.last.accepts(f)) {
      rows.last.add(f);
    } else {
      rows.add(_Row(f));
    }
  }
  for (final r in rows) {
    r.finish();
  }
  return rows;
}

/// Low percentile rather than median: in list-heavy pages paragraph gaps can
/// outnumber in-paragraph gaps, which would hide every paragraph break.
double _typicalValue(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * 0.3).round()];
}

/// Turns positioned PDF lines into speakable blocks: removes running
/// headers/footers, detects headings and code blocks by font, rebuilds
/// paragraphs from vertical spacing, and applies spoken substitutions.
List<TextBlock> cleanPages(List<PdfPageLines> pages,
    {CleanerConfig config = const CleanerConfig()}) {
  final rowsByPage = [for (final p in pages) _buildRows(p)];

  // Running headers and footers.
  final zoneOf = <_Row, String>{};
  final pagesWithKey = <String, Set<int>>{};
  for (var i = 0; i < pages.length; i++) {
    final h = pages[i].height;
    for (final row in rowsByPage[i]) {
      final String zone;
      if (row.centerY <= h * config.marginFraction) {
        zone = 'top';
      } else if (row.centerY >= h * (1 - config.marginFraction)) {
        zone = 'bottom';
      } else {
        continue;
      }
      final key = '$zone|${normalizeForRepeat(row.text)}';
      zoneOf[row] = key;
      pagesWithKey.putIfAbsent(key, () => {}).add(i);
    }
  }
  bool isRunningMargin(_Row row) {
    final key = zoneOf[row];
    if (key == null) return false;
    if (_pageNumberOnly.hasMatch(key.substring(key.indexOf('|') + 1))) {
      return true;
    }
    return pages.length >= 2 &&
        pagesWithKey[key]!.length >= pages.length * config.repeatPageFraction;
  }

  for (final rows in rowsByPage) {
    rows.removeWhere(isRunningMargin);
  }

  // Body font size: the size carrying the most characters.
  final charsBySize = <double, int>{};
  for (final rows in rowsByPage) {
    for (final r in rows) {
      if (r.isMono) continue;
      final size = (r.fontSize * 2).round() / 2;
      charsBySize[size] = (charsBySize[size] ?? 0) + r.text.length;
    }
  }
  final bodySize = charsBySize.isEmpty
      ? 12.0
      : charsBySize.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final headingSize = bodySize * config.headingSizeRatio;

  // Typical gap between consecutive body lines.
  final gaps = <double>[];
  for (final rows in rowsByPage) {
    for (var i = 1; i < rows.length; i++) {
      final a = rows[i - 1], b = rows[i];
      if ((a.fontSize - bodySize).abs() > 0.75 ||
          (b.fontSize - bodySize).abs() > 0.75) {
        continue;
      }
      final gap = b.top - a.bottom;
      if (gap > 0 && gap < bodySize * 2) gaps.add(gap);
    }
  }
  final lineGap = _typicalValue(gaps);
  final typicalGap = gaps.isEmpty
      ? bodySize * 0.4
      : (lineGap < bodySize * 0.15 ? bodySize * 0.15 : lineGap);
  final paragraphGap = typicalGap * config.paragraphGapFactor;

  bool looksLikeSubheading(_Row r) {
    final t = r.text.trim();
    return (r.fontSize - bodySize).abs() <= 0.75 &&
        t.length <= 60 &&
        t.split(' ').length <= 8 &&
        !_sentenceEnd.hasMatch(t) &&
        _startsUpperOrDigit.hasMatch(t);
  }

  final blocks = <TextBlock>[];
  for (var p = 0; p < pages.length; p++) {
    final pageNumber = pages[p].pageNumber;
    final rows = rowsByPage[p];

    // A code block is a run of 2+ rows that are entirely monospace.
    for (var i = 0; i < rows.length; i++) {
      rows[i].isCode = rows[i].isMono &&
          ((i > 0 && rows[i - 1].isMono) ||
              (i + 1 < rows.length && rows[i + 1].isMono));
    }

    var para = <_Row>[];
    var paraIsHeading = false;
    final code = <_Row>[];

    void flushPara({required bool boundaryAfter}) {
      if (para.isEmpty) return;
      final joined = joinWrappedLines(para.map((r) => r.text).toList());
      final heading = paraIsHeading ||
          (boundaryAfter && para.length == 1 && looksLikeSubheading(para.first));
      if (heading) {
        var t = applySpokenSubstitutions(joined);
        if (RegExp(r'[:;,]$').hasMatch(t)) t = t.substring(0, t.length - 1);
        if (!RegExp(r'[.!?]$').hasMatch(t)) t = '$t.';
        blocks.add(TextBlock(BlockKind.heading, t, pageNumber));
      } else {
        final t = applySpokenSubstitutions(joined);
        if (t.isNotEmpty) blocks.add(TextBlock(BlockKind.paragraph, t, pageNumber));
      }
      para = [];
      paraIsHeading = false;
    }

    void flushCode() {
      if (code.isEmpty) return;
      final text = config.readCodeBlocks
          ? code.map((r) => r.text.trim()).join('\n')
          : codeSkippedCue;
      blocks.add(TextBlock(BlockKind.code, text, pageNumber));
      code.clear();
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final prev = i > 0 ? rows[i - 1] : null;
      final gap = prev == null ? 0.0 : row.top - prev.bottom;

      if (row.isCode) {
        flushPara(boundaryAfter: true);
        code.add(row);
        continue;
      }
      flushCode();

      if (row.fontSize >= headingSize) {
        final continuesHeading = paraIsHeading &&
            para.isNotEmpty &&
            gap <= paragraphGap * (row.fontSize / bodySize);
        if (!continuesHeading) {
          flushPara(boundaryAfter: true);
          paraIsHeading = true;
        }
        para.add(row);
        continue;
      }

      if (para.isNotEmpty && (paraIsHeading || gap > paragraphGap)) {
        flushPara(boundaryAfter: true);
      }
      para.add(row);
    }
    flushCode();
    flushPara(boundaryAfter: false);
  }
  return blocks;
}
