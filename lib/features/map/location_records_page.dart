import 'package:flutter/material.dart';
import '../../models/location_models.dart';
import '../../services/external_launcher.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Location history — faithful port of `Views/Map/LocationRecordsPage.xaml(.cs)`.
///
/// Loads paginated records from [LocationService] with a summary header
/// (total / transfers / this month), infinite-scroll load-more, a type filter
/// (all / custody / general), and per-record details with delete.
///
/// NOTE: "View on Map" and external "Navigate" are native map features → phase 3;
/// the details sheet offers Delete (wired) and notes those as coming later.
class LocationRecordsPage extends StatefulWidget {
  const LocationRecordsPage({super.key, this.latitude, this.longitude, this.locationName});

  /// When set, the page shows only records near this location (mirrors MAUI's
  /// `LocationRecordsPage(latitude, longitude, locationName)` overload).
  final double? latitude;
  final double? longitude;
  final String? locationName;

  bool get _forLocation => latitude != null && longitude != null;

  @override
  State<LocationRecordsPage> createState() => _LocationRecordsPageState();
}

class _LocationRecordsPageState extends State<LocationRecordsPage> {
  final _scroll = ScrollController();
  final List<LocationRecord> _records = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const _pageSize = 20;

  // Summary counts (from a wide fetch, mirroring MAUI's page-1/1000 query).
  int _total = 0;
  int _transfers = 0;
  int _thisMonth = 0;

