import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import 'call_screen.dart';

/// Starts an outgoing call to [contactEmail] and, on success, opens the
/// full-screen [CallScreen]. Shared by the chat header and the contact page so
/// the launch flow lives in one place.
Future<void> startOutgoingCall(
  BuildContext context,
  String contactEmail, {
  required bool video,
}) async {
  final ok = await ServiceLocator.calling.initiateCall(
    contactEmail,
    video: video,
    livekitUrl: ServiceLocator.livekitUrl,
  );
  if (!ok || !context.mounted) return;

  final room = ServiceLocator.calling.activeRoom;
  if (room == null) return;

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
}
