-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class com.supabase.** { *; }
-dontwarn com.supabase.**
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**
-keep class com.powersync.** { *; }
-dontwarn com.powersync.**
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

# Flutter (keep app/plugin surface; silence embedding warnings during shrink)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.embedding.**
