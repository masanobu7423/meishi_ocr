# google_mlkit_text_recognition references every script's options class but
# only the Japanese model is shipped (see build.gradle.kts). Tell R8 the
# others are intentionally absent; otherwise minifyRelease fails.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.korean.**
