import 'dart:io' show Platform;

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_models.dart';
import 'api_client.dart';

/// Port of `Services/LocationService.cs`. Location records, custody-transfer
/// locations, and POIs. Routes/payloads are 1:1 with the C# service and
/// `LocationController.cs` / `PlacesController.cs`. Native geolocation +
/// reverse-geocoding use the `geolocator` / `geocoding` plugins.
class LocationService {
  LocationService(this._api);
  final ApiClient _api;

  /// Matches the C# `DeviceInfo.Platform` tag.
  static String get _deviceInfo =>
      Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'flutter');

  // ---- Location records ---------------------------------------------------

  Future<LocationRecord> createLocationRecord(LocationRecord record) async {
    final json = await _api.postJson(
      'api/location',
      CreateLocationRecordRequest(
        latitude: record.latitude,
        longitude: record.longitude,
        locationName: record.locationName,
        address: record.address,
        notes: record.notes,
        isCustodyTransfer: record.isCustodyTransfer,
        transferDayOfWeek: record.transferDayOfWeek,
        transferTime: record.transferTime,
        transferDescription: record.transferDescription,
        accuracy: record.accuracy,
        deviceInfo: _deviceInfo,
      ).toJson(),
    );
    if (json is Map<String, dynamic>) {
      final resp = CreateLocationRecordResponse.fromJson(json);
      if (resp.success && resp.locationRecordId > 0) {
        record.locationRecordId = resp.locationRecordId;
        return record;
      }
    }
    throw Exception('Failed to create location record');
  }

  Future<(List<LocationRecord>, PaginationInfo)> getLocationRecords({
    int page = 1,
    int pageSize = 20,
    bool? isCustodyTransfer,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final qs = _recordQuery(page, pageSize, isCustodyTransfer, startDate, endDate);
    final json = await _api.getJson('api/location?$qs');
    return _records(json);
  }

  Future<(List<LocationRecord>, PaginationInfo)> getLocationRecordsForLocation(
    double latitude,
    double longitude, {
    int page = 1,
    int pageSize = 20,
    bool? isCustodyTransfer,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String>[
      'latitude=$latitude',
      'longitude=$longitude',
      ..._recordQuery(page, pageSize, isCustodyTransfer, startDate, endDate).split('&'),
    ];
    final json = await _api.getJson('api/location/for-location?${params.join('&')}');
    return _records(json);
  }

  Future<List<LocationRecord>> getCustodyTransferLocations() async {
    final json = await _api.getJson('api/location/custody-transfers');
    if (json is Map<String, dynamic>) {
      final r = CustodyTransferLocationsResponse.fromJson(json);
      if (r.success) return r.transferLocations;
    }
    return [];
  }

  Future<List<ScheduleTransferPin>> getScheduleTransferLocations() async {
    final json = await _api.getJson('api/location/schedule-transfers');
    if (json is Map<String, dynamic>) {
      final r = ScheduleTransferLocationsResponse.fromJson(json);
      if (r.success) return r.transferPins;
    }
    return [];
  }

  Future<LocationRecord> createTransferRecord(
    double latitude,
    double longitude, {
    String? locationName,
    String? notes,
    int? transferDayOfWeek,
    Duration? transferTime,
  }) async {
    final json = await _api.postJson(
      'api/location/create-transfer-record',
      CreateTransferRecordRequest(
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        notes: notes,
        transferDayOfWeek: transferDayOfWeek,
        transferTime: transferTime == null ? null : _hms(transferTime),
      ).toJson(),
    );
    if (json is Map<String, dynamic>) {
      final resp = CreateLocationRecordResponse.fromJson(json);
      if (resp.success && resp.locationRecordId > 0) {
        return LocationRecord(
          locationRecordId: resp.locationRecordId,
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
          notes: notes,
          isCustodyTransfer: true,
          transferDayOfWeek: transferDayOfWeek,
          transferTime: transferTime == null ? null : _hms(transferTime),
          timestamp: DateTime.now(),
        );
      }
    }
    throw Exception('Failed to create transfer record');
  }

  Future<bool> deleteLocationRecord(int locationRecordId) async {
    final json = await _api.deleteJson('api/location/$locationRecordId');
    return json is Map<String, dynamic> &&
        DeleteLocationRecordResponse.fromJson(json).success;
  }

  // ---- POIs ---------------------------------------------------------------

  Future<PointOfInterest> createPoi(PointOfInterest poi) async {
    final json = await _api.postJson(
      'api/location/poi',
      CreatePoiRequest(
        name: poi.name,
        description: poi.description,
        latitude: poi.latitude,
        longitude: poi.longitude,
        address: poi.address,
        category: poi.category,
        isSharedWithPartner: poi.isSharedWithPartner,
      ).toJson(),
    );
    if (json is Map<String, dynamic>) {
      final resp = CreatePoiResponse.fromJson(json);
      if (resp.success && resp.poiId > 0) {
        poi.poiId = resp.poiId;
        return poi;
      }
    }
    throw Exception('Failed to create POI');
  }

  Future<List<PointOfInterest>> getPois() async {
    final json = await _api.getJson('api/location/poi');
    if (json is Map<String, dynamic>) {
      final r = PoisResponse.fromJson(json);
      if (r.success) return r.pois;
    }
    return [];
  }

  Future<PointOfInterest?> getPoi(int poiId) async {
    final json = await _api.getJson('api/location/poi/$poiId');
    if (json is Map<String, dynamic>) {
      final r = PoiResponse.fromJson(json);
      if (r.success) return r.poi;
    }
    return null;
  }

  Future<bool> updatePoi(PointOfInterest poi) async {
    final json = await _api.postJson(
      'api/location/poi/${poi.poiId}',
      UpdatePoiRequest(
        name: poi.name,
        description: poi.description,
        address: poi.address,
        category: poi.category,
        isSharedWithPartner: poi.isSharedWithPartner,
      ).toJson(),
    );
    return json is Map<String, dynamic> && ApiResponse.fromJson(json).success;
  }

  Future<bool> deletePoi(int poiId) async {
    final json = await _api.deleteJson('api/location/poi/$poiId');
    return json is Map<String, dynamic> && ApiResponse.fromJson(json).success;
  }

  // ---- Pure ---------------------------------------------------------------

  bool isValidCoordinates(double latitude, double longitude) =>
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;

  /// Device geolocation via the `geolocator` plugin (port of
  /// `GetCurrentLocationAsync`). Returns null when services/permission are off.
  Future<({double latitude, double longitude})?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition();
      return (latitude: pos.latitude, longitude: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocoding via the `geocoding` plugin (port of
  /// `GetAddressFromCoordinatesAsync`).
  Future<String?> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      final marks = await placemarkFromCoordinates(latitude, longitude);
      if (marks.isEmpty) return null;
      final p = marks.first;
      final parts = [p.street, p.locality, p.administrativeArea, p.postalCode]
          .where((s) => s != null && s.isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  // ---- Helpers ------------------------------------------------------------

  String _recordQuery(int page, int pageSize, bool? isCustodyTransfer,
      DateTime? startDate, DateTime? endDate) {
    final params = <String>['page=$page', 'pageSize=$pageSize'];
    if (isCustodyTransfer != null) params.add('isCustodyTransfer=$isCustodyTransfer');
    if (startDate != null) params.add('startDate=${_ymd(startDate)}');
    if (endDate != null) params.add('endDate=${_ymd(endDate)}');
    return params.join('&');
  }

  (List<LocationRecord>, PaginationInfo) _records(dynamic json) {
    if (json is Map<String, dynamic>) {
      final r = LocationRecordsResponse.fromJson(json);
      if (r.success) return (r.records, r.pagination);
    }
    return (<LocationRecord>[], PaginationInfo());
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hms(Duration d) {
    final h = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
