import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/preferences.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';

const _shownKey = 'call_perms_primer_shown';

/// One-time calling-permissions primer, shown the first time the user reaches the
/// app after finishing onboarding (i.e. post-subscription).
///
/// Why pre-grant here instead of at call time: an incoming call can arrive while
/// the app is killed and the device is locked, and neither iOS nor Android can
/// show a permission prompt over the lock screen — so a first-time recipient who
/// never granted the mic simply can't answer. Asking now (with context) means the
/// permission is already granted by the time a call comes in.
Future<void> maybeShowCallPermissionsPrimer(BuildContext context) async {
  if (Preferences.getBool(_shownKey)) return;
  if (!Preferences.getBool('calling_enabled', true)) return;

  // If the mic is already granted there's nothing to prime; mark done and move on.
  final mic = await Permission.microphone.status;
  if (mic.isGranted) {
    await Preferences.setBool(_shownKey, true);
    return;
  }
  if (!context.mounted) return;

  // Only ever show the primer once, regardless of the choice.
  await Preferences.setBool(_shownKey, true);
  if (!context.mounted) return;

  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _CallPermissionsDialog(),
  );
  if (proceed != true) return;

  // Trigger the system prompts. Mic covers every call; camera covers video.
  await Permission.microphone.request();
  await Permission.camera.request();
}

class _CallPermissionsDialog extends StatelessWidget {
  const _CallPermissionsDialog();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceElevated,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: Icon(Icons.call, color: Colors.white, size: 30)),
            ),
            const SizedBox(height: 18),
            Text('Enable calling',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 10),
            Text(
              'CoHarmony lets you make and receive voice and video calls with your '
              'co-parent. To answer a call — even when your phone is locked — we need '
              'access to your microphone and camera.\n\nWe\'ll never use them outside a call.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: palette.textSecondary),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textSecondary,
                      side: BorderSide(color: palette.border, width: 2),
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.successGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Allow access',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
