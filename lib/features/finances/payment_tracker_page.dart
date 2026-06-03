import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/financial_models.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/skeleton.dart';

/// Payments — faithful port of `Views/Finances/PaymentTracker.xaml(.cs)`.
///
/// Loads the month's charges + the charges awaiting the user's verification from
/// [FinancialService]. Outgoing/Incoming split is by whether the charge's email
/// matches the signed-in user; split charges show the user's share. Month nav,
/// the monthly summary, add-payment (`makeCharge`), and the per-charge
/// mark-paid / verify / dispute lifecycle are all wired.
///
/// Marking a charge paid prompts to attach a **receipt photo** (camera or
/// gallery) — base64-uploaded via `uploadReceipt` — or "Skip - No Receipt",
/// mirroring MAUI's `MarkChargeAsPaidAsync`. Receipt images are displayed
/// (`getReceipt`) on the charge details sheet when present.
class PaymentTrackerPage extends StatefulWidget {
  const PaymentTrackerPage({super.key});

  @override
  State<PaymentTrackerPage> createState() => _PaymentTrackerPageState();
}

class _PaymentTrackerPageState extends State<PaymentTrackerPage> {
  late int _year;
  late int _month;
  bool _outgoing = true;
  bool _loading = true;
  bool _busy = false;

  String _email = '';
  List<FCharge> _charges = const [];
  List<FCharge> _awaiting = const [];

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _email = Preferences.getString('email');
    _load();
  }

  DateTime get _monthStart => DateTime(_year, _month, 1);

  bool _isMine(FCharge c) => (c.email ?? '').toLowerCase() == _email.toLowerCase();

  double _userShare(FCharge c) {
    if (c.isSplitPayment && c.splitPercentage != null) {
      return c.amount * (c.splitPercentage! / 100);
    }
    return c.amount;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final charges = await ServiceLocator.financial.getCharges(date: _monthStart);
      final awaiting = (await ServiceLocator.financial.getChargesAwaitingVerification())
          .where((c) => !_isMine(c))
          .toList();
      if (!mounted) return;
      setState(() {
        _charges = charges;
        _awaiting = awaiting;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _alert('Error', 'Failed to load payments: $e');
    }
  }

  Future<void> _shiftMonth(int delta) async {
    var m = _month + delta, y = _year;
    while (m < 1) {
      m += 12;
      y--;
    }
    while (m > 12) {
      m -= 12;
      y++;
    }
    setState(() {
      _month = m;
      _year = y;
    });
    await _load();
  }

  List<FCharge> get _monthCharges => _charges
      .where((c) => c.date != null && c.date!.month == _month && c.date!.year == _year)
      .toList();

  List<FCharge> get _visible {
    final list = _monthCharges.where((c) => _isMine(c) == _outgoing).toList()
      ..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
    return list;
  }

  double get _monthTotal => _visible.fold(0, (s, c) => s + _userShare(c));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              _header(context),
              _tabSelector(context),
              Expanded(
                child: LoadingSwitcher(
                  loading: _loading,
                  skeleton: const SkeletonCardList(),
                  child: _visible.isEmpty
                      ? Center(
                          child: Text(_outgoing ? 'No outgoing payments' : 'No incoming payments',
                              style: TextStyle(color: palette.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _visible.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _paymentCard(context, _visible[i]),
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final palette = context.palette;
    final direction = _outgoing ? 'Owed' : 'Expected';
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 12, 20, 16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 4),
              blurRadius: 16),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _navButton(context, 'icon_chevron_left', () => _shiftMonth(-1)),
              Expanded(
                child: Column(
                  children: [
                    Text('${_monthNames[_month - 1]} $_year',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text('$direction: \$${_monthTotal.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
              _navButton(context, 'icon_chevron_right', () => _shiftMonth(1)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _solidBtn(context, '+ Add', AppColors.successGreen, () => _showAddPayment(context)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _outlineBtn(context, 'Summary', AppColors.primaryBlue, () => _showSummary(context)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: _outlineBtn(
                    context,
                    _awaiting.isEmpty ? 'Verify' : 'Verify (${_awaiting.length})',
                    AppColors.accentPurple,
                    () => _showVerification(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, String icon, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(child: AppIcon(icon, size: 24, color: palette.textSecondary)),
      ),
    );
  }

  Widget _solidBtn(BuildContext context, String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      );

  Widget _outlineBtn(BuildContext context, String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(20)),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ),
      );

  // ── Tab selector ────────────────────────────────────────────────────────────
  Widget _tabSelector(BuildContext context) {
    final palette = context.palette;
    final outCount = _monthCharges.where(_isMine).length;
    final inCount = _monthCharges.where((c) => !_isMine(c)).length;
    Widget tab(String icon, String label, int count, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                  color: selected ? AppColors.primaryBlue : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(icon, size: 16, color: selected ? Colors.white : palette.textSecondary),
                  const SizedBox(width: 6),
                  Text(count > 0 ? '$label ($count)' : label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : palette.textSecondary)),
                ],
              ),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          tab('icon_arrow_up', 'Outgoing', outCount, _outgoing, () => setState(() => _outgoing = true)),
          const SizedBox(width: 4),
          tab('icon_arrow_down', 'Incoming', inCount, !_outgoing, () => setState(() => _outgoing = false)),
        ],
      ),
    );
  }

  // ── Payment card ───────────────────────────────────────────────────────────────
  ({String icon, Color bg, Color tint, String label}) _statusStyle(FCharge c) {
    final overdue = c.paymentStatus == 'unpaid' &&
        c.date != null &&
        c.date!.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
    final isMine = _isMine(c);
    switch (c.paymentStatus) {
      case 'verified':
        return (icon: 'icon_checkmark', bg: AppColors.iconBgGreen, tint: AppColors.successGreen, label: 'Verified');
      case 'pending_verification':
        return (
          icon: isMine ? 'icon_clock' : 'icon_alert',
          bg: AppColors.iconBgPurple,
          tint: AppColors.accentPurple,
          label: isMine ? 'Awaiting Confirmation' : 'Verify Payment'
        );
      case 'disputed':
        return (icon: 'icon_close', bg: AppColors.iconBgRed, tint: AppColors.dangerRed, label: 'Disputed');
      default:
        return overdue
            ? (icon: 'icon_alert', bg: AppColors.iconBgRed, tint: AppColors.dangerRed, label: 'Overdue')
            : (icon: 'icon_clock', bg: AppColors.iconBgYellow, tint: AppColors.warningAmber, label: 'Unpaid');
    }
  }

  String _typeDisplay(FCharge c) {
    switch ((c.type ?? '').toLowerCase()) {
      case 'court':
      case 'child support':
        return 'Child Support';
      case 'alimony':
        return 'Alimony';
      default:
        return 'Split';
    }
  }

  Widget _paymentCard(BuildContext context, FCharge c) {
    final palette = context.palette;
    final s = _statusStyle(c);
    final due = c.date != null ? 'Due ${_fmtDate(c.date!)}' : '';
    final isSplit = (c.type ?? '').toLowerCase() == 'split';
    final payer = _isMine(c);
    final pct = c.isSplitPayment && c.splitPercentage != null ? ' (${c.splitPercentage!.toStringAsFixed(0)}%)' : '';
    final roleText = isSplit ? (payer ? 'You pay$pct' : 'You receive$pct') : '';
    final hasDispute = c.paymentStatus == 'disputed' && (c.disputeReason?.isNotEmpty ?? false);
    final hasReceipt = c.receiptUrl?.isNotEmpty ?? false;
    final roleColor = context.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    return GestureDetector(
      onTap: () => _showDetails(c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: AppIcon(s.icon, size: 22, color: s.tint)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.category?.isNotEmpty == true ? c.category! : _typeDisplay(c),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 2),
                      Text('${_typeDisplay(c)} • $due', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('\$${_userShare(c).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(s.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: s.tint)),
                  ],
                ),
              ],
            ),
            // Role row (split only) + receipt chip, aligned right under the amount.
            if (roleText.isNotEmpty || hasReceipt) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (roleText.isNotEmpty) ...[
                    AppIcon(payer ? 'icon_arrow_up' : 'icon_arrow_down', size: 13, color: roleColor),
                    const SizedBox(width: 4),
                    Text(roleText, style: TextStyle(fontSize: 12, color: roleColor)),
                  ],
                  const Spacer(),
                  if (hasReceipt)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          AppIcon('icon_image', size: 12, color: Color(0xFF1E40AF)),
                          SizedBox(width: 4),
                          Text('Receipt',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            // Dispute reason (full width, red).
            if (hasDispute) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: AppIcon('icon_info', size: 12, color: Color(0xFFB91C1C)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Reason: ${c.disputeReason!}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Details (tap a card) ─────────────────────────────────────────────────────
  void _showDetails(FCharge c) {
    final isMine = _isMine(c);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        final palette = sheetCtx.palette;
        Widget detail(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                      width: 120,
                      child: Text(label,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textSecondary))),
                  Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: palette.textPrimary))),
                ],
              ),
            );
        final actions = <Widget>[];
        if (isMine && (c.paymentStatus == 'unpaid' || c.paymentStatus == 'disputed')) {
          actions.add(_sheetAction('Mark as Paid', AppColors.successGreen, () {
            Navigator.of(sheetCtx).pop();
            _markPaid(c);
          }));
        } else if (!isMine && c.paymentStatus == 'pending_verification') {
          actions.add(Row(children: [
            Expanded(
                child: _sheetAction('Verify', AppColors.successGreen, () {
              Navigator.of(sheetCtx).pop();
              _verify(c);
            })),
            const SizedBox(width: 12),
            Expanded(
                child: _sheetAction('Dispute', AppColors.dangerRed, () {
              Navigator.of(sheetCtx).pop();
              _dispute(c);
            })),
          ]));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
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
              Center(
                child: Text(c.category?.isNotEmpty == true ? c.category! : _typeDisplay(c),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('\$${_userShare(c).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
              ),
              const SizedBox(height: 16),
              if (c.isSplitPayment && c.splitPercentage != null)
                detail('Split', isMine
                    ? 'You pay ${c.splitPercentage!.toStringAsFixed(0)}%'
                    : 'You receive ${c.splitPercentage!.toStringAsFixed(0)}%'),
              detail('Type', _typeDisplay(c)),
              if (c.date != null) detail('Due Date', _fmtDate(c.date!)),
              detail('Status', _formatStatus(c.paymentStatus)),
              if (c.paidDate != null) detail('Paid Date', _fmtDate(c.paidDate!)),
              if (c.paymentStatus == 'disputed' && (c.disputeReason?.isNotEmpty ?? false))
                detail('Dispute Reason', c.disputeReason!),
              if ((c.repeatPattern?.isNotEmpty ?? false) && c.repeatPattern!.toLowerCase() != 'once')
                detail('Repeats', c.repeatPattern!),
              if ((c.receiptUrl?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 12),
                _ReceiptImage(chargeId: c.chargeId),
              ],
              const SizedBox(height: 20),
              ...actions,
            ],
          ),
        );
      },
    );
  }

  Widget _sheetAction(String label, Color color, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
            child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      );

  // ── Actions ─────────────────────────────────────────────────────────────────
  Future<void> _markPaid(FCharge c) async {
    // MAUI's single action sheet: Take Photo / Choose from Gallery /
    // Skip - No Receipt / Cancel.
    final choice = await _receiptChoice();
    if (choice == null || choice == 'cancel' || !mounted) return;

    ({String base64, String fileName})? receipt;
    if (choice == 'camera' || choice == 'gallery') {
      receipt = await _captureReceipt(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
      if (receipt == null) return; // user cancelled or error capturing
    }

    await _run(() async {
      if (receipt != null) {
        await ServiceLocator.financial.uploadReceipt(c.chargeId, receipt.base64, receipt.fileName);
      }
      final result = await ServiceLocator.financial
          .updateChargePaymentStatus(c.chargeId, 'pending_verification', category: c.category);
      if (result.contains('success')) {
        await _load();
        await _alert('Marked as Paid', 'Your payment has been marked as paid. The receiver will be notified to verify receipt.');
      } else {
        await _alert('Error', result);
      }
    });
  }

  /// MAUI's "Add Receipt?" action sheet — returns 'camera' | 'gallery' | 'skip' | 'cancel'.
  Future<String?> _receiptChoice() => showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.palette.surfaceElevated,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Add Receipt?',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: ctx.palette.textSecondary)),
              ),
              ListTile(
                leading: const AppIcon('icon_camera', size: 22, color: AppColors.primaryBlue),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
              ListTile(
                leading: const AppIcon('icon_image', size: 22, color: AppColors.primaryBlue),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.of(ctx).pop('gallery'),
              ),
              ListTile(
                leading: const AppIcon('icon_checkmark', size: 22, color: AppColors.successGreen),
                title: const Text('Skip - No Receipt'),
                onTap: () => Navigator.of(ctx).pop('skip'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

  /// Capture a receipt photo from [source] and return it base64-encoded.
  Future<({String base64, String fileName})?> _captureReceipt(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return (base64: base64Encode(bytes), fileName: file.name);
    } catch (_) {
      if (mounted) await _alert('Error', 'Could not access the photo. Please check app permissions.');
      return null;
    }
  }

  Future<void> _verify(FCharge c) async {
    if (await _confirm('Verify Payment', 'Confirm that you received \$${c.amount.toStringAsFixed(2)} from your co-parent?',
            'Yes, Received') !=
        true) {
      return;
    }
    await _run(() async {
      final result = await ServiceLocator.financial.verifyOrDisputePayment(c.chargeId, true);
      if (result.contains('success')) {
        await _load();
        await _alert('Payment Verified', 'Thank you! The payment has been verified.');
      } else {
        await _alert('Error', result);
      }
    });
  }

  Future<void> _dispute(FCharge c) async {
    final reason = await _prompt('Dispute Payment', 'Please provide a reason for disputing this payment:',
        'e.g., Payment not received, incorrect amount, etc.');
    if (reason == null || reason.trim().isEmpty) return;
    await _run(() async {
      final result = await ServiceLocator.financial.verifyOrDisputePayment(c.chargeId, false, disputeReason: reason);
      if (result.contains('success')) {
        await _load();
        await _alert('Payment Disputed', 'The payment has been marked as disputed. Your partner has been notified.');
      } else {
        await _alert('Error', result);
      }
    });
  }

  // ── Sheets ─────────────────────────────────────────────────────────────────────
  void _showAddPayment(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddPaymentSheet(onSave: _saveCharge),
    );
  }

  Future<void> _saveCharge(
      {required double amount,
      required String type,
      required bool paying,
      required double split,
      required String repeat,
      required DateTime due}) async {
    // Map UI labels to the API's vocabulary (matches MAUI).
    final apiType = switch (type) {
      'Child Support' => 'child support',
      'Alimony' => 'alimony',
      _ => 'split',
    };
    final repeatPattern = repeat.toLowerCase();
    // Split → chosen %, else direction maps to 100 (paying) / 0 (requesting).
    final splitPercentage = apiType == 'split' ? split : (paying ? 100.0 : 0.0);

    await _run(() async {
      final result = await ServiceLocator.financial
          .makeCharge(due, repeatPattern, amount, apiType, splitPercentage: splitPercentage);
      if (result.contains('success')) {
        await _load();
        await _alert('Success', 'Payment added successfully');
      } else {
        await _alert('Error', result);
      }
    });
  }

  void _showSummary(BuildContext context) {
    // Summary is the user's own (outgoing) charges for the month (matches MAUI).
    final mine = _monthCharges.where(_isMine).toList();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final verified = mine.where((c) => c.paymentStatus == 'verified');
    final pending = mine.where((c) =>
        c.paymentStatus == 'pending_verification' ||
        (c.paymentStatus == 'unpaid' && !c.date!.isBefore(today)));
    final overdue = mine.where((c) => c.paymentStatus == 'unpaid' && c.date != null && c.date!.isBefore(today));
    double sum(Iterable<FCharge> cs) => cs.fold(0, (s, c) => s + _userShare(c));

    // Breakdown by type (user's charges), highest total first — matches MAUI.
    final byType = <String, ({double total, int count})>{};
    for (final c in mine) {
      final key = _typeDisplay(c);
      final prev = byType[key];
      byType[key] = (total: (prev?.total ?? 0) + _userShare(c), count: (prev?.count ?? 0) + 1);
    }
    final breakdown = [
      for (final e in byType.entries) (label: e.key, total: e.value.total, count: e.value.count),
    ]..sort((a, b) => b.total.compareTo(a.total));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SummarySheet(
        verifiedTotal: sum(verified),
        verifiedCount: verified.length,
        pendingTotal: sum(pending),
        pendingCount: pending.length,
        overdueTotal: sum(overdue),
        overdueCount: overdue.length,
        breakdown: breakdown,
      ),
    );
  }

  void _showVerification(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        final palette = sheetCtx.palette;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
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
              const SizedBox(height: 12),
              Center(
                child: Text('Awaiting Your Verification',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ),
              const SizedBox(height: 16),
              if (_awaiting.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: Text('No payments awaiting verification',
                          style: TextStyle(fontSize: 14, color: palette.textSecondary))),
                )
              else
                for (final c in _awaiting) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surfaceInput,
                      border: Border.all(color: AppColors.accentPurple, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.category?.isNotEmpty == true ? c.category! : _typeDisplay(c),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Amount: \$${c.amount.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                        if (c.verificationRequestDate != null)
                          Text('Marked paid: ${_fmtDate(c.verificationRequestDate!)}',
                              style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                        if (c.receiptUrl?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 10),
                          _ReceiptImage(chargeId: c.chargeId, height: 120),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child: _sheetAction('Verify', AppColors.successGreen, () {
                              Navigator.of(sheetCtx).pop();
                              _verify(c);
                            })),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _sheetAction('Dispute', AppColors.dangerRed, () {
                              Navigator.of(sheetCtx).pop();
                              _dispute(c);
                            })),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }

  // ── Dialog helpers ────────────────────────────────────────────────────────────
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) await _alert('Error', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String title, String message, String confirmLabel) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmLabel)),
        ],
      ),
    );
  }

  Future<String?> _prompt(String title, String message, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(hintText: hint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Submit')),
        ],
      ),
    );
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

  static String _formatStatus(String status) => switch (status) {
        'unpaid' => 'Unpaid',
        'pending_verification' => 'Pending Verification',
        'verified' => 'Verified',
        'disputed' => 'Disputed',
        _ => status,
      };

  static const _shortMonths = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _fmtDate(DateTime d) => '${_shortMonths[d.month]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
}

