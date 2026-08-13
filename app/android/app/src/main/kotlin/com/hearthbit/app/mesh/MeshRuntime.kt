package com.hearthbit.app.mesh

import android.content.Context

internal object MeshRuntime {
    @Volatile
    var eventListener: ((Map<String, Any?>) -> Unit)? = null

    @Volatile
    var notificationListener: ((MeshNotificationState) -> Unit)? = null

    @Volatile
    private var engineInstance: MeshEngine? = null

    fun engine(
        context: Context,
        requiredRole: MeshNodeRole? = null,
    ): MeshEngine {
        return synchronized(this) {
            engineInstance?.also { engine ->
                requiredRole?.let(engine::configureStartupRole)
            } ?: MeshEngine(
                context = context.applicationContext,
                requiredRole = requiredRole,
                emit = { event -> eventListener?.invoke(event) },
                observeNotification = { state -> notificationListener?.invoke(state) },
            ).also { engineInstance = it }
        }
    }

    fun stateSnapshot(): Map<String, Any?>? = engineInstance?.stateSnapshot()

    fun notificationSnapshot(): MeshNotificationState? = engineInstance?.notificationSnapshot()

    fun destroy() {
        synchronized(this) {
            engineInstance?.stop()
            engineInstance = null
        }
    }
}
