import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';

/// Export Data — port of `Views/Main/ExportDataPage.xaml(.cs)`. A list of report
/// types, each generated server-side as a court-admissible PDF (`api/export/*`).
///
/// The byte-fetch is wired to the real endpoint; persisting the PDF to device
/// storage (MAUI's `IMediaService.SaveToPublicStorageAsync`) is native — deferred to
/// phase 3 (path_provider / share_plus). On success we confirm the report generated.
class ExportDataPage extends StatefulWidget {
  const ExportDataPage({super.key});

  @override
  State<ExportDataPage> createState() => _ExportDataPageState();
}

class _ExportDataPageState extends State<ExportDataPage> {
  bool _busy = false;

  static const _reports = <_Report>[
    _Report('icon_calendar', AppColors.iconBgBlue, AppColors.primaryBlue, 'Custody Schedule',
        'Calendar and pattern details', AppColors.primaryBlue, 'api/export/custody', 'Custody_Schedule'),
    _Report('icon_money', AppColors.iconBgYellow, AppColors.warningAmber, 'Payment Verification',
        'Financial records and status', AppColors.primaryBlue, 'api/export/payments', 'Payment_Verification'),
    _Report('icon_chat', AppColors.iconBgGreen, AppColors.successGreen, 'Message Transcript',
        'Full conversation history', AppColors.primaryBlue, 'api/export/messages', 'Message_Transcript'),
    _Report('icon_location', AppColors.iconBgRed, AppColors.dangerRed, 'Location Records',
        'GPS logs and transfers', AppColors.primaryBlue, 'api/export/locations', 'Location_Records'),
    _Report('icon_layers', AppColors.iconBgPurple, AppColors.accentPurple, 'Comprehensive Report',
        'All data in one document', AppColors.accentPurple, 'api/export/comprehensive', 'Comprehensive_Case_Report'),
  ];

  Future<void> _download(_Report r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await ServiceLocator.api.getBytes(r.endpoint);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        await _alert('Error', 'Failed to generate report. Please try again.');
        return;
      }
      // Write to a temp file with a timestamped name (mirrors MAUI), then hand to
      // the system share sheet (save to Files, email, etc.).
      final now = DateTime.now();
      final stamp = '${now.year}${_pad(now.month)}${_pad(now.day)}';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${r.fileBaseName}_$stamp.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: r.title);
    } catch (e) {
      if (mounted) await _alert('Error', 'An error occurred: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: 'Export Data',
                subtitle: 'Download court-admissible reports',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Select a report to generate and download as PDF.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                          const SizedBox(height: 20),
                          for (int i = 0; i < _reports.length; i++) ...[
                            _reportCard(context, _reports[i]),
                            if (i < _reports.length - 1) const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, _Report r) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
              offset: const Offset(0, 4),
              blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(color: r.iconBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: AppIcon(r.icon, size: 24, color: r.iconTint)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text(r.subtitle, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _download(r),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: r.buttonColor, borderRadius: BorderRadius.circular(20)),
              child: const Center(
                child: Text('Download',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Report {
  final String icon;
  final Color iconBg;
  final Color iconTint;
  final String title;
  final String subtitle;
  final Color buttonColor;
  final String endpoint;
  final String fileBaseName;
  const _Report(this.icon, this.iconBg, this.iconTint, this.title, this.subtitle, this.buttonColor,
      this.endpoint, this.fileBaseName);
}
