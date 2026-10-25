import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'ocr/auto_shutter.dart';
import 'ocr/burst.dart';
import 'ocr/capture_guide.dart';
import 'ocr/crop.dart';
import 'theme.dart';

/// In-app camera with a business-card framing guide.
///
/// Single shot (no [burst]): pops with the captured file path, or null when
/// cancelled. Burst ([burst] set): stays open, says which side is next,
/// hands every capture to [onPage] (inbox name included), offers 白地で保管
/// while a back is expected and 撮影を終了 between cards; pops when ended.
// ponytail: no crop to the guide yet. CameraX stills can have a different
// aspect than the preview, so a naive crop would cut text; ML Kit copes with
// the desk background anyway (see golden 2xx).
class CaptureScreen extends StatefulWidget {
  final String label;
  final BurstSession? burst;
  final Future<void> Function(String path, String name)? onPage;
  final Future<void> Function(String stem)? onBlank;
  /// Debug builds append the auto-shutter numbers here once a second, so
  /// the thresholds can be tuned from a real desk without watching the screen.
  final File? statsLog;
  const CaptureScreen(
      {super.key, required this.label, this.burst, this.onPage, this.onBlank, this.statsLog});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _ctl;
  String? _error;
  bool _shooting = false;
  // Burst auto-capture: the preview frames are sampled every third frame;
  // a still, bright, textured card fires the shutter.
  bool _auto = true;
  final _sampler = FrameSampler();
  final _shutter = AutoShutter();
  int _frame = 0;
  double _progress = 0;
  FrameStats? _stats; // shown in debug builds to tune the thresholds
  Size? _previewBox; // the preview's on-screen size: the guide is drawn in it
  List<QuadPoint>? _quad; // detected card corners in preview-box coordinates, smoothed
  int _rotation = 90; // frame -> preview rotation, set once the camera is known

