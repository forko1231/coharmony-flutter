import 'package:flutter/material.dart';

import '../../models/call_models.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import 'call_screen.dart';

/// Displays an incoming call banner over whatever screen is currently visible.
/// Attach this to AppShell by listening to [CallingService.onIncomingCall].
class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  IncomingCallEvent? _pendingCall;

  @override
  void initState() {
    super.initState();
    ServiceLocator.calling.onIncomingCall.listen(_onIncoming);
  }

  void _onIncoming(IncomingCallEvent event) {
    if (mounted) setState(() => _pendingCall = event);
  }

  Future<void> _accept() async {
    final event = _pendingCall;
    if (event == null) return;
    setState(() => _pendingCall = null);

    final ok = await ServiceLocator.calling.acceptCall(
      event,
      livekitUrl: ServiceLocator.livekitUrl,
    );
    if (!ok || !mounted) return;

    final room = ServiceLocator.calling.activeRoom;
    if (room == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          room: room,
          contactEmail: event.callerEmail,
          hasVideo: event.hasVideo,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    final roomName = _pendingCall?.roomName;
    setState(() => _pendingCall = null);
    if (roomName != null) await ServiceLocator.calling.rejectCall(roomName);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_pendingCall != null) _IncomingCallBanner(
          event: _pendingCall!,
          onAccept: _accept,
          onDecline: _decline,
        ),
      ],
    );
  }
}

class _IncomingCallBanner extends StatelessWidget {
  const _IncomingCallBanner({
    required this.event,
    required this.onAccept,
    required this.onDecline,
  });

  final IncomingCallEvent event;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: ColoredBox(
          color: Colors.black54,
          child: Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primaryBlue,
                      child: Icon(
                        event.hasVideo ? Icons.videocam : Icons.call,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.callerEmail,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            event.hasVideo ? 'Incoming video call' : 'Incoming voice call',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Decline
                    GestureDetector(
                      onTap: onDecline,
                      child: const CircleAvatar(
                        backgroundColor: AppColors.dangerRed,
                        child: Icon(Icons.call_end, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Accept
                    GestureDetector(
                      onTap: onAccept,
                      child: const CircleAvatar(
                        backgroundColor: AppColors.successGreen,
                        child: Icon(Icons.call, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