/// Loads + shows a charge's receipt image (base64) from the financial service.
class _ReceiptImage extends StatefulWidget {
  final int chargeId;
  final double height;
  const _ReceiptImage({required this.chargeId, this.height = 200});

  @override
  State<_ReceiptImage> createState() => _ReceiptImageState();
}

class _ReceiptImageState extends State<_ReceiptImage> {
  // Receipts are immutable once uploaded, so cache the fetched result in memory
  // and reuse it when the same charge's details sheet is reopened (no refetch /
  // base64 round-trip). Keyed by chargeId.
  static final Map<int, ReceiptResponse> _cache = {};

  ReceiptResponse? _receipt;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.chargeId];
    if (cached != null) {
      _receipt = cached;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final r = await ServiceLocator.financial.getReceipt(widget.chargeId);
      if (!mounted) return;
      if (r != null) _cache[widget.chargeId] = r;
      setState(() {
        _receipt = r;
        _loading = false;
        _failed = r == null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Receipt',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textSecondary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: widget.height,
            width: double.infinity,
            color: palette.surfaceInput,
            alignment: Alignment.center,
            child: _loading
                ? const CircularProgressIndicator()
                : _failed || _receipt?.base64Data == null
                    ? Text('Receipt not available', style: TextStyle(fontSize: 12, color: palette.textSecondary))
                    : Image.memory(_decode(_receipt!.base64Data!), fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }

  static Uint8List _decode(String b64) {
    try {
      return base64Decode(b64);
    } catch (_) {
      return Uint8List(0);
    }
  }
}

// ── Add payment sheet ─────────────────────────────────────────────────────────────
class _AddPaymentSheet extends StatefulWidget {
  final Future<void> Function({
    required double amount,
    required String type,
    required bool paying,
    required double split,
    required String repeat,
    required DateTime due,
  }) onSave;
  const _AddPaymentSheet({required this.onSave});
  @override
  State<_AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends State<_AddPaymentSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _type = 'Split'; // Child Support | Alimony | Split
  bool _paying = true;
  double _split = 50;
  String _repeat = 'Once';
  DateTime _due = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final desc = _description.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    if (desc.isEmpty) {
      setState(() => _error = 'Please enter a description');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter a valid amount');
      return;
    }
    Navigator.of(context).pop();
    await widget.onSave(
      amount: amount,
      type: _type,
      paying: _paying,
      split: _split,
      repeat: _repeat,
      due: _due,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isSplit = _type == 'Split';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(context),
              const SizedBox(height: 12),
              Center(
                child: Text('Add Payment',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ),
              const SizedBox(height: 20),
              _label(context, 'Payment Type'),
              const SizedBox(height: 8),
              _segmented(context, const ['Child Support', 'Alimony', 'Split'], _type, (v) => setState(() => _type = v)),
              if (!isSplit) ...[
                const SizedBox(height: 16),
                _label(context, 'Direction'),
                const SizedBox(height: 8),
                _segmented(context, const ['I\'m Paying', 'I\'m Requesting'], _paying ? 'I\'m Paying' : 'I\'m Requesting',
                    (v) => setState(() => _paying = v == 'I\'m Paying')),
              ],
              const SizedBox(height: 16),
              _label(context, 'Description'),
              const SizedBox(height: 8),
              _field(context, 'Rent, groceries, etc.', controller: _description),
              const SizedBox(height: 16),
              _label(context, 'Amount'),
              const SizedBox(height: 8),
              _field(context, '0.00', controller: _amount, number: true),
              if (isSplit) ...[
                const SizedBox(height: 16),
                _label(context, 'Split Percentage'),
                const SizedBox(height: 8),
                _splitCard(context),
              ],
              const SizedBox(height: 16),
              _label(context, 'Due Date'),
              const SizedBox(height: 8),
              _dateField(context),
              const SizedBox(height: 16),
              _label(context, 'Repeat'),
              const SizedBox(height: 8),
              _repeatField(context),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.dangerRed)),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        side: BorderSide(color: palette.border, width: 2),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: _save,
                      child: const Text('Save Payment', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _splitCard(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('You pay:', style: TextStyle(fontSize: 14, color: palette.textPrimary))),
              Text('${_split.round()}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
            ],
          ),
          Slider(
            value: _split,
            max: 100,
            activeColor: AppColors.primaryBlue,
            onChanged: (v) => setState(() => _split = v),
          ),
          Align(
            alignment: Alignment.center,
            child: Text('Partner pays: ${(100 - _split).round()}%',
                style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _segmented(BuildContext context, List<String> options, String selected, ValueChanged<String> onChanged) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(options[i]),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: options[i] == selected ? AppColors.primaryBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(options[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: options[i] == selected ? Colors.white : palette.textSecondary)),
                ),
              ),
            ),
            if (i < options.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String hint, {required TextEditingController controller, bool number = false}) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: TextStyle(fontSize: 15, color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: palette.textSecondary),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _due,
          firstDate: DateTime(DateTime.now().year - 1),
          lastDate: DateTime(DateTime.now().year + 5),
        );
        if (picked != null) setState(() => _due = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_due.year}-${_due.month.toString().padLeft(2, '0')}-${_due.day.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 15, color: palette.textPrimary)),
            Icon(Icons.calendar_today, size: 16, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _repeatField(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _repeat,
          isExpanded: true,
          dropdownColor: palette.surfaceElevated,
          style: TextStyle(fontSize: 15, color: palette.textPrimary),
          items: const [
            DropdownMenuItem(value: 'Once', child: Text('Once')),
            DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'Biweekly', child: Text('Biweekly')),
            DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
            DropdownMenuItem(value: 'Quarterly', child: Text('Quarterly')),
            DropdownMenuItem(value: 'Yearly', child: Text('Yearly')),
          ],
          onChanged: (v) => setState(() => _repeat = v ?? 'Once'),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) =>
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textSecondary));

  Widget _handle(BuildContext context) => Center(
        child: Container(
            width: 48, height: 6, decoration: BoxDecoration(color: context.palette.border, borderRadius: BorderRadius.circular(3))),
      );
}

