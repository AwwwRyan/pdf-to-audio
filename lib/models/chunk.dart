import 'package:hive_ce/hive_ce.dart';

class Chunk {
  const Chunk({
    required this.index,
    required this.text,
    required this.pageNumber,
    this.isHeading = false,
    this.startOffset = Duration.zero,
    this.duration = Duration.zero,
  });

  final int index;
  final String text;
  final int pageNumber;
  final bool isHeading;

  /// Start of this chunk within the merged audio file.
  final Duration startOffset;
  final Duration duration;

  Chunk withTiming(Duration startOffset, Duration duration) => Chunk(
        index: index,
        text: text,
        pageNumber: pageNumber,
        isHeading: isHeading,
        startOffset: startOffset,
        duration: duration,
      );
}

/// Field-tagged so records written by older schemas still read: missing
/// fields fall back to defaults (e.g. pre-v2 chunks have no isHeading).
class ChunkAdapter extends TypeAdapter<Chunk> {
  @override
  final int typeId = 1;

  @override
  Chunk read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{for (var i = 0; i < n; i++) reader.readByte(): reader.read()};
    return Chunk(
      index: f[0] as int,
      text: f[1] as String,
      pageNumber: f[2] as int,
      startOffset: Duration(microseconds: (f[3] as int?) ?? 0),
      duration: Duration(microseconds: (f[4] as int?) ?? 0),
      isHeading: (f[5] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Chunk obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.index)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.pageNumber)
      ..writeByte(3)
      ..write(obj.startOffset.inMicroseconds)
      ..writeByte(4)
      ..write(obj.duration.inMicroseconds)
      ..writeByte(5)
      ..write(obj.isHeading);
  }
}
