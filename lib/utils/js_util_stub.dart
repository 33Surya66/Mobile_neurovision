// Stub file for non-web platforms
// Provides the small subset of dart:js_util API used by the app so files can
// import a single symbol `js_util` via conditional import.

/// Represent `globalThis` from JS. Null on non-web platforms.
dynamic globalThis = null;

/// Stub for `hasProperty(obj, name)`
bool hasProperty(dynamic obj, String name) => false;

/// Stub for `getProperty(obj, name)`
dynamic getProperty(dynamic obj, String name) => null;

/// Stub for `callMethod(obj, method, args)`
dynamic callMethod(dynamic obj, String method, List<dynamic> args) => null;

/// Stub for `promiseToFuture` - unsupported on non-web platforms
Future<T> promiseToFuture<T>(dynamic promise) => Future<T>.error(UnsupportedError('promiseToFuture not supported on this platform'));

/// Stub for `setProperty` (no-op)
void setProperty(dynamic obj, String name, dynamic value) {}
