import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/providers.dart';

enum LocationPermissionState {
  unknown,
  locating,
  granted,
  approximate,
  denied,
  disabled,
  error,
  manual,
}

class LocationState {
  const LocationState({
    required this.permission,
    this.latitude,
    this.longitude,
    this.label,
    this.administrativeArea,
    this.accuracyMeters,
    this.geocodingFailed = false,
  });
  final LocationPermissionState permission;
  final double? latitude, longitude, accuracyMeters;
  final String? label, administrativeArea;
  final bool geocodingFailed;
  bool get hasCoordinates => latitude != null && longitude != null;
  LocationState copyWith({
    LocationPermissionState? permission,
    double? latitude,
    double? longitude,
    String? label,
  }) => LocationState(
    permission: permission ?? this.permission,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    label: label ?? this.label,
    administrativeArea: administrativeArea,
    accuracyMeters: accuracyMeters,
    geocodingFailed: geocodingFailed,
  );
}

class LocationController extends Notifier<LocationState> {
  int _request = 0;
  bool _disposed = false;
  @override
  LocationState build() {
    ref.onDispose(() {
      _disposed = true;
      _request++;
    });
    return const LocationState(permission: LocationPermissionState.unknown);
  }

  Future<void> detect({bool force = false}) async {
    if (!force &&
        (state.permission == LocationPermissionState.manual ||
            state.permission == LocationPermissionState.locating)) {
      return;
    }
    final request = ++_request;
    state = const LocationState(permission: LocationPermissionState.locating);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!_disposed && request == _request) {
          state = const LocationState(
            permission: LocationPermissionState.disabled,
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (_disposed || request != _request) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = const LocationState(permission: LocationPermissionState.denied);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (_disposed || request != _request) return;
      String label = 'Position GPS';
      String? area;
      bool failed = false;
      try {
        final response = await ref
            .read(apiClientProvider)
            .dio
            .get(
              '/locations/reverse',
              queryParameters: {
                'latitude': position.latitude,
                'longitude': position.longitude,
              },
            );
        label = response.data['label'] as String;
        area = response.data['administrative_area'] as String?;
      } catch (_) {
        failed = true;
      }
      if (_disposed || request != _request) return;
      state = LocationState(
        permission: position.accuracy > 100
            ? LocationPermissionState.approximate
            : LocationPermissionState.granted,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        label: label,
        administrativeArea: area,
        geocodingFailed: failed,
      );
    } catch (_) {
      if (!_disposed && request == _request) {
        state = const LocationState(permission: LocationPermissionState.error);
      }
    }
  }

  void setManualCity(String label, double latitude, double longitude) {
    _request++;
    state = LocationState(
      permission: LocationPermissionState.manual,
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
  }
}

final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);
