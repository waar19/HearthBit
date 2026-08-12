package com.hearthbit.app.mesh

import android.content.Context

internal object MeshRuntime {
    @Volatile
    var eventListener: ((Map<String, Any?>) -> Unit)? = null

    @Volatile
    private var engineInstance: MeshEngine? = null

    fun engine(context: Context): MeshEngine {
        return engineInstance ?: synchronized(this) {
            engineInstance ?: MeshEngine(context.applicationContext) { event ->
                eventListener?.invoke(event)
            }.also { engineInstance = it }
        }
    }

    fun stateSnapshot(): Map<String, Any?>? = engineInstance?.stateSnapshot()

    fun destroy() {
        synchronized(this) {
            engineInstance?.stop()
            engineInstance = null
        }
    }
}
