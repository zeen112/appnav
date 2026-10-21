import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'trip_tracking_service.dart';

class ShareableImageService {
  static final ShareableImageService _instance = ShareableImageService._internal();
  factory ShareableImageService() => _instance;
  ShareableImageService._internal();

  /// Formats seconds into HH:MM:SS or MM:SS
  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// High-performance Canvas rendering of the telemetry card + GPS route polyline
  Future<Uint8List> generateRideSummaryImage({
    required TripSummary summary,
    required String originName,
    required String destinationName,
  }) async {
    const double width = 1080;
    const double height = 1350; // Optimized 4:5 aspect ratio for Instagram / WhatsApp

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // 1. Dark Futuristic Touring Background
    final bgPaint = Paint()..color = const Color(0xFF0F172A); // Dark Slate 900
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Decorative gradient accent bar
    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(width, 0),
        [const Color(0xFF06B6D4), const Color(0xFFF59E0B), const Color(0xFF10B981)],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, 12), gradientPaint);

    // 2. Header: App Branding & Date
    _drawText(canvas, 'MOTO-TOURING HUD', const Offset(60, 60),
        fontSize: 34, fontWeight: FontWeight.w900, color: const Color(0xFF38BDF8), letterSpacing: 3.0);

    final dateStr = DateTime.fromMillisecondsSinceEpoch(summary.startTimestamp).toLocal().toString().substring(0, 16);
    _drawText(canvas, 'RIDE TELEMETRY RECORD • $dateStr', const Offset(60, 110),
        fontSize: 22, fontWeight: FontWeight.w500, color: const Color(0xFF94A3B8));

    // 3. Map Viewport Box & Polyline Simulation
    final mapRect = Rect.fromLTWH(60, 170, width - 120, 560);
    final mapBoxPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(mapRect, const Radius.circular(24)), mapBoxPaint);

    // Border for map
    final mapBorderPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(RRect.fromRectAndRadius(mapRect, const Radius.circular(24)), mapBorderPaint);

    // Draw GPS Polyline
    _drawPolyline(canvas, mapRect, summary.polylinePoints);

    // 4. Origin & Destination Route Card
    final routeCardRect = Rect.fromLTWH(60, 760, width - 120, 150);
    final routeCardPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRRect(RRect.fromRectAndRadius(routeCardRect, const Radius.circular(20)), routeCardPaint);

    _drawText(canvas, 'ORIGIN', const Offset(100, 790), fontSize: 18, color: const Color(0xFF64748B), fontWeight: FontWeight.bold);
    _drawText(canvas, originName, const Offset(100, 820), fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold);

    _drawText(canvas, '➔', const Offset(520, 810), fontSize: 40, color: const Color(0xFF06B6D4), fontWeight: FontWeight.bold);

    _drawText(canvas, 'DESTINATION', const Offset(600, 790), fontSize: 18, color: const Color(0xFF64748B), fontWeight: FontWeight.bold);
    _drawText(canvas, destinationName, const Offset(600, 820), fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold);

    // 5. Telemetry Metrics Grid (Duration, Distance, Avg Speed, Top Speed)
    final metricsY = 940.0;
    final colWidth = (width - 120) / 3;

    // Col 1: Actual Duration (Strict Unix Delta)
    _drawMetricBox(canvas, Rect.fromLTWH(60, metricsY, colWidth - 15, 170),
        'ACTUAL DURATION', _formatDuration(summary.actualDurationSeconds), const Color(0xFF10B981));

    // Col 2: Total Distance
    _drawMetricBox(canvas, Rect.fromLTWH(60 + colWidth, metricsY, colWidth - 15, 170),
        'TOTAL DISTANCE', '${summary.totalDistanceKm} KM', const Color(0xFF38BDF8));

    // Col 3: Average Speed
    _drawMetricBox(canvas, Rect.fromLTWH(60 + colWidth * 2, metricsY, colWidth - 15, 170),
        'AVG SPEED', '${summary.avgSpeedKmh} KM/H', const Color(0xFFF59E0B));

    // Col 4 (Footer banner): Top Hardware Speed
    final footerRect = Rect.fromLTWH(60, 1140, width - 120, 120);
    final footerPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRRect(RRect.fromRectAndRadius(footerRect, const Radius.circular(16)), footerPaint);

    _drawText(canvas, 'MAX GPS SPEED RECORDED', const Offset(100, 1165), fontSize: 20, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600);
    _drawText(canvas, '${summary.maxSpeedKmh} km/h', const Offset(100, 1200), fontSize: 36, color: const Color(0xFFEF4444), fontWeight: FontWeight.bold);

    // Watermark
    _drawText(canvas, 'VERIFIED BY HARDWARE GPS • BATTERY OPTIMIZED TOURING', const Offset(60, 1290),
        fontSize: 18, color: const Color(0xFF475569), fontWeight: FontWeight.w500);

    // Convert to Image
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _drawMetricBox(Canvas canvas, Rect rect, String label, String value, Color accentColor) {
    final bgPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), bgPaint);

    _drawText(canvas, label, Offset(rect.left + 24, rect.top + 28),
        fontSize: 18, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600);

    _drawText(canvas, value, Offset(rect.left + 24, rect.top + 75),
        fontSize: 40, color: accentColor, fontWeight: FontWeight.w900);
  }

  void _drawPolyline(Canvas canvas, Rect bounds, List<LatLng> points) {
    if (points.length < 2) return;

    double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latRange = (maxLat - minLat).abs().clamp(0.001, 180.0);
    final lngRange = (maxLng - minLng).abs().clamp(0.001, 360.0);

    final path = Path();
    final padding = 40.0;
    final innerW = bounds.width - (padding * 2);
    final innerH = bounds.height - (padding * 2);

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final normX = (p.longitude - minLng) / lngRange;
      final normY = 1.0 - ((p.latitude - minLat) / latRange); // Invert Y

      final px = bounds.left + padding + (normX * innerW);
      final py = bounds.top + padding + (normY * innerH);

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    // Glow effect
    final glowPaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    // Primary polyline
    final linePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  void _drawText(Canvas canvas, String text, Offset offset, {
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.normal,
    double letterSpacing = 0.0,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  /// Save PNG locally and trigger the native Android Share sheet
  Future<void> shareRideSummaryImage(Uint8List imageBytes, String title) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/ride_summary_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(imageBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Ride Telemetry: $title. Generated with Moto Touring Nav.',
    );
  }

  /// Upload the shareable card to Supabase Storage bucket ('trip_shares')
  Future<String?> uploadToSupabaseStorage(Uint8List imageBytes, String sessionId) async {
    try {
      final supabase = Supabase.instance.client;
      final filePath = 'summaries/$sessionId.png';

      await supabase.storage.from('trip_shares').uploadBinary(
        filePath,
        imageBytes,
        fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
      );

      final publicUrl = supabase.storage.from('trip_shares').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      return null;
    }
  }
}
