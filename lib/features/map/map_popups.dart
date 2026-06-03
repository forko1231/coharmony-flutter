import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Map-related dialogs — ports of `AddPoiPopupView`, `AddRecordPopupView`,
/// `FilterPopupView`, and `PinDetailsPopupView`. Grouped in one file since they
/// share the same dialog chrome (icon header + close + form + actions).

// ── Shared dialog chrome ─────────────────────────────────────────────────────────
class _DialogShell extends StatelessWidget {
  final String icon;
  final Color iconBg;
  final Color iconTint;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final double maxWidth;
  const _DialogShell({
    required this.icon,
    required this.iconBg,
    required this.iconTint,
    required this.title,
    required this.subtitle,
    required this.children,
    this.maxWidth = 380,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: AppIcon(icon, size: 24, color: iconTint)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: AppIcon('icon_close', size: 18, color: palette.textSecondary)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _fieldLabel(BuildContext context, String text, {bool muted = false}) => Text(text,
    style: TextStyle(
        fontSize: 13,
        fontWeight: muted ? FontWeight.normal : FontWeight.bold,
        color: muted ? context.palette.textSecondary : context.palette.textPrimary));

Widget _entryBox(BuildContext context, String hint,
    {int maxLines = 1, TextEditingController? controller}) {
  final palette = context.palette;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: palette.surfaceElevated,
      border: Border.all(color: palette.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(fontSize: 15, color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.textPlaceholder),
        border: InputBorder.none,
        isDense: true,
      ),
    ),
  );
}

Widget _checkRow(BuildContext context, bool value, String label, Color color, ValueChanged<bool> onChanged) {
  final palette = context.palette;
  return Row(
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
            value: value, activeColor: color, onChanged: (v) => onChanged(v ?? false)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: palette.textPrimary))),
    ],
  );
}

