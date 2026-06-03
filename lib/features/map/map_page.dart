import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/location_models.dart';
import '../../services/external_launcher.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import 'map_popups.dart';
import 'platform_map.dart';
import 'location_records_page.dart';

/// Location Map — port of `Views/Map/MapPage.xaml(.cs)`. A live map of the family's
/// POIs and location records, with header controls (refresh / records / filter), an
/// address search, current-location, and an Add-POI FAB.
///
/// Uses native **Apple MapKit on iOS** and **Google Maps on Android** (see
/// [PlatformMap]) — matching the MAUI app. Apple MapKit needs no key; Android reads
/// the Maps key from the manifest. On a platform where the key is invalid the tiles
/// stay blank but the overlay UI + marker logic are unaffected.
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  PlatformMapController? _controller;
  final _searchCtrl = TextEditingController();
  final List<MapMarkerData> _markers = [];
  bool _myLocationEnabled = false;
  // Default camera: continental US, zoomed out, until we resolve a location.
  double _initialLat = 39.8283;
  double _initialLng = -98.5795;
  double _initialZoom = 3;

  // Loaded data + filter state (mirrors MAUI's _showPois / _showCustodyTransfers).
  List<PointOfInterest> _pois = [];
  List<ScheduleTransferPin> _transferPins = [];
  bool _showPois = true;
  bool _showTransfers = true;

  // The location the user tapped on the map (drives the Add-POI / Add-Record flows).
  double? _selLat;
  double? _selLng;
  bool _busy = false;

  // Address-search autocomplete (debounced, Google Places via server proxy with
  // an on-device geocoding fallback) — mirrors MAUI's suggestion list.
  Timer? _addrDebounce;
  // placeId is set for Places results (coords fetched on tap); for geocoding
  // fallbacks placeId is empty and lat/lng are filled inline.
  List<({String label, String placeId, double? lat, double? lng})> _suggestions = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _resolvePermissionAndCenter();
    await _loadMarkers();
  }

  Future<void> _resolvePermissionAndCenter() async {
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          _myLocationEnabled = true;
          final pos = await Geolocator.getCurrentPosition();
          _initialLat = pos.latitude;
          _initialLng = pos.longitude;
          _initialZoom = 13;
        }
      }
    } catch (_) {/* keep the default camera */}
    if (mounted) setState(() {});
  }

  Future<void> _loadMarkers() async {
    List<PointOfInterest> pois = [];
    List<ScheduleTransferPin> transfers = [];
    try {
      pois = await ServiceLocator.location.getPois();
    } catch (_) {/* continue without POIs */}
    try {
      // Dedicated recurring schedule-transfer locations (mirrors MAUI's map),
      // NOT logged location records (those live on the Location Records page).
      transfers = await ServiceLocator.location.getScheduleTransferLocations();
    } catch (_) {/* continue without transfer pins */}
    if (!mounted) return;
    setState(() {
      _pois = pois;
      _transferPins = transfers;
    });
    _rebuildMarkers();
  }

  /// Rebuilds the marker set from loaded data, applying the filter toggles and
  /// adding the user's tapped "selected location" pin (mirrors MAUI's
  /// UpdateMapPinsAsync + selected-location overlay).
  void _rebuildMarkers() {
    final markers = <MapMarkerData>[];
    if (_showPois) {
      for (final p in _pois) {
        markers.add(MapMarkerData(
          id: 'poi_${p.poiId}',
          lat: p.latitude,
          lng: p.longitude,
          hue: MapHue.azure,
          title: p.displayName,
          snippet: p.address,
          onTap: () => _showPinDetails(
              title: p.displayName,
              subtitle: 'Point of Interest',
              lat: p.latitude,
              lng: p.longitude,
              locationName: p.displayName,
              address: p.address),
        ));
      }
    }
    if (_showTransfers) {
      for (int i = 0; i < _transferPins.length; i++) {
        final t = _transferPins[i];
        final name = t.locationName.isNotEmpty ? t.locationName : 'Transfer location';
        final when = [
          if (t.dayName.isNotEmpty) t.dayName,
          if (t.transferTime.isNotEmpty && t.transferTime != '00:00') t.transferTime,
        ].join(' · ');
        markers.add(MapMarkerData(
          id: 'transfer_$i',
          lat: t.latitude,
          lng: t.longitude,
          hue: MapHue.green,
          title: name,
          snippet: when.isNotEmpty ? 'Custody transfer · $when' : 'Custody transfer',
          onTap: () => _showPinDetails(
              title: name,
              subtitle: when.isNotEmpty ? 'Custody transfer · $when' : 'Custody transfer',
              lat: t.latitude,
              lng: t.longitude,
              locationName: name),
        ));
      }
    }
    if (_selLat != null && _selLng != null) {
      markers.add(MapMarkerData(
        id: 'selected',
        lat: _selLat!,
        lng: _selLng!,
        hue: MapHue.violet,
        title: 'Selected location',
        snippet: '${_selLat!.toStringAsFixed(6)}, ${_selLng!.toStringAsFixed(6)}',
      ));
    }
    if (!mounted) return;
    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
    });
  }

  void _onMapTap(double lat, double lng) {
    setState(() {
      _selLat = lat;
      _selLng = lng;
    });
    _rebuildMarkers();
  }

  Future<void> _refresh() async {
    await _loadMarkers();
    if (!mounted || _controller == null) return;
    // Recenter so the refresh has a visible effect: prefer the device's current
    // location, otherwise fall back to the first loaded marker.
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition();
          await _controller?.moveTo(pos.latitude, pos.longitude, 14);
          return;
        }
      }
    } catch (_) {/* fall through to marker fallback */}
    if (_markers.isNotEmpty) {
      final first = _markers.first;
      await _controller?.moveTo(first.lat, first.lng, 12);
    }
  }

  /// Centers the map on [lat]/[lng] and drops the violet "selected" pin +
  /// highlight ring there, so a searched address has a clear visual landing
  /// point (mirrors MAUI dropping a pin on search).
  Future<void> _goTo(double lat, double lng, {double zoom = 15}) async {
    setState(() {
      _selLat = lat;
      _selLng = lng;
    });
    _rebuildMarkers();
    await _controller?.moveTo(lat, lng, zoom);
  }

  // ── POI create (Add-POI FAB) ───────────────────────────────────────────────
  Future<void> _addPoi() async {
    if (_busy) return;
    // If nothing tapped, fall back to the device's current location.
    if (_selLat == null || _selLng == null) {
      final cur = await ServiceLocator.location.getCurrentLocation();
      if (cur != null) {
        _selLat = cur.latitude;
        _selLng = cur.longitude;
        _rebuildMarkers();
        await _controller?.moveTo(cur.latitude, cur.longitude, 15);
      }
    }
    if (!mounted) return;
    final label = (_selLat != null && _selLng != null)
        ? 'Location: ${_selLat!.toStringAsFixed(6)}, ${_selLng!.toStringAsFixed(6)}'
        : null;
    final result = await AddPoiPopup.show(context, locationLabel: label);
    if (result == null) return;
    if (_selLat == null || _selLng == null) {
      await _alert('Error', 'Please select a location on the map first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final address =
          await ServiceLocator.location.getAddressFromCoordinates(_selLat!, _selLng!);
      await ServiceLocator.location.createPoi(PointOfInterest(
        name: result.name,
        description: result.description,
        latitude: _selLat!,
        longitude: _selLng!,
        address: address,
        category: result.category,
        isSharedWithPartner: result.share,
      ));
      _selLat = null;
      _selLng = null;
      await _loadMarkers();
    } catch (_) {
      if (mounted) await _alert('Error', 'Failed to save POI. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Pin details → Record / Records / Navigate ──────────────────────────────
  void _showPinDetails({
    required String title,
    required String subtitle,
    required double lat,
    required double lng,
    required String locationName,
    String? address,
  }) {
    PinDetailsPopup.show(
      context,
      title: title,
      subtitle: subtitle,
      lat: lat,
      lng: lng,
      address: address,
      onCreateRecord: () => _createRecord(lat, lng, locationName),
      onViewRecords: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LocationRecordsPage(
              latitude: lat, longitude: lng, locationName: locationName))),
      onNavigate: () => ExternalLauncher.openMaps(lat, lng, label: locationName),
    );
  }

  Future<void> _createRecord(double lat, double lng, String locationName) async {
    final result = await AddRecordPopup.show(context, locationLabel: locationName);
    if (result == null) return;
    setState(() => _busy = true);
    try {
      // Proximity check (within 200 m), mirroring MAUI VerifyProximityAsync.
      if (!await _verifyProximity(lat, lng)) {
        if (mounted) {
          await _alert('Location Verification',
              'You are not within 200 meters of selected POI, retry when closer.');
        }
        return;
      }
      await ServiceLocator.location.createLocationRecord(LocationRecord(
        latitude: lat,
        longitude: lng,
        locationName: locationName,
        notes: result.notes,
        isCustodyTransfer: result.isTransfer,
        timestamp: DateTime.now(),
      ));
      await _loadMarkers();
    } catch (_) {
      if (mounted) await _alert('Error', 'Failed to save location record. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _verifyProximity(double lat, double lng) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return false;
      }
      final cur = await Geolocator.getCurrentPosition();
      final meters = Geolocator.distanceBetween(cur.latitude, cur.longitude, lat, lng);
      return meters <= 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openFilter() async {
    final result = await MapFilterPopup.show(context,
        showPois: _showPois, showTransfers: _showTransfers);
    if (result == null) return;
    setState(() {
      _showPois = result.showPois;
      _showTransfers = result.showTransfers;
    });
    _rebuildMarkers();
  }

  Future<void> _alert(String title, String message) async {
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

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    // If we already have suggestions, apply the first; otherwise resolve directly.
    if (_suggestions.isNotEmpty) {
      await _applySuggestion(_suggestions.first);
      return;
    }
    setState(() => _suggestions = const []);
    try {
      // Prefer the Places proxy (real place results); fall back to the geocoder.
      final places = await ServiceLocator.location.searchPlaces(query, maxResults: 1);
      if (places.isNotEmpty) {
        final d = await ServiceLocator.location.getPlaceDetails(places.first.placeId);
        if (d != null) {
          await _goTo(d.lat, d.lng);
          return;
        }
      }
      final results = await locationFromAddress(query);
      if (results.isEmpty) return;
      await _goTo(results.first.latitude, results.first.longitude, zoom: 14);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not find that address.'), duration: Duration(seconds: 2)));
      }
    }
  }

  /// Debounced autocomplete: 500 ms after typing stops (≥3 chars). Queries the
  /// Google Places proxy for real place suggestions; on failure/empty, falls back
  /// to the on-device geocoder (reverse-geocoded to readable labels).
  void _onSearchChanged(String text) {
    _addrDebounce?.cancel();
    final q = text.trim();
    if (q.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _addrDebounce = Timer(const Duration(milliseconds: 500), () => _fetchSuggestions(q));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (mounted) setState(() => _searching = true);
    var out = <({String label, String placeId, double? lat, double? lng})>[];
    try {
      final places = await ServiceLocator.location.searchPlaces(query, maxResults: 5);
      out = [
        for (final p in places) (label: p.description, placeId: p.placeId, lat: null, lng: null),
      ];
    } catch (_) {/* fall through to geocoder */}

    if (out.isEmpty) {
      try {
        final locs = await locationFromAddress(query);
        for (final loc in locs.take(5)) {
          String label = query;
          try {
            final marks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
            if (marks.isNotEmpty) {
              final m = marks.first;
              label = [
                if (m.name?.isNotEmpty ?? false) m.name,
                if ((m.street?.isNotEmpty ?? false) && m.street != m.name) m.street,
                if (m.locality?.isNotEmpty ?? false) m.locality,
                if (m.administrativeArea?.isNotEmpty ?? false) m.administrativeArea,
              ].whereType<String>().toSet().join(', ');
            }
          } catch (_) {/* keep the raw query as the label */}
          out.add((label: label.isEmpty ? query : label, placeId: '', lat: loc.latitude, lng: loc.longitude));
        }
      } catch (_) {/* no matches */}
    }
    if (!mounted) return;
    setState(() {
      _suggestions = out;
      _searching = false;
    });
  }

  Future<void> _applySuggestion(({String label, String placeId, double? lat, double? lng}) s) async {
    FocusScope.of(context).unfocus();
    _searchCtrl.text = s.label;
    setState(() => _suggestions = const []);
    // Places results need a details lookup for coordinates; geocoder results
    // already carry lat/lng.
    var lat = s.lat;
    var lng = s.lng;
    if ((lat == null || lng == null) && s.placeId.isNotEmpty) {
      final d = await ServiceLocator.location.getPlaceDetails(s.placeId);
      if (d != null) {
        lat = d.lat;
        lng = d.lng;
      }
    }
    if (lat != null && lng != null) {
      await _goTo(lat, lng);
    }
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
            child: Stack(
              children: [
                PlatformMap(
                  initialLat: _initialLat,
                  initialLng: _initialLng,
                  initialZoom: _initialZoom,
                  markers: _markers,
                  myLocationEnabled: _myLocationEnabled,
                  onMapReady: (c) => _controller = c,
                  onTap: _onMapTap,
                  highlightLat: _selLat,
                  highlightLng: _selLng,
                ),
                Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      children: [
                        _searchBar(context),
                        if (_suggestions.isNotEmpty || _searching) _suggestionsList(context),
                      ],
                    )),
                Positioned(
                  right: 16,
                  bottom: 120,
                  child: GestureDetector(
                    onTap: _busy ? null : _addPoi,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(28)),
                      child: Center(
                          child: _busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const AppIcon('icon_plus', size: 28, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    Widget control(String icon, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: AppIcon(icon, size: 18, color: palette.textSecondary)),
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 10, 20, 14),
      color: palette.surface,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: AppIcon('icon_location', size: 22, color: AppColors.primaryBlue)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location Map',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('POIs & Transfers', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
          control('icon_refresh', _refresh),
          control('icon_clipboard',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocationRecordsPage()))),
          control('icon_gear', _openFilter),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          AppIcon('icon_search', size: 18, color: palette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _search(),
              style: TextStyle(fontSize: 15, color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search address...',
                hintStyle: TextStyle(color: palette.textPlaceholder),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              setState(() => _suggestions = const []);
              FocusScope.of(context).unfocus();
            },
            child: AppIcon('icon_close', size: 16, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsList(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: _searching && _suggestions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _suggestions.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.border),
                  InkWell(
                    onTap: () => _applySuggestion(_suggestions[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          AppIcon('icon_location', size: 16, color: palette.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_suggestions[i].label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, color: palette.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
