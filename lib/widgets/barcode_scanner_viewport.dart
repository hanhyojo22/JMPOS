import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerViewport extends StatefulWidget {
  const BarcodeScannerViewport({super.key, required this.onDetect});

  final ValueChanged<String> onDetect;

  @override
  State<BarcodeScannerViewport> createState() => _BarcodeScannerViewportState();
}

class _BarcodeScannerViewportState extends State<BarcodeScannerViewport> {
  static const _frameAspectRatio = 300 / 140;
  static const _maxFrameWidth = 300.0;
  static const _horizontalMargin = 40.0;
  static const _accent = Color(0xFF667EEA);

  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = (constraints.maxWidth - _horizontalMargin).clamp(
          0.0,
          _maxFrameWidth,
        );
        final frameHeight = frameWidth / _frameAspectRatio;
        final scanWindow = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
          width: frameWidth,
          height: frameHeight,
        );

        return Stack(
          children: [
            MobileScanner(
              scanWindow: scanWindow,
              onDetect: (capture) {
                if (_scanned) return;
                for (final barcode in capture.barcodes) {
                  final code = barcode.rawValue;
                  if (code == null || code.isEmpty) continue;
                  _scanned = true;
                  widget.onDetect(code);
                  break;
                }
              },
            ),
            Center(
              child: SizedBox(
                width: frameWidth,
                height: frameHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: _accent, width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      for (final alignment in [
                        Alignment.topLeft,
                        Alignment.topRight,
                        Alignment.bottomLeft,
                        Alignment.bottomRight,
                      ])
                        Align(
                          alignment: alignment,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              border: Border(
                                top: alignment.y < 0
                                    ? const BorderSide(color: _accent, width: 4)
                                    : BorderSide.none,
                                bottom: alignment.y > 0
                                    ? const BorderSide(color: _accent, width: 4)
                                    : BorderSide.none,
                                left: alignment.x < 0
                                    ? const BorderSide(color: _accent, width: 4)
                                    : BorderSide.none,
                                right: alignment.x > 0
                                    ? const BorderSide(color: _accent, width: 4)
                                    : BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Align barcode within the frame',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