  BurstSession? get _burst => widget.burst;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final ctl = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await ctl.initialize();
      if (!mounted) return;
      // ponytail: portrait use is what the guide is drawn for; the sensor is
      // landscape, rotated by its own orientation. Landscape phones get 0.
      _rotation = MediaQuery.orientationOf(context) == Orientation.portrait
          ? back.sensorOrientation % 360
          : 0;
      await ctl.startImageStream(_onFrame);
      setState(() => _ctl = ctl);
    } catch (e) {
      setState(() => _error = 'カメラを開けません: $e');
    }
  }

  @override
  void dispose() {
    final ctl = _ctl;
    if (ctl != null && ctl.value.isStreamingImages) ctl.stopImageStream();
    ctl?.dispose();
    super.dispose();
  }

  void _onFrame(CameraImage img) {
    if (_shooting || ++_frame % 3 != 0) return;
    final p = img.planes[0];
    final stats = _sampler.sample(p.bytes, img.width, img.height, rowStride: p.bytesPerRow);
    // The frame that follows the card: detected corners mapped into the
    // preview box and smoothed so the overlay does not jitter.
    final raw = stats.quad?.map((q) => frameToView(q, rotation: _rotation)).toList();
    final prev = _quad;
    final quad = raw == null
        ? null
        : prev == null
            ? raw
            : [for (var i = 0; i < 4; i++) (x: (prev[i].x + raw[i].x) / 2, y: (prev[i].y + raw[i].y) / 2)];
    if (mounted && (quad != null || prev != null)) setState(() => _quad = quad);
    if (!_auto || _burst == null) return;
    final fire = _shutter.feed(stats, DateTime.now());
    if (kDebugMode && widget.statsLog != null && _frame % 30 == 0) {
      widget.statsLog!.parent.createSync(recursive: true);
      widget.statsLog!.writeAsString(
          '${DateTime.now().toIso8601String()} c=${stats.center.toStringAsFixed(0)} '
          'b=${stats.border.toStringAsFixed(0)} e=${stats.edges.toStringAsFixed(1)} '
          'm=${stats.motion.toStringAsFixed(1)} s=${stats.shift.toStringAsFixed(3)} '
          'q=${stats.quad == null ? "-" : "y"} p=${_shutter.progress.toStringAsFixed(2)} '
          '${img.width}x${img.height} stride=${p.bytesPerRow}\n',
          mode: FileMode.append);
    }
    if (mounted && (kDebugMode || _shutter.progress != _progress)) {
      setState(() {
        _progress = _shutter.progress;
        _stats = stats;
      });
    }
    if (fire) _shoot();
  }

  Future<void> _shoot() async {
    if (_ctl == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      final x = await _ctl!.takePicture();
      // Auto frame: straighten the detected card; else keep the guide area.
      final box = _previewBox;
      final quad = _quad;
      final shot = box == null
          ? File(x.path)
          : quad != null
              ? await rectifyToQuad(File(x.path), quad, box)
              : await cropToGuide(File(x.path), box);
      if (!mounted) return;
      final b = _burst;
      if (b == null) {
        Navigator.pop(context, shot.path);
        return;
      }
      await widget.onPage!(shot.path, b.nextName(DateTime.now()));
      if (mounted) setState(() => _shooting = false);
    } catch (e) {
      setState(() {
        _shooting = false;
        _error = '撮影に失敗: $e';
      });
    }
  }

  Future<void> _blank() async {
    final stem = _burst?.blankStem();
    if (stem == null) return;
    await widget.onBlank!(stem);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final b = _burst;
    final title = b == null ? '${widget.label}を撮影' : b.title;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black54,
        actions: [
          if (b != null && b.canFinish)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, b),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('撮影を終了'),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : _ctl == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // Preview and guide share one box, so the guide maps
                    // 1:1 onto the still for the crop.
                    Center(
                      child: AspectRatio(
                        aspectRatio: MediaQuery.orientationOf(context) == Orientation.portrait
                            ? 1 / _ctl!.value.aspectRatio
                            : _ctl!.value.aspectRatio,
                        child: LayoutBuilder(builder: (_, c) {
                          _previewBox = c.biggest;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(_ctl!),
                              CustomPaint(painter: _GuidePainter()),
                              if (_quad != null) CustomPaint(painter: _QuadPainter(_quad!)),
                            ],
                          );
                        }),
                      ),
                    ),
                    if (b != null)
                      Align(
                        alignment: const Alignment(0, -0.95),
                        child: SegmentedButton<bool>(
                          style: SegmentedButton.styleFrom(
                              backgroundColor: Colors.black45, foregroundColor: Colors.white),
                          segments: const [
                            ButtonSegment(value: true, label: Text('自動撮影')),
                            ButtonSegment(value: false, label: Text('手動')),
                          ],
                          selected: {_auto},
                          onSelectionChanged: (s) => setState(() {
                            _auto = s.first;
                            _progress = 0;
                          }),
                        ),
                      ),
                    Align(
                      alignment: const Alignment(0, -0.75),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            b == null
                                ? '名刺を枠に合わせる　影と反射を避ける　水平に'
                                : b.side == CardSide.front
                                    ? '表面を枠に合わせる　${b.cards} 枚保存済み'
                                    : '裏面を枠に合わせる　印字がなければ「白地で保管」',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)]),
                          ),
                          if (b != null && _auto)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.unit),
                              child: Text(
                                _progress > 0
                                    ? '動かさないでください…'
                                    : _quad != null
                                        ? '名刺を検出しました　止めると自動で撮ります'
                                        : '名刺を枠に入れると自動で撮ります',
                                style: const TextStyle(
                                    color: Colors.amber, fontSize: 14, shadows: [Shadow(blurRadius: 4)]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, 0.85),
                      child: FloatingActionButton.large(
                        onPressed: _shooting ? null : _shoot,
                        child: Icon(_shooting ? Icons.hourglass_top : Icons.camera_alt),
                      ),
                    ),
                    if (kDebugMode && b != null && _stats != null)
                      Align(
                        alignment: const Alignment(-0.95, 0.6),
                        child: Semantics(
                          label: 'auto-shutter stats',
                          child: Text(
                            'c=${_stats!.center.toStringAsFixed(0)} b=${_stats!.border.toStringAsFixed(0)} '
                            'e=${_stats!.edges.toStringAsFixed(1)} m=${_stats!.motion.toStringAsFixed(1)} '
                            's=${_stats!.shift.toStringAsFixed(3)} p=${_progress.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ),
                    if (b != null && b.side == CardSide.back)
                      Align(
                        alignment: const Alignment(0.85, 0.85),
                        child: FilledButton.tonalIcon(
                          onPressed: _shooting ? null : _blank,
                          icon: const Icon(Icons.crop_portrait, size: AppSize.iconSmall),
                          label: const Text('白地で保管'),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// The frame that follows the detected card.
class _QuadPainter extends CustomPainter {
  final List<QuadPoint> quad;
  _QuadPainter(this.quad);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(quad[0].x * size.width, quad[0].y * size.height);
    for (final q in quad.skip(1)) {
      path.lineTo(q.x * size.width, q.y * size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.lightGreenAccent.withValues(alpha: 0.18));
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.lightGreenAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.quad != quad;
}

/// Dims everything outside the 91:55 guide and draws its outline + corners.
class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = guideRect(size);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
    canvas.drawPath(
      Path.combine(PathOperation.difference,
          Path()..addRect(Offset.zero & size), Path()..addRRect(rr)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(rr, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final corner = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    const l = 28.0;
    for (final (dx, dy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
      final x = dx > 0 ? r.left : r.right;
      final y = dy > 0 ? r.top : r.bottom;
      canvas.drawLine(Offset(x, y), Offset(x + dx * l, y), corner);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * l), corner);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => false;
}
