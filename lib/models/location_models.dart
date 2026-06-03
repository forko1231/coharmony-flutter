// DTOs for the location/POI domain. 1:1 with `Services/LocationService.cs`.
// Default camelCase naming. C# `TimeSpan?` serializes as "HH:mm:ss" strings, so
// transfer-time fields are kept as String? here.

double _dbl(dynamic v) => v == null ? 0 : (v as num).toDouble();
double? _dblN(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class PointOfInterest {
  PointOfInterest({
    this.poiId = 0,
    this.name = '',
    this.description,
    this.latitude = 0,
    this.longitude = 0,
    this.address,
    this.category,
    this.isSharedWithPartner = true,
    this.createdAt,
    this.updatedAt,
  });
  int poiId;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final String? address;
  final String? category;
  final bool isSharedWithPartner;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName =>
      name.isNotEmpty ? name : (address ?? 'Unknown Location');

  factory PointOfInterest.fromJson(Map<String, dynamic> j) => PointOfInterest(
        poiId: (j['poiId'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        latitude: _dbl(j['latitude']),
        longitude: _dbl(j['longitude']),
        address: j['address'] as String?,
        category: j['category'] as String?,
        isSharedWithPartner: j['isSharedWithPartner'] as bool? ?? true,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

class LocationRecord {
  LocationRecord({
    this.locationRecordId = 0,
    this.latitude = 0,
    this.longitude = 0,
    this.locationName,
    this.address,
    this.notes,
    this.isCustodyTransfer = false,
    this.transferDayOfWeek,
    this.transferTime,
    this.transferDescription,
    this.accuracy,
    this.deviceInfo,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);

  int locationRecordId;
  final double latitude;
  final double longitude;
  final String? locationName;
  final String? address;
  final String? notes;
  final bool isCustodyTransfer;
  final int? transferDayOfWeek;
  final String? transferTime; // "HH:mm:ss"
  final String? transferDescription;
  final double? accuracy;
  final String? deviceInfo;
  final DateTime timestamp;

  String get friendlyAddress => (locationName != null && locationName!.isNotEmpty)
      ? locationName!
      : (address ?? 'Unknown Location');
  String get recordType => isCustodyTransfer ? 'Custody Transfer' : 'Location Record';
  String get formattedTimestamp {
    final t = timestamp;
    final mon = _monthAbbr[t.month - 1];
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final mm = t.minute.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    return '$mon $dd, ${t.year} $hour12:$mm $ampm';
  }

  factory LocationRecord.fromJson(Map<String, dynamic> j) => LocationRecord(
        locationRecordId: (j['locationRecordId'] as num?)?.toInt() ?? 0,
        latitude: _dbl(j['latitude']),
        longitude: _dbl(j['longitude']),
        locationName: j['locationName'] as String?,
        address: j['address'] as String?,
        notes: j['notes'] as String?,
        isCustodyTransfer: j['isCustodyTransfer'] as bool? ?? false,
        transferDayOfWeek: (j['transferDayOfWeek'] as num?)?.toInt(),
        transferTime: j['transferTime'] as String?,
        transferDescription: j['transferDescription'] as String?,
        accuracy: _dblN(j['accuracy']),
        deviceInfo: j['deviceInfo'] as String?,
        timestamp: _date(j['timestamp']),
      );
}

class ScheduleTransferPin {
  ScheduleTransferPin({
    this.latitude = 0,
    this.longitude = 0,
    this.locationName = '',
    this.address = '',
    this.dayOfWeek = 0,
    this.transferTime = '',
    this.dayName = '',
  });
  final double latitude;
  final double longitude;
  final String locationName;
  final String address;
  final int dayOfWeek;
  final String transferTime;
  final String dayName;

  factory ScheduleTransferPin.fromJson(Map<String, dynamic> j) => ScheduleTransferPin(
        latitude: _dbl(j['latitude']),
        longitude: _dbl(j['longitude']),
        locationName: j['locationName'] as String? ?? '',
        address: j['address'] as String? ?? '',
        dayOfWeek: (j['dayOfWeek'] as num?)?.toInt() ?? 0,
        transferTime: j['transferTime'] as String? ?? '',
        dayName: j['dayName'] as String? ?? '',
      );
}

class PaginationInfo {
  PaginationInfo({
    this.currentPage = 0,
    this.pageSize = 0,
    this.totalCount = 0,
    this.totalPages = 0,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
  });
  final int currentPage;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPreviousPage;

  factory PaginationInfo.fromJson(Map<String, dynamic> j) => PaginationInfo(
        currentPage: (j['currentPage'] as num?)?.toInt() ?? 0,
        pageSize: (j['pageSize'] as num?)?.toInt() ?? 0,
        totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
        totalPages: (j['totalPages'] as num?)?.toInt() ?? 0,
        hasNextPage: j['hasNextPage'] as bool? ?? false,
        hasPreviousPage: j['hasPreviousPage'] as bool? ?? false,
      );
}

// ---- Requests ------------------------------------------------------------

class CreatePoiRequest {
  CreatePoiRequest({
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    this.address,
    this.category,
    this.isSharedWithPartner = true,
  });
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final String? address;
  final String? category;
  final bool isSharedWithPartner;
  Map<String, dynamic> toJson() => _stripNulls({
        'name': name,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'category': category,
        'isSharedWithPartner': isSharedWithPartner,
      });
}

class UpdatePoiRequest {
  UpdatePoiRequest({
    required this.name,
    this.description,
    this.address,
    this.category,
    this.isSharedWithPartner = true,
  });
  final String name;
  final String? description;
  final String? address;
  final String? category;
  final bool isSharedWithPartner;
  Map<String, dynamic> toJson() => _stripNulls({
        'name': name,
        'description': description,
        'address': address,
        'category': category,
        'isSharedWithPartner': isSharedWithPartner,
      });
}

class CreateLocationRecordRequest {
  CreateLocationRecordRequest({
    required this.latitude,
    required this.longitude,
    this.locationName,
    this.address,
    this.notes,
    this.isCustodyTransfer = false,
    this.transferDayOfWeek,
    this.transferTime,
    this.transferDescription,
    this.accuracy,
    this.deviceInfo,
  });
  final double latitude;
  final double longitude;
  final String? locationName;
  final String? address;
  final String? notes;
  final bool isCustodyTransfer;
  final int? transferDayOfWeek;
  final String? transferTime; // "HH:mm:ss"
  final String? transferDescription;
  final double? accuracy;
  final String? deviceInfo;
  Map<String, dynamic> toJson() => _stripNulls({
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'address': address,
        'notes': notes,
        'isCustodyTransfer': isCustodyTransfer,
        'transferDayOfWeek': transferDayOfWeek,
        'transferTime': transferTime,
        'transferDescription': transferDescription,
        'accuracy': accuracy,
        'deviceInfo': deviceInfo,
      });
}

class CreateTransferRecordRequest {
  CreateTransferRecordRequest({
    required this.latitude,
    required this.longitude,
    this.locationName,
    this.notes,
    this.transferDayOfWeek,
    this.transferTime,
  });
  final double latitude;
  final double longitude;
  final String? locationName;
  final String? notes;
  final int? transferDayOfWeek;
  final String? transferTime; // "HH:mm:ss"
  Map<String, dynamic> toJson() => _stripNulls({
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'notes': notes,
        'transferDayOfWeek': transferDayOfWeek,
        'transferTime': transferTime,
      });
}

// ---- Responses -----------------------------------------------------------

class CreatePoiResponse {
  CreatePoiResponse({this.success = false, this.poiId = 0, this.message = ''});
  final bool success;
  final int poiId;
  final String message;
  factory CreatePoiResponse.fromJson(Map<String, dynamic> j) => CreatePoiResponse(
        success: j['success'] as bool? ?? false,
        poiId: (j['poiId'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
      );
}

class PoisResponse {
  PoisResponse({this.success = false, this.pois = const []});
  final bool success;
  final List<PointOfInterest> pois;
  factory PoisResponse.fromJson(Map<String, dynamic> j) => PoisResponse(
        success: j['success'] as bool? ?? false,
        pois: (j['pois'] as List<dynamic>? ?? [])
            .map((e) => PointOfInterest.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PoiResponse {
  PoiResponse({this.success = false, this.poi});
  final bool success;
  final PointOfInterest? poi;
  factory PoiResponse.fromJson(Map<String, dynamic> j) => PoiResponse(
        success: j['success'] as bool? ?? false,
        poi: j['poi'] is Map<String, dynamic>
            ? PointOfInterest.fromJson(j['poi'] as Map<String, dynamic>)
            : null,
      );
}

class ApiResponse {
  ApiResponse({this.success = false, this.message = ''});
  final bool success;
  final String message;
  factory ApiResponse.fromJson(Map<String, dynamic> j) => ApiResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String? ?? '',
      );
}

class CreateLocationRecordResponse {
  CreateLocationRecordResponse(
      {this.success = false, this.locationRecordId = 0, this.message = ''});
  final bool success;
  final int locationRecordId;
  final String message;
  factory CreateLocationRecordResponse.fromJson(Map<String, dynamic> j) =>
      CreateLocationRecordResponse(
        success: j['success'] as bool? ?? false,
        locationRecordId: (j['locationRecordId'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
      );
}

class LocationRecordsResponse {
  LocationRecordsResponse(
      {this.success = false, this.records = const [], PaginationInfo? pagination})
      : pagination = pagination ?? PaginationInfo();
  final bool success;
  final List<LocationRecord> records;
  final PaginationInfo pagination;
  factory LocationRecordsResponse.fromJson(Map<String, dynamic> j) =>
      LocationRecordsResponse(
        success: j['success'] as bool? ?? false,
        records: (j['records'] as List<dynamic>? ?? [])
            .map((e) => LocationRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        pagination: j['pagination'] is Map<String, dynamic>
            ? PaginationInfo.fromJson(j['pagination'] as Map<String, dynamic>)
            : PaginationInfo(),
      );
}

class CustodyTransferLocationsResponse {
  CustodyTransferLocationsResponse(
      {this.success = false, this.transferLocations = const []});
  final bool success;
  final List<LocationRecord> transferLocations;
  factory CustodyTransferLocationsResponse.fromJson(Map<String, dynamic> j) =>
      CustodyTransferLocationsResponse(
        success: j['success'] as bool? ?? false,
        transferLocations: (j['transferLocations'] as List<dynamic>? ?? [])
            .map((e) => LocationRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ScheduleTransferLocationsResponse {
  ScheduleTransferLocationsResponse(
      {this.success = false, this.transferPins = const []});
  final bool success;
  final List<ScheduleTransferPin> transferPins;
  factory ScheduleTransferLocationsResponse.fromJson(Map<String, dynamic> j) =>
      ScheduleTransferLocationsResponse(
        success: j['success'] as bool? ?? false,
        transferPins: (j['transferPins'] as List<dynamic>? ?? [])
            .map((e) => ScheduleTransferPin.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DeleteLocationRecordResponse {
  DeleteLocationRecordResponse({this.success = false, this.message = ''});
  final bool success;
  final String message;
  factory DeleteLocationRecordResponse.fromJson(Map<String, dynamic> j) =>
      DeleteLocationRecordResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String? ?? '',
      );
}
