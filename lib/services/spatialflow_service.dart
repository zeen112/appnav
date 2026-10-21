import 'package:flutter/services.dart';

class SpatialflowService {
  static const MethodChannel _channel = MethodChannel('com.mototouring.nav/spatialflow');

  static final SpatialflowService _instance = SpatialflowService._internal();
  factory SpatialflowService() => _instance;
  SpatialflowService._internal();

  /// Launches Spatialflow via deep-link (spatialflow://), Android package intent,
  /// or falls back to opening the open-source GitHub project page.
  Future<String> launchSpatialflow({
    String routeId = '',
    double targetSpeedLimitKmh = 0.0,
    String telemetryPayload = '',
  }) async {
    try {
      final payload = 'route_id=$routeId&speed_limit=$targetSpeedLimitKmh&telemetry=$telemetryPayload';
      final String? result = await _channel.invokeMethod<String>('openSpatialflow', {
        'data': payload,
      });
      return result ?? 'UNKNOWN_STATUS';
    } on PlatformException catch (e) {
      return 'FAILED: ${e.message}';
    }
  }
}
