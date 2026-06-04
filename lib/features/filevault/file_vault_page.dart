import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Port of `Views/FileVault/Filevault.xaml(.cs)` — a private, on-device document
/// locker rooted at `<AppSupportDir>/PrivateLocker`. A 3-column grid of folders
/// and files with drill-down navigation, multi-select delete, import from
/// camera / files / photo-library, new-folder, per-item rename/share/delete, an
/// immersive image viewer, and the system viewer for documents/videos, plus
/// search + extension filtering. Pure local filesystem — no API (matches MAUI).
class FileVaultPage extends StatefulWidget {
  const FileVaultPage(
      {super.key, this.pickFile = false, this.pickFolder = false, this.pickFiles = false});

  /// File-picker mode (MAUI's `Filevault(false, true)`): tapping a file pops the
  /// page returning its path instead of opening it. Folders still navigate.
  /// Used by the chat composer's "Select from Vault" attachment source.
  final bool pickFile;

  /// Folder-picker mode (MAUI's `Filevault(true)`): drill into folders, then tap
  /// "Save Here" to pop the chosen directory path. Used by chat "Save to Vault".
  final bool pickFolder;

  /// Multi-file-picker mode: tapping files toggles selection; an "Attach N" bar
  /// pops the list of chosen file paths. Used by the chat composer to attach
  /// several vault files to one message.
  final bool pickFiles;

  @override
  State<FileVaultPage> createState() => _FileVaultPageState();
}

class _FsItem {
  _FsItem({
    required this.name,
    required this.path,
    required this.isFolder,
    required this.isImage,
  });
  String name;
  String path;
  final bool isFolder;
  final bool isImage;
  bool selected = false;
  // Folders sort before files (mirrors C# SortOrder 0/1).
  int get sortOrder => isFolder ? 0 : 1;
}

class _FileVaultPageState extends State<FileVaultPage> {
  static const _imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'};

  Directory? _root;
  late Directory _current;
  final List<Directory> _history = [];

  final List<_FsItem> _items = [];
  bool _loading = true;

  bool _multiSelect = false;
  bool _searchActive = false;
  String _searchText = '';
  String _extFilter = 'All Files';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initFileSystem();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filesystem init / load ───────────────────────────────────────────────
  Future<void> _initFileSystem() async {
    try {
      final base = await getApplicationSupportDirectory();
      final root = Directory(p.join(base.path, 'PrivateLocker'));
      if (!await root.exists()) await root.create(recursive: true);
      _root = root;
      _current = root;
      await _loadCurrentFolder();
    } catch (e) {
      if (mounted) _showError('Failed to initialize file system: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCurrentFolder() async {
    final items = <_FsItem>[];
    try {
      if (await _current.exists()) {
        for (final entity in _current.listSync()) {
          final name = p.basename(entity.path);
          if (entity is Directory) {
            items.add(_FsItem(name: name, path: entity.path, isFolder: true, isImage: false));
          } else if (entity is File) {
            if (name.startsWith('.')) continue; // skip hidden/system files
            final ext = p.extension(name).toLowerCase();
            items.add(_FsItem(
                name: name, path: entity.path, isFolder: false, isImage: _imageExts.contains(ext)));
          }
        }
      }
    } catch (e) {
      if (mounted) _showError('Failed to load folder contents: $e');
    }
    items.sort((a, b) {
      final s = a.sortOrder.compareTo(b.sortOrder);
      return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
    });
  }

  // Items after search + extension filtering (mirrors C# ApplyFilter).
  List<_FsItem> get _filtered {
    Iterable<_FsItem> r = _items;
    if (_searchText.trim().isNotEmpty) {
      final q = _searchText.toLowerCase();
      r = r.where((i) => i.name.toLowerCase().contains(q));
    }
    if (_extFilter != 'All Files') {
      r = r.where((i) => !i.isFolder && p.extension(i.path).toLowerCase() == _extFilter);
    }
    return r.toList();
  }

  List<String> get _availableExtensions {
    final exts = _items
        .where((i) => !i.isFolder && p.extension(i.path).isNotEmpty)
        .map((i) => p.extension(i.path).toLowerCase())
        .toSet()
        .toList()
      ..sort();
    return ['All Files', ...exts];
  }

  bool get _atRoot => _root != null && _current.path == _root!.path;
  String get _title => _atRoot
      ? (widget.pickFolder
          ? 'Choose Folder'
          : (widget.pickFiles
              ? 'Select Files'
              : (widget.pickFile ? 'Select from Vault' : 'File Vault')))
      : p.basename(_current.path);
  List<_FsItem> get _selectedItems => _items.where((i) => i.selected).toList();

  // ── Navigation ───────────────────────────────────────────────────────────
  Future<void> _navigateTo(_FsItem folder) async {
    _history.add(_current);
    _current = Directory(folder.path);
    await _loadCurrentFolder();
  }

  Future<void> _navigateBack() async {
    if (_history.isEmpty) return;
    _current = _history.removeLast();
    await _loadCurrentFolder();
  }

  Future<bool> _handleSystemBack() async {
    if (_multiSelect) {
      _toggleMultiSelect();
      return false;
    }
    if (_history.isNotEmpty) {
      await _navigateBack();
      return false;
    }
    return true;
  }

  // ── Item tap ─────────────────────────────────────────────────────────────
  Future<void> _onItemTap(_FsItem item) async {
    if (_multiSelect) {
      setState(() => item.selected = !item.selected);
      return;
    }
    if (item.isFolder) {
      await _navigateTo(item);
    } else if (widget.pickFiles) {
      // Multi-file-picker: tapping a file toggles its selection.
      setState(() => item.selected = !item.selected);
    } else if (widget.pickFolder) {
      // Folder-picker mode: files aren't selectable; only folders + "Save Here".
      return;
    } else if (widget.pickFile) {
      // File-picker mode: return the chosen file's path to the caller.
      Navigator.of(context).pop(item.path);
    } else {
      await _openFile(item);
    }
  }

  // ── Import ───────────────────────────────────────────────────────────────
  Future<void> _importFromCamera() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;
      await _processImportedFile(photo.path, p.basename(photo.path), askToDelete: true);
    } catch (e) {
      await _showError('Camera error: $e');
    }
  }

