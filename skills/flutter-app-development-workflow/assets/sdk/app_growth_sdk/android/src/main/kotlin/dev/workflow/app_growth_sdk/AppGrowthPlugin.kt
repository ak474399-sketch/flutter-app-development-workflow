package dev.workflow.app_growth_sdk

import android.app.Application
import android.content.Context
import android.os.Bundle
import com.facebook.FacebookSdk
import com.facebook.appevents.AppEventsLogger
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AppGrowthPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var allowed = false
    private var logger: AppEventsLogger? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.workflow/app_growth")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        allowed = false
        logger = null
    }

    @Suppress("DEPRECATION")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val id = requireNotNull(call.argument<String>("appId"))
                    val token = requireNotNull(call.argument<String>("clientToken"))
                    require(id.matches(Regex("^[0-9]+$")) && token.isNotBlank())
                    require(!FacebookSdk.isInitialized() || FacebookSdk.getApplicationId() == id)
                    FacebookSdk.setAutoLogAppEventsEnabled(false)
                    FacebookSdk.setAdvertiserIDCollectionEnabled(false)
                    FacebookSdk.setApplicationId(id)
                    FacebookSdk.setClientToken(token)
                    FacebookSdk.sdkInitialize(context)
                    FacebookSdk.fullyInitialize()
                    logger = AppEventsLogger.newLogger(context)
                    result.success(null)
                }
                "consent" -> {
                    allowed = call.argument<Boolean>("events") == true
                    val ids = allowed && call.argument<Boolean>("advertiserId") == true
                    FacebookSdk.setAutoLogAppEventsEnabled(false)
                    FacebookSdk.setAdvertiserIDCollectionEnabled(ids)
                    result.success(null)
                }
                "activate" -> {
                    if (allowed && logger != null) {
                        AppEventsLogger.activateApp(context as Application)
                    }
                    result.success(null)
                }
                "event" -> {
                    if (!allowed || logger == null) {
                        result.error("CONSENT_REQUIRED", "Meta event collection is disabled", null)
                        return
                    }
                    val name = requireNotNull(call.argument<String>("name"))
                    require(name.matches(Regex("^[A-Za-z][A-Za-z0-9_]{0,39}$")))
                    val params = call.argument<Map<String, Any>>("params") ?: emptyMap()
                    require(params.size <= 25)
                    val bundle = Bundle()
                    for ((key, value) in params) {
                        require(key.matches(Regex("^[A-Za-z][A-Za-z0-9_]{0,39}$")))
                        when (value) {
                            is String -> { require(value.length <= 100); bundle.putString(key, value) }
                            is Boolean -> bundle.putInt(key, if (value) 1 else 0)
                            is Number -> { require(value.toDouble().isFinite()); bundle.putDouble(key, value.toDouble()) }
                            else -> throw IllegalArgumentException("Invalid parameter type")
                        }
                    }
                    val value = call.argument<Number>("value")?.toDouble()
                    if (value == null) logger!!.logEvent(name, bundle)
                    else { require(value.isFinite()); logger!!.logEvent(name, value, bundle) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("GROWTH_SDK_ERROR", error.javaClass.simpleName, null)
        }
    }
}
