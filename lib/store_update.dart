import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Whether Google Play has an update **this specific device can install right
/// now**, and the ability to run Play's own blocking update flow.
///
/// Play answering "yes" is a stronger signal than "a newer version exists in
/// the store": it accounts for staged rollout, device compatibility and
/// country targeting. That is exactly what makes it safe to block on - the
/// user is only ever walled off when they genuinely can update.
///
/// An interface, so the gate can be tested without Play.
abstract class StoreUpdates {
  /// True only when an update is available *and* the immediate (blocking) flow
  /// is allowed. Any doubt returns false - see [PlayStoreUpdates].
  Future<bool> isUpdateReady();

  /// Runs Play's full-screen update. Returns true if the update went through;
  /// false if the user backed out or Play refused.
  Future<bool> startImmediateUpdate();
}

/// The real thing. Android only.
class PlayStoreUpdates implements StoreUpdates {
  const PlayStoreUpdates();

  /// Play's APIs exist only on Android, and only work at all for a build
  /// **installed by Play**. A sideloaded APK, a debug build, or a device
  /// without Play Services throws - which is why every call here swallows
  /// errors and reports "no update".
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isUpdateReady() async {
    if (!supported) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed;
    } catch (_) {
      // Sideloaded build, no Play Services, offline, Play rate-limiting the
      // check - none of these are reasons to lock someone out.
      return false;
    }
  }

  @override
  Future<bool> startImmediateUpdate() async {
    if (!supported) return false;
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      return result == AppUpdateResult.success;
    } catch (_) {
      return false;
    }
  }
}

/// Everything that is not Android: iOS, macOS, Windows, web, and tests.
class NoStoreUpdates implements StoreUpdates {
  const NoStoreUpdates();

  @override
  Future<bool> isUpdateReady() async => false;

  @override
  Future<bool> startImmediateUpdate() async => false;
}
