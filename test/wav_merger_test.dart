import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/services/wav_merger.dart';

/// Builds a WAV with optional extra chunks before "data", like real TTS
/// engines sometimes write (LIST/INFO, fact, odd-sized padding).
Uint8List wav({
  int sampleRate = 22050,
  int channels = 1,
  int bits = 16,
  required List<int> samples,
  List<(String, int)> extraChunks = const [],
  int? declaredDataSize,
}) {
  final blockAlign = channels * bits ~/ 8;
  final data = BytesBuilder();
  for (final s in samples) {
    final b = ByteData(2)..setInt16(0, s, Endian.little);
    data.add(b.buffer.asUint8List());
  }
  final dataBytes = data.toBytes();
  final out = BytesBuilder();
  void u32(int v) => out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => out.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  out.add('RIFF'.codeUnits);
  u32(0); // patched below
  out.add('WAVE'.codeUnits);
  for (final (id, size) in extraChunks) {
    out.add(id.codeUnits);
    u32(size);
    out.add(List.filled(size + (size.isOdd ? 1 : 0), 7));
  }
  out.add('fmt '.codeUnits);
  u32(18); // non-standard fmt size with cbSize
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * blockAlign);
  u16(blockAlign);
  u16(bits);
  u16(0);
  out.add('data'.codeUnits);
  u32(declaredDataSize ?? dataBytes.length);
  out.add(dataBytes);
  final bytes = out.toBytes();
  ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
  return bytes;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wav_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, Uint8List bytes) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  group('parseWavHeader', () {
    test('finds fmt and data past extra and odd-sized chunks', () {
      final bytes = wav(samples: [1, 2, 3, 4], extraChunks: [('LIST', 25), ('fact', 4)]);
      final info = parseWavHeader(bytes, fileLength: bytes.length);
      expect(info.sampleRate, 22050);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
      expect(info.dataSize, 8);
      expect(info.dataOffset, bytes.length - 8);
      expect(info.dataOffset, isNot(44));
    });

    test('falls back to file length for streamed (0xFFFFFFFF / 0) sizes', () {
      for (final declared in [0xFFFFFFFF, 0]) {
        final bytes = wav(samples: List.filled(100, 5), declaredDataSize: declared);
        expect(parseWavHeader(bytes, fileLength: bytes.length).dataSize, 200);
      }
    });

    test('clamps a data size larger than the file (truncated write)', () {
      final bytes = wav(samples: List.filled(10, 5), declaredDataSize: 5000);
      expect(parseWavHeader(bytes, fileLength: bytes.length).dataSize, 20);
    });

    test('rejects non-WAV input', () {
      expect(() => parseWavHeader(Uint8List.fromList(List.filled(64, 0)), fileLength: 64),
          throwsA(isA<WavFormatException>()));
    });
  });

  group('mergeWavFiles', () {
    test('concatenates data with one correct header and offsets', () async {
      final a = write('a.wav', wav(samples: List.filled(22050, 1))); // 1.0 s
      final b = write('b.wav', wav(samples: List.filled(11025, 2), extraChunks: [('LIST', 9)])); // 0.5 s
      final c = write('c.wav', wav(samples: List.filled(44100, 3))); // 2.0 s
      final outPath = '${dir.path}/out.wav';

      final result = await mergeWavFiles([a, b, c], outPath);

      expect(result.durations, [
        const Duration(seconds: 1),
        const Duration(milliseconds: 500),
        const Duration(seconds: 2),
      ]);
      expect(result.startOffsets, [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(milliseconds: 1500),
      ]);
      expect(result.total, const Duration(milliseconds: 3500));

      final out = File(outPath).readAsBytesSync();
      final info = parseWavHeader(out, fileLength: out.length);
      expect(info.dataOffset, 44);
      expect(info.dataSize, (22050 + 11025 + 44100) * 2);
      expect(ByteData.sublistView(out).getUint32(4, Endian.little), out.length - 8);
      // The sample right at b's start is b's value.
      final view = ByteData.sublistView(out);
      expect(view.getInt16(44 + 22050 * 2 - 2, Endian.little), 1);
      expect(view.getInt16(44 + 22050 * 2, Endian.little), 2);
      expect(File('$outPath.tmp').existsSync(), isFalse);
    });

    test('handles 200 small chunks', () async {
      final paths = [
        for (var i = 0; i < 200; i++) write('c$i.wav', wav(samples: List.filled(2205, i))),
      ];
      final result = await mergeWavFiles(paths, '${dir.path}/big.wav');
      expect(result.startOffsets.length, 200);
      expect(result.startOffsets[199], const Duration(milliseconds: 19900));
      expect(result.total, const Duration(seconds: 20));
    });

    test('refuses chunks with mismatched formats', () async {
      final a = write('a.wav', wav(samples: [1, 2]));
      final b = write('b.wav', wav(samples: [1, 2], sampleRate: 24000));
      expect(mergeWavFiles([a, b], '${dir.path}/x.wav'),
          throwsA(isA<WavFormatException>()));
    });

    test('isValidWav rejects missing and corrupt files', () async {
      expect(await isValidWav('${dir.path}/missing.wav'), isFalse);
      expect(await isValidWav(write('bad.wav', Uint8List.fromList([1, 2, 3]))), isFalse);
      expect(await isValidWav(write('ok.wav', wav(samples: [1]))), isTrue);
    });
  });
}
