import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/service_locator.dart';
import 'call_screen.dart';

/// Starts an outgoing call to [contactEmail] and, on success, opens the
/// full-screen [CallScreen]. Shared by the chat header and the contact page so
/// the launch flow lives in one place.
///
/// Every failure path surfaces a message (mic/camera permission, server/LiveKit
/// unavailable, unexpected error) instead of failing silently — a silently
/// returning button looks broken and gives no signal about what went wrong.
Future<void> startOutgoingCall(
  BuildContext context,
  String contactEmail, {
  required bool video,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String message) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  try {
    // 0. Already in (or ringing/connecting) a call — don't start another; the
    // service holds one room at a time and a second call would tear down the first.
    if (ServiceLocator.calling.isInCall) {
      toast("You're already in a call.");
      return;
    }

    // 1. Microphone is required for any call; camera additionally for video.
    if (!await _ensurePermission(context, Permission.microphone, 'Microphone', toast)) {
      return;
    }
    if (!context.mounted) return;
    if (video && !await _ensurePermission(context, Permission.camera, 'Camera', toast)) {
      return;
    }

    // 2. Kick off the room/token mint + LiveKit connect, and open the call UI
    // IMMEDIATELY with the connecting future — the screen shows "Connecting…" and
    // attaches the room when it's live, so there's no lag staring at the contact.
    // Connection failures are surfaced (and the screen closed) inside CallScreen.
    final connecting = ServiceLocator.calling.initiateCall(
      contactEmail,
      video: video,
      livekitUrl: ServiceLocator.livekitUrl,
    );
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          connecting: connecting,
          contactEmail: contactEmail,
          hasVideo: video,
        ),
      ),
    );
  } catch (e) {
    toast('Call error: $e');
  }
}

/// Requests [permission]. On a permanent denial (where iOS no longer shows the
/// system prompt) it first explains what to do in a dialog and only opens
/// Settings if the user agrees. Returns true only when granted.
Future<bool> _ensurePermission(
  BuildContext context,
  Permission permission,
  String label,
  void Function(String) toast,
) async {
  final status = await permission.request();
  if (status.isGranted || status.isLimited) return true;

  if (status.isPermanentlyDenied || status.isRestricted) {
    if (!context.mounted) return false;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label access needed'),
        content: Text(
          'CoHarmony needs $label access to make calls, but it\'s currently '
          'turned off.\n\nTap "Open Settings", then enable $label for CoHarmony.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (openSettings == true) await openAppSettings();
  } else {
    toast('$label permission is needed to make calls.');
  }
  return false;
}
