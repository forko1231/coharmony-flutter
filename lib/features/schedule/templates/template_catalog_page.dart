import 'package:flutter/material.dart';
import '../../../services/custody_templates/custody_template.dart';
import '../../../services/custody_templates/template_registry.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../widgets/app_header.dart';
import 'template_config_page.dart';

/// Template catalog — port of `TemplateCatalogPage.xaml(.cs)`. Cards are grouped by
/// category from [TemplateRegistry.groupedByCategory]; tapping one opens
/// [TemplateConfigPage] for that template.
class TemplateCatalogPage extends StatelessWidget {
  const TemplateCatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final groups = TemplateRegistry.groupedByCategory();
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          AppHeader(
            title: 'Choose a Template',
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Pick the closest match — you can fine-tune any day after.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                      const SizedBox(height: 16),
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
                          child: Text(group.category.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: palette.textSecondary)),
                        ),
                        for (final t in group.templates) ...[
                          _TemplateCard(template: t),
                          const SizedBox(height: 12),
                        ],
                      ],
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
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template});
  final CustodyTemplate template;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TemplateConfigPage(template: template)),
        );
      },
      child: Container(
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  const SizedBox(height: 4),
                  Text(template.shortDescription, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(8)),
                    child: Text('${template.patternLengthWeeks}-week pattern',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('›', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}
