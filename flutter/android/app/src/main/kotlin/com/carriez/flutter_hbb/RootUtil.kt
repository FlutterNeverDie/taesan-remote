package com.carriez.flutter_hbb

import android.util.Log

/**
 * Taesan: 루팅된 무인 키오스크에서 "켜면 자동으로 원격이 되는" 것을 위한 root 헬퍼.
 *
 * 표준 안드로이드는 (1) 화면공유(MediaProjection) 동의 팝업, (2) 접근성(입력) 수동 활성화 때문에
 * 무인 동작이 막힌다. 제어 가능한(루팅된) 박스에서는 su 로 접근성을 자동 활성화하고,
 * 화면공유 팝업은 접근성 서비스가 자동 클릭하도록 하여 사람 손 없이 동작하게 한다.
 *
 * 모든 호출은 실패해도 조용히 넘어간다(루트 없음/명령 실패 시 기존 수동 흐름으로 폴백).
 */
object RootUtil {
    private const val logTag = "TaesanRoot"

    /** su 로 한 줄 명령 실행. 성공 시 stdout, 실패/루트없음 시 null. */
    fun runAsRoot(cmd: String): String? {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            val code = p.waitFor()
            if (code != 0) {
                Log.w(logTag, "root cmd rc=$code cmd=$cmd err=${err.trim()}")
            }
            out
        } catch (e: Exception) {
            Log.w(logTag, "root unavailable or cmd failed: $cmd (${e.message})")
            null
        }
    }

    fun isRootAvailable(): Boolean {
        val out = runAsRoot("id") ?: return false
        return out.contains("uid=0")
    }

    /**
     * 무인 동작에 필요한 표준 권한/설정을 root 로 한 번에 확정한다.
     *  - 접근성 InputService 활성화(입력)
     *  - 배터리 최적화 화이트리스트(부팅/백그라운드 유지)
     *  - 다른 앱 위에 표시(SYSTEM_ALERT_WINDOW) — BootReceiver 통과 조건
     * 이미 되어 있으면 무해하게 통과. 부팅 시/서비스 시작 시 호출한다.
     */
    fun ensureUnattendedGrants(pkg: String) {
        // 접근성(입력) 활성화
        // applicationId(com.taesan.remote)와 Kotlin 네임스페이스가 달라 클래스 이름은 전체 이름으로 적는다(Q-29, D35).
        val service = "$pkg/com.carriez.flutter_hbb.InputService"
        val current = runAsRoot("settings get secure enabled_accessibility_services")?.trim() ?: ""
        if (!current.contains(service)) {
            val merged = if (current.isBlank() || current == "null") service else "$current:$service"
            runAsRoot("settings put secure enabled_accessibility_services '$merged'")
        }
        runAsRoot("settings put secure accessibility_enabled 1")

        // 배터리 최적화 예외(도즈 화이트리스트)
        runAsRoot("dumpsys deviceidle whitelist +$pkg")

        // 다른 앱 위에 표시(오버레이) 허용 — BootReceiver 의 SYSTEM_ALERT_WINDOW 조건 통과용
        runAsRoot("appops set $pkg SYSTEM_ALERT_WINDOW allow")
    }
}