  bool? _filterCustodyTransfer; // null = all, true = custody, false = general
  DateTime? _filterFrom; // inclusive lower bound (null = unbounded)
  DateTime? _filterTo; // inclusive upper bound (null = unbounded)

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _records.clear();
      _page = 1;
      _hasMore = true;
    });
    try {
      await _loadPage();
      await _updateSummary();
    } catch (_) {
      if (mounted) await _alert('Error', 'Failed to load location records. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPage() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final (records, pagination) = widget._forLocation
          ? await ServiceLocator.location.getLocationRecordsForLocation(
              widget.latitude!,
              widget.longitude!,
              page: _page,
              pageSize: _pageSize,
              isCustodyTransfer: _filterCustodyTransfer,
              startDate: _filterFrom,
              endDate: _filterTo,
            )
          : await ServiceLocator.location.getLocationRecords(
              page: _page,
              pageSize: _pageSize,
              isCustodyTransfer: _filterCustodyTransfer,
              startDate: _filterFrom,
              endDate: _filterTo,
            );
      if (!mounted) return;
      setState(() {
        _records.addAll(records);
        if (records.isNotEmpty) {
          _page++;
          _hasMore = pagination.hasNextPage;
        } else {
          _hasMore = false;
        }
      });
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() {}); // reflect footer spinner
    await _loadPage();
    if (mounted) setState(() {});
  }

  Future<void> _updateSummary() async {
    try {
      final (all, _) = widget._forLocation
          ? await ServiceLocator.location.getLocationRecordsForLocation(
              widget.latitude!,
              widget.longitude!,
              page: 1,
              pageSize: 1000,
              isCustodyTransfer: _filterCustodyTransfer,
              startDate: _filterFrom,
              endDate: _filterTo,
            )
          : await ServiceLocator.location.getLocationRecords(
              page: 1,
              pageSize: 1000,
              isCustodyTransfer: _filterCustodyTransfer,
              startDate: _filterFrom,
              endDate: _filterTo,
            );
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _total = all.length;
        _transfers = all.where((r) => r.isCustodyTransfer).length;
        _thisMonth = all.where((r) => r.timestamp.year == now.year && r.timestamp.month == now.month).length;
      });
    } catch (_) {/* non-critical */}
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
                : _records.isEmpty
                    ? _empty(context)
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          _summary(context, _total, _transfers, _thisMonth),
                          const SizedBox(height: 16),
                          for (final r in _records) ...[
                            _recordCard(context, r),
                            const SizedBox(height: 12),
                          ],
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 16, 20, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.1),
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
                color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: AppIcon('icon_chevron_left', size: 22, color: palette.textSecondary)),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.iconBgGreen, borderRadius: BorderRadius.circular(14)),
            child: const Center(child: AppIcon('icon_folder', size: 22, color: AppColors.successGreen)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location Records',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Your location history', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showFilter(context),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: AppIcon('icon_gear', size: 18, color: palette.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary ─────────────────────────────────────────────────────────────────
  Widget _summary(BuildContext context, int total, int transfers, int thisMonth) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Text('Summary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _stat(context, '$total', 'Total', AppColors.primaryBlue)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, '$transfers', 'Transfers', AppColors.successGreen)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, '$thisMonth', 'This Month', AppColors.warningAmber)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label, Color color) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
        ],
      ),
    );
  }

  // ── Record card ───────────────────────────────────────────────────────────────
  static const _shortMonths = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _fmtTimestamp(DateTime t) =>
      '${_shortMonths[t.month]} ${t.day.toString().padLeft(2, '0')}, ${t.year} • '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _recordCard(BuildContext context, LocationRecord r) {
    final palette = context.palette;
    final iconBg = r.isCustodyTransfer ? AppColors.iconBgGreen : AppColors.iconBgYellow;
    final iconTint = r.isCustodyTransfer ? AppColors.successGreen : AppColors.warningAmber;
    return GestureDetector(
      onTap: () => _showRecordDetails(r),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
              child: Center(child: AppIcon(r.isCustodyTransfer ? 'icon_users' : 'icon_location', size: 22, color: iconTint)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.locationName?.isNotEmpty == true ? r.locationName! : 'Unknown',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  const SizedBox(height: 4),
                  Text(_fmtTimestamp(r.timestamp), style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                  const SizedBox(height: 2),
                  Text('${r.latitude.toStringAsFixed(6)}, ${r.longitude.toStringAsFixed(6)}',
                      style: TextStyle(fontSize: 11, color: palette.textMuted)),
                ],
              ),
            ),
            Text('›', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.border)),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: 0.5, child: AppIcon('icon_map', size: 60, color: palette.textSecondary)),
            const SizedBox(height: 16),
            Text('No Location Records',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 4),
            Text('Create records from the map view',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ── Record details ──────────────────────────────────────────────────────────
  void _showRecordDetails(LocationRecord r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        final palette = sheetCtx.palette;
        Widget detail(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 110,
                      child: Text(label,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textSecondary))),
                  Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: palette.textPrimary))),
                ],
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 48,
                    height: 6,
                    decoration: BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(3))),
              ),
              const SizedBox(height: 16),
              detail('Location', r.locationName?.isNotEmpty == true ? r.locationName! : 'Unknown'),
              detail('Recorded', _fmtTimestamp(r.timestamp)),
              detail('Type', r.isCustodyTransfer ? 'Custody Transfer' : 'General Location'),
              detail('Coordinates', '${r.latitude.toStringAsFixed(6)}, ${r.longitude.toStringAsFixed(6)}'),
              if (r.notes?.isNotEmpty == true) detail('Notes', r.notes!),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => ExternalLauncher.openMaps(r.latitude, r.longitude, label: r.locationName),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surfaceInput,
                    border: Border.all(color: AppColors.primaryBlue),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon('icon_map', size: 18, color: AppColors.primaryBlue),
                      SizedBox(width: 8),
                      Text('Navigate',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _deleteRecord(r);
                },
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.dangerRed, borderRadius: BorderRadius.circular(24)),
                  child: const Text('Delete Record',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteRecord(LocationRecord r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text(
            'Are you sure you want to delete this location record?\n\n${r.locationName?.isNotEmpty == true ? r.locationName! : "Unknown Location"}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final ok = await ServiceLocator.location.deleteLocationRecord(r.locationRecordId);
      if (!mounted) return;
      if (ok) {
        setState(() => _records.remove(r));
        await _updateSummary();
        await _alert('Success', 'Location record deleted successfully.');
      } else {
        await _alert('Error', 'Failed to delete location record. Please try again.');
      }
    } catch (_) {
      if (mounted) await _alert('Error', 'Failed to delete location record. Please try again.');
    }
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  // ── Filter bottom sheet ─────────────────────────────────────────────────────
  Future<void> _showFilter(BuildContext context) async {
    final result = await showModalBottomSheet<({String type, DateTime? from, DateTime? to})>(
      context: context,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _RecordsFilterSheet(
        initial: _filterCustodyTransfer == null ? 'all' : (_filterCustodyTransfer! ? 'custody' : 'general'),
        initialFrom: _filterFrom,
        initialTo: _filterTo,
      ),
    );
    if (result == null) return;
    setState(() {
      _filterCustodyTransfer = switch (result.type) {
        'custody' => true,
        'general' => false,
        _ => null,
      };
      _filterFrom = result.from;
      _filterTo = result.to;
    });
    await _loadInitial();
  }
}

// ── Filter sheet ─────────────────────────────────────────────────────────────────
class _RecordsFilterSheet extends StatefulWidget {
  final String initial;
  final DateTime? initialFrom;
  final DateTime? initialTo;
  const _RecordsFilterSheet({required this.initial, this.initialFrom, this.initialTo});
  @override
  State<_RecordsFilterSheet> createState() => _RecordsFilterSheetState();
}

class _RecordsFilterSheetState extends State<_RecordsFilterSheet> {
  late String _type = widget.initial;
  // Pre-seed the pickers to a last-3-months → today window when no filter is
  // active yet (mirrors MAUI's default filter range). The list itself stays
  // unbounded until the user applies; "Clear" resets these to null.
  late DateTime? _from =
      widget.initialFrom ?? DateTime(DateTime.now().year, DateTime.now().month - 3, DateTime.now().day);
  late DateTime? _to = widget.initialTo ??
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: _to ?? DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: _from ?? DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    // Include the whole selected day by snapping to end-of-day.
    if (picked != null) {
      setState(() => _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
    }
  }

  Widget _dateBox(BuildContext context, String label, DateTime? value, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surfaceInput,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
            const SizedBox(height: 4),
            Text(value == null ? 'Any' : _fmt(value),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget radio(String value, String label, Color color) => GestureDetector(
          onTap: () => setState(() => _type = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(_type == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: color, size: 22),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 15, color: palette.textPrimary)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.iconBgYellow, borderRadius: BorderRadius.circular(14)),
                child: const Center(child: AppIcon('icon_search', size: 24, color: AppColors.warningAmber)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filter Records',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text('Customize your view', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: AppIcon('icon_close', size: 20, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Record Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 8),
          radio('all', 'Show all records', AppColors.primaryBlue),
          radio('custody', 'Custody transfers only', AppColors.successGreen),
          radio('general', 'General locations only', AppColors.warningAmber),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Date Range',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const Spacer(),
              if (_from != null || _to != null)
                GestureDetector(
                  onTap: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  child: const Text('Clear',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _dateBox(context, 'From', _from, _pickFrom)),
              const SizedBox(width: 10),
              Expanded(child: _dateBox(context, 'To', _to, _pickTo)),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.of(context).pop((type: _type, from: _from, to: _to)),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primaryBlue, AppColors.primaryBlueLight]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('Apply Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
