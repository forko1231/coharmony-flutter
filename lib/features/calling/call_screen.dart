import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../models/call_models.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';

/// Full-screen active call UI. Open this route the instant a call is accepted/
/// placed — pass [connecting] (a future of the room) so the screen appears
/// immediately showing "Connecting…" and attaches the room when it's live,
/// rather than the caller/recipient staring at a frozen screen during the join.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    this.room,
    this.connecting,
    this.roomName,
    required this.contactEmail,
    this.contactName,
    required this.hasVideo,
  }) : assert(room != null || connecting != null, 'need a room or a connecting future');

  /// An already-connected room. If null, [connecting] is awaited to obtain it.
  final Room? room;

  /// Resolves to the connected room (or null on failure). Lets the UI open
  /// instantly and show a connecting state while the LiveKit join completes.
  final Future<Room?>? connecting;

  /// Room name known up-front (recipient side), used to match WebSocket events
  /// while still connecting. Falls back to room.name once connected.
  final String? roomName;

  final String contactEmail;
  final String? contactName; // shown instead of the email when available
  final bool hasVideo;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = true;

  Room? _room; // null while still connecting
  String? _roomName; // for WS matching even before the room is live

  EventsListener<RoomEvent>? _roomListener;
  StreamSubscription<CallStateEvent>? _stateSub;
  bool _remoteEverConnected = false; // has the other party ever been in the room?
  bool _answered = false; // call_accepted received or remote joined the room
  Timer? _ringTimeout; // caller-side: end the call if nobody answers
  Timer? _rejectGrace; // brief wait before honoring a reject (accept may race it)
  Timer? _remoteGoneTimer; // remote left the room — close if they don't return

  @override
  void initState() {
    super.initState();
    _cameraEnabled = widget.hasVideo;
    _roomName = widget.roomName;
    _room = widget.room;

    // The WebSocket call-state listener is active immediately — even while
    // connecting — so an accept/reject/end that arrives during the join is handled.
    _stateSub = ServiceLocator.calling.onCallStateChanged.listen(_onWsState);

    if (_room != null) {
      _attachRoom(_room!);
    } else {
      widget.connecting!.then(_onConnected);
    }
  }

  /// The connect future resolved. Attach the room, or close the screen (surfacing
  /// the reason) if the connection failed.
  void _onConnected(Room? room) {
    if (!mounted) return;
    if (room == null) {
      debugPrint('[CALL] screen: connect returned null → closing');
      final err = ServiceLocator.calling.lastConnectError;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(err != null ? 'Call failed: $err' : 'Call failed to connect.'),
      ));
      _endAndClose();
      return;
    }
    setState(() {
      _room = room;
      _roomName ??= room.name;
    });
    _attachRoom(room);
  }

  /// Wire up room event listeners + the caller no-answer timeout. Called once the
  /// room is live (either passed in, or after [connecting] resolves).
  void _attachRoom(Room room) {
    _roomName ??= room.name;
    _remoteEverConnected = room.remoteParticipants.isNotEmpty;
    if (_remoteEverConnected) _answered = true;

    // Rebuild whenever participants or their tracks change so the remote/local
    // video tiles appear as soon as tracks are published/subscribed.
    _roomListener = room.createListener()
      ..on<ParticipantConnectedEvent>((e) {
        debugPrint('[CALL] screen: ParticipantConnected ${e.participant.identity} '
            'remotes=${room.remoteParticipants.length}');
        _remoteEverConnected = true;
        _answered = true; // remote is in the room — a later reject is stale
        _ringTimeout?.cancel(); // answered — stop the no-answer timeout
        _rejectGrace?.cancel();
        _remoteGoneTimer?.cancel(); // remote (re)joined — cancel the leave timer
        _refresh();
      })
      // Just refresh the UI — do NOT auto-end here. A live (esp. video) call can
      // briefly fire ParticipantDisconnected during a renegotiation/reconnect, and
      // auto-ending on that was killing working calls. The real "other side hung up"
      // signal is the call_ended WebSocket event handled below.
      ..on<ParticipantDisconnectedEvent>((e) {
        debugPrint('[CALL] screen: ParticipantDisconnected ${e.participant.identity} '
            'remotes=${room.remoteParticipants.length}');
        _refresh();
        // The remote left. Close the call if they don't return within a grace
        // window — we can't rely solely on the call_ended WebSocket event, which
        // sometimes never arrives (other side killed / lost network). The grace is
        // long enough that a brief LiveKit reconnect won't drop a live call, and
        // ParticipantConnected cancels it. Only after the call was actually answered.
        if (_answered && room.remoteParticipants.isEmpty) {
          _scheduleEndIfRemoteGone();
        }
      })
      ..on<TrackSubscribedEvent>((_) => _refresh())
      ..on<TrackUnsubscribedEvent>((_) => _refresh())
      ..on<TrackPublishedEvent>((_) => _refresh())
      ..on<TrackUnpublishedEvent>((_) => _refresh())
      ..on<RoomDisconnectedEvent>((e) {
        debugPrint('[CALL] screen: RoomDisconnected reason=${e.reason} → endAndClose');
        _endAndClose();
      });

    // Caller-side no-answer timeout: if nobody has joined within 45s, end the
    // call so the caller isn't stuck ringing forever. (A recipient attaches with
    // the caller already present, so this never fires for them.)
    if (!_remoteEverConnected) {
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (mounted && !_remoteEverConnected) {
          debugPrint('[CALL] screen: ring timeout (45s, no answer) → endAndClose');
          _endAndClose();
        }
      });
    }
    _refresh();
  }

  /// Call state from the WebSocket. Only react to events for THIS room — a stray/
  /// late event from a previous or concurrent call must not touch this call.
  void _onWsState(CallStateEvent event) {
    final myRoom = _roomName;
    if (myRoom == null || event.roomName != myRoom) {
      debugPrint('[CALL] screen: IGNORED ${event.type} (room ${event.roomName} != $myRoom)');
      return;
    }
    debugPrint('[CALL] screen: WS ${event.type} (answered=$_answered)');
    switch (event.type) {
      case 'call_accepted':
        // The callee answered — the call is live. Accept WINS over any reject.
        _answered = true;
        _rejectGrace?.cancel();
        break;
      case 'call_ended':
        _endAndClose();
        break;
      case 'call_rejected':
        // A duplicate ring on the callee (WebSocket + push) can emit a spurious
        // reject right around the accept. If we've already been answered, ignore
        // it. Otherwise wait briefly — an accept may be racing this reject — and
        // only end if no answer arrives in that window.
        if (_answered) {
          debugPrint('[CALL] screen: ignoring call_rejected (already answered)');
        } else {
          _rejectGrace?.cancel();
          _rejectGrace = Timer(const Duration(seconds: 2), () {
            if (mounted && !_answered) {
              debugPrint('[CALL] screen: call_rejected stands (no answer) → endAndClose');
              _endAndClose();
            }
          });
        }
        break;
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// The remote left the room. Wait a grace window and close only if they're still
  /// gone — a brief LiveKit reconnect (ParticipantConnected) cancels this. This is
  /// the fallback for when the call_ended WebSocket event never arrives.
  void _scheduleEndIfRemoteGone() {
    _remoteGoneTimer?.cancel();
    _remoteGoneTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _closing) return;
      if (_room?.remoteParticipants.isEmpty ?? true) {
        debugPrint('[CALL] screen: remote gone for 6s (no call_ended) → endAndClose');
        _endAndClose();
      }
    });
  }

  /// Status line under the avatar.
  String _statusText(bool hasRemote) {
    if (_closing) return 'Call ended';
    if (_room == null) return 'Connecting…';
    if (hasRemote) return 'Connected';
    if (_remoteEverConnected) return 'Call ended'; // remote left — not "Ringing"
    return 'Ringing…';
  }

  @override
  void dispose() {
    _ringTimeout?.cancel();
    _rejectGrace?.cancel();
    _remoteGoneTimer?.cancel();
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
    debugPrint('[CALL] screen: _endAndClose room=${_roomName ?? _room?.name}');
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
    final participants = _room?.remoteParticipants.values.toList() ?? const <RemoteParticipant>[];
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
                      (widget.contactName?.trim().isNotEmpty ?? false)
                          ? widget.contactName!.trim()
                          : widget.contactEmail,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusText(participants.isNotEmpty),
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
    final pubs = _room?.localParticipant?.videoTrackPublications ?? const [];
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
