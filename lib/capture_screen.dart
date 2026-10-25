import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'ocr/burst.dart';
import 'ocr/capture_guide.dart';
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
  const CaptureScreen({super.key, required this.label, this.burst, this.onPage, this.onBlank});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _ctl;
  String? _error;
  bool _shooting = false;

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
      final ctl = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await ctl.initialize();
      if (!mounted) return;
      setState(() => _ctl = ctl);
    } catch (e) {
      setState(() => _error = 'カメラを開けません: $e');
    }
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    if (_ctl == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      final x = await _ctl!.takePicture();
      if (!mounted) return;
      final b = _burst;
      if (b == null) {
        Navigator.pop(context, x.path);
        return;
      }
      await widget.onPage!(x.path, b.nextName(DateTime.now()));
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
                    CameraPreview(_ctl!),
                    CustomPaint(painter: _GuidePainter()),
                    Align(
                      alignment: const Alignment(0, -0.8),
                      child: Text(
                        b == null
                            ? '名刺を枠に合わせる　影と反射を避ける　水平に'
                            : b.side == CardSide.front
                                ? '表面を枠に合わせる　${b.cards} 枚保存済み'
                                : '裏面を枠に合わせる　印字がなければ「白地で保管」',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)]),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, 0.85),
                      child: FloatingActionButton.large(
                        onPressed: _shooting ? null : _shoot,
                        child: Icon(_shooting ? Icons.hourglass_top : Icons.camera_alt),
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
