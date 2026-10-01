package io.github.simonsteindl.picontrol.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import io.github.simonsteindl.picontrol.MainActivity
import io.github.simonsteindl.picontrol.R

private object PiControlWidgetViews {
    fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
        layoutId: Int,
        compact: Boolean,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, layoutId)
            val state = widgetData.getString("pi_widget_status", "UNKNOWN") ?: "UNKNOWN"
            val updatedAt = widgetData.getString("pi_widget_updated", null)?.toLongOrNull() ?: 0L
            val ageMinutes = if (updatedAt == 0L) Long.MAX_VALUE
                else ((System.currentTimeMillis() - updatedAt).coerceAtLeast(0L) / 60_000L)
            // Periodic background work is scheduled every 15 minutes; allow
            // Android's batching/doze window before labelling data stale.
            val stale = ageMinutes >= 20L
            val statusText = when {
                updatedAt == 0L -> "APP ÖFFNEN"
                state == "LOGIN_REQUIRED" -> "ANMELDEN"
                state == "OFFLINE" -> "OFFLINE"
                stale -> "LETZTER STAND"
                else -> "ONLINE"
            }
            val statusColor = when {
                state == "OFFLINE" -> context.getColor(R.color.pi_widget_red)
                updatedAt == 0L || stale || state == "LOGIN_REQUIRED" -> context.getColor(R.color.pi_widget_amber)
                else -> context.getColor(R.color.pi_widget_green)
            }

            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextColor(R.id.widget_status, statusColor)
            if (compact) {
                views.setTextViewText(
                    R.id.widget_subtitle,
                    when {
                        updatedAt == 0L -> "Tippen zum Verbinden"
                        state == "LOGIN_REQUIRED" -> "In Pi Control anmelden"
                        state == "OFFLINE" -> "Pi nicht erreichbar"
                        stale -> "Status vor ${ageMinutes} Min."
                        else -> "${widgetData.getString("pi_widget_temperature", "— °C")} · Server bereit"
                    },
                )
            } else {
                views.setTextViewText(R.id.widget_cpu, widgetData.getString("pi_widget_cpu", "—%"))
                views.setTextViewText(R.id.widget_ram, widgetData.getString("pi_widget_ram", "—%"))
                views.setTextViewText(R.id.widget_temperature, widgetData.getString("pi_widget_temperature", "— °C"))
                views.setTextViewText(R.id.widget_sd, widgetData.getString("pi_widget_sd", "—%"))
                views.setTextViewText(
                    R.id.widget_updated,
                    when {
                updatedAt == 0L -> "Pi Control öffnen, um Daten zu laden"
                state == "LOGIN_REQUIRED" -> "Bitte in Pi Control anmelden"
                ageMinutes < 1L -> "Gerade aktualisiert"
                        else -> "Zuletzt aktualisiert vor ${ageMinutes} Min."
                    },
                )
            }

            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                widgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

class PiControlCompactWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = PiControlWidgetViews.render(
        context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.pi_control_compact_widget, compact = true,
    )
}

class PiControlStatusWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = PiControlWidgetViews.render(
        context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.pi_control_status_widget, compact = false,
    )
}

class PiControlLargeWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = PiControlWidgetViews.render(
        context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.pi_control_large_widget, compact = false,
    )
}
