package com.pouse.app

import android.util.Log
import java.io.OutputStream
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Background socket writer that keeps all RFCOMM I/O off the Android main thread.
 *
 * The previous sendEvent() was invoked via MethodChannel on the Android platform
 * (main) thread and called outputStream.write() + flush() directly, blocking
 * Flutter rendering for several milliseconds per MOVE event at 60 Hz.
 *
 * This writer runs on a daemon thread. Callers call enqueue() (non-blocking) and
 * return immediately. The writer drains the queue and does I/O on its own thread.
 *
 * MOVE events are dropped if the queue is full (bounded backpressure) -- safe
 * because stale cursor movement is worse than a missed frame.
 * Discrete events (click, key, scroll) use a short timeout to prevent silent drops.
 */
class PouseSocketWriter(
    private val out: OutputStream,
    private val stats: BluetoothLatencyStats,
) {
    private companion object {
        const val TAG = "PouseSocketWriter"
        const val QUEUE_CAPACITY = 64
        val POISON = ByteArray(0)
    }

    private data class Entry(val bytes: ByteArray, val enqueuedAtNs: Long, val isMove: Boolean)

    private val queue = ArrayBlockingQueue<Entry>(QUEUE_CAPACITY)
    private val poisonEntry = Entry(POISON, 0L, false)
    private lateinit var thread: Thread

    fun start() {
        thread = Thread({
            Log.d(TAG, "[WRITER] thread started")
            while (true) {
                val entry = try {
                    queue.take()
                } catch (e: InterruptedException) {
                    Log.d(TAG, "[WRITER] thread interrupted, stopping")
                    break
                }
                if (entry.bytes === POISON) {
                    Log.d(TAG, "[WRITER] poison pill received, stopping")
                    break
                }
                try {
                    out.write(entry.bytes)
                    out.flush()
                    val latencyUs = (System.nanoTime() - entry.enqueuedAtNs) / 1_000
                    stats.record(latencyUs.toInt(), entry.isMove)
                } catch (e: Exception) {
                    Log.e(TAG, "[WRITER] write error: ${e.message}")
                    break
                }
            }
            Log.d(TAG, "[WRITER] thread exited")
        }, "PouseSocketWriter")
        thread.isDaemon = true
        thread.start()
    }

    fun enqueue(message: String, isMoveEvent: Boolean): Boolean {
        val bytes = (message + "\n").toByteArray(Charsets.UTF_8)
        val entry = Entry(bytes, System.nanoTime(), isMoveEvent)
        return if (isMoveEvent) {
            val ok = queue.offer(entry)
            if (!ok) stats.recordDrop()
            ok
        } else {
            val ok = queue.offer(entry, 100, TimeUnit.MILLISECONDS)
            if (!ok) Log.w(TAG, "[WRITER] queue full: dropped discrete event (${message.take(60)})")
            ok
        }
    }

    fun stop() {
        val ok = queue.offer(poisonEntry, 200, TimeUnit.MILLISECONDS)
        if (!ok) thread.interrupt()
        stats.reportFinal()
    }
}

/**
 * Sampled Bluetooth send-path latency instrumentation.
 * Reports enqueue-to-write latency statistics every 5 seconds, never per-event.
 */
class BluetoothLatencyStats {
    private companion object {
        const val TAG = "PouseBtStats"
        const val REPORT_INTERVAL_MS = 5_000L
    }

    @Volatile private var nextReportAt = System.currentTimeMillis() + REPORT_INTERVAL_MS
    private val samples = ArrayList<Int>(1024)
    private var moveCount = 0L
    private var totalCount = 0L
    private var dropCount = 0L

    @Synchronized
    fun record(latencyUs: Int, isMove: Boolean) {
        samples.add(latencyUs)
        totalCount++
        if (isMove) moveCount++
        if (System.currentTimeMillis() >= nextReportAt) reportLocked()
    }

    @Synchronized
    fun recordDrop() { dropCount++ }

    fun reportFinal() = synchronized(this) { reportLocked() }

    private fun reportLocked() {
        if (samples.isEmpty()) return
        val sorted = samples.sorted()
        val n = sorted.size
        val avg = sorted.map { it.toLong() }.sum() / n
        val p50 = sorted[n * 50 / 100]
        val p95 = sorted[n * 95 / 100]
        val p99 = sorted[n * 99 / 100]
        val max = sorted.last()
        val rateSec = totalCount.toDouble() / (REPORT_INTERVAL_MS / 1000.0)
        Log.i(TAG,
            "[BT_WRITE_STATS] total=$totalCount moves=$moveCount drops=$dropCount " +
            "rate=${"%.1f".format(rateSec)}/s enqueue_to_write_us avg=$avg p50=$p50 p95=$p95 p99=$p99 max=$max")
        samples.clear(); totalCount = 0L; moveCount = 0L; dropCount = 0L
        nextReportAt = System.currentTimeMillis() + REPORT_INTERVAL_MS
    }
}
