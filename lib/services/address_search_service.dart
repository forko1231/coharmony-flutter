import '../models/places_models.dart';
import 'api_client.dart';

/// Port of `Services/AddressSearchService.cs`. Address autocomplete via the
/// server's Google Places proxy (API key stays server-side). Two-step flow:
/// autocomplete (suggestions) → details (lat/lng for a chosen place).
class AddressSearchService {
  AddressSearchService(this._api);
  final ApiClient _api;

  /// Address suggestions (descriptions + place IDs, no coordinates yet).
  Future<List<AddressResult>> search(String query, {int maxResults = 5}) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeQueryComponent(query.trim());
    final json =
        await _api.getJson('api/places/autocomplete?input=$encoded&maxResults=$maxResults');
    if (json is! List) return [];

    return json
        .map((e) => PlaceSuggestion.fromJson(e as Map<String, dynamic>))
        .where((r) => r.description.isNotEmpty)
        .map((r) => AddressResult(
              displayText: r.description,
              placeId: r.placeId,
              latitude: 0,
              longitude: 0,
            ))
        .toList();
  }

  /// Coordinates + formatted address for a selected place by its [placeId].
  Future<AddressResult?> getPlaceDetails(String placeId) async {
    if (placeId.trim().isEmpty) return null;
    final encoded = Uri.encodeQueryComponent(placeId);
    final json = await _api.getJson('api/places/details?placeId=$encoded');
    if (json is! Map<String, dynamic>) return null;

    final details = PlaceDetailsResponse.fromJson(json);
    if (details.latitude == 0 && details.longitude == 0) return null;

    return AddressResult(
      displayText: details.formattedAddress,
      placeId: placeId,
      latitude: details.latitude,
      longitude: details.longitude,
    );
  }
}