// ── Summary sheet ─────────────────────────────────────────────────────────────────
class _SummarySheet extends StatelessWidget {
  final double verifiedTotal, pendingTotal, overdueTotal;
  final int verifiedCount, pendingCount, overdueCount;
  final List<({String label, double total, int count})> breakdown;
  const _SummarySheet({
    required this.verifiedTotal,
    required this.verifiedCount,
    required this.pendingTotal,
    required this.pendingCount,
    required this.overdueTotal,
    required this.overdueCount,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
                width: 48, height: 6, decoration: BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Monthly Summary',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ),
          const SizedBox(height: 20),
          _row(AppColors.iconBgGreen, const Color(0xFF15803D), 'icon_checkmark', 'Verified', verifiedTotal, verifiedCount),
          const SizedBox(height: 12),
          _row(AppColors.iconBgYellow, const Color(0xFFA16207), 'icon_clock', 'Pending', pendingTotal, pendingCount),
          const SizedBox(height: 12),
          _row(AppColors.iconBgRed, const Color(0xFFB91C1C), 'icon_alert', 'Overdue', overdueTotal, overdueCount),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Breakdown by Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 8),
            for (final b in breakdown) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: Border.all(color: context.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${b.label} (${b.count})',
                          style: TextStyle(fontSize: 14, color: palette.textPrimary)),
                    ),
                    Text('\$${b.total.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _row(Color bg, Color fg, String icon, String label, double total, int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          AppIcon(icon, size: 28, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 14, color: fg)),
                Text('\$${total.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fg)),
              ],
            ),
          ),
          Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }
}