  Future<void> _importFromFilesApp() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (result == null || result.files.isEmpty) return;
      var imported = 0;
      for (final f in result.files) {
        if (f.path == null) continue;
        if (await _copyInto(f.path!, f.name)) imported++;
      }
      await _loadCurrentFolder();
      await _showInfo(imported > 0 ? 'Success' : 'Information',
          imported > 0 ? '$imported file(s) imported successfully' : 'No files were imported');
    } catch (e) {
      await _showError('File picker error: $e');
    }
  }

  Future<void> _importFromPhotoLibrary() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia();
      if (picked.isEmpty) return;
      var imported = 0;
      for (final x in picked) {
        if (await _copyInto(x.path, p.basename(x.path))) imported++;
      }
      await _loadCurrentFolder();
      await _showInfo(imported > 0 ? 'Success' : 'Information',
          imported > 0 ? '$imported file(s) imported successfully' : 'No files were imported');
    } catch (e) {
      await _showError('Photo library error: $e');
    }
  }

  /// Copies [sourcePath] into the current folder under [fileName]. On a name
  /// clash, prompts to replace (instead of silently skipping). Returns true when
  /// copied. Used by the multi-file Files-app / photo-library imports.
  Future<bool> _copyInto(String sourcePath, String fileName) async {
    try {
      final dest = p.join(_current.path, fileName);
      if (await File(dest).exists()) {
        final overwrite = await _confirm('File Exists',
            '"$fileName" already exists. Do you want to replace it?',
            yes: 'Replace', no: 'Skip');
        if (!overwrite) return false;
        await File(dest).delete();
      }
      await File(sourcePath).copy(dest);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Single import with overwrite prompt + optional "delete original?" prompt +
  /// success alert (mirrors C# ProcessImportedFile).
  Future<void> _processImportedFile(String sourcePath, String fileName,
      {required bool askToDelete}) async {
    try {
      final dest = p.join(_current.path, fileName);
      if (await File(dest).exists()) {
        final overwrite = await _confirm('File Exists',
            'A file with this name already exists. Do you want to replace it?',
            yes: 'Yes', no: 'No');
        if (!overwrite) return;
        await File(dest).delete();
      }
      await File(sourcePath).copy(dest);
      await _loadCurrentFolder();
      // Offer to remove the source copy after a successful import (matches MAUI).
      if (askToDelete) {
        final del = await _confirm('Import Complete',
            'File imported successfully. Delete the original file?',
            yes: 'Delete Original', no: 'Keep');
        if (del) {
          try {
            await File(sourcePath).delete();
          } catch (_) {/* original may be in a read-only cache — ignore */}
        }
      } else {
        await _showInfo('Success', 'File imported successfully');
      }
    } catch (e) {
      await _showError('Failed to process file: $e');
    }
  }

  // ── New folder ───────────────────────────────────────────────────────────
  Future<void> _newFolder() async {
    final name = await _prompt('New Folder', 'Enter folder name:', confirm: 'Create');
    if (name == null || name.trim().isEmpty) return;
    try {
      final path = p.join(_current.path, name);
      if (await Directory(path).exists()) {
        await _showError('A folder with this name already exists.');
        return;
      }
      await Directory(path).create(recursive: true);
      await _loadCurrentFolder();
    } catch (e) {
      await _showError('Failed to create folder: $e');
    }
  }

  // ── Context menu: share / rename / delete ────────────────────────────────
  Future<void> _showContextMenu(_FsItem item) async {
    final palette = context.palette;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surfaceElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        Widget row(String value, String icon, String label, {Color? color}) => ListTile(
              leading: AppIcon(icon, size: 20, color: color ?? palette.textSecondary),
              title: Text(label,
                  style: TextStyle(color: color ?? palette.textPrimary, fontSize: 16)),
              onTap: () => Navigator.of(sheetCtx).pop(value),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              if (!item.isFolder) row('savefiles', 'icon_document', 'Save to Files'),
              if (!item.isFolder) row('share', 'icon_share', 'Share'),
              row('rename', 'icon_edit', 'Rename'),
              row('delete', 'icon_trash', 'Delete', color: AppColors.dangerRed),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    switch (action) {
      case 'savefiles':
        await _saveItemToFiles(item);
        break;
      case 'share':
        await _shareItem(item);
        break;
      case 'rename':
        await _renameItem(item);
        break;
      case 'delete':
        await _deleteItem(item);
        break;
    }
  }

  Future<void> _shareItem(_FsItem item) async {
    try {
      await Share.shareXFiles([XFile(item.path)], subject: item.name);
    } catch (e) {
      await _showError('Failed to share: $e');
    }
  }

  /// Native "Save to Files": exports a copy of the vault file to a location the
  /// user picks via the system document picker (UIDocumentPicker on iOS / SAF on
  /// Android), writing the bytes there.
  Future<void> _saveItemToFiles(_FsItem item) async {
    try {
      final bytes = await File(item.path).readAsBytes();
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save to Files',
        fileName: item.name,
        bytes: bytes,
      );
      if (saved != null && mounted) await _showInfo('Saved', 'Saved to Files.');
    } catch (e) {
      // Fall back to the share sheet (also offers "Save to Files").
      try {
        await Share.shareXFiles([XFile(item.path)], subject: item.name);
      } catch (_) {
        await _showError('Could not save the file: $e');
      }
    }
  }

  Future<void> _renameItem(_FsItem item) async {
    final newName =
        await _prompt('Rename', 'Enter new name:', confirm: 'Rename', initial: item.name);
    if (newName == null || newName.trim().isEmpty || newName == item.name) return;
    try {
      final newPath = p.join(p.dirname(item.path), newName);
      if (item.isFolder) {
        if (await Directory(newPath).exists()) {
          await _showError('A folder with this name already exists.');
          return;
        }
        await Directory(item.path).rename(newPath);
      } else {
        if (await File(newPath).exists()) {
          await _showError('A file with this name already exists.');
          return;
        }
        await File(item.path).rename(newPath);
      }
      await _loadCurrentFolder();
    } catch (e) {
      await _showError('Failed to rename: $e');
    }
  }

  Future<void> _deleteItem(_FsItem item) async {
    final confirm = await _confirm('Confirm Delete',
        'Are you sure you want to delete ${item.name}? This action cannot be undone.',
        yes: 'Delete', no: 'Cancel');
    if (!confirm) return;
    try {
      if (item.isFolder) {
        await Directory(item.path).delete(recursive: true);
      } else {
        await File(item.path).delete();
      }
      await _loadCurrentFolder();
    } catch (e) {
      await _showError('Failed to delete: $e');
    }
  }

  // ── Multi-select ─────────────────────────────────────────────────────────
  void _toggleMultiSelect() {
    setState(() {
      _multiSelect = !_multiSelect;
      for (final i in _items) {
        i.selected = false;
      }
    });
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedItems;
    if (selected.isEmpty) {
      await _showInfo('No Selection', 'Please select items to delete');
      return;
    }
    final confirm = await _confirm('Confirm Delete',
        'Are you sure you want to delete ${selected.length} item(s)? This action cannot be undone.',
        yes: 'Delete', no: 'Cancel');
    if (!confirm) return;
    try {
      var folders = 0, files = 0;
      for (final item in selected) {
        if (item.isFolder) {
          await Directory(item.path).delete(recursive: true);
          folders++;
        } else {
          await File(item.path).delete();
          files++;
        }
      }
      await _loadCurrentFolder();
      if (_multiSelect) _toggleMultiSelect();
      await _showInfo('Success', 'Deleted $folders folder(s) and $files file(s)');
    } catch (e) {
      await _showError('Failed to delete items: $e');
    }
  }

  // ── Open / preview ───────────────────────────────────────────────────────
  Future<void> _openFile(_FsItem file) async {
    try {
      final ext = p.extension(file.path).toLowerCase();
      if (_imageExts.contains(ext)) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _ImageViewerPage(path: file.path, name: file.name)));
        return;
      }
      // Documents, videos, and everything else → system viewer.
      await OpenFilex.open(file.path);
    } catch (e) {
      await _showError('Cannot open file: $e');
    }
  }

  // ── Search ───────────────────────────────────────────────────────────────
  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchCtrl.clear();
        _searchText = '';
        _extFilter = 'All Files';
      }
    });
  }

  // ── Dialog helpers ───────────────────────────────────────────────────────
  Future<void> _showError(String message) => _showInfo('Error', message);

  Future<void> _showInfo(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  Future<bool> _confirm(String title, String message,
      {required String yes, required String no}) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(no)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(yes)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _prompt(String title, String label,
      {required String confirm, String? initial}) async {
    final ctrl = TextEditingController(text: initial);
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: label),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: Text(confirm)),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filtered = _filtered;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _handleSystemBack();
        if (shouldPop) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            Column(
              children: [
                _headerBar(context),
                if (_searchActive) _searchBar(context),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? _emptyState(context)
                          : GridView.count(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 100),
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 0.85,
                              children: [for (final it in filtered) _tile(context, it)],
                            ),
                ),
              ],
            ),
            if (widget.pickFolder)
              _saveHereBar(context)
            else if (widget.pickFiles)
              _attachSelectedBar(context)
            else
              _fab(context),
          ],
        ),
      ),
    );
  }

  /// Multi-file-picker mode: a bottom "Attach N file(s)" button that pops the
  /// list of selected file paths back to the chat composer.
  Widget _attachSelectedBar(BuildContext context) {
    final selected = _selectedItems.where((i) => !i.isFolder).toList();
    if (selected.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 20,
      right: 20,
      bottom: 32,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(selected.map((i) => i.path).toList()),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    offset: const Offset(0, 4),
                    blurRadius: 12),
              ],
            ),
            child: Text('Attach ${selected.length} file${selected.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  /// Folder-picker mode: a bottom "Save Here" button that returns the current
  /// directory path to the caller (chat "Save to Vault").
  Widget _saveHereBar(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 32,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(_current.path),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    offset: const Offset(0, 4),
                    blurRadius: 12),
              ],
            ),
            child: Text(_atRoot ? 'Save to Vault root' : 'Save Here (${p.basename(_current.path)})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  Widget _headerBar(BuildContext context) {
    final palette = context.palette;
    Widget btn(String icon, VoidCallback onTap,
            {EdgeInsets margin = EdgeInsets.zero, Color? bg}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            margin: margin,
            decoration: BoxDecoration(
              color: bg ?? (context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: AppIcon(icon, size: 22, color: palette.textSecondary)),
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16 + MediaQuery.viewPaddingOf(context).top, 20, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 4),
              blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          btn('icon_chevron_left', () async {
            if (_history.isNotEmpty) {
              await _navigateBack();
            } else if (mounted) {
              Navigator.of(context).maybePop();
            }
          }),
          // Spacer matching the right side's extra button (48) + its margin (8)
          // so the Expanded title region is symmetric and the title is centered
          // relative to the whole header, not just the gap between the controls.
          const SizedBox(width: 56),
          Expanded(
            child: Center(
              child: Text(_title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
          ),
          btn('icon_checkmark', _toggleMultiSelect,
              margin: const EdgeInsets.only(right: 8),
              bg: _multiSelect ? AppColors.iconBgBlue : null),
          btn('icon_search', _toggleSearch),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: TextStyle(fontSize: 15, color: palette.textPrimary),
              onChanged: (v) => setState(() => _searchText = v),
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: TextStyle(color: palette.textSecondary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_availableExtensions.length > 1) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: DropdownButton<String>(
                value: _extFilter,
                items: [
                  for (final ext in _availableExtensions)
                    DropdownMenuItem(value: ext, child: Text(ext)),
                ],
                onChanged: (v) => setState(() => _extFilter = v ?? 'All Files'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, _FsItem it) {
    final palette = context.palette;
    final isFolder = it.isFolder;
    final showImage = it.isImage && File(it.path).existsSync();
    return GestureDetector(
      onTap: () => _onItemTap(it),
      onLongPress: _multiSelect ? null : () => _showContextMenu(it),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: it.selected ? AppColors.primaryBlue : palette.border,
            width: it.selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (showImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(it.path),
                        width: 48, height: 48, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: isFolder ? AppColors.iconBgPurple : AppColors.iconBgBlue,
                        borderRadius: BorderRadius.circular(12)),
                    child: Center(
                        child: AppIcon(isFolder ? 'icon_folder' : 'icon_document',
                            size: 24, color: isFolder ? AppColors.accentPurple : AppColors.primaryBlue)),
                  ),
                if (it.selected)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: AppIcon('icon_checkmark', size: 22, color: Colors.white)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(it.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(24)),
              child: const Center(child: AppIcon('icon_folder', size: 40, color: Colors.white)),
            ),
            const SizedBox(height: 20),
            Text('No Files or Folders Yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text('Start by creating folders or importing files',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _fab(BuildContext context) {
    final isDelete = _multiSelect;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 32,
      child: Center(
        child: GestureDetector(
          onTap: isDelete ? _deleteSelected : () => _showAddMenu(context),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDelete ? AppColors.dangerRed : AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: (isDelete ? AppColors.dangerRed : AppColors.primaryBlue).withValues(alpha: 0.3),
                    offset: const Offset(0, 4),
                    blurRadius: 12),
              ],
            ),
            child: Center(child: AppIcon(isDelete ? 'icon_trash' : 'icon_plus', size: 28, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: const Color(0x80000000),
      builder: (_) => _AddToVaultMenu(
        onCamera: _importFromCamera,
        onFiles: _importFromFilesApp,
        onPhotos: _importFromPhotoLibrary,
        onNewFolder: _newFolder,
      ),
    );
  }
}

/// Immersive full-screen image viewer (matches MAUI's in-page image viewer:
/// black background, top bar with close + share).
class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.path, required this.name});
  final String path;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _circleButton(Icons.close, () => Navigator.of(context).pop()),
                  const Spacer(),
                  _circleButton(Icons.ios_share, () async {
                    try {
                      await Share.shareXFiles([XFile(path)], subject: name);
                    } catch (_) {}
                  }),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0x66000000),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}

