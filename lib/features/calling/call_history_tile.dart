import 'package:flutter/material.dart';

import '../../models/call_models.dart';
import '../../theme/app_colors.dart';

/// Inline tile shown in the chat thread for a completed/missed call.
class CallHistoryTile extends StatelessWidget {
  const CallHistoryTile({
    super.key,
    required this.session,
    required this.currentUserEmail,
  });

  final CallSession session;
  final String currentUserEmail;

  bool get _isOutgoing => session.initiatorEmail == currentUserEmail;

  @override
  Widget build(BuildContext context) {
    final missed = session.isMissed;
    final icon = session.hasVideo ? Icons.videocam_outlined : Icons.call_outlined;
    final color = missed ? AppColors.dangerRed : AppColors.successGreen;
    final label = _label();
    final duration = session.duration;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              if (duration != null) ...[
                const SizedBox(width: 4),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
              if (session.transcript != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.text_snippet_outlined, size: 14, color: AppColors.infoBlue),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _label() {
    if (session.status == 'missed') return _isOutgoing ? 'No answer' : 'Missed call';
    if (session.status == 'rejected') return _isOutgoing ? 'Call declined' : 'Declined';
    return _isOutgoing ? 'Outgoing call' : 'Incoming call';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }
}
