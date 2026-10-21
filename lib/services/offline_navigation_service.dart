import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';

class NavigationManeuver {
  final LatLng point;
  final String instruction;
  final double distanceToNextManeuverMeters;
  final String iconCode;

  const NavigationManeuver({
    required this.point,
    required this.instruction,
    required this.distanceToNextManeuverMeters,
    required this.iconCode,
  });
}

class OfflineNavigationService {
  static final OfflineNavigationService _instance = OfflineNavigationService._internal();
  factory OfflineNavigationService() => _instance;
  OfflineNavigationService._internal();

  final FlutterTts _tts = FlutterTts();
  static const MethodChannel _serviceChannel = MethodChannel('com.mototouring.nav/foreground_service');

  bool _isNavigating = false;
  bool _isPocketMode = false;
  List<NavigationManeuver> _maneuvers = [];
  int _currentManeuverIndex = 0;

  bool get isNavigating => _isNavigating;
  bool get isPocketMode => _isPocketMode;

  /// Initialize Text-To-Speech with low-latency offline voice
  Future<void> initTTS() async {
    await _tts.setLanguage("id-ID"); // Indonesian rider voice guidance
    await _tts.setSpeechRate(0.52);   // Clear pronunciation at speed
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Audio focus listener bindings
    _tts.setStartHandler(() {
      // Audio focus will duck background music automatically via Android AudioAttributes
    });

    _tts.setCompletionHandler(() {
      // Audio focus automatically restored by OS
    });
  }

  /// 1. Download and cache Mapbox Route Corridor before departure
  /// Calculates bounding box with safety buffer for offline storage
  Map<String, dynamic> calculateCorridorBoundingBox(List<LatLng> routePoints, {double bufferDegree = 0.05}) {
    double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;

    for (final p in routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Add buffer around the corridor (approx 5-10 km)
    return {
      'southWest': LatLng(minLat - bufferDegree, minLng - bufferDegree),
      'northEast': LatLng(maxLat + bufferDegree, maxLng + bufferDegree),
      'bbox': [minLng - bufferDegree, minLat - bufferDegree, maxLng + bufferDegree, maxLat + bufferDegree]
    };
  }

  /// 2. Trigger "Start": Enter Battery Saver & Offline Mode
  Future<void> startNavigation({
    required List<LatLng> routeCorridor,
    required List<NavigationManeuver> instructions,
  }) async {
    _maneuvers = instructions;
    _currentManeuverIndex = 0;
    _isNavigating = true;

    // Start Foreground Service with Wakelock + AudioFocus
    await _serviceChannel.invokeMethod('startTouringService');

    // Announce departure
    await speakInstruction("Navigasi dimulai. Modus hemat baterai aktif. Ponsel aman dimasukkan ke saku.");
  }

  /// Toggle Pocket Mode (Turns off UI map rendering loop to save thermal budget & battery)
  void setPocketMode(bool enabled) {
    _isPocketMode = enabled;
  }

  /// Process hardware GPS update against maneuvers (Lightweight offline lookup)
  void onLocationChanged(LatLng currentPos) {
    if (!_isNavigating || _currentManeuverIndex >= _maneuvers.length) return;

    final targetManeuver = _maneuvers[_currentManeuverIndex];
    final distance = const Distance().as(LengthUnit.Meter, currentPos, targetManeuver.point);

    // Turn-by-Turn Voice Alert thresholds
    if (distance <= 50) {
      speakInstruction(targetManeuver.instruction);
      _currentManeuverIndex++;
    } else if (distance <= 300 && distance > 250) {
      speakInstruction("Dalam 300 meter, ${targetManeuver.instruction}");
    }
  }

  /// Voice guidance execution
  Future<void> speakInstruction(String text) async {
    await _tts.speak(text);
  }

  /// Stop Navigation & stop foreground service
  Future<void> stopNavigation() async {
    _isNavigating = false;
    _isPocketMode = false;
    await _tts.stop();
    await _serviceChannel.invokeMethod('stopTouringService');
  }
}
