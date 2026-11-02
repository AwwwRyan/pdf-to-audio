import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_listener/constants/prompts.dart';
import 'package:pdf_listener/widgets/study_prompt_row.dart';

void main() {
  testWidgets('tapping the row copies the full prompt', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: StudyPromptRow()),
      ),
    ));

    final text = tester.widget<Text>(find.text(kStudyReferencesPrompt));
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Copy study references prompt'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(copied, kStudyReferencesPrompt);
    expect(copied, contains('2–4'));
    expect(find.text('Prompt copied'), findsOneWidget);
  });
}
