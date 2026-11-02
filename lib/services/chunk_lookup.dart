/// Index of the chunk playing at [position], given each chunk's start offset
/// in ascending order. Binary search, so it stays cheap for long documents.
int chunkIndexAt(List<Duration> startOffsets, Duration position) {
  if (startOffsets.isEmpty) return -1;
  var lo = 0, hi = startOffsets.length - 1;
  if (position <= startOffsets.first) return 0;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (startOffsets[mid] <= position) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}
