// Speech to text for the global search (Android / iOS). The app talks to
// [VoiceInput]; the device implementation wraps `speech_to_text`, and
// [NoVoiceInput] stands in where speech is not supported (desktop, tests).
library;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why speech could not start.
enum VoiceStart { ok, denied, unavailable }

/// Callbacks of one listening session.
class VoiceSession {
  const VoiceSession({
    required this.onWords,
    required this.onDone,
    required this.onError,
  });

  /// Recognised words so far; [isFinal] on the last result.
  final void Function(String words, bool isFinal) onWords;

  /// Listening ended (stopped, timed out or finished).
  final void Function() onDone;

  /// Recognition failed; [permanent] when retrying will not help now.
  final void Function(String code, bool permanent) onError;
}

abstract interface class VoiceInput {
  /// Prepares recognition, asking for microphone / speech permission the
  /// first time.
  Future<VoiceStart> prepare();

  Future<void> listen(VoiceSession s);

  Future<void> stop();
}

/// No speech on this platform.
class NoVoiceInput implements VoiceInput {
  const NoVoiceInput();
  @override
  Future<VoiceStart> prepare() async => VoiceStart.unavailable;
  @override
  Future<void> listen(VoiceSession s) async {}
  @override
  Future<void> stop() async {}
}

/// The device's speech recognition (`speech_to_text`).
class DeviceVoiceInput implements VoiceInput {
  DeviceVoiceInput([SpeechToText? stt]) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  VoiceSession? _session;
  bool _ready = false;

  @override
  Future<VoiceStart> prepare() async {
    if (_ready) return VoiceStart.ok;
    try {
      _ready = await _stt.initialize(
        onError: (SpeechRecognitionError e) =>
            _session?.onError(e.errorMsg, e.permanent),
        onStatus: (String s) {
          if (s == SpeechToText.doneStatus ||
              s == SpeechToText.notListeningStatus) {
            _session?.onDone();
          }
        },
      );
    } catch (_) {
      _ready = false;
    }
    if (_ready) return VoiceStart.ok;
    // Not ready: refused permission, or no recognition service.
    bool allowed = false;
    try {
      allowed = await _stt.hasPermission;
    } catch (_) {
      allowed = false;
    }
    return allowed ? VoiceStart.unavailable : VoiceStart.denied;
  }

  @override
  Future<void> listen(VoiceSession s) async {
    _session = s;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) =>
          s.onWords(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.search,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {
      // Already stopped.
    }
  }
}
