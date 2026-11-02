# Accha Sunno

![Accha Sunno icon](assets/icon/icon_192.png)

Android app that turns text-based PDFs into audio with the phone's built-in
text-to-speech engine, then plays them with seek controls, background
playback and follow-along text. No cloud APIs or network calls.

## Pipeline

1. **Extract**: `PdfTextExtractor.extractTextLines()` (Syncfusion) gives
   positioned lines with font name and size (`lib/services/pdf_extractor.dart`).
2. **Clean** (`lib/services/text_cleaner.dart`, pure Dart):
   - drop running headers and footers (top/bottom 8% of the page, repeated on ≥50% of pages)
   - turn headings (≥1.25× body size, or short standalone lines) into their own sentences
   - replace code blocks (2+ monospace lines) with "Code example skipped."
   - rebuild paragraphs from vertical gaps
   - apply spoken substitutions
3. **Chunk** (`lib/services/chunker.dart`): 1–4 sentences, at most 600 characters, never
   crossing a paragraph or page.
4. **Synthesise**: each chunk becomes its own WAV via `flutter_tts`. This step is resumable.
5. **Merge** (`lib/services/wav_merger.dart`): parse the RIFF chunks, check the
   formats match, and stream everything into one WAV. Chunk start offsets are recorded.

## Development

```sh
flutter test      # unit tests; the fixture test runs if test/fixtures/study_guide.pdf exists
flutter analyze
flutter run       # Android device or emulator
```

Voice quality depends on the installed TTS engine. Install offline voice
data from Android's text-to-speech settings; the app's Settings screen links
there.

## Icon, splash and store assets

Everything is generated from one source glyph, `assets/icon/book-headphones.svg`:

```sh
python -m pip install resvg-py pillow
python tool/generate_icons.py                  # PNGs in assets/icon, notification icons, store images
dart run flutter_launcher_icons                # launcher icons: legacy, adaptive and Android 13 themed
dart run flutter_native_splash:create          # splash screens, including the Android 12+ splash API
```

The Play Store listing (title, descriptions, changelog, icon, feature graphic) is in
`fastlane/metadata/android/en-US/`.

## Credits

The app icon uses [Lucide](https://lucide.dev)'s `book-headphones` icon (v1.57.0,
ISC licence; full text in `assets/licenses/lucide.txt`, also shown in the app under
Settings → About → View licences).
