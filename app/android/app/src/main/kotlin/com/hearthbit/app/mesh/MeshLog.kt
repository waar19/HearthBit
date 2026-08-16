package com.hearthbit.app.mesh

import android.util.Log as AndroidLog
import com.hearthbit.app.BuildConfig

internal object MeshLog {
    fun d(tag: String, message: String): Int =
        if (BuildConfig.DEBUG) AndroidLog.d(tag, message) else 0

    fun i(tag: String, message: String): Int =
        if (BuildConfig.DEBUG) AndroidLog.i(tag, message) else 0

    fun w(tag: String, message: String): Int =
        if (BuildConfig.DEBUG) AndroidLog.w(tag, message) else 0

    fun w(tag: String, message: String, error: Throwable): Int =
        if (BuildConfig.DEBUG) AndroidLog.w(tag, message, error) else 0
}
