import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../models/call_models.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';

/// Full-screen active call UI. Push this route when the call is connected.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.room,
    required this.contactEmail,
    required this.hasVideo,
  });

  final Room room;
  final String contactEmail;
  final bool hasVideo;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = true;

  EventsListener<RoomEvent>? _roomListener;
  StreamSubscription<CallStateEvent>? _stateSub;

  @override
  void initState() {
    super.initState();
    _cameraEnabled = widget.hasVideo;

    // Rebuild whenever participants or their tracks change so the remote/local
    // video tiles appear as soon as tracks are published/subscribed.
    _roomListener = widget.room.createListener()
      ..on<ParticipantConnectedEvent>((_) => _refresh())
      ..on<ParticipantDisconnectedEvent>((_) {
        _refresh();
        // The other party left the room — end the call on this side too, even if
        // the call_ended WebSocket event never arrives. Without this the local
        // user is stuck on the call screen / native CallKit UI after a remote
        // hang-up.
        if (widget.room.remoteParticipants.isEmpty) _endAndClose();
      })
      ..on<TrackSubscribedEvent>((_) => _refresh())
      ..on<TrackUnsubscribedEvent>((_) => _refresh())
      ..on<TrackPublishedEvent>((_) => _refresh())
      ..on<TrackUnpublishedEvent>((_) => _refresh())
      ..on<RoomDisconnectedEvent>((_) => _endAndClose());

    // Remote hang-up arrives as a call_ended WebSocket event.
    _stateSub = ServiceLocator.calling.onCallStateChanged.listen((event) {
      if (event.type == 'call_ended' || event.type == 'call_rejected') {
        _endAndClose();
      }
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _roomListener?.dispose();
    super.dispose();
  }

  Future<void> _hangUp() => _endAndClose();

  /// Single termination path for every way a call can end (local hang-up, remote
  /// hang-up, room disconnect, server call_ended). Idempotent: tears down the
  /// LiveKit room, clears any native CallKit UI, and closes the screen exactly
  /// once.
  bool _closing = false;
  Future<void> _endAndClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await ServiceLocator.calling.endCall();
    } catch (_) {/* best-effort */}
    try {
      await ServiceLocator.callKit.dismissAll();
    } catch (_) {/* best-effort */}
    if (mounted) Navigator.of(context).maybePop();
  }

  void _toggleMic() {
    ServiceLocator.calling.toggleMicrophone();
    setState(() => _micEnabled = !_micEnabled);
  }

  void _toggleCamera() {
    ServiceLocator.calling.toggleCamera();
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  void _toggleSpeaker() {
    final next = !_speakerEnabled;
    Hardware.instance.setSpeakerphoneOn(next);
    setState(() => _speakerEnabled = next);
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.room.remoteParticipants.values.toList();
    final remoteVideo = _firstRemoteVideoTrack(participants);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (full screen) or avatar placeholder
            if (widget.hasVideo && remoteVideo != null)
              Positioned.fill(child: VideoTrackRenderer(remoteVideo))
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 52,
                      backgroundColor: AppColors.primaryBlue,
                      child: Icon(Icons.person, size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.contactEmail,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      participants.isEmpty ? 'Ringing…' : 'Connected',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),

            // Local camera PiP (top-right)
            if (widget.hasVideo && _cameraEnabled)
              Positioned(
                top: 16,
                right: 16,
                child: SizedBox(
                  width: 90,
                  height: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _localVideo() ?? const ColoredBox(color: Colors.black87),
                  ),
                ),
              ),

            // Controls (bottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ControlButton(
                    icon: _micEnabled ? Icons.mic : Icons.mic_off,
                    label: _micEnabled ? 'Mute' : 'Unmute',
                    onTap: _toggleMic,
                  ),
                  _ControlButton(
                    icon: Icons.call_end,
                    label: 'End',
                    color: AppColors.dangerRed,
                    iconSize: 32,
                    onTap: _hangUp,
                  ),
                  if (widget.hasVideo)
                    _ControlButton(
                      icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _cameraEnabled ? 'Camera off' : 'Camera on',
                      onTap: _toggleCamera,
                    )
                  else
                    _ControlButton(
                      icon: _speakerEnabled ? Icons.volume_up : Icons.volume_off,
                      label: _speakerEnabled ? 'Speaker' : 'Earpiece',
                      onTap: _toggleSpeaker,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  VideoTrack? _firstRemoteVideoTrack(List<RemoteParticipant> participants) {
    for (final p in participants) {
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (pub.subscribed && track is VideoTrack) return track;
      }
    }
    return null;
  }

  Widget? _localVideo() {
    final pubs = widget.room.localParticipant?.videoTrackPublications ?? const [];
    for (final pub in pubs) {
      // Local video publications are LocalVideoTrack (a VideoTrack); a null check
      // narrows the nullable getter so the renderer accepts it.
      final track = pub.track;
      if (track != null) return VideoTrackRenderer(track);
    }
    return null;
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.iconSize = 24.0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Colors.white24;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: bg,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
