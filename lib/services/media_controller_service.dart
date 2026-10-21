import 'dart:async';
import 'package:flutter/services.dart';

class MediaTrackInfo {
  final bool hasActiveSession;
  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final int duration;
  final int position;
  final String packageName;

  const MediaTrackInfo({
    required this.hasActiveSession,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.isPlaying = false,
    this.duration = 0,
    this.position = 0,
    this.packageName = '',
  });

  factory MediaTrackInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null || map['hasActiveSession'] != true) {
      return const MediaTrackInfo(hasActiveSession: false);
    }
    return MediaTrackInfo(
      hasActiveSession: true,
      title: map['title'] ?? 'Unknown Track',
      artist: map['artist'] ?? 'Unknown Artist',
      album: map['album'] ?? '',
      isPlaying: map['isPlaying'] == true,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      position: (map['position'] as num?)?.toInt() ?? 0,
      packageName: map['packageName'] ?? '',
    );
  }
}

class MediaControllerService {
  static const MethodChannel _methodChannel = MethodChannel('com.mototouring.nav/media_controller');
  static const EventChannel _eventChannel = EventChannel('com.mototouring.nav/media_events');

  static final MediaControllerService _instance = MediaControllerService._internal();
  factory MediaControllerService() => _instance;
  MediaControllerService._internal();

  Stream<MediaTrackInfo>? _mediaStream;

  /// Stream of active media track metadata and playback states from Spotify, YouTube Music, etc.
  Stream<MediaTrackInfo> get mediaStream {
    _mediaStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => MediaTrackInfo.fromMap(event as Map<dynamic, dynamic>?));
    return _mediaStream!;
  }

  /// Check if Android Notification Listener permission is granted
  Future<bool> isPermissionGranted() async {
    try {
      final bool? granted = await _methodChannel.invokeMethod<bool>('isPermissionGranted');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open Android OS settings to grant Notification Listener access
  Future<void> requestPermission() async {
    await _methodChannel.invokeMethod('requestPermission');
  }

  /// Universal Play command
  Future<void> play() async {
    await _methodChannel.invokeMethod('play');
  }

  /// Universal Pause command
  Future<void> pause() async {
    await _methodChannel.invokeMethod('pause');
  }

  /// Toggle Play/Pause
  Future<void> togglePlayPause() async {
    await _methodChannel.invokeMethod('togglePlayPause');
  }

  /// Skip to Next track
  Future<void> skipToNext() async {
    await _methodChannel.invokeMethod('skipToNext');
  }

  /// Skip to Previous track
  Future<void> skipToPrevious() async {
    await _methodChannel.invokeMethod('skipToPrevious');
  }
}
