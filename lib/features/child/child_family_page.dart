import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Port of `Views/Child/ChildFamilyPage.xaml(.cs)` — the child's family members
/// (parents + siblings), loaded from [AuthService.getFamilyInfo].
class ChildFamilyPage extends StatefulWidget {
  const ChildFamilyPage({super.key});

  @override
  State<ChildFamilyPage> createState() => _ChildFamilyPageState();
}

class _ChildFamilyPageState extends State<ChildFamilyPage> {
  bool _loading = true;
  FamilyInfo? _family;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      _family = await ServiceLocator.auth.getFamilyInfo();
    } catch (_) {
      _family = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _displayName(String? email) {
    if (email == null || email.isEmpty) return 'Unknown';
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    final words = local.replaceAll('.', ' ').replaceAll('_', ' ').replaceAll('-', ' ').split(' ').where((w) => w.isNotEmpty);
    return words.isEmpty ? email : words.map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _family == null
                    ? _emptyState(context)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        children: _content(context),
                      ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final f = _family!;
    final widgets = <Widget>[];
    widgets.add(_sectionHeader(context, 'Parents'));
    widgets.add(const SizedBox(height: 12));
    if (f.parent1Email?.isNotEmpty ?? false) {
      final name = (f.parent1Name?.isNotEmpty ?? false) ? f.parent1Name! : _displayName(f.parent1Email);
      // Neutral colour for both parents — we don't know gender, so no blue/pink coding.
      widgets.add(_memberCard(context, name, f.parent1Email!, 'Parent', AppColors.accentTeal));
      widgets.add(const SizedBox(height: 12));
    }
    if (f.parent2Email?.isNotEmpty ?? false) {
      final name = (f.parent2Name?.isNotEmpty ?? false) ? f.parent2Name! : _displayName(f.parent2Email);
      widgets.add(_memberCard(context, name, f.parent2Email!, 'Parent', AppColors.accentTeal));
      widgets.add(const SizedBox(height: 12));
    }
    if (f.siblings.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(_sectionHeader(context, 'Siblings'));
      widgets.add(const SizedBox(height: 12));
      for (final s in f.siblings) {
        var name = '${s.firstName ?? ''} ${s.lastName ?? ''}'.trim();
        if (name.isEmpty) name = _displayName(s.email);
        widgets.add(_memberCard(context, name, s.email ?? '', 'Sibling', AppColors.accentPurple));
        widgets.add(const SizedBox(height: 12));
      }
    }
    return widgets;
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      // Top inset accounts for the status bar / Dynamic Island.
      padding: EdgeInsets.fromLTRB(16, MediaQuery.viewPaddingOf(context).top + 12, 16, 16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 4),
              blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: AppIcon('icon_chevron_left', size: 24, color: palette.textSecondary)),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('My Family',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Your family members', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Text(title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary));

  Widget _memberCard(BuildContext context, String name, String email, String role, Color color) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
            child: Center(
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                ],
                const SizedBox(height: 2),
                Text(role, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load family information',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text('Please try again later.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}
