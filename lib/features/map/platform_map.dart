import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amap;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

/// Platform-conditional map — native **Apple MapKit** on iOS (via apple_maps_flutter)
/// and **Google Maps** on Android (via google_maps_flutter). This mirrors the MAUI
/// app, which rendered native MapKit on iOS. Both plugins expose colliding top-level
/// names (`LatLng`, `CameraPosition`, `BitmapDescriptor`, …), so each is imported with
/// a prefix and the page above only ever sees the neutral [MapMarkerData] /
/// [PlatformMapController] types declared here.
///
/// Apple MapKit needs no API key; Android Google Maps reads the key from the manifest.

/// Shared hue values (identical 0–360 constants in both plugins).
class MapHue {
  MapHue._();
  static const double azure = 210.0; // POIs
  static const double green = 120.0; // custody-transfer location records
  static const double orange = 30.0; // general location records
  static const double violet = 270.0; // the user's tapped/selected location
}

/// A platform-neutral map marker.
class MapMarkerData {
  const MapMarkerData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.hue,
    this.title,
    this.snippet,
    this.onTap,
  });

  final String id;
  final double lat;
  final double lng;
  final double hue;
  final String? title;
  final String? snippet;
  final VoidCallback? onTap;
}

/// Wraps whichever native controller backs the visible map so the page can move
/// the camera without knowing which platform it is on.
class PlatformMapController {
  PlatformMapController._(this._google, this._apple);

  final gmap.GoogleMapController? _google;
  final amap.AppleMapController? _apple;

  Future<void> moveTo(double lat, double lng, double zoom) async {
    if (_google != null) {
      await _google.animateCamera(
          gmap.CameraUpdate.newLatLngZoom(gmap.LatLng(lat, lng), zoom));
    } else if (_apple != null) {
      await _apple.animateCamera(
          amap.CameraUpdate.newLatLngZoom(amap.LatLng(lat, lng), zoom));
    }
  }
}

class PlatformMap extends StatelessWidget {
  const PlatformMap({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.initialZoom,
    required this.markers,
    this.myLocationEnabled = false,
    this.onMapReady,
    this.onTap,
    this.highlightLat,
    this.highlightLng,
  });

  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final List<MapMarkerData> markers;
  final bool myLocationEnabled;
  final void Function(PlatformMapController controller)? onMapReady;

  /// Called when the user taps an empty part of the map (lat/lng of the tap).
  final void Function(double lat, double lng)? onTap;

  /// When set, draws a translucent highlight circle around this point (the
  /// user's tapped/selected location) — mirrors MAUI's selected-location ring.
  final double? highlightLat;
  final double? highlightLng;

  static const _ringFill = Color(0x338B5CF6); // violet @ 20%
  static const _ringStroke = Color(0xFF8B5CF6);

  bool get _useApple => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    if (_useApple) {
      return amap.AppleMap(
        initialCameraPosition: amap.CameraPosition(
          target: amap.LatLng(initialLat, initialLng),
          zoom: initialZoom,
        ),
        annotations: {
          for (final m in markers)
            amap.Annotation(
              annotationId: amap.AnnotationId(m.id),
              position: amap.LatLng(m.lat, m.lng),
              icon: amap.BitmapDescriptor.defaultAnnotationWithHue(m.hue),
              infoWindow: amap.InfoWindow(title: m.title, snippet: m.snippet),
              onTap: m.onTap,
            ),
        },
        circles: {
          if (highlightLat != null && highlightLng != null)
            amap.Circle(
              circleId: amap.CircleId('highlight'),
              center: amap.LatLng(highlightLat!, highlightLng!),
              radius: 120,
              fillColor: _ringFill,
              strokeColor: _ringStroke,
              strokeWidth: 2,
            ),
        },
        myLocationEnabled: myLocationEnabled,
        myLocationButtonEnabled: myLocationEnabled,
        onMapCreated: (c) =>
            onMapReady?.call(PlatformMapController._(null, c)),
        onTap: onTap == null ? null : (pos) => onTap!(pos.latitude, pos.longitude),
      );
    }
    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(
        target: gmap.LatLng(initialLat, initialLng),
        zoom: initialZoom,
      ),
      markers: {
        for (final m in markers)
          gmap.Marker(
            markerId: gmap.MarkerId(m.id),
            position: gmap.LatLng(m.lat, m.lng),
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(m.hue),
            infoWindow: gmap.InfoWindow(title: m.title, snippet: m.snippet),
            onTap: m.onTap,
          ),
      },
      circles: {
        if (highlightLat != null && highlightLng != null)
          gmap.Circle(
            circleId: const gmap.CircleId('highlight'),
            center: gmap.LatLng(highlightLat!, highlightLng!),
            radius: 120,
            fillColor: _ringFill,
            strokeColor: _ringStroke,
            strokeWidth: 2,
          ),
      },
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: myLocationEnabled,
      zoomControlsEnabled: false,
      onMapCreated: (c) => onMapReady?.call(PlatformMapController._(c, null)),
      onTap: onTap == null ? null : (pos) => onTap!(pos.latitude, pos.longitude),
    );
  }
}
