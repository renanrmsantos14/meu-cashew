package com.budget.tracker_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class MeuBancoWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val pct = widgetData.getString("mb_pct", null)?.toIntOrNull() ?: 0
            val alerta = widgetData.getString("mb_alerta", null) == "1"

            val views = RemoteViews(context.packageName, R.layout.meu_banco_widget_layout).apply {
                setTextViewText(R.id.mb_disponivel, widgetData.getString("mb_disponivel", null) ?: "R$ 0,00")
                setTextViewText(R.id.mb_gasto, widgetData.getString("mb_gasto", null) ?: "")
                setTextViewText(R.id.mb_sinc, widgetData.getString("mb_sinc", null) ?: "")
                setProgressBar(R.id.mb_medidor, 100, if (alerta) 0 else pct, false)
                setProgressBar(R.id.mb_medidor_alerta, 100, if (alerta) pct else 0, false)
                setViewVisibility(R.id.mb_medidor_alerta, if (alerta) View.VISIBLE else View.GONE)

                setOnClickPendingIntent(R.id.mb_raiz, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
