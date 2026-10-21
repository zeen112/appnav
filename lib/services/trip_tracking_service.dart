import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class GpsBreadcrumb {
  final int timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speedKmh;

  GpsBreadcrumb({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speedKmh,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'speed_kmh': speedKmh,
  };
}

class TripSummary {
  final String sessionId;
  final int startTimestamp;
  final int finishTimestamp;
  final int actualDurationSeconds;
  final double totalDistanceKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final List<LatLng> polylinePoints;

  TripSummary({
    required this.sessionId,
    required this.startTimestamp,
    required this.finishTimestamp,
    required this.actualDurationSeconds,
    required this.totalDistanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.polylinePoints,
  });
}

class TripTrackingService {
  static final TripTrackingService _instance = TripTrackingService._internal();
  factory TripTrackingService() => _instance;
  TripTrackingService._internal();

  Database? _db;
  int? _startTimestamp;
  String? _activeSessionId;

  // Lightweight accumulated hardware metrics
  double _accumulatedDistanceMeters = 0.0;
  double _maxSpeedKmh = 0.0;
  LatLng? _lastKnownPoint;
  final List<LatLng> _sessionPolyline = [];

  bool get isRecording => _startTimestamp != null;

  Future<void> initDatabase() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'moto_touring_offline.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_breadcrumbs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude REAL,
            speed_kmh REAL
          )
        ''');
      },
    );
  }

  /// 1. Trigger "Start": Store exact Unix Milliseconds (NO Background Timers!)
  Future<void> startTrip(String sessionId) async {
    await initDatabase();
    _activeSessionId = sessionId;
    _startTimestamp = DateTime.now().millisecondsSinceEpoch;
    _accumulatedDistanceMeters = 0.0;
    _maxSpeedKmh = 0.0;
    _lastKnownPoint = null;
    _sessionPolyline.clear();
  }

  /// 2. Handle hardware GPS fix directly from location listener
  Future<void> recordGpsPoint({
    required double lat,
    required double lng,
    required double altitude,
    required double speedMs, // Speed provided directly by hardware GPS chip
  }) async {
    if (!isRecording || _db == null) return;

    final currentPoint = LatLng(lat, lng);
    final currentSpeedKmh = (speedMs > 0 ? speedMs * 3.6 : 0.0);

    if (currentSpeedKmh > _maxSpeedKmh) {
      _maxSpeedKmh = currentSpeedKmh;
    }

    if (_lastKnownPoint != null) {
      // Calculate distance from previous fix
      final deltaMeters = const Distance().as(LengthUnit.Meter, _lastKnownPoint!, currentPoint);
      // Filter out GPS jitter (< 3 meters while standing still)
      if (deltaMeters >= 3.0) {
        _accumulatedDistanceMeters += deltaMeters;
        _sessionPolyline.add(currentPoint);
      }
    } else {
      _sessionPolyline.add(currentPoint);
    }
    _lastKnownPoint = currentPoint;

    // Buffer to local SQLite for complete offline safety
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.insert('offline_breadcrumbs', {
      'session_id': _activeSessionId,
      'timestamp': now,
      'latitude': lat,
      'longitude': lng,
      'altitude': altitude,
      'speed_kmh': currentSpeedKmh,
    });
  }

  /// 3. Trigger "Finish": Compute metrics via pure timestamp arithmetic
  Future<TripSummary> finishTrip() async {
    final finishTimestamp = DateTime.now().millisecondsSinceEpoch;
    final start = _startTimestamp ?? finishTimestamp;

    // Actual duration calculated strictly from delta without background interval drift
    final actualDurationSeconds = ((finishTimestamp - start) / 1000).round();
    final totalDistanceKm = _accumulatedDistanceMeters / 1000.0;
    
    // Hardware-accurate average speed calculation
    final hours = actualDurationSeconds / 3600.0;
    final avgSpeedKmh = hours > 0 ? (totalDistanceKm / hours) : 0.0;

    final summary = TripSummary(
      sessionId: _activeSessionId ?? '',
      startTimestamp: start,
      finishTimestamp: finishTimestamp,
      actualDurationSeconds: actualDurationSeconds,
      totalDistanceKm: double.parse(totalDistanceKm.toStringAsFixed(2)),
      avgSpeedKmh: double.parse(avgSpeedKmh.toStringAsFixed(1)),
      maxSpeedKmh: double.parse(_maxSpeedKmh.toStringAsFixed(1)),
      polylinePoints: List.unmodifiable(_sessionPolyline),
    );

    // Reset runtime trip state
    _startTimestamp = null;
    return summary;
  }

  /// 4. Synchronize completed trip data to Supabase
  Future<void> syncTripToSupabase({
    required TripSummary summary,
    required String title,
    String? routeId,
    String? shareableImageUrl,
  }) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // 1. Insert Trip Session
    final sessionResponse = await supabase.from('trip_sessions').insert({
      'id': summary.sessionId,
      'user_id': userId,
      'route_id': routeId,
      'title': title,
      'start_timestamp': summary.startTimestamp,
      'finish_timestamp': summary.finishTimestamp,
      'actual_duration_seconds': summary.actualDurationSeconds,
      'total_distance_km': summary.totalDistanceKm,
      'avg_speed_kmh': summary.avgSpeedKmh,
      'max_speed_kmh': summary.maxSpeedKmh,
      'shareable_image_url': shareableImageUrl,
      'sync_status': 'SYNCED',
    }).select().single();

    // 2. Fetch local breadcrumbs and batch sync
    if (_db != null) {
      final rows = await _db!.query(
        'offline_breadcrumbs',
        where: 'session_id = ?',
        whereArgs: [summary.sessionId],
      );

      if (rows.isNotEmpty) {
        final breadcrumbsPayload = rows.map((r) => {
          'session_id': summary.sessionId,
          'timestamp': r['timestamp'],
          'latitude': r['latitude'],
          'longitude': r['longitude'],
          'altitude': r['altitude'],
          'speed_ms': ((r['speed_kmh'] as num?)?.toDouble() ?? 0.0) / 3.6,
        }).toList();

        await supabase.from('trip_gps_breadcrumbs').insert(breadcrumbsPayload);
      }
    }
  }
}