class _AddToVaultMenu extends StatelessWidget {
  const _AddToVaultMenu({
    required this.onCamera,
    required this.onFiles,
    required this.onPhotos,
    required this.onNewFolder,
  });

  final Future<void> Function() onCamera;
  final Future<void> Function() onFiles;
  final Future<void> Function() onPhotos;
  final Future<void> Function() onNewFolder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text('Add to Vault',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ),
              const SizedBox(height: 2),
              Center(child: Text('Choose an option below', style: TextStyle(fontSize: 13, color: palette.textSecondary))),
              const SizedBox(height: 16),
              Container(height: 1, color: palette.border),
              const SizedBox(height: 16),
              _option(context, 'icon_camera', AppColors.iconBgBlue, AppColors.primaryBlue, 'Take Photo', onCamera),
              const SizedBox(height: 10),
              _option(context, 'icon_document', AppColors.iconBgYellow, AppColors.warningAmber, 'Files App', onFiles),
              const SizedBox(height: 10),
              _option(context, 'icon_image', AppColors.iconBgGreen, AppColors.successGreen, 'Photo Library', onPhotos),
              const SizedBox(height: 10),
              _option(context, 'icon_folder', AppColors.iconBgPurple, AppColors.accentPurple, 'New Folder', onNewFolder),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, String icon, Color bg, Color tint, String label,
      Future<void> Function() action) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () async {
        Navigator.of(context).pop();
        await action();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: palette.surfaceInput,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Center(child: AppIcon(icon, size: 20, color: tint)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
            AppIcon('icon_chevron_right', size: 16, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}
