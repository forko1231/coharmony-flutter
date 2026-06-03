import 'package:flutter/material.dart';
import '../../../services/custody_templates/pending_template_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../widgets/app_icon.dart';
import '../../ai/ai_chat_page.dart';
import '../custody_schedule_page.dart';
import 'template_catalog_page.dart';

/// "How would you like to start?" — port of `CustodyStartChoicePage.xaml(.cs)`.
/// First screen of the template-setup flow: Ask AI, Choose a template, or build from
/// scratch. Clears any stale [PendingTemplateService] state on entry.
class CustodyStartChoicePage extends StatefulWidget {
  const CustodyStartChoicePage({super.key});

  @override
  State<CustodyStartChoicePage> createState() => _CustodyStartChoicePageState();
}

class _CustodyStartChoicePageState extends State<CustodyStartChoicePage> {
  @override
  void initState() {
    super.initState();
    PendingTemplateService.clear();
  }

  void _askAi() {
    PendingTemplateService.requestAiPath();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AiChatPage(chatContext: 'schedule')),
    );
  }

  void _chooseTemplate() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplateCatalogPage()));
  }

  void _buildFromScratch() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustodySchedulePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Header with close
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 12, 20, 16),
            color: palette.surfaceElevated,
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text('✕', style: TextStyle(fontSize: 18, color: palette.textSecondary))),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(24)),
                        child: const Center(child: AppIcon('icon_calendar', size: 40, color: AppColors.primaryBlue)),
                      ),
                      const SizedBox(height: 12),
                      Text('Set up your custody schedule',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 12),
                      Text('How would you like to start?',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: palette.textSecondary)),
                      const SizedBox(height: 32),
                      _card(
                        context,
                        onTap: _askAi,
                        gradient: const [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                        iconBg: const Color(0x33FFFFFF),
                        icon: 'icon_sparkle',
                        iconTint: Colors.white,
                        title: 'Ask AI',
                        titleColor: Colors.white,
                        desc: "Describe your schedule in plain English. We'll build it for you.",
                        descColor: const Color(0xFFE0E7FF),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        context,
                        onTap: _chooseTemplate,
                        surface: palette.surfaceElevated,
                        iconBg: AppColors.iconBgGreen,
                        icon: 'icon_calendar',
                        iconTint: AppColors.successGreen,
                        title: 'Choose a template',
                        titleColor: palette.textPrimary,
                        desc: 'Pick from common patterns: 50/50, every other weekend, and more.',
                        descColor: palette.textSecondary,
                      ),
                      const SizedBox(height: 32),
                      GestureDetector(
                        onTap: _buildFromScratch,
                        child: const Text('Build from scratch (advanced)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required VoidCallback onTap,
    List<Color>? gradient,
    Color? surface,
    required Color iconBg,
    required String icon,
    required Color iconTint,
    required String title,
    required Color titleColor,
    required String desc,
    required Color descColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: surface,
          gradient: gradient != null
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient)
              : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (gradient != null ? const Color(0xFF8B5CF6) : Colors.black)
                  .withValues(alpha: gradient != null ? 0.30 : (context.isDark ? 0.25 : 0.08)),
              offset: Offset(0, gradient != null ? 6 : 4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16)),
              child: Center(child: AppIcon(icon, size: 32, color: iconTint)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: titleColor)),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontSize: 14, color: descColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
