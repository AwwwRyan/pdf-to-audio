package com.awwwryan.pdf_listener

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen player. Dart writes the state with home_widget (see
 * lib/services/home_widget_sync.dart); the buttons send the same media-button
 * events as headphones, so they work even when the app process isn't running.
 */
class PlayerWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("title", null)
        val subtitle = widgetData.getString("subtitle", null)
        val playing = widgetData.getBoolean("playing", false)
        val progress = widgetData.getInt("progress", 0)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.player_widget).apply {
                setTextViewText(R.id.widget_title,
                    title ?: context.getString(R.string.widget_empty_title))
                setTextViewText(R.id.widget_subtitle,
                    subtitle ?: context.getString(R.string.widget_empty_subtitle))
                setViewVisibility(R.id.widget_progress, if (title == null) View.GONE else View.VISIBLE)
                setProgressBar(R.id.widget_progress, 100, progress, false)
                setImageViewResource(R.id.widget_play,
                    if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
                setContentDescription(R.id.widget_play, context.getString(
                    if (playing) R.string.widget_pause else R.string.widget_play))

                setOnClickPendingIntent(android.R.id.background, openApp(context))
                setOnClickPendingIntent(R.id.widget_play,
                    mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                setOnClickPendingIntent(R.id.widget_rewind,
                    mediaButton(context, KeyEvent.KEYCODE_MEDIA_REWIND))
                setOnClickPendingIntent(R.id.widget_forward,
                    mediaButton(context, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
        return PendingIntent.getActivity(context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
            .setComponent(ComponentName(context, MediaButtonReceiver::class.java))
            .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        // The key code doubles as the request code so each button keeps its own intent.
        return PendingIntent.getBroadcast(context, keyCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
