// DTOs for address autocomplete (Google Places via server proxy). 1:1 with the
// model classes in `Services/AddressSearchService.cs`. Default camelCase naming.

double _dbl(dynamic v) => v == null ? 0 : (v as num).toDouble();

/// A single address search result with coordinates (client-side view model).
class AddressResult {
  AddressResult({
    this.displayText = '',
    this.placeId = '',
    this.latitude = 0,
    this.longitude = 0,
    this.type = '',
  });
  final String displayText;
  final String placeId;
  final double latitude;
  final double longitude;
  final String type;
}

class PlaceSuggestion {
  PlaceSuggestion({this.placeId = '', this.description = ''});
  final String placeId;
  final String description;
  factory PlaceSuggestion.fromJson(Map<String, dynamic> j) => PlaceSuggestion(
        placeId: j['placeId'] as String? ?? '',
        description: j['description'] as String? ?? '',
      );
}

class PlaceDetailsResponse {
  PlaceDetailsResponse({this.formattedAddress = '', this.latitude = 0, this.longitude = 0});
  final String formattedAddress;
  final double latitude;
  final double longitude;
  factory PlaceDetailsResponse.fromJson(Map<String, dynamic> j) =>
      PlaceDetailsResponse(
        formattedAddress: j['formattedAddress'] as String? ?? '',
        latitude: _dbl(j['latitude']),
        longitude: _dbl(j['longitude']),
      );
}
