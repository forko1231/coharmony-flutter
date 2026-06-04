import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../services/notification_service.dart';
import 'app_icon.dart';

/// In-app notification banner — port of `Services/InAppNotificationBanner.cs`.
/// Slides a tappable, auto-dismissing card down from the top over the current
/// screen (via the global navigator overlay), styled per [NotificationType].
class AppNotificationBanner {
  AppNotificationBanner._();

  static OverlayEntry? _entry;

  static void show({
    required String title,
    required String body,
    required NotificationType type,
    VoidCallback? onTapped,
    int autoDismissSeconds = 4,
  }) {
    final overlay = AppNavigation.navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    // Dismiss any existing banner first.
    _entry?.remove();
    _entry = null;

    final (icon, accent) = _styleFor(type);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerCard(
        title: title,
        body: body,
        icon: icon,
        accent: accent,
        autoDismiss: Duration(seconds: autoDismissSeconds),
        onTap: onTapped,
        onRemove: () {
          if (_entry == entry) {
            entry.remove();
            _entry = null;
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Type → (icon asset, accent colour), matching MAUI's GetNotificationStyle.
  static (String, Color) _styleFor(NotificationType type) {
    switch (type) {
      case NotificationType.messageReceived:
        return ('icon_chat', const Color(0xFF3B82F6)); // Blue
      case NotificationType.courtMessage:
        return ('icon_scale', const Color(0xFF8B5CF6)); // Purple
      case NotificationType.partnerInviteReceived:
        return ('icon_user_plus', const Color(0xFF10B981)); // Green
      case NotificationType.partnerInviteAccepted:
        return ('icon_check_circle', const Color(0xFF10B981)); // Green
      case NotificationType.partnerInviteDeclined:
        return ('icon_close', const Color(0xFFEF4444)); // Red
      case NotificationType.paymentComingUp:
        return ('icon_money', const Color(0xFFF59E0B)); // Amber
      case NotificationType.eventComingUp:
        return ('icon_calendar', const Color(0xFF6366F1)); // Indigo
      case NotificationType.scheduleReminder:
        return ('icon_clock', const Color(0xFFEC4899)); // Pink
      case NotificationType.custodyUpdate:
        return ('icon_clipboard', const Color(0xFF14B8A6)); // Teal
      case NotificationType.custodyResponse:
        return ('icon_document', const Color(0xFF0EA5E9)); // Sky blue
      case NotificationType.incomingCall:
        return ('icon_phone', const Color(0xFF22C55E)); // Green
      case NotificationType.callEnded:
        return ('icon_phone', const Color(0xFF6B7280)); // Gray
    }
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.autoDismiss,
    required this.onRemove,
    this.onTap,
  });

  final String title;
  final String body;
  final String icon;
  final Color accent;
  final Duration autoDismiss;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  Timer? _dismissTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _dismissTimer = Timer(widget.autoDismiss, _close);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _dismissTimer?.cancel();
    if (mounted) await _ctrl.reverse();
    widget.onRemove();
  }

  void _handleTap() {
    widget.onTap?.call();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _ctrl,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _handleTap,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2937) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border(left: BorderSide(color: widget.accent, width: 4)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: widget.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: Center(child: AppIcon(widget.icon, size: 20, color: widget.accent)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF111827))),
                              const SizedBox(height: 2),
                              Text(widget.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563))),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _close,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: AppIcon('icon_close',
                                size: 16, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
