import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/media_controller_service.dart';
import '../services/offline_navigation_service.dart';
import '../services/voice_room_service.dart';
import '../services/trip_tracking_service.dart';
import '../services/shareable_image_service.dart';
import '../services/spatialflow_service.dart';

class TouringCockpitScreen extends StatefulWidget {
  const TouringCockpitScreen({Key? key}) : super(key: key);

  @override
  State<TouringCockpitScreen> createState() => _TouringCockpitScreenState();
}

class _TouringCockpitScreenState extends State<TouringCockpitScreen> {
  final MediaControllerService _mediaService = MediaControllerService();
  final OfflineNavigationService _navService = OfflineNavigationService();
  final VoiceRoomService _voiceService = VoiceRoomService();
  final TripTrackingService _tripService = TripTrackingService();
  final ShareableImageService _imageService = ShareableImageService();
  final SpatialflowService _spatialflowService = SpatialflowService();

  bool _isPermissionGranted = false;
  bool _isRideActive = false;
  bool _isPocketMode = false;
  bool _isVoiceRoomConnected = false;
  bool _isMicMuted = false;

  // Runtime telemetry display (updated via event callbacks)
  double _currentSpeedKmh = 0.0;
  double _distanceKm = 0.0;
  String _formattedDuration = "00:00:00";
  Timer? _uiRefreshTimer; // ONLY runs when screen is ON and ride is active; cancelled in Pocket Mode!

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _navService.initTTS();
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final granted = await _mediaService.isPermissionGranted();
    setState(() {
      _isPermissionGranted = granted;
    });
  }

  void _startRide() async {
    final sessionId = 'ride_${DateTime.now().millisecondsSinceEpoch}';
    await _tripService.startTrip(sessionId);

    // Mock Route Corridor for Demo
    final corridor = [
      const LatLng(-6.200000, 106.816666), // Jakarta
      const LatLng(-6.595038, 106.816635), // Bogor / Puncak
    ];

    final maneuvers = [
      const NavigationManeuver(
        point: LatLng(-6.210000, 106.820000),
        instruction: "Belok kanan ke arah Jalan Raya Puncak",
        distanceToNextManeuverMeters: 500,
        iconCode: "turn_right",
      ),
      const NavigationManeuver(
        point: LatLng(-6.400000, 106.810000),
        instruction: "Tetap lurus di jalur kanan sejauh 15 kilometer",
        distanceToNextManeuverMeters: 15000,
        iconCode: "straight",
      ),
    ];

    await _navService.startNavigation(
      routeCorridor: corridor,
      instructions: maneuvers,
    );

    setState(() {
      _isRideActive = true;
    });

    // Start lightweight UI stopwatch refresh only when screen is on
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isRideActive && !_isPocketMode) {
        // Computed on the fly strictly from system timestamp delta
        final now = DateTime.now().millisecondsSinceEpoch;
        // In real use, computed from tripService
        setState(() {});
      }
    });
  }

  void _finishRide() async {
    _uiRefreshTimer?.cancel();
    await _navService.stopNavigation();
    final summary = await _tripService.finishTrip();

    setState(() {
      _isRideActive = false;
      _isPocketMode = false;
    });

    if (!mounted) return;

    // Show generating summary dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          color: Color(0xFF1E293B),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF06B6D4)),
                SizedBox(height: 16),
                Text(
                  "Menyusun Bukti Touring...",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Generate Shareable Telemetry Graphic Card
    final imageBytes = await _imageService.generateRideSummaryImage(
      summary: summary,
      originName: "Monas, Jakarta",
      destinationName: "Puncak Pass, Bogor",
    );

    Navigator.of(context).pop(); // Dismiss loading

    // Sync to Supabase in background
    _tripService.syncTripToSupabase(
      summary: summary,
      title: "Touring Puncak Sunday Ride",
    );

    // Show completed share preview modal
    _showSummaryModal(summary, imageBytes);
  }

  void _showSummaryModal(TripSummary summary, dynamic imageBytes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text(
              "🏁 PERJALANAN SELESAI",
              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(imageBytes, height: 260, fit: BoxFit.cover),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.share, color: Colors.black),
                    label: const Text("BAGIKAN FOTO", style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      _imageService.shareRideSummaryImage(imageBytes, "Touring Puncak Sunday Ride");
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _togglePocketMode() {
    setState(() {
      _isPocketMode = !_isPocketMode;
      _navService.setPocketMode(_isPocketMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    // If Pocket Mode is active, render ultra-minimal AMOLED Black screen
    if (_isPocketMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: InkWell(
            onDoubleTap: _togglePocketMode,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.screen_lock_portrait, size: 64, color: Color(0xFF334155)),
                  const SizedBox(height: 16),
                  const Text(
                    "POCKET MODE AKTIF",
                    style: TextStyle(color: Color(0xFF64748B), letterSpacing: 3, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Peta & layar dimatikan demi suhu & baterai.\nSuara navigasi & intercom tetap aktif.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF475569), fontSize: 13),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF1E293B)),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      "Ketuk 2x untuk membuka layar",
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.two_wheeler, color: Color(0xFF06B6D4)),
            SizedBox(width: 10),
            Text(
              "MOTO NAV",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          // Spatialflow Integration Button
          IconButton(
            tooltip: "Buka Spatialflow HUD",
            icon: const Icon(Icons.speed, color: Color(0xFFF59E0B)),
            onPressed: () {
              _spatialflowService.launchSpatialflow(targetSpeedLimitKmh: 90.0);
            },
          ),
          // Voice Room Intercom Button
          IconButton(
            tooltip: "Squad Voice Room",
            icon: Icon(
              _isVoiceRoomConnected ? Icons.headset_mic : Icons.headset_off,
              color: _isVoiceRoomConnected ? const Color(0xFF10B981) : Colors.white38,
            ),
            onPressed: () {
              setState(() {
                _isVoiceRoomConnected = !_isVoiceRoomConnected;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Permission Warning Banner if Media Controller is not activated
          if (!_isPermissionGranted)
            GestureDetector(
              onTap: () async {
                await _mediaService.requestPermission();
                await _checkPermissions();
              },
              child: Container(
                color: const Color(0xFFF59E0B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.black, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Aktifkan izin kontrol musik Spotify/Player di sini.",
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.black),
                  ],
                ),
              ),
            ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // 2. Telemetry HUD Card
                  _buildTelemetryHud(),

                  const SizedBox(height: 16),

                  // 3. Universal Media Controller Mini-Player
                  _buildUniversalMediaController(),

                  const SizedBox(height: 16),

                  // 4. Voice Intercom Squad Status (Discord-Like)
                  if (_isVoiceRoomConnected) _buildVoiceIntercomBanner(),

                  const Spacer(),

                  // 5. Pocket Mode Quick Toggle (Crucial for Battery & Heat)
                  if (_isRideActive)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.phone_android),
                        label: const Text(
                          "MASUK POCKET MODE (LAYAR MATI)",
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        onPressed: _togglePocketMode,
                      ),
                    ),

                  // 6. Action Control Bar (Start / Finish Ride)
                  _buildMainRideButton(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryHud() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("STATUS RUTE", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isRideActive ? const Color(0xFF10B981) : Colors.white38,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRideActive ? "OFFLINE CORRIDOR READY" : "STANDBY",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.battery_charging_full, size: 16, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text("ECO-TOURING", style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricColumn("SPEED", "${_currentSpeedKmh.toInt()}", "KM/H", const Color(0xFF38BDF8)),
              _buildMetricColumn("DISTANCE", "${_distanceKm.toStringAsFixed(1)}", "KM", const Color(0xFFF59E0B)),
              _buildMetricColumn("DURATION", _formattedDuration, "", const Color(0xFF10B981)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value, String unit, Color accent) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: TextStyle(color: accent, fontSize: 32, fontWeight: FontWeight.w900)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildUniversalMediaController() {
    return StreamBuilder<MediaTrackInfo>(
      stream: _mediaService.mediaStream,
      builder: (context, snapshot) {
        final track = snapshot.data;
        final hasSession = track != null && track.hasActiveSession;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.music_note, color: Color(0xFF06B6D4)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSession ? track.title : "Tidak Ada Musik Berjalan",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSession ? track.artist : "Buka Spotify/Player lain di HP",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (hasSession) ...[
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white70),
                  onPressed: _mediaService.skipToPrevious,
                ),
                IconButton(
                  icon: Icon(
                    track.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: const Color(0xFF06B6D4),
                    size: 36,
                  ),
                  onPressed: _mediaService.togglePlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white70),
                  onPressed: _mediaService.skipToNext,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceIntercomBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.record_voice_over, color: Color(0xFF10B981)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("SQUAD INTERCOM (VAD ACTIVE)", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                Text("Wind-noise filter aktif • 16kbps Opus", style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_isMicMuted ? Icons.mic_off : Icons.mic, color: _isMicMuted ? Colors.redAccent : Colors.white),
            onPressed: () {
              setState(() {
                _isMicMuted = !_isMicMuted;
                _voiceService.toggleMute();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainRideButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isRideActive ? const Color(0xFFEF4444) : const Color(0xFF06B6D4),
          foregroundColor: _isRideActive ? Colors.white : Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 6,
        ),
        onPressed: _isRideActive ? _finishRide : _startRide,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_isRideActive ? Icons.stop_circle : Icons.navigation, size: 28),
            const SizedBox(width: 10),
            Text(
              _isRideActive ? "FINISH TOURING" : "START TOURING",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
