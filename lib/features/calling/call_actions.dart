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
    // 1. Microphone is required for any call; camera additionally for video.
    if (!await _ensurePermission(context, Permission.microphone, 'Microphone', toast)) {
      return;
    }
    if (!context.mounted) return;
    if (video && !await _ensurePermission(context, Permission.camera, 'Camera', toast)) {
      return;
    }

    // 2. Mint the room/token on the server and connect to LiveKit.
    final ok = await ServiceLocator.calling.initiateCall(
      contactEmail,
      video: video,
      livekitUrl: ServiceLocator.livekitUrl,
    );
    if (!context.mounted) return;
    if (!ok) {
      toast("Couldn't start the call — the calling service may be unavailable. Please try again.");
      return;
    }

    final room = ServiceLocator.calling.activeRoom;
    if (room == null) {
      toast('Call connection failed. Please try again.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          room: room,
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
