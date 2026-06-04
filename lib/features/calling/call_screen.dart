import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

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

  final List<EventsListener<RoomEvent>> _listeners = [];

  @override
  void initState() {
    super.initState();
    _cameraEnabled = widget.hasVideo;
    _listenForCallEnd();
  }

  void _listenForCallEnd() {
    final sub = ServiceLocator.calling.onCallStateChanged.listen((event) {
      if ((event.type == 'call_ended') && mounted) {
        Navigator.of(context).pop();
      }
    });
    // Store sub for cancel — simple approach using EventsListener
    _listeners.add(widget.room.createListener()
      ..on<RoomDisconnectedEvent>((_) {
        sub.cancel();
        if (mounted) Navigator.of(context).pop();
      }));
  }

  @override
  void dispose() {
    for (final l in _listeners) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _hangUp() async {
    await ServiceLocator.calling.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleMic() {
    ServiceLocator.calling.toggleMicrophone();
    setState(() => _micEnabled = !_micEnabled);
  }

  void _toggleCamera() {
    ServiceLocator.calling.toggleCamera();
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.room.remoteParticipants.values.toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (full screen)
            if (widget.hasVideo && participants.isNotEmpty)
              _RemoteVideoView(participant: participants.first)
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
                    const Text(
                      'Connected',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),

            // Local camera PiP (top-right)
            if (widget.hasVideo)
              Positioned(
                top: 16,
                right: 16,
                child: SizedBox(
                  width: 90,
                  height: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _LocalVideoView(localParticipant: widget.room.localParticipant!),
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
                      onTap: () => setState(() => _speakerEnabled = !_speakerEnabled),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteVideoView extends StatelessWidget {
  const _RemoteVideoView({required this.participant});
  final RemoteParticipant participant;

  @override
  Widget build(BuildContext context) {
    final videoTrack = participant.videoTrackPublications.firstOrNull?.track;
    if (videoTrack == null) return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    return SizedBox.expand(
      child: VideoTrackRenderer(videoTrack),
    );
  }
}

class _LocalVideoView extends StatelessWidget {
  const _LocalVideoView({required this.localParticipant});
  final LocalParticipant localParticipant;

  @override
  Widget build(BuildContext context) {
    final videoTrack = localParticipant.videoTrackPublications.firstOrNull?.track;
    if (videoTrack == null) return const ColoredBox(color: Colors.black87);
    return VideoTrackRenderer(videoTrack as VideoTrack);
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