Widget _formCard(BuildContext context, List<Widget> children) {
  final palette = context.palette;
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: palette.surfaceInput,
      border: Border.all(color: palette.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

Widget _actions(BuildContext context, {required String saveLabel, required Color saveColor, required VoidCallback onSave}) {
  final palette = context.palette;
  return Row(
    children: [
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.textSecondary,
            side: BorderSide(color: palette.border, width: 2),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: saveColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onSave,
          child: Text(saveLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ],
  );
}

// ── Add POI ──────────────────────────────────────────────────────────────────────
/// Result of the Add-POI form (the page owns the lat/lng + the create call).
class AddPoiResult {
  AddPoiResult({required this.name, this.description, required this.category, required this.share});
  final String name;
  final String? description;
  final String category;
  final bool share;
}

class AddPoiPopup extends StatefulWidget {
  const AddPoiPopup({super.key, this.locationLabel});

  /// Shown in place of "Tap on map to set location" once a point is chosen.
  final String? locationLabel;

  static Future<AddPoiResult?> show(BuildContext context, {String? locationLabel}) =>
      showDialog<AddPoiResult>(
          context: context, builder: (_) => AddPoiPopup(locationLabel: locationLabel));
  @override
  State<AddPoiPopup> createState() => _AddPoiPopupState();
}

class _AddPoiPopupState extends State<AddPoiPopup> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'School';
  bool _share = true;
  static const _categories = ['School', 'Daycare', 'Park', 'Restaurant', 'Medical', 'Other'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a name for the POI.'), duration: Duration(seconds: 2)));
      return;
    }
    final desc = _descCtrl.text.trim();
    Navigator.of(context).pop(AddPoiResult(
      name: _nameCtrl.text.trim(),
      description: desc.isEmpty ? null : desc,
      category: _category,
      share: _share,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _DialogShell(
      icon: 'icon_location',
      iconBg: AppColors.iconBgGreen,
      iconTint: AppColors.successGreen,
      title: 'Add POI',
      subtitle: 'Create a new location',
      children: [
        _formCard(context, [
          _fieldLabel(context, 'Name *'),
          const SizedBox(height: 8),
          _entryBox(context, 'e.g., School, Park', controller: _nameCtrl),
          const SizedBox(height: 16),
          _fieldLabel(context, 'Category'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                dropdownColor: palette.surfaceElevated,
                style: TextStyle(fontSize: 15, color: palette.textPrimary),
                items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _category = v ?? 'School'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel(context, 'Description', muted: true),
          const SizedBox(height: 8),
          _entryBox(context, 'Optional notes...', maxLines: 3, controller: _descCtrl),
          const SizedBox(height: 16),
          Text(widget.locationLabel ?? 'Tap on map to set location',
              style: TextStyle(fontSize: 13, color: palette.textSecondary)),
          const SizedBox(height: 8),
          _checkRow(context, _share, 'Share with partner', AppColors.primaryBlue, (v) => setState(() => _share = v)),
        ]),
        const SizedBox(height: 20),
        _actions(context, saveLabel: 'Save POI', saveColor: AppColors.successGreen, onSave: _save),
      ],
    );
  }
}

// ── Add Record ───────────────────────────────────────────────────────────────────
class AddRecordResult {
  AddRecordResult({this.notes, required this.isTransfer});
  final String? notes;
  final bool isTransfer;
}

class AddRecordPopup extends StatefulWidget {
  const AddRecordPopup({super.key, this.locationLabel, this.isTransfer = false});

  final String? locationLabel;
  final bool isTransfer;

  static Future<AddRecordResult?> show(BuildContext context,
          {String? locationLabel, bool isTransfer = false}) =>
      showDialog<AddRecordResult>(
          context: context,
          builder: (_) => AddRecordPopup(locationLabel: locationLabel, isTransfer: isTransfer));
  @override
  State<AddRecordPopup> createState() => _AddRecordPopupState();
}

class _AddRecordPopupState extends State<AddRecordPopup> {
  final _notesCtrl = TextEditingController();
  late bool _isTransfer = widget.isTransfer;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final notes = _notesCtrl.text.trim();
    Navigator.of(context).pop(AddRecordResult(
      notes: notes.isEmpty ? null : notes,
      isTransfer: _isTransfer,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _DialogShell(
      icon: 'icon_edit',
      iconBg: AppColors.iconBgYellow,
      iconTint: AppColors.warningAmber,
      title: 'Add Record',
      subtitle: 'Document your visit',
      children: [
        _formCard(context, [
          _fieldLabel(context, 'Notes', muted: true),
          const SizedBox(height: 8),
          _entryBox(context, 'What happened here...', maxLines: 3, controller: _notesCtrl),
          const SizedBox(height: 16),
          _checkRow(context, _isTransfer, 'This is a custody transfer', AppColors.successGreen,
              (v) => setState(() => _isTransfer = v)),
          const SizedBox(height: 8),
          Text(widget.locationLabel ?? 'No location selected',
              style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        ]),
        const SizedBox(height: 20),
        _actions(context, saveLabel: 'Save Record', saveColor: AppColors.successGreen, onSave: _save),
      ],
    );
  }
}

// ── Map filter ─────────────────────────────────────────────────────────────────
class MapFilterResult {
  MapFilterResult({required this.showPois, required this.showTransfers});
  final bool showPois;
  final bool showTransfers;
}

class MapFilterPopup extends StatefulWidget {
  const MapFilterPopup({super.key, this.showPois = true, this.showTransfers = true});

  final bool showPois;
  final bool showTransfers;

  static Future<MapFilterResult?> show(BuildContext context,
          {required bool showPois, required bool showTransfers}) =>
      showDialog<MapFilterResult>(
          context: context,
          builder: (_) => MapFilterPopup(showPois: showPois, showTransfers: showTransfers));
  @override
  State<MapFilterPopup> createState() => _MapFilterPopupState();
}

class _MapFilterPopupState extends State<MapFilterPopup> {
  late bool _pois = widget.showPois;
  late bool _transfers = widget.showTransfers;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: 'icon_gear',
      iconBg: AppColors.iconBgYellow,
      iconTint: AppColors.warningAmber,
      title: 'Map Filters',
      subtitle: 'Choose what to display',
      maxWidth: 340,
      children: [
        _checkRow(context, _pois, 'Show Points of Interest', AppColors.primaryBlue, (v) => setState(() => _pois = v)),
        const SizedBox(height: 14),
        _checkRow(context, _transfers, 'Show custody transfers', AppColors.successGreen,
            (v) => setState(() => _transfers = v)),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => Navigator.of(context)
              .pop(MapFilterResult(showPois: _pois, showTransfers: _transfers)),
          child: const Text('Apply Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ── Pin details ──────────────────────────────────────────────────────────────────
class PinDetailsPopup extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onCreateRecord;
  final VoidCallback? onViewRecords;
  final VoidCallback? onNavigate;
  const PinDetailsPopup(
      {super.key,
      required this.title,
      this.subtitle = 'Point of Interest',
      this.onCreateRecord,
      this.onViewRecords,
      this.onNavigate});

  static Future<void> show(BuildContext context,
          {required String title,
          String subtitle = 'Point of Interest',
          VoidCallback? onCreateRecord,
          VoidCallback? onViewRecords,
          VoidCallback? onNavigate}) =>
      showDialog(
          context: context,
          builder: (_) => PinDetailsPopup(
              title: title,
              subtitle: subtitle,
              onCreateRecord: onCreateRecord,
              onViewRecords: onViewRecords,
              onNavigate: onNavigate));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _DialogShell(
      icon: 'icon_location',
      iconBg: AppColors.iconBgBlue,
      iconTint: AppColors.primaryBlue,
      title: title,
      subtitle: subtitle,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              AppIcon('icon_location', size: 18, color: palette.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Tap a button below to record a visit, view its history, or navigate here.',
                    style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _pinBtn(context, 'Record', AppColors.primaryBlue, Colors.white, () {
                Navigator.of(context).pop();
                onCreateRecord?.call();
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pinBtn(context, 'Records', AppColors.successGreen, Colors.white, () {
                Navigator.of(context).pop();
                onViewRecords?.call();
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pinBtn(
                  context,
                  'Navigate',
                  context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                  palette.textSecondary, () {
                Navigator.of(context).pop();
                onNavigate?.call();
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pinBtn(BuildContext context, String label, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg)),
      ),
    );
  }
}
