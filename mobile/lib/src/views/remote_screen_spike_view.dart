import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/remote_screen_coordinate_mapper.dart';
import '../websocket_service.dart';

/// Spike 3 — Remote Screen Touch + Control View
///
/// Implements live Remote Screen video decoding alongside touch-to-cursor control.
///
/// Touch interactions:
/// - Single-finger touch/move -> ABS_MOVE (normalized x,y in [0.0, 1.0])
/// - Single-finger tap -> LEFT_CLICK
/// - Single-finger double-tap -> DOUBLE_CLICK
/// - Two-finger tap -> RIGHT_CLICK
/// - Touch drag -> BUTTON_DOWN('left') -> ABS_MOVE stream -> BUTTON_UP('left')
/// - Touches in letterbox/pillarbox padding are strictly ignored.
class RemoteScreenSpikeView extends StatefulWidget {
  const RemoteScreenSpikeView({super.key});

  @override
  State<RemoteScreenSpikeView> createState() => _RemoteScreenSpikeViewState();
}

class _RemoteScreenSpikeViewState extends State<RemoteScreenSpikeView> {
  static const _methodChannel = MethodChannel('pouse/remote_screen/method');
  static const _eventChannel = EventChannel('pouse/remote_screen/events');

  final TextEditingController _hostController = TextEditingController(text: '192.168.1.10');
  final TextEditingController _portController = TextEditingController(text: '8081');

  final WebSocketService _controlWs = WebSocketService();

  StreamSubscription? _metricsSub;

  String _videoState = 'UNINITIALIZED';
  double _wsRxFps = 0.0;
  double _decoderFps = 0.0;
  int _rxCount = 0;
  int _decodedCount = 0;
  int _droppedCount = 0;
  int _timeToFirstFrameMs = -1;
  int _timeFromForcedIdrMs = -1;
  String _lastError = '';

  // Captured monitor dimensions (defaults to 1280x720)
  int _capturedWidth = 1280;
  int _capturedHeight = 720;
  RemoteScreenCoordinateMapper get _mapper => RemoteScreenCoordinateMapper(width: _capturedWidth, height: _capturedHeight);

  // Touch & Control metrics
  double? _lastAbsX;
  double? _lastAbsY;
  int _absMoveCount = 0;
  String _lastGesture = 'None';
  bool _isOutsideTouch = false;

  // Touch gesture state machine
  int _pointerCount = 0;
  int _maxPointerCount = 0;
  final Map<int, Offset> _pointerPositions = {};
  final Map<int, Offset> _initialPositions = {};

  bool _isDragging = false;
  bool _isLeftButtonHeld = false;

  DateTime? _lastTapUpTime;
  Offset? _lastTapUpPos;
  Timer? _singleTapTimer;

  static const double _touchSlop = 6.0;
  static const int _doubleTapTimeoutMs = 300;
  static const int _singleTapDelayMs = 200;

  @override
  void initState() {
    super.initState();
    _listenMetrics();
  }

