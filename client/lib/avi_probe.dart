// CI-only probe (branch ci/emu-avi): plays AVI files with libmpv on the
// Android emulator in a few configurations and prints playback statistics.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const base = String.fromEnvironment(
  'BASE',
  defaultValue: 'http://10.0.2.2:8431',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: Probe()));
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  VideoController? controller;
  String status = 'starting';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(seconds: 3));
    // before: media_kit defaults on Android (mpeg4 in hwdec-codecs, 128 KiB stream buffer)
    await _case('xvid-before', 'xvid.avi', fix: false);
    await _case('xvid-after', 'xvid.avi', fix: true);
    await _case('badint-before', 'badint.avi', fix: false);
    await _case('badint-after', 'badint.avi', fix: true);
    debugPrint('PROBE DONE');
    setState(() => status = 'done');
  }

  Future<void> _case(String name, String file, {required bool fix}) async {
    final p = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    final c = VideoController(
      p,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: 'auto-safe',
      ),
    );
    setState(() {
      controller = c;
      status = name;
    });
    final logs = <String>[];
    final sub = p.stream.log.listen(
      (l) => logs.add('${l.prefix}/${l.level}: ${l.text.trim()}'),
    );
    var buffering = 0;
    final bsub = p.stream.buffering.listen((b) {
      if (b) buffering++;
    });
    await c.platform.future;
    final np = p.platform as NativePlayer;
    Future<void> set(String k, String v) async {
      try {
        await np.setProperty(k, v);
      } catch (e) {
        debugPrint('PROBE set $k failed: $e');
      }
    }

    await set('cache', 'yes');
    await set('cache-secs', '120');
    await set('demuxer-readahead-secs', '60');
    await set('demuxer-max-back-bytes', '${16 * 1024 * 1024}');
    if (fix) {
      await set('hwdec-codecs', 'h264,hevc,mpeg2video,vp8,vp9,av1');
      await set('stream-buffer-size', '${8 * 1024 * 1024}');
    }
    await p.open(Media('$base/$file'));
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(seconds: 30));
    final props = [
      'hwdec-current',
      'time-pos',
      'frame-drop-count',
      'decoder-frame-drop-count',
      'mistimed-frame-count',
      'vo-delayed-frame-count',
      'estimated-vf-fps',
      'container-fps',
      'hwdec-codecs',
      'stream-buffer-size',
    ];
    final m = <String, String>{};
    for (final k in props) {
      try {
        m[k] = await np.getProperty(k);
      } catch (_) {}
    }
    final missing = logs.where((l) => l.contains('missing PTS')).length;
    final ts = logs.where((l) => l.toLowerCase().contains('timestamp')).length;
    debugPrint(
      'PROBE RESULT $name wall=${sw.elapsed.inSeconds}s $m '
      'bufferingEvents=$buffering missingPTS=$missing timestampWarnings=$ts logLines=${logs.length}',
    );
    final seen = <String>{};
    for (final l in logs) {
      if (seen.add(l) && seen.length <= 25) debugPrint('PROBE LOG $name $l');
    }
    await sub.cancel();
    await bsub.cancel();
    setState(() => controller = null);
    await p.dispose();
    await Future.delayed(const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (controller != null)
            Positioned.fill(
              child: Video(controller: controller!, controls: NoVideoControls),
            ),
          Positioned(
            left: 10,
            top: 30,
            child: Text(
              status,
              style: const TextStyle(color: Colors.yellow, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}
