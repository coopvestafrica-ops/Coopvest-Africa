package com.coopvestafrica.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View

/**
 * Full-logo handoff screen shown after Android's mandatory system splash.
 * Android 12's system slot is icon-shaped, so the complete wordmark and tagline
 * are displayed here before MainActivity/Flutter takes over.
 */
class SplashActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val launchMainActivity = Runnable {
        if (isFinishing) return@Runnable
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            }
        )
        finish()
        overridePendingTransition(0, 0)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = resources.getColor(com.coopvestafrica.app.R.color.splash_background)
        window.navigationBarColor = resources.getColor(com.coopvestafrica.app.R.color.splash_background)
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        setContentView(R.layout.activity_splash)
        handler.postDelayed(launchMainActivity, 900L)
    }

    override fun onDestroy() {
        handler.removeCallbacks(launchMainActivity)
        super.onDestroy()
    }
}
