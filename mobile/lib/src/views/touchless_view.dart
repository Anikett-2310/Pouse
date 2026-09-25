import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../sources/touchless_source.dart';
import '../widgets/shared_utilities_dock.dart';

/// Flutter UI view for V4 Touchless / Invisible Mouse mode.
///
/// Displays real-time camera tracking status, interactive hand skeleton visualization overlay,
/// Touchless sensitivity controls, and unified action dock via [SharedUtilitiesDock].
class TouchlessView extends StatefulWidget {
  final TouchlessSource source;

  const TouchlessView({
    super.key,
    required this.source,
  });

  @override
  State<TouchlessView> createState() => _TouchlessViewState();
}

class _TouchlessViewState extends State<TouchlessView> with WidgetsBindingObserver {
  bool _isUtilityPanelActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.source.activate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      widget.source.deactivate();
    } else {
      widget.source.activate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.source,
      builder: (context, _) {
        final cameraService = widget.source.cameraService;

        return ValueListenableBuilder<String>(
          valueListenable: cameraService.statusNotifier,
          builder: (context, trackingStatus, child) {
            final isHandDetected = trackingStatus == 'HAND_DETECTED';
            final isInitializing = trackingStatus == 'INITIALIZING';
            final isError = trackingStatus == 'CAMERA_ERROR' || trackingStatus == 'PERMISSION_DENIED';
            final errorMsg = cameraService.errorMessageNotifier.value;

            Color statusColor;
            String statusText;

            if (isHandDetected) {
              statusColor = Colors.cyanAccent;
              statusText = 'TOUCHLESS ACTIVE (Hand Detected)';
            } else if (trackingStatus == 'LEFT PINCH') {
              statusColor = Colors.cyanAccent;
              statusText = 'LEFT PINCH';
            } else if (trackingStatus == 'RIGHT PINCH') {
              statusColor = Colors.cyanAccent;
              statusText = 'RIGHT PINCH';
            } else if (trackingStatus == 'DOUBLE CLICK') {
              statusColor = Colors.cyanAccent;
              statusText = 'DOUBLE CLICK';
            } else if (trackingStatus == 'DRAGGING') {
              statusColor = Colors.orangeAccent;
              statusText = 'DRAGGING';
            } else if (trackingStatus == 'PAUSED_TRACKING') {
              statusColor = Colors.purpleAccent;
              statusText = 'TRACKING PAUSED (Closed Fist)';
            } else if (isInitializing) {
              statusColor = Colors.amberAccent;
              statusText = 'INITIALIZING CAMERA...';
            } else if (isError) {
              statusColor = Colors.redAccent;
              statusText = trackingStatus == 'PERMISSION_DENIED'
                  ? 'CAMERA PERMISSION DENIED'
                  : 'CAMERA ERROR: ${errorMsg.isNotEmpty ? errorMsg : "Check Camera Permissions"}';
            } else {
              statusColor = Colors.amberAccent;
              statusText = 'SEARCHING FOR HAND (Position Hand in View)';
            }

            return Column(
              children: [
                // Status Badge Header
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                          boxShadow: isHandDetected
                              ? [
                                  BoxShadow(
                                    color: statusColor,
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: statusColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Complete Un-truncated Error Diagnostic Panel
                if (isError && errorMsg.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxHeight: 140),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1515),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent, width: 1.5),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        errorMsg,
                        style: const TextStyle(
                          color: Color(0xFFFF8A8A),
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),

                // Main Constrained Touchless Camera Surface & Skeleton Visualizer
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Center(
                      child: SizedBox(
                        width: double.infinity,
                        height: 220,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16161D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isHandDetected
                                  ? Colors.cyanAccent.withValues(alpha: 0.4)
                                  : Colors.white12,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Live Native CameraX Preview & Native Hand Skeleton Overlay (Android) or Fallback Placeholder
                                if (defaultTargetPlatform == TargetPlatform.android)
                                  const SizedBox(
                                    width: double.infinity,
                                    height: 220,
                                    child: AndroidView(
                                      viewType: 'pouse/touchless_camera_preview',
                                      layoutDirection: TextDirection.ltr,
                                      creationParamsCodec: StandardMessageCodec(),
                                    ),
                                  )
                                else ...[
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.videocam_outlined,
                                          size: 48,
                                          color: isHandDetected ? Colors.cyanAccent : Colors.white24,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          isHandDetected
                                              ? 'Move Hand in Camera View to Control Cursor'
                                              : 'Place phone on desk stand facing your hand',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isHandDetected ? Colors.white : Colors.white54,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Front-facing selfie camera tracks index fingertip in real-time',
                                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Fallback Skeleton Overlay Painter for Non-Android platforms
                                  ValueListenableBuilder<List<Offset>>(
                                    valueListenable: cameraService.landmarksNotifier,
                                    builder: (context, landmarks, _) {
                                      if (landmarks.isEmpty) return const SizedBox.shrink();
                                      return CustomPaint(
                                        size: Size.infinite,
                                        painter: HandSkeletonPainter(landmarks: landmarks),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Touchless Settings Controls (Collapses when Utility panel active)
                if (!_isUtilityPanelActive) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    margin: const EdgeInsets.only(top: 4),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Pointer Sensitivity
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Pointer Sensitivity',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              Text(
                                '${widget.source.sensitivity.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: Colors.cyanAccent,
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.cyanAccent,
                              overlayColor: Colors.cyanAccent.withValues(alpha: 0.2),
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                            ),
                            child: Slider(
                              value: widget.source.sensitivity,
                              min: 0.5,
                              max: 3.0,
                              divisions: 25,
                              onChanged: (val) {
                                widget.source.setSensitivity(val);
                              },
                              onChangeEnd: (val) {
                                widget.source.saveSensitivity(val);
                              },
                            ),
                          ),

                          // Touchless Scroll Sensitivity
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Touchless Scroll Sensitivity',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              Text(
                                '${widget.source.touchlessScrollSensitivity.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: Colors.cyanAccent,
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.cyanAccent,
                              overlayColor: Colors.cyanAccent.withValues(alpha: 0.2),
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                            ),
                            child: Slider(
                              value: widget.source.touchlessScrollSensitivity,
                              min: 0.2,
                              max: 2.0,
                              divisions: 18,
                              onChanged: (val) {
                                widget.source.setTouchlessScrollSensitivity(val);
                              },
                              onChangeEnd: (val) {
                                widget.source.saveTouchlessScrollSensitivity(val);
                              },
                            ),
                          ),

                          // 2-Finger Horizontal Mode Selector
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '2-Finger Horizontal',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => widget.source.setHorizontalMode('browser'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: widget.source.horizontalMode == 'browser'
                                            ? Colors.cyanAccent.withValues(alpha: 0.2)
                                            : Colors.white10,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: widget.source.horizontalMode == 'browser'
                                              ? Colors.cyanAccent
                                              : Colors.transparent,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        'Browser',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: widget.source.horizontalMode == 'browser'
                                              ? Colors.cyanAccent
                                              : Colors.white60,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => widget.source.setHorizontalMode('presentation'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: widget.source.horizontalMode == 'presentation'
                                            ? Colors.orangeAccent.withValues(alpha: 0.2)
                                            : Colors.white10,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: widget.source.horizontalMode == 'presentation'
                                              ? Colors.orangeAccent
                                              : Colors.transparent,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        'Presentation',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: widget.source.horizontalMode == 'presentation'
                                              ? Colors.orangeAccent
                                              : Colors.white60,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Action Dock (Keyboard, Gaming, OS Actions)
                SharedUtilitiesDock(
                  transport: widget.source.transport,
                  onLeftClick: () => widget.source.transport.sendLeftClick(),
                  onRightClick: () => widget.source.transport.sendRightClick(),
                  onPanelStateChanged: (isActive) {
                    setState(() {
                      _isUtilityPanelActive = isActive;
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Custom painter rendering MediaPipe 21-landmark hand skeleton.
class HandSkeletonPainter extends CustomPainter {
  final List<Offset> landmarks;

  HandSkeletonPainter({required this.landmarks});

  static const List<List<int>> connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // Index
    [5, 9], [9, 10], [10, 11], [11, 12], // Middle
    [9, 13], [13, 14], [14, 15], [15, 16], // Ring
    [13, 17], [17, 18], [18, 19], [19, 20], // Pinky
    [0, 17] // Palm base
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.length < 21) return;

    final linePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final tipPaint = Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.fill;

    // Draw skeleton bones
    for (final conn in connections) {
      final p1 = Offset(landmarks[conn[0]].dx * size.width, landmarks[conn[0]].dy * size.height);
      final p2 = Offset(landmarks[conn[1]].dx * size.width, landmarks[conn[1]].dy * size.height);
      canvas.drawLine(p1, p2, linePaint);
    }

    // Draw joints
    for (int i = 0; i < landmarks.length; i++) {
      final p = Offset(landmarks[i].dx * size.width, landmarks[i].dy * size.height);
      if (i == 8) {
        // Highlight Index Tip (Landmark 8) used for pointer tracking
        canvas.drawCircle(p, 6.0, tipPaint);
      } else {
        canvas.drawCircle(p, 3.5, jointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HandSkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks;
  }
}
