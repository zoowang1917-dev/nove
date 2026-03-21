# ════════════════════════════════════════════
# 三省六部 × InkOS — ProGuard / R8 混淆规则
# ════════════════════════════════════════════

# ── Flutter 引擎核心 ──────────────────────────
-keep class io.flutter.app.**                { *; }
-keep class io.flutter.plugin.**             { *; }
-keep class io.flutter.util.**               { *; }
-keep class io.flutter.view.**               { *; }
-keep class io.flutter.**                    { *; }
-keep class plugins.flutter.io.**            { *; }
-keep class io.flutter.embedding.**          { *; }
-keep class io.flutter.embedding.engine.**   { *; }

# ── Kotlin 协程 ───────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keep class kotlinx.coroutines.**            { *; }
-dontwarn kotlinx.coroutines.**

# ── SQLite（sqflite）──────────────────────────
-keep class io.flutter.plugins.sqflite.**    { *; }
-keep class com.tekartik.sqflite.**          { *; }

# ── 安全存储（flutter_secure_storage）────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.**             { *; }

# ── 本地通知（flutter_local_notifications）───
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

# ── 分享（share_plus）─────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }

# ── 设备信息（device_info_plus）──────────────
-keep class dev.fluttercommunity.plus.deviceinfo.** { *; }

# ── 唤醒锁（wakelock_plus）───────────────────
-keep class creativemaybeno.wakelock.**      { *; }
-keep class nl.mrtn.wakelock.**             { *; }

# ── 权限（permission_handler）────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── Android Lifecycle（Riverpod 状态管理需要）─
-keep class * extends androidx.lifecycle.ViewModel { *; }
-keep class androidx.lifecycle.**            { *; }

# ── 注解与泛型（保留 JSON 解析所需）─────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes Exceptions

# ── 原生 Activity ─────────────────────────────
-keep class com.novel.ai.MainActivity        { *; }
-keep class com.novel.ai.**                  { *; }

# ── 防止 R8 错误地移除反射类 ──────────────────
-dontwarn sun.misc.**
-dontwarn java.lang.instrument.**
-dontwarn javax.annotation.**

# ── Google Fonts（网络字体）───────────────────
-keep class com.google.android.gms.**        { *; }
-dontwarn com.google.android.gms.**

# ── Dart 层：Isolate + 反射相关保护 ──────────
# Dart 代码通过 --obfuscate 由 Flutter 工具自动处理
# 以下保护 JNI 桥接层不被错误移除
-keep class io.flutter.plugin.common.**      { *; }
-keep class io.flutter.plugin.platform.**    { *; }
