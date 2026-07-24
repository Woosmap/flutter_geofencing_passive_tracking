package com.woosmap.woosmap_geofencing_rest_sample

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.webgeoservices.woosmapgeofencingcore.database.POI
import com.webgeoservices.woosmapgeofencingcore.database.WoosmapDb
import org.json.JSONObject
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Listens for the `com.woosmap.action.GEOFENCE_TRIGGERED` broadcast emitted by
 * the Woosmap Geofencing SDK and forwards the region event to the customer's
 * back-office via a REST call (replacing the Batch SDK call from the Woosmap
 * Batch connector sample).
 *
 * The `regionLog` extra is a JSON string, e.g.:
 * {
 *   "longitude": -0.1337,
 *   "latitude": 51.50998,
 *   "date": 1700824501480,
 *   "didenter": true,
 *   "identifier": "custom-region1",
 *   "radius": 100,
 *   "frompositiondetection": false,
 *   "eventname": "woos_geofence_exited_event",
 *   "spenttime": 75
 * }
 */
class GeofencingEventsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofencingReceiver"

        // TODO: point these at the customer's back-office.
        private const val BACK_OFFICE_URL =
            "https://api.customer-backoffice.example.com/geofence-events"
        private const val API_KEY = "CUSTOMER_API_KEY"
    }

    private val executorService: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "Received geofence broadcast")
        if (context == null || intent == null) return

        executorService.execute {
            try {
                val regionLog = intent.getStringExtra("regionLog") ?: return@execute
                val regionData = JSONObject(regionLog)

                // Build the base payload from the region log.
                val payload = JSONObject().apply {
                    put("date", regionData.optLong("date"))
                    put("eventName", regionData.optString("eventname"))
                    put("id", regionData.optString("identifier"))
                    put("latitude", regionData.optDouble("latitude"))
                    put("longitude", regionData.optDouble("longitude"))
                    put("radius", regionData.optDouble("radius"))
                    put("didEnter", regionData.optBoolean("didenter"))
                    put("spentTime", regionData.optLong("spenttime"))
                }

                // Enrich with POI attributes if the region maps to a known POI.
                // poi is null for custom regions.
                val poi: POI? = WoosmapDb.getInstance(context)
                    .poIsDAO
                    .getPOIbyStoreId(regionData.optString("identifier"))
                if (poi != null) {
                    payload.put("idStore", poi.idStore)
                    payload.put("name", poi.name)
                    payload.put("city", poi.city)
                    payload.put("zipCode", poi.zipCode)
                    payload.put("distance", poi.distance)
                    payload.put("countryCode", poi.countryCode)
                    payload.put("address", poi.address)
                    payload.put("tags", poi.tags)
                    payload.put("types", poi.types)
                }

                postEvent(payload)
            } catch (ex: Exception) {
                Log.e(TAG, "Failed to handle geofence event: $ex")
            }
        }
    }

    private fun postEvent(payload: JSONObject) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(BACK_OFFICE_URL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 30_000
                readTimeout = 30_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $API_KEY")
            }

            connection.outputStream.use { os: OutputStream ->
                os.write(payload.toString().toByteArray(Charsets.UTF_8))
            }

            val code = connection.responseCode
            Log.d(TAG, "Back-office responded $code")
        } catch (ex: Exception) {
            Log.e(TAG, "Back-office POST error: $ex")
        } finally {
            connection?.disconnect()
        }
    }
}
