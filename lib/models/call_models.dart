class CallSession {
  final int callSessionId;
  final String initiatorEmail;
  final String recipientEmail;
  final String roomName;
  final String status; // pending | active | ended | missed | rejected
  final bool hasVideo;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? recordingUrl;
  final String? transcript;

  const CallSession({
    required this.callSessionId,
    required this.initiatorEmail,
    required this.recipientEmail,
    required this.roomName,
    required this.status,
    required this.hasVideo,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.recordingUrl,
    this.transcript,
  });

  factory CallSession.fromJson(Map<String, dynamic> json) => CallSession(
        callSessionId: json['callSessionId'] as int? ?? 0,
        initiatorEmail: json['initiatorEmail'] as String,
        recipientEmail: json['recipientEmail'] as String,
        roomName: json['roomName'] as String,
        status: json['status'] as String,
        hasVideo: json['hasVideo'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt'] as String) : null,
        endedAt: json['endedAt'] != null ? DateTime.parse(json['endedAt'] as String) : null,
        recordingUrl: json['recordingUrl'] as String?,
        transcript: json['transcript'] as String?,
      );

  Duration? get duration {
    if (startedAt == null || endedAt == null) return null;
    return endedAt!.difference(startedAt!);
  }

  bool get isMissed => status == 'missed' || status == 'rejected';
  bool get isEnded => status == 'ended' || isMissed;
}

class IncomingCallEvent {
  final String roomName;
  final String callerEmail;
  final bool hasVideo;

  const IncomingCallEvent({
    required this.roomName,
    required this.callerEmail,
    required this.hasVideo,
  });

  factory IncomingCallEvent.fromJson(Map<String, dynamic> json) => IncomingCallEvent(
        roomName: json['roomName'] as String,
        callerEmail: json['callerEmail'] as String,
        hasVideo: json['hasVideo'] as bool? ?? false,
      );
}

class CallStateEvent {
  final String type; // call_accepted | call_rejected | call_ended
  final String roomName;

  const CallStateEvent({required this.type, required this.roomName});

  factory CallStateEvent.fromJson(String type, Map<String, dynamic> json) =>
      CallStateEvent(type: type, roomName: json['roomName'] as String? ?? '');
}
