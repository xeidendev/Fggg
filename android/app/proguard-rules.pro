# Arrows v5.0 — R8 rules.
# google_mobile_ads and in_app_purchase ship consumer rules via AARs;
# these extras cover reflective access from the GMA SDK and webviews.

-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Flutter
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**
