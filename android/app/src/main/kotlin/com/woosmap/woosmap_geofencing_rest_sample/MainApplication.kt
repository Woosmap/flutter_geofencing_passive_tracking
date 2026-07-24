package com.woosmap.woosmap_geofencing_rest_sample

import android.app.Application
import android.content.Context
import android.content.IntentFilter
import android.os.Build

/**
 * Registers the [GeofencingEventsReceiver] so it receives
 * `com.woosmap.action.GEOFENCE_TRIGGERED` broadcasts for the app's lifetime.
 *
 * Make sure this class is referenced from AndroidManifest.xml via
 * android:name=".MainApplication" on the <application> tag.
 */
class MainApplication : Application() {

    private lateinit var geofencingEventsReceiver: GeofencingEventsReceiver

    override fun onCreate() {
        super.onCreate()

        geofencingEventsReceiver = GeofencingEventsReceiver()
        val filter = IntentFilter("com.woosmap.action.GEOFENCE_TRIGGERED")

        // RECEIVER_EXPORTED / RECEIVER_NOT_EXPORTED flag is required on API 34+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(geofencingEventsReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(geofencingEventsReceiver, filter)
        }
    }
}
