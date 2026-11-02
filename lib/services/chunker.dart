import 'text_cleaner.dart';

/// A chunk of text to synthesise, before audio timing is known.
class ChunkDraft {
  const ChunkDraft(this.text, this.pageNumber, {this.isHeading = false});

  final String text;
  final int pageNumber;
  final bool isHeading;

  @override
  String toString() => 'ChunkDraft(p$pageNumber${isHeading ? ', heading' : ''}, "$text")';
}

final _sentenceBoundary =
    RegExp(r'[.!?…]+["”’)\]]*\s+(?=["“‘(\[]?[A-Z0-9])');

const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'no', 'fig', 'approx', 'inc', //
  'ltd', 'jr', 'sr', 'vol', 'pp', 'cf',
};

/// Splits text into sentences, avoiding common abbreviations, initials
/// ("J. Smith") and leading section numbers ("1. Cloud basics").
List<String> splitSentences(String text) {
  final out = <String>[];
  var start = 0;
  for (final m in _sentenceBoundary.allMatches(text)) {
    final before = text.substring(start, m.start);
    final lastWord = RegExp(r'(\S+)$').firstMatch(before)?.group(1) ?? '';
    final bare = lastWord.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final isAbbreviation = _abbreviations.contains(bare);
    final isInitial = RegExp(r'^[A-Z]$').hasMatch(lastWord);
    final isSectionNumber =
        RegExp(r'^\d{1,3}$').hasMatch(lastWord) && before.trim() == lastWord;
    if (isAbbreviation || isInitial || isSectionNumber) continue;
    out.add(text.substring(start, m.end).trim());
    start = m.end;
  }
  final rest = text.substring(start).trim();
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// Breaks a piece longer than [maxChars] at the most natural point available:
/// a line break, then clause punctuation, then a space.
List<String> splitLong(String text, int maxChars) {
  final out = <String>[];
  var rest = text.trim();
  while (rest.length > maxChars) {
    final window = rest.substring(0, maxChars);
    var cut = -1;
    for (final sep in const ['\n', '; ', ': ', ' — ', ', ', ' ']) {
      final i = window.lastIndexOf(sep);
      if (i > maxChars * 0.4) {
        cut = i + sep.length;
        break;
      }
    }
    if (cut <= 0) cut = maxChars;
    out.add(rest.substring(0, cut).trim());
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// Packs each block's sentences into chunks of 1–[maxSentences] sentences and
/// at most [maxChars] characters. Chunks never cross a block, so they never
/// cross a paragraph or page boundary.
List<ChunkDraft> chunkBlocks(List<TextBlock> blocks,
    {int maxChars = 600, int maxSentences = 4}) {
  final chunks = <ChunkDraft>[];
  for (final block in blocks) {
    final sentences = [
      for (final s in splitSentences(block.text)) ...splitLong(s, maxChars),
    ];
    final current = <String>[];
    var length = 0;
    void flush() {
      if (current.isEmpty) return;
      chunks.add(ChunkDraft(current.join(' '), block.pageNumber,
          isHeading: block.isHeading));
      current.clear();
      length = 0;
    }

    for (final s in sentences) {
      if (current.isNotEmpty &&
          (current.length >= maxSentences || length + 1 + s.length > maxChars)) {
        flush();
      }
      current.add(s);
      length += (current.length > 1 ? 1 : 0) + s.length;
    }
    flush();
  }
  return chunks;
}
