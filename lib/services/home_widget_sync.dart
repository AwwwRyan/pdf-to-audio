import 'package:home_widget/home_widget.dart';

import '../models/document.dart';

/// Pushes player state to the home-screen widget
/// (android/.../PlayerWidgetProvider.kt).
class HomeWidgetSync {
  static const _provider = 'com.awwwryan.pdf_listener.PlayerWidgetProvider';

  String? _last;

  /// Shows [doc] in the widget, or the empty state when null. Skips the
  /// platform round-trip when nothing visible changed.
  Future<void> push(Document? doc, {required bool playing, Duration? position}) async {
    final percent = doc == null ? 0 : _percent(doc, position ?? doc.lastPosition);
    final subtitle = doc == null
        ? null
        : '${playing ? 'Playing' : 'Paused'} · $percent% listened';
    final key = '${doc?.id}|${doc?.title}|$subtitle|$playing';
    if (key == _last) return;
    _last = key;
    try {
      await HomeWidget.saveWidgetData<String>('title', doc?.title);
      await HomeWidget.saveWidgetData<String>('subtitle', subtitle);
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.saveWidgetData<int>('progress', percent);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } on Object {
      _last = null; // No widget host (tests) or a transient failure; retry next time.
    }
  }

  static int _percent(Document doc, Duration position) {
    final total = doc.totalDuration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (position.inMilliseconds * 100 ~/ total).clamp(0, 100);
  }
}
