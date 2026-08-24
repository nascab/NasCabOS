package com.nascabos.tv.core.api.p2p

import android.content.Context
import org.webrtc.PeerConnectionFactory

object P2pWebRtc {
    @Volatile
    private var initialized = false

    @Volatile
    private var factory: PeerConnectionFactory? = null

    fun getFactory(appContext: Context): PeerConnectionFactory {
        val existing = factory
        if (existing != null) return existing
        synchronized(this) {
            if (!initialized) {
                PeerConnectionFactory.initialize(
                    PeerConnectionFactory.InitializationOptions.builder(appContext)
                        .setEnableInternalTracer(false)
                        .createInitializationOptions(),
                )
                initialized = true
            }
            val created = PeerConnectionFactory.builder().createPeerConnectionFactory()
            factory = created
            return created
        }
    }
}
