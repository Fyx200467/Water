# flutter_local_notifications 用 Gson 反射反序列化通知详情；
# release 下 R8 裁掉泛型签名会抛 "Missing type parameter"，
# 导致 zonedSchedule / pendingNotificationRequests 全部失败（通知不排程）。
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.google.gson.**
