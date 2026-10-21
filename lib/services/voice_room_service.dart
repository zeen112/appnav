import 'dart:async';
import 'package:livekit_client/livekit_client.dart';

class VoiceRoomService {
  static final VoiceRoomService _instance = VoiceRoomService._internal();
  factory VoiceRoomService() => _instance;
  VoiceRoomService._internal();

  Room? _room;
  LocalAudioTrack? _audioTrack;
  bool _isConnected = false;
  bool _isMicMuted = false;

  bool get isConnected => _isConnected;
  bool get isMicMuted => _isMicMuted;

  StreamController<List<Participant>> _participantsController = StreamController.broadcast();
  Stream<List<Participant>> get participantsStream => _participantsController.stream;

  /// Connect to Touring Voice Room (Discord-like hands-free squad intercom)
  Future<void> connectToRoom({
    required String liveKitUrl,
    required String token,
  }) async {
    try {
      // 1. Configure Room with SFU Audio optimization
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            // Low-bitrate Opus for extreme quota & battery savings
            audioBitrate: 16000, // 16 kbps Opus
            dtx: true,           // Discontinuous Transmission (Zero upload when silent)
          ),
        ),
      );

      // Setup room listeners
      _room?.addListener(_onRoomUpdate);

      // 2. Connect to LiveKit SFU server
      await _room?.connect(liveKitUrl, token);
      _isConnected = true;

      // 3. Setup Hands-Free Microphone with Hardware VAD & Wind Noise Suppression
      await _enableHandsFreeMicrophone();

    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// Configures microphone capture with DSP filters for motorcycle touring:
  /// - Highpass filter: cuts engine low rumble (< 100Hz)
  /// - Noise suppression: reduces aerodynamic wind noise
  /// - Echo cancellation: prevents helmet speaker feedback
  Future<void> _enableHandsFreeMicrophone() async {
    final audioOptions = AudioCaptureOptions(
      autoGainControl: true,
      echoCancellation: true,
      noiseSuppression: true,
      highpassFilter: true, // Crucial for motorcycle engine vibration suppression
    );

    _audioTrack = await LocalAudioTrack.create(audioOptions);
    
    // Publish track to the squad room with DTX active
    await _room?.localParticipant?.publishAudioTrack(
      _audioTrack!,
      publishOptions: const AudioPublishOptions(
        audioBitrate: 16000,
        dtx: true, // VAD: WebRTC stops sending packets when no human speech is detected
      ),
    );
  }

  /// Toggle Microphone Mute/Unmute
  Future<void> toggleMute() async {
    if (_audioTrack == null) return;
    _isMicMuted = !_isMicMuted;
    if (_isMicMuted) {
      await _audioTrack?.mute();
    } else {
      await _audioTrack?.unmute();
    }
  }

  /// Disconnect from Voice Room
  Future<void> disconnect() async {
    await _audioTrack?.stop();
    await _audioTrack?.dispose();
    _audioTrack = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
    _isConnected = false;
  }

  void _onRoomUpdate() {
    if (_room == null) return;
    final allParticipants = <Participant>[];
    if (_room!.localParticipant != null) {
      allParticipants.add(_room!.localParticipant!);
    }
    allParticipants.addAll(_room!.remoteParticipants.values);
    _participantsController.add(allParticipants);
  }
}
