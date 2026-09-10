# The ML Kit text-recognition plugin references every script's recognizer
# options, but this app bundles only the Latin model (see pubspec: the OCR
# dependency comment). R8 treats the absent script classes as an error unless
# told they are knowingly missing — the plugin falls back at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
