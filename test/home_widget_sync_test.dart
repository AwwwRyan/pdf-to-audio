import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/models/document.dart';
import 'package:pdf_listener/services/home_widget_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  late Map<String, Object?> saved;
  late List<Map<Object?, Object?>> updates;

  setUp(() {
    saved = {};
    updates = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      switch (call.method) {
        case 'saveWidgetData':
          saved[args['id']! as String] = args['data'];
        case 'updateWidget':
          updates.add(args);
      }
      return true;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  final doc = Document(
    id: 'd1',
    title: 'AWS Study Guide',
    originalFileName: 'guide.pdf',
    pdfPath: '/x.pdf',
    pageCount: 28,
    startPage: 1,
    endPage: 28,
    createdAt: DateTime(2026),
    status: DocStatus.ready,
    audioPath: '/a.wav',
    totalDuration: const Duration(minutes: 40),
    lastPosition: const Duration(minutes: 10),
  );

  test('pushes title, state and progress to the widget provider', () async {
    final sync = HomeWidgetSync();
    await sync.push(doc, playing: true, position: const Duration(minutes: 20));

    expect(saved['title'], 'AWS Study Guide');
    expect(saved['subtitle'], 'Playing · 50% listened');
    expect(saved['playing'], true);
    expect(saved['progress'], 50);
    expect(updates.single['qualifiedAndroidName'],
        'com.awwwryan.pdf_listener.PlayerWidgetProvider');
  });

  test('falls back to the saved position and skips unchanged pushes', () async {
    final sync = HomeWidgetSync();
    await sync.push(doc, playing: false);
    await sync.push(doc, playing: false);
    expect(saved['subtitle'], 'Paused · 25% listened');
    expect(updates, hasLength(1));
  });

  test('empty state clears the document', () async {
    final sync = HomeWidgetSync();
    await sync.push(doc, playing: false);
    await sync.push(null, playing: false);
    expect(saved['title'], isNull);
    expect(saved['progress'], 0);
    expect(updates, hasLength(2));
  });
}
