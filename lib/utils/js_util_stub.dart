// Stub file for mobile platforms
// This file provides empty implementations of JS interop functions for mobile

class JsUtil {
  static dynamic globalThis = null;
  
  static bool hasProperty(dynamic obj, String property) => false;
  
  static dynamic callMethod(dynamic obj, String method, List<dynamic> args) => null;
  
  static Future<T> promiseToFuture<T>(dynamic promise) async {
    throw UnsupportedError('promiseToFuture not supported on mobile');
  }
}
