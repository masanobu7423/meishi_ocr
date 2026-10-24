import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'ocr/capture_guide.dart';

/// In-app camera with a business-card framing guide. Pops with the captured
/// file path, or null when cancelled.
// ponytail: no crop to the guide yet. CameraX stills can have a different
// aspect than the preview, so a naive crop would cut text; ML Kit copes with
// the desk background anyway (see golden 2xx).
class CaptureScreen extends StatefulWidget {
  final String label;
  const CaptureScreen({super.key, required this.label});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _ctl;
  String? _error;
  bool _shooting = false;

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
      if (mounted) Navigator.pop(context, x.path);
    } catch (e) {
      setState(() {
        _shooting = false;
        _error = '撮影に失敗: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('${widget.label}を撮影'), backgroundColor: Colors.black54),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : _ctl == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_ctl!),
                    CustomPaint(painter: _GuidePainter()),
                    const Align(
                      alignment: Alignment(0, -0.8),
                      child: Text(
                        '名刺を枠に合わせる　影と反射を避ける　水平に',
                        style: TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)]),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, 0.85),
                      child: FloatingActionButton.large(
                        onPressed: _shooting ? null : _shoot,
                        child: Icon(_shooting ? Icons.hourglass_top : Icons.camera_alt),
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
