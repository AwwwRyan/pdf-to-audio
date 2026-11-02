import 'package:hive_ce/hive_ce.dart';

/// Bump when cleaning/chunking changes enough that existing audio's chunk
/// text no longer matches what a fresh conversion would produce.
/// v1: page-level paragraphs, ~3000-char chunks. v2: line-level cleaning,
/// sentence chunks with headings.
const kPipelineVersion = 2;

enum DocStatus {
  /// Waiting for another conversion to finish.
  queued,
  extracting,
  converting,
  ready,
  failed,

  /// No audio (never converted, or audio deleted).
  idle,
}

class Document {
  const Document({
    required this.id,
    required this.title,
    required this.originalFileName,
    required this.pdfPath,
    required this.pageCount,
    required this.startPage,
    required this.endPage,
    required this.createdAt,
    this.status = DocStatus.idle,
    this.progress = 0,
    this.error,
    this.audioPath,
    this.totalDuration,
    this.lastPosition = Duration.zero,
    this.pipelineVersion = kPipelineVersion,
    this.chunkCount = 0,
  });

  final String id;
  final String title;
  final String originalFileName;
  final String pdfPath;
  final int pageCount;

  /// 1-based inclusive page range that was (or will be) converted.
  final int startPage;
  final int endPage;
  final DocStatus status;

  /// 0–1 while converting.
  final double progress;
  final String? error;
  final String? audioPath;
  final Duration? totalDuration;
  final Duration lastPosition;
  final DateTime createdAt;

  /// Pipeline version that produced the current chunks/audio.
  final int pipelineVersion;
  final int chunkCount;

  bool get isBusy =>
      status == DocStatus.queued ||
      status == DocStatus.extracting ||
      status == DocStatus.converting;

  bool get needsReconversion =>
      status == DocStatus.ready && pipelineVersion < kPipelineVersion;

  bool get isPlayable => status == DocStatus.ready && !needsReconversion;

  double get listenedFraction {
    final total = totalDuration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (lastPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Document copyWith({
    String? title,
    int? startPage,
    int? endPage,
    DocStatus? status,
    double? progress,
    String? error,
    bool clearError = false,
    String? audioPath,
    bool clearAudio = false,
    Duration? totalDuration,
    Duration? lastPosition,
    int? pipelineVersion,
    int? chunkCount,
  }) =>
      Document(
        id: id,
        title: title ?? this.title,
        originalFileName: originalFileName,
        pdfPath: pdfPath,
        pageCount: pageCount,
        startPage: startPage ?? this.startPage,
        endPage: endPage ?? this.endPage,
        createdAt: createdAt,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
        audioPath: clearAudio ? null : (audioPath ?? this.audioPath),
        totalDuration: clearAudio ? null : (totalDuration ?? this.totalDuration),
        lastPosition: clearAudio ? Duration.zero : (lastPosition ?? this.lastPosition),
        pipelineVersion: pipelineVersion ?? this.pipelineVersion,
        chunkCount: chunkCount ?? this.chunkCount,
      );
}

/// Field-tagged like generated adapters. Records from older schemas lack
/// fields 14–15; they default to pipeline v1 so the library offers
/// "Reconvert". Unknown status names read as failed.
class DocumentAdapter extends TypeAdapter<Document> {
  @override
  final int typeId = 0;

  @override
  Document read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{for (var i = 0; i < n; i++) reader.readByte(): reader.read()};
    final statusName = f[6] as String?;
    final status = DocStatus.values
        .firstWhere((s) => s.name == statusName, orElse: () => DocStatus.failed);
    final durationUs = f[10] as int?;
    return Document(
      id: f[0] as String,
      title: f[1] as String,
      originalFileName: f[2] as String,
      pdfPath: f[3] as String,
      startPage: f[4] as int,
      endPage: f[5] as int,
      status: status,
      progress: (f[7] as num?)?.toDouble() ?? 0,
      error: f[8] as String? ??
          (statusName != null && status.name != statusName
              ? 'Unknown status "$statusName"'
              : null),
      audioPath: f[9] as String?,
      totalDuration: durationUs == null ? null : Duration(microseconds: durationUs),
      lastPosition: Duration(microseconds: (f[11] as int?) ?? 0),
      createdAt: DateTime.fromMillisecondsSinceEpoch((f[12] as int?) ?? 0),
      pageCount: (f[13] as int?) ?? (f[5] as int),
      pipelineVersion: (f[14] as int?) ?? 1,
      chunkCount: (f[15] as int?) ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, Document obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.originalFileName)
      ..writeByte(3)
      ..write(obj.pdfPath)
      ..writeByte(4)
      ..write(obj.startPage)
      ..writeByte(5)
      ..write(obj.endPage)
      ..writeByte(6)
      ..write(obj.status.name)
      ..writeByte(7)
      ..write(obj.progress)
      ..writeByte(8)
      ..write(obj.error)
      ..writeByte(9)
      ..write(obj.audioPath)
      ..writeByte(10)
      ..write(obj.totalDuration?.inMicroseconds)
      ..writeByte(11)
      ..write(obj.lastPosition.inMicroseconds)
      ..writeByte(12)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(13)
      ..write(obj.pageCount)
      ..writeByte(14)
      ..write(obj.pipelineVersion)
      ..writeByte(15)
      ..write(obj.chunkCount);
  }
}