  void _listenMetrics() {
    _metricsSub = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        setState(() {
          _videoState = event['state']?.toString() ?? 'UNKNOWN';
          _wsRxFps = (event['wsReceivedFps'] as num?)?.toDouble() ?? 0.0;
          _decoderFps = (event['decoderOutputFps'] as num?)?.toDouble() ?? 0.0;
          _rxCount = (event['framesReceived'] as num?)?.toInt() ?? 0;
          _decodedCount = (event['framesDecoded'] as num?)?.toInt() ?? 0;
          _droppedCount = (event['framesDropped'] as num?)?.toInt() ?? 0;
          _timeToFirstFrameMs = (event['timeToFirstDecodedFrameMs'] as num?)?.toInt() ?? -1;
          _timeFromForcedIdrMs = (event['timeFromForcedIdrMs'] as num?)?.toInt() ?? -1;
          if (event['width'] != null && (event['width'] as num).toInt() > 0) {
            _capturedWidth = (event['width'] as num).toInt();
          }
          if (event['height'] != null && (event['height'] as num).toInt() > 0) {
            _capturedHeight = (event['height'] as num).toInt();
          }
          _lastError = event['lastError']?.toString() ?? '';
        });
      }
    }, onError: (err) {
      debugPrint('[SPIKE 3] Error receiving metrics: $err');
    });
  }

  Future<void> _startSession() async {
    try {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 8081;

      // Connect control WebSocket (/ path on same port)
      if (!_controlWs.isConnected) {
        await _controlWs.connect(host, port: port);
      }

      // Start Android decoder (/screen path)
      await _methodChannel.invokeMethod('start', {'host': host, 'port': port});
    } catch (e) {
      debugPrint('[SPIKE 3] Error starting session: $e');
    }
  }

  Future<void> _stopSession() async {
    try {
      _controlWs.releaseAll();
      await _controlWs.disconnect();
      await _methodChannel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[SPIKE 3] Error stopping session: $e');
    }
  }

  Future<void> _requestForcedIdr() async {
    try {
      await _methodChannel.invokeMethod('requestForcedIdr');
    } catch (e) {
      debugPrint('[SPIKE 3] Error requesting IDR: $e');
    }
  }

  Future<void> _resetDecoder() async {
    try {
      await _methodChannel.invokeMethod('resetDecoder');
    } catch (e) {
      debugPrint('[SPIKE 3] Error resetting decoder: $e');
    }
  }

  @override
  void dispose() {
    _controlWs.releaseAll();
    _controlWs.dispose();
    _metricsSub?.cancel();
    _singleTapTimer?.cancel();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _sendAbsMove(double x, double y) {
    _controlWs.sendAbsMove(x, y);
    setState(() {
      _lastAbsX = x;
      _lastAbsY = y;
      _absMoveCount++;
      _isOutsideTouch = false;
    });
  }

  void _onPointerDown(PointerDownEvent event, Size widgetSize) {
    final mapper = _mapper;
    final videoRect = mapper.calculateVideoRect(widgetSize);
    final norm = mapper.mapTouchToNormalized(event.localPosition, videoRect);

    if (norm == null) {
      setState(() {
        _isOutsideTouch = true;
      });
      return;
    }

    _pointerCount++;
    _maxPointerCount = math.max(_maxPointerCount, _pointerCount);
    _pointerPositions[event.pointer] = event.localPosition;
    _initialPositions[event.pointer] = event.localPosition;

    if (_pointerCount == 1) {
      _sendAbsMove(norm.dx, norm.dy);
    } else if (_pointerCount >= 2) {
      // Multi-touch candidate: cancel single-finger tap/drag
      _cancelSingleTapTimer();
      if (_isLeftButtonHeld) {
        _isLeftButtonHeld = false;
        _controlWs.sendButtonUp('left');
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event, Size widgetSize) {
    final mapper = _mapper;
    final videoRect = mapper.calculateVideoRect(widgetSize);
    final norm = mapper.mapTouchToNormalized(event.localPosition, videoRect);

    if (norm == null) {
      setState(() {
        _isOutsideTouch = true;
      });
      return;
    }

    _pointerPositions[event.pointer] = event.localPosition;

    if (_pointerCount == 1 && _maxPointerCount == 1) {
      final initPos = _initialPositions[event.pointer];
      if (initPos != null) {
        final dist = (event.localPosition - initPos).distance;
        if (dist > _touchSlop) {
          _isDragging = true;
          _cancelSingleTapTimer();
          if (!_isLeftButtonHeld) {
            _isLeftButtonHeld = true;
            _controlWs.sendButtonDown('left');
            setState(() {
              _lastGesture = 'Drag Started';
            });
          }
        }
      }

      _sendAbsMove(norm.dx, norm.dy);
    }
  }

  void _onPointerUp(PointerUpEvent event, Size widgetSize) {
    final mapper = _mapper;
    final videoRect = mapper.calculateVideoRect(widgetSize);
    final upPos = event.localPosition;

    if (_pointerCount == 1 && _maxPointerCount == 1) {
      if (_isLeftButtonHeld) {
        _isLeftButtonHeld = false;
        _controlWs.sendButtonUp('left');
        setState(() {
          _lastGesture = 'Drag Released';
        });
      } else if (!_isDragging) {
        final norm = mapper.mapTouchToNormalized(upPos, videoRect);
        if (norm != null) {
          final now = DateTime.now();
          if (_lastTapUpTime != null &&
              _lastTapUpPos != null &&
              now.difference(_lastTapUpTime!).inMilliseconds < _doubleTapTimeoutMs &&
              (upPos - _lastTapUpPos!).distance < 30.0) {
            // Double Tap
            _cancelSingleTapTimer();
            _lastTapUpTime = null;
            _lastTapUpPos = null;
            _controlWs.sendDoubleClick();
            setState(() {
              _lastGesture = 'Double Tap (LEFT_CLICK x2)';
            });
          } else {
            // Potential single tap
            _lastTapUpTime = now;
            _lastTapUpPos = upPos;
            _singleTapTimer = Timer(const Duration(milliseconds: _singleTapDelayMs), () {
              _controlWs.sendLeftClick();
              _lastTapUpTime = null;
              _lastTapUpPos = null;
              setState(() {
                _lastGesture = 'Single Tap (LEFT_CLICK)';
              });
            });
          }
        }
      }
    } else if (_maxPointerCount == 2 && _pointerCount == 1) {
      // Two-finger tap completion
      bool exceededSlop = false;
      for (final entry in _pointerPositions.entries) {
        final init = _initialPositions[entry.key];
        if (init != null && (entry.value - init).distance > 15.0) {
          exceededSlop = true;
          break;
        }
      }
      if (!exceededSlop) {
        final norm = mapper.mapTouchToNormalized(upPos, videoRect);
        if (norm != null) {
          _controlWs.sendRightClick();
          setState(() {
            _lastGesture = 'Two-Finger Tap (RIGHT_CLICK)';
          });
        }
      }
    }

    _pointerCount = math.max(0, _pointerCount - 1);
    _pointerPositions.remove(event.pointer);
    _initialPositions.remove(event.pointer);

    if (_pointerCount == 0) {
      _maxPointerCount = 0;
      _isDragging = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_isLeftButtonHeld) {
      _isLeftButtonHeld = false;
      _controlWs.sendButtonUp('left');
    }
    _controlWs.releaseAll();
    _resetGestureState();
  }

  void _resetGestureState() {
    _cancelSingleTapTimer();
    _pointerCount = 0;
    _maxPointerCount = 0;
    _pointerPositions.clear();
    _initialPositions.clear();
    _isDragging = false;
    _isLeftButtonHeld = false;
  }

  void _cancelSingleTapTimer() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Spike 3: Remote Screen Touch & Control'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls Card
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _hostController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'PC Host IP',
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blueAccent),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _portController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blueAccent),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _startSession,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Connect Video & Control'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                        ElevatedButton.icon(
                          onPressed: _stopSession,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        ),
                        OutlinedButton.icon(
                          onPressed: _requestForcedIdr,
                          icon: const Icon(Icons.sync),
                          label: const Text('Force IDR'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.orangeAccent),
                        ),
                        OutlinedButton.icon(
                          onPressed: _resetDecoder,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset Decoder'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.purpleAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live Remote Screen Video Container + Touch Controller Layer
            LayoutBuilder(
              builder: (context, constraints) {
                final mapper = _mapper;
                final containerSize = Size(constraints.maxWidth, 240);
                final videoRect = mapper.calculateVideoRect(containerSize);

                return Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueAccent, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Video Decoder View Surface
                      Positioned.fill(
                        child: defaultTargetPlatform == TargetPlatform.android
                            ? const AndroidView(
                                viewType: 'pouse/remote_screen_view',
                                creationParamsCodec: StandardMessageCodec(),
                              )
                            : const Center(
                                child: Text('Android Only Platform View', style: TextStyle(color: Colors.white54)),
                              ),
                      ),

                      // Touch Overlay Listener
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (e) => _onPointerDown(e, containerSize),
                          onPointerMove: (e) => _onPointerMove(e, containerSize),
                          onPointerUp: (e) => _onPointerUp(e, containerSize),
                          onPointerCancel: _onPointerCancel,
                          child: CustomPaint(
                            size: containerSize,
                            painter: _TouchOverlayPainter(
                              videoRect: videoRect,
                              lastAbsX: _lastAbsX,
                              lastAbsY: _lastAbsY,
                              isDragging: _isDragging,
                              isOutsideTouch: _isOutsideTouch,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Metrics Display Card
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Video: $_videoState',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _videoState == 'DECODING' ? Colors.greenAccent : Colors.amberAccent,
                          ),
                        ),
                        ValueListenableBuilder<ConnectionStatus>(
                          valueListenable: _controlWs.statusNotifier,
                          builder: (context, status, _) {
                            return Text(
                              'Control WS: ${status.name.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: status == ConnectionStatus.connected ? Colors.greenAccent : Colors.redAccent,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.grey),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('WS RX FPS: ${_wsRxFps.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white)),
                        Text('Decoder Output FPS: ${_decoderFps.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Received: $_rxCount', style: const TextStyle(color: Colors.white70)),
                        Text('Decoded: $_decodedCount', style: const TextStyle(color: Colors.white70)),
                        Text('Dropped: $_droppedCount', style: const TextStyle(color: Colors.orangeAccent)),
                      ],
                    ),
                    Text(
                      'ABS_MOVE Target: ${_lastAbsX != null ? "x=${_lastAbsX!.toStringAsFixed(4)}, y=${_lastAbsY!.toStringAsFixed(4)}" : "None"}',
                      style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('ABS_MOVE Events Sent: $_absMoveCount', style: const TextStyle(color: Colors.white70)),
                    Text('Last Gesture: $_lastGesture', style: const TextStyle(color: Colors.lightGreenAccent)),
                    Text('Time to First Frame: ${_timeToFirstFrameMs >= 0 ? "${_timeToFirstFrameMs}ms" : "N/A"}',
                        style: const TextStyle(color: Colors.cyanAccent)),
                    Text('Forced IDR Recovery: ${_timeFromForcedIdrMs >= 0 ? "${_timeFromForcedIdrMs}ms" : "N/A"}',
                        style: const TextStyle(color: Colors.cyanAccent)),
                    if (_isOutsideTouch)
                      Text('Last Touch: OUTSIDE VIDEO RECT (IGNORED)', style: TextStyle(color: Colors.amberAccent)),
                    if (_lastError.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Error: $_lastError', style: const TextStyle(color: Colors.redAccent)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter to visualize the 16:9 active video rectangle and touch cursor point
class _TouchOverlayPainter extends CustomPainter {
  final Rect videoRect;
  final double? lastAbsX;
  final double? lastAbsY;
  final bool isDragging;
  final bool isOutsideTouch;

  _TouchOverlayPainter({
    required this.videoRect,
    required this.lastAbsX,
    required this.lastAbsY,
    required this.isDragging,
    required this.isOutsideTouch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw subtle border around active 16:9 video content
    final rectPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(videoRect, rectPaint);

    // Draw active touch indicator dot if inside
    if (lastAbsX != null && lastAbsY != null) {
      final touchX = videoRect.left + (lastAbsX! * videoRect.width);
      final touchY = videoRect.top + (lastAbsY! * videoRect.height);

      final dotPaint = Paint()
        ..color = isDragging ? Colors.redAccent : Colors.greenAccent
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(touchX, touchY), 8.0, dotPaint);

      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(Offset(touchX, touchY), 12.0, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TouchOverlayPainter oldDelegate) {
    return oldDelegate.videoRect != videoRect ||
        oldDelegate.lastAbsX != lastAbsX ||
        oldDelegate.lastAbsY != lastAbsY ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.isOutsideTouch != isOutsideTouch;
  }
}
