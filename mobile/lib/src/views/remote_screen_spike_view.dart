import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sources/remote_screen_source.dart';
import '../transports/pouse_transport.dart';
import '../utils/remote_screen_coordinate_mapper.dart';
import '../websocket_service.dart';
import '../widgets/shared_utilities_dock.dart';

/// Gesture state machine states for Remote Screen control
enum RemoteScreenGestureState {
  idle,
  oneFingerUndecided,
  oneFingerDrag,
  twoFingerUndecided,
  twoFingerPinchPan,
}

enum TwoFingerMode { undecided, scroll, zoom }

/// Production Remote Screen UX & Interaction V1 View
class RemoteScreenSpikeView extends StatefulWidget {
  final RemoteScreenSource? source;
  final String? initialHost;
  final ValueChanged<bool>? onFullscreenChanged;

  /// Optional Wi-Fi transport reference.
  ///
  /// When the active control transport is Bluetooth, Remote Screen video
  /// cannot be carried over RFCOMM. However, if [wifiTransport] is provided
  /// and is currently connected, the view uses its IP for the video session
  /// instead of showing a "Wi-Fi Required" banner.
  ///
  /// If [wifiTransport] is null or not connected when Bluetooth is active,
  /// the "Wi-Fi Required" banner is shown.
  final WebSocketService? wifiTransport;

  const RemoteScreenSpikeView({
    super.key,
    this.source,
    this.initialHost,
    this.onFullscreenChanged,
    this.wifiTransport,
  });

  @override
  State<RemoteScreenSpikeView> createState() => _RemoteScreenSpikeViewState();
}

class _RemoteScreenSpikeViewState extends State<RemoteScreenSpikeView> {
  static const _methodChannel = MethodChannel('pouse/remote_screen/method');
  static const _eventChannel = EventChannel('pouse/remote_screen/events');

  StreamSubscription? _metricsSub;

  String _videoState = 'UNINITIALIZED';
  String _lastError = '';

  // Captured monitor dimensions (defaults to 1280x720)
  int _capturedWidth = 1280;
  int _capturedHeight = 720;
  RemoteScreenCoordinateMapper get _mapper =>
      RemoteScreenCoordinateMapper(width: _capturedWidth, height: _capturedHeight);

  // Zoom & Pan transform state
  double _zoomScale = 1.0;
  Offset _panOffset = Offset.zero;

  // Fullscreen state
  bool _isFullscreen = false;
  bool _showFullscreenUtilities = false;

  // Touch indicator state
  Offset? _touchIndicatorLocalPos;
  Timer? _touchIndicatorTimer;

  // Gesture state machine
  RemoteScreenGestureState _gestureState = RemoteScreenGestureState.idle;

  // Pointer tracking (max 2)
  final Map<int, Offset> _pointerPositions = {};
  final Map<int, Offset> _initialPositions = {};
  final List<int> _pointerOrder = [];

  int? _primaryPointerId;
  Offset? _primaryStartPos;
  bool _isLeftButtonHeld = false;

  // Double-tap and single-tap timer
  Timer? _singleTapTimer;
  DateTime? _lastTapTime;
  Offset? _lastTapLocalPos;

  // Two-finger classification tracking
  double _initialTwoFingerDistance = 0.0;
  Offset _initialTwoFingerMidpoint = Offset.zero;
  double _initialZoomOnPinch = 1.0;
  Offset _initialPanOnPinch = Offset.zero;
  TwoFingerMode _twoFingerMode = TwoFingerMode.undecided;
  DateTime? _twoFingerStartTime;

  static const double _touchSlopDp = 8.0;
  static const int _doubleTapTimeoutMs = 300;
  static const int _singleTapDelayMs = 220;

  @override
  void initState() {
    super.initState();
    _listenMetrics();
    _autoStartSession();
  }

  String _sessionState = 'IDLE';
  String _uiState = 'CONNECTING';
  int _framesDecoded = 0;

  /// True when the current transport is Bluetooth-only and cannot carry Remote
  /// Screen video.  Set during [_autoStartSession]; causes a Wi-Fi info banner
  /// to replace the stuck "CONNECTING" overlay.
  bool _wifiRequired = false;

  void _listenMetrics() {
    _metricsSub = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map && mounted) {
        final newWidth = (event['width'] != null && (event['width'] as num).toInt() > 0)
            ? (event['width'] as num).toInt()
            : _capturedWidth;
        final newHeight = (event['height'] != null && (event['height'] as num).toInt() > 0)
            ? (event['height'] as num).toInt()
            : _capturedHeight;

        setState(() {
          _videoState = event['state']?.toString() ?? 'UNKNOWN';
          _sessionState = event['sessionState']?.toString() ?? 'IDLE';
          _uiState = event['uiState']?.toString() ?? 'CONNECTING';
          _framesDecoded = (event['framesDecoded'] as num?)?.toInt() ?? _framesDecoded;
          // Reset zoom/pan if PC resolution / metadata changes
          if (newWidth != _capturedWidth || newHeight != _capturedHeight) {
            _capturedWidth = newWidth;
            _capturedHeight = newHeight;
            _resetZoomPan();
          }
          _lastError = event['lastError']?.toString() ?? '';
        });
      }
    }, onError: (err) {
      debugPrint('[REMOTE_SCREEN] Error receiving metrics: $err');
    });
  }

  Future<void> _autoStartSession() async {
    final transport = widget.source?.transport;
    final wifiTransport = widget.wifiTransport;

    // Remote Screen video is Wi-Fi only. RFCOMM Bluetooth does not have
    // sufficient bandwidth for real-time screen streaming.
    //
    // However, if the user has Bluetooth connected for control AND Wi-Fi is
    // also connected, we can use Wi-Fi for video while BT handles input.
    // Only show the "Wi-Fi Required" banner when Wi-Fi is genuinely unavailable.
    if (transport != null && transport.type == TransportType.bluetooth) {
      // Check if Wi-Fi is available as a fallback video transport
      final wifiConnected = wifiTransport != null &&
          (wifiTransport.status == ConnectionStatus.connected ||
              wifiTransport.status == ConnectionStatus.connecting);
      final wifiIp = wifiTransport?.currentIp;

      if (!wifiConnected || wifiIp == null || wifiIp.isEmpty) {
        // Wi-Fi is not available — show the informational banner
        if (mounted) {
          setState(() {
            _wifiRequired = true;
            _uiState = 'WIFI_REQUIRED';
          });
        }
        return;
      }

      // Wi-Fi IS available even though Bluetooth is the control transport.
      // Use the Wi-Fi IP for the video session. This is the correct behaviour:
      // BT carries control events, Wi-Fi carries video.
      debugPrint('[REMOTE_SCREEN] BT control + Wi-Fi video mode: host=$wifiIp');
      final pairToken = wifiTransport.pairToken ?? '';
      try {
        await _methodChannel.invokeMethod('startSession', {
          'host': wifiIp,
          'port': 8081,
          'pairToken': pairToken,
        });
      } catch (e) {
        debugPrint('[REMOTE_SCREEN] Error starting session (BT+WiFi mode): $e');
      }
      return;
    }

    String host = '127.0.0.1';
    if (transport is WebSocketService &&
        transport.currentIp != null &&
        transport.currentIp!.isNotEmpty) {
      host = transport.currentIp!;
    } else if (widget.initialHost != null && widget.initialHost!.trim().isNotEmpty) {
      host = widget.initialHost!.trim();
    }
    final pairToken = (transport is WebSocketService ? transport.pairToken : '') ?? '';

    try {
      await _methodChannel.invokeMethod('startSession', {
        'host': host,
        'port': 8081,
        'pairToken': pairToken,
      });
    } catch (e) {
      debugPrint('[REMOTE_SCREEN] Error starting session: $e');
    }
  }

  Future<void> _stopSession() async {
    try {
      widget.source?.transport.releaseAll();
      await _methodChannel.invokeMethod('stopSession');
    } catch (e) {
      debugPrint('[REMOTE_SCREEN] Error stopping session: $e');
    }
  }

  String? _activeHeldArrowKey;

  void _releaseHeldArrowKey() {
    if (_activeHeldArrowKey != null) {
      widget.source?.sendKeyUp(_activeHeldArrowKey!);
      _activeHeldArrowKey = null;
    }
  }

  @override
  void dispose() {
    _releaseHeldArrowKey();
    _stopSession();
    _metricsSub?.cancel();
    _singleTapTimer?.cancel();
    _touchIndicatorTimer?.cancel();
    if (_isFullscreen) {
      widget.onFullscreenChanged?.call(false);
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _resetZoomPan() {
    _releaseHeldArrowKey();
    setState(() {
      _zoomScale = 1.0;
      _panOffset = Offset.zero;
    });
  }

  void _enterFullscreen() {
    _releaseHeldArrowKey();
    setState(() {
      _isFullscreen = true;
      _showFullscreenUtilities = false;
      _zoomScale = 1.0;
      _panOffset = Offset.zero;
    });
    widget.onFullscreenChanged?.call(true);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    _releaseHeldArrowKey();
    setState(() {
      _isFullscreen = false;
      _showFullscreenUtilities = false;
      _zoomScale = 1.0;
      _panOffset = Offset.zero;
    });
    widget.onFullscreenChanged?.call(false);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _showTouchIndicator(Offset localPos) {
    _touchIndicatorTimer?.cancel();
    setState(() {
      _touchIndicatorLocalPos = localPos;
    });
    _touchIndicatorTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _touchIndicatorLocalPos = null;
        });
      }
    });
  }

  void _sendAbsMove(double x, double y) {
    widget.source?.sendAbsMove(x, y);
  }

  void _onPointerDown(PointerDownEvent event, Rect fitRect) {
    if (fitRect.isEmpty) return;

    // Touches outside fitRect MUST be ignored!
    if (event.localPosition.dx < fitRect.left ||
        event.localPosition.dx > fitRect.right ||
        event.localPosition.dy < fitRect.top ||
        event.localPosition.dy > fitRect.bottom) {
      return;
    }

    // Ignore 3rd finger entirely
    if (_pointerPositions.length >= 2) {
      return;
    }

    // Rule: A 2nd finger touching down while a 1-finger drag is already committed
    // MUST NOT reinterpret the gesture. Ignore additional fingers & finish drag.
    if (_gestureState == RemoteScreenGestureState.oneFingerDrag) {
      return;
    }

    _pointerPositions[event.pointer] = event.localPosition;
    _initialPositions[event.pointer] = event.localPosition;
    if (!_pointerOrder.contains(event.pointer)) {
      _pointerOrder.add(event.pointer);
    }

    if (_pointerPositions.length == 1) {
      // Single finger DOWN
      _primaryPointerId = event.pointer;
      _primaryStartPos = event.localPosition;
      _gestureState = RemoteScreenGestureState.oneFingerUndecided;

      final norm = _mapper.mapTouchToNormalized(
        event.localPosition,
        fitRect,
        zoomScale: _zoomScale,
        panOffset: _panOffset,
      );
      if (norm != null) {
        _sendAbsMove(norm.dx, norm.dy);
        _showTouchIndicator(event.localPosition);
      }
    } else if (_pointerPositions.length == 2) {
      // Second finger DOWN -> enter two-finger undecided
      _cancelSingleTapTimer();
      _gestureState = RemoteScreenGestureState.twoFingerUndecided;
      _twoFingerMode = TwoFingerMode.undecided;
      _twoFingerStartTime = DateTime.now();

      final p1 = _pointerPositions[_pointerOrder[0]]!;
      final p2 = _pointerPositions[_pointerOrder[1]]!;
      _initialTwoFingerDistance = math.max(1.0, (p1 - p2).distance);
      _initialTwoFingerMidpoint = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
      _initialZoomOnPinch = _zoomScale;
      _initialPanOnPinch = _panOffset;

      if (_isLeftButtonHeld) {
        _isLeftButtonHeld = false;
        widget.source?.sendButtonUp('left');
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event, Rect fitRect) {
    if (!_pointerPositions.containsKey(event.pointer)) return;
    _pointerPositions[event.pointer] = event.localPosition;

    final devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final slop = _touchSlopDp * devicePixelRatio;

    if (_gestureState == RemoteScreenGestureState.oneFingerUndecided &&
        event.pointer == _primaryPointerId &&
        _primaryStartPos != null) {
      final dist = (event.localPosition - _primaryStartPos!).distance;
      if (dist > slop) {
        _gestureState = RemoteScreenGestureState.oneFingerDrag;
        _cancelSingleTapTimer();
        if (!_isLeftButtonHeld) {
          _isLeftButtonHeld = true;
          widget.source?.sendButtonDown('left');
        }
      }
    }

    if (_gestureState == RemoteScreenGestureState.oneFingerDrag &&
        event.pointer == _primaryPointerId) {
      final norm = _mapper.mapTouchToNormalized(
        event.localPosition,
        fitRect,
        zoomScale: _zoomScale,
        panOffset: _panOffset,
      );
      if (norm != null) {
        _sendAbsMove(norm.dx, norm.dy);
      }
      return;
    }

    if ((_gestureState == RemoteScreenGestureState.twoFingerUndecided ||
            _gestureState == RemoteScreenGestureState.twoFingerPinchPan) &&
        _pointerOrder.length >= 2) {
      final p1 = _pointerPositions[_pointerOrder[0]];
      final p2 = _pointerPositions[_pointerOrder[1]];
      if (p1 == null || p2 == null) return;

      final currentDist = math.max(1.0, (p1 - p2).distance);
      final currentMidpoint = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);

      final distanceChange = (currentDist - _initialTwoFingerDistance).abs();
      final translationMag = (currentMidpoint - _initialTwoFingerMidpoint).distance;

      if (_initialZoomOnPinch == 1.0) {
        // Disambiguate 1x Pinch Zoom vs PC Scroll with density-aware slop & minimum signal
        if (_twoFingerMode == TwoFingerMode.undecided) {
          final signal = distanceChange + translationMag;
          final elapsedMs = _twoFingerStartTime != null
              ? DateTime.now().difference(_twoFingerStartTime!).inMilliseconds
              : 0;

          if (signal >= 1.5 * slop || elapsedMs >= 100 || signal >= 3.0 * slop) {
            if (distanceChange > 1.5 * translationMag) {
              _twoFingerMode = TwoFingerMode.zoom;
            } else if (translationMag > 1.5 * distanceChange) {
              _twoFingerMode = TwoFingerMode.scroll;
            } else if (elapsedMs >= 100 || signal >= 3.0 * slop) {
              _twoFingerMode = TwoFingerMode.scroll; // Safe default
            }
          }
        }

        if (_twoFingerMode == TwoFingerMode.scroll) {
          final midDelta = currentMidpoint - _initialTwoFingerMidpoint;
          widget.source?.sendScroll(midDelta.dx / 3.0, midDelta.dy / 3.0);
          _initialTwoFingerMidpoint = currentMidpoint;
          return;
        } else if (_twoFingerMode == TwoFingerMode.zoom) {
          _gestureState = RemoteScreenGestureState.twoFingerPinchPan;
        } else {
          return; // Still undecided signal
        }
      } else {
        _gestureState = RemoteScreenGestureState.twoFingerPinchPan;
        _twoFingerMode = TwoFingerMode.zoom;
      }

      // Pinch + Pan (at zoom > 1.0x or committed zoom)
      final distRatio = currentDist / _initialTwoFingerDistance;
      final newZoom = (_initialZoomOnPinch * distRatio).clamp(1.0, 4.0);

      // Midpoint-centered zoom + pan calculations
      final initialFitRectMid = _initialTwoFingerMidpoint - fitRect.topLeft;
      final currentFitRectMid = currentMidpoint - fitRect.topLeft;

      final normMidX = _initialPanOnPinch.dx +
          (initialFitRectMid.dx / fitRect.width) * (1.0 / _initialZoomOnPinch);
      final normMidY = _initialPanOnPinch.dy +
          (initialFitRectMid.dy / fitRect.height) * (1.0 / _initialZoomOnPinch);

      final newPanX = normMidX - (currentFitRectMid.dx / fitRect.width) * (1.0 / newZoom);
      final newPanY = normMidY - (currentFitRectMid.dy / fitRect.height) * (1.0 / newZoom);

      final clampedPan = _mapper.clampPanOffset(Offset(newPanX, newPanY), newZoom);

      setState(() {
        _zoomScale = newZoom;
        _panOffset = clampedPan;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event, Rect fitRect) {
    final upPos = event.localPosition;

    if (_gestureState == RemoteScreenGestureState.oneFingerDrag &&
        event.pointer == _primaryPointerId) {
      if (_isLeftButtonHeld) {
        _isLeftButtonHeld = false;
        widget.source?.sendButtonUp('left');
      }
      _gestureState = RemoteScreenGestureState.idle;
    } else if (_gestureState == RemoteScreenGestureState.oneFingerUndecided &&
        event.pointer == _primaryPointerId) {
      final norm = _mapper.mapTouchToNormalized(
        upPos,
        fitRect,
        zoomScale: _zoomScale,
        panOffset: _panOffset,
      );
      if (norm != null) {
        final now = DateTime.now();
        if (_lastTapTime != null &&
            _lastTapLocalPos != null &&
            now.difference(_lastTapTime!).inMilliseconds < _doubleTapTimeoutMs &&
            (upPos - _lastTapLocalPos!).distance < 30.0) {
          // Double Tap
          _cancelSingleTapTimer();
          _lastTapTime = null;
          _lastTapLocalPos = null;
          widget.source?.sendDoubleClick();
          _showTouchIndicator(upPos);
        } else {
          // Single Tap candidate
          _lastTapTime = now;
          _lastTapLocalPos = upPos;
          _singleTapTimer = Timer(const Duration(milliseconds: _singleTapDelayMs), () {
            widget.source?.sendLeftClick();
            _showTouchIndicator(upPos);
            _lastTapTime = null;
            _lastTapLocalPos = null;
          });
        }
      }
      _gestureState = RemoteScreenGestureState.idle;
    } else if (_gestureState == RemoteScreenGestureState.twoFingerUndecided &&
        _twoFingerMode == TwoFingerMode.undecided) {
      // Two-finger tap -> Right Click
      final norm = _mapper.mapTouchToNormalized(
        upPos,
        fitRect,
        zoomScale: _zoomScale,
        panOffset: _panOffset,
      );
      if (norm != null) {
        widget.source?.sendRightClick();
        _showTouchIndicator(upPos);
      }
      _gestureState = RemoteScreenGestureState.idle;
    } else if (_pointerPositions.length <= 1) {
      _gestureState = RemoteScreenGestureState.idle;
    }

    _pointerPositions.remove(event.pointer);
    _initialPositions.remove(event.pointer);
    _pointerOrder.remove(event.pointer);

    if (_pointerPositions.isEmpty) {
      _primaryPointerId = null;
      _primaryStartPos = null;
      _gestureState = RemoteScreenGestureState.idle;
      _twoFingerMode = TwoFingerMode.undecided;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_isLeftButtonHeld) {
      _isLeftButtonHeld = false;
      widget.source?.sendButtonUp('left');
    }
    widget.source?.transport.releaseAll();
    _resetGestureState();
  }

  void _resetGestureState() {
    _cancelSingleTapTimer();
    _pointerPositions.clear();
    _initialPositions.clear();
    _pointerOrder.clear();
    _primaryPointerId = null;
    _primaryStartPos = null;
    _isLeftButtonHeld = false;
    _gestureState = RemoteScreenGestureState.idle;
    _twoFingerMode = TwoFingerMode.undecided;
  }

  void _cancelSingleTapTimer() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
  }

  void _adjustZoom(double delta) {
    final newZoom = (_zoomScale + delta).clamp(1.0, 4.0);
    final clampedPan = _mapper.clampPanOffset(_panOffset, newZoom);
    setState(() {
      _zoomScale = newZoom;
      _panOffset = clampedPan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final rightInset = MediaQuery.paddingOf(context).right;
    final leftInset = MediaQuery.paddingOf(context).left;
    final isDecoding = _videoState == 'DECODING' ||
        _videoState == 'CONNECTED' ||
        _sessionState == 'CONNECTED' ||
        _framesDecoded > 0;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullscreen) {
          _exitFullscreen();
        }
      },
      child: Container(
        color: const Color(0xFF0F172A),
        child: Stack(
          children: [
            Column(
              children: [
                // Top Status Bar (Portrait only)
                if (!_isFullscreen)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _wifiRequired
                                ? Colors.amberAccent
                                : (_uiState == 'LIVE'
                                    ? Colors.greenAccent
                                    : (_uiState == 'ERROR'
                                        ? Colors.redAccent
                                        : Colors.orangeAccent)),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _wifiRequired
                                ? 'Wi-Fi Required — Remote Screen needs Wi-Fi, not Bluetooth'
                                : (_lastError.isNotEmpty
                                    ? 'ERROR: $_lastError'
                                    : (_uiState == 'LIVE'
                                        ? 'LIVE • Remote Screen Active'
                                        : (_uiState == 'WAITING_FOR_FIRST_FRAME'
                                            ? 'WAITING_FOR_FIRST_FRAME • Initializing'
                                            : (_uiState == 'VIDEO_CONNECTED'
                                                ? 'VIDEO_CONNECTED • Waiting for Keyframe'
                                                : (_uiState == 'VIDEO_STALLED'
                                                    ? 'VIDEO_STALLED • Recovering'
                                                    : (_uiState == 'RECONNECTING'
                                                        ? 'RECONNECTING'
                                                        : 'CONNECTING')))))),
                            style: TextStyle(
                              color: _wifiRequired
                                  ? Colors.amberAccent
                                  : (_lastError.isNotEmpty || _uiState == 'ERROR'
                                      ? Colors.redAccent
                                      : Colors.white70),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDecoding)
                          Text(
                            '$_capturedWidth×$_capturedHeight',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(width: 8),
                        // Fullscreen Enter Button ⛶
                        IconButton(
                          onPressed: _enterFullscreen,
                          icon: const Icon(Icons.fullscreen, size: 18),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF2A2A36),
                          ),
                          tooltip: 'Fullscreen Mode',
                        ),
                      ],
                    ),
                  ),

                // Main Live Video Surface Container (ALWAYS MOUNTED IN SUBTREE)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
                      final fitRect = _mapper.calculateVideoRect(containerSize);

                      return Container(
                        color: Colors.black,
                        child: Stack(
                          children: [
                            // Video Decoder Native Surface inside fitRect
                            if (fitRect.width > 0 && fitRect.height > 0)
                              Positioned.fromRect(
                                rect: fitRect,
                                child: ClipRect(
                                  child: Transform(
                                    transform: Matrix4.identity()
                                      ..translateByDouble(
                                        -_panOffset.dx * _zoomScale * fitRect.width,
                                        -_panOffset.dy * _zoomScale * fitRect.height,
                                        0.0,
                                        1.0,
                                      )
                                      ..scaleByDouble(_zoomScale, _zoomScale, 1.0, 1.0),
                                    transformHitTests: false,
                                    child: defaultTargetPlatform == TargetPlatform.android
                                        ? const AndroidView(
                                            viewType: 'pouse/remote_screen_view',
                                            creationParamsCodec: StandardMessageCodec(),
                                          )
                                        : const Center(
                                            child: Text(
                                              'Android Platform View',
                                              style: TextStyle(color: Colors.white54),
                                            ),
                                          ),
                                  ),
                                ),
                              ),

                            // Touch Interaction Overlay over full container
                            Positioned.fill(
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (e) => _onPointerDown(e, fitRect),
                                onPointerMove: (e) => _onPointerMove(e, fitRect),
                                onPointerUp: (e) => _onPointerUp(e, fitRect),
                                onPointerCancel: _onPointerCancel,
                                child: CustomPaint(
                                  size: containerSize,
                                  painter: _TouchIndicatorPainter(
                                    fitRect: fitRect,
                                    indicatorLocalPos: _touchIndicatorLocalPos,
                                  ),
                                ),
                              ),
                            ),

                            // Wi-Fi Required Banner (shown when Bluetooth is the active transport)
                            if (_wifiRequired)
                              Positioned.fill(
                                child: Container(
                                  color: const Color(0xCC0F172A),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.wifi_off_rounded,
                                            size: 56,
                                            color: Colors.amberAccent,
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            'Wi-Fi Required',
                                            style: TextStyle(
                                              color: Colors.amberAccent,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Remote Screen video cannot be streamed over Bluetooth. '
                                            'Please connect to your Pouse PC via Wi-Fi to use this feature.',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                              height: 1.5,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 24),
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _wifiRequired = false;
                                                _uiState = 'CONNECTING';
                                              });
                                              _autoStartSession();
                                            },
                                            icon: const Icon(Icons.refresh, size: 18),
                                            label: const Text('Retry with Wi-Fi'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.amberAccent,
                                              side: const BorderSide(color: Colors.amberAccent, width: 1),
                                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Portrait Mode Zoom HUD (top-right overlay)
                            if (!_isFullscreen)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: _buildZoomHud(),
                              ),

                            // Fullscreen CLOSED State: LIVE PC SCREEN + ⋯ ONLY
                            if (_isFullscreen && !_showFullscreenUtilities)
                              Positioned(
                                bottom: 16 + bottomInset,
                                right: 16 + rightInset,
                                child: IconButton.filled(
                                  onPressed: () {
                                    setState(() {
                                      _showFullscreenUtilities = true;
                                    });
                                  },
                                  icon: const Icon(Icons.more_horiz, size: 20),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xDD0F172A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(12),
                                  ),
                                  tooltip: 'Utilities',
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // In Portrait mode, Utilities Dock is anchored at bottom of column
                if (!_isFullscreen)
                  SharedUtilitiesDock(
                    transport: widget.source?.transport ?? WebSocketService(),
                    onLeftClick: () => widget.source?.sendLeftClick(),
                    onRightClick: () => widget.source?.sendRightClick(),
                  ),
              ],
            ),

            // Fullscreen OPEN State: Floating Overlay with Full Utilities + Toggle
            if (_isFullscreen && _showFullscreenUtilities)
              Positioned(
                bottom: 16 + bottomInset,
                left: 16 + leftInset,
                right: 16 + rightInset,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E1E24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12, width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with Exit Fullscreen button
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF16161D),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Fullscreen Utilities',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: _exitFullscreen,
                              icon: const Icon(Icons.fullscreen_exit, size: 16),
                              label: const Text('Exit Fullscreen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2A2A36),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SharedUtilitiesDock(
                        transport: widget.source?.transport ?? WebSocketService(),
                        onLeftClick: () => widget.source?.sendLeftClick(),
                        onRightClick: () => widget.source?.sendRightClick(),
                        initiallyExpanded: true,
                        onToggle: () {
                          setState(() {
                            _showFullscreenUtilities = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Contextual Zoom HUD ([-] 2.0x [+] ⟳) + discrete scroll buttons (▲ ▼) when zoomed
  Widget _buildZoomHud() {
    final isZoomed = _zoomScale > 1.05;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xDD0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isZoomed ? Colors.blueAccent.withValues(alpha: 0.6) : Colors.white12,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Zoom Out Button [-]
              IconButton(
                onPressed: () => _adjustZoom(-0.5),
                icon: const Icon(Icons.remove, size: 16),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF1E293B),
                ),
                tooltip: 'Zoom Out',
              ),
              const SizedBox(width: 4),

              // Zoom Scale Text
              Container(
                constraints: const BoxConstraints(minWidth: 44),
                alignment: Alignment.center,
                child: Text(
                  '${_zoomScale.toStringAsFixed(1)}×',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Zoom In Button [+]
              IconButton(
                onPressed: () => _adjustZoom(0.5),
                icon: const Icon(Icons.add, size: 16),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF1E293B),
                ),
                tooltip: 'Zoom In',
              ),
              const SizedBox(width: 4),

              // Reset Zoom Button ⟳
              IconButton(
                onPressed: _resetZoomPan,
                icon: const Icon(Icons.refresh, size: 16),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: isZoomed ? Colors.blueAccent : Colors.white38,
                  backgroundColor: const Color(0xFF1E293B),
                ),
                tooltip: 'Reset Zoom (1.0x)',
              ),
            ],
          ),

          // PC Scroll Arrow Controls (Short tap = 1 Arrow press, Hold = KEY_DOWN/KEY_UP)
          if (isZoomed) ...[
            const SizedBox(height: 4),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PC Scroll',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const SizedBox(width: 8),
                _ArrowHoldButton(
                  icon: Icons.arrow_drop_up,
                  tooltip: 'Scroll Up',
                  keyName: 'ArrowUp',
                  source: widget.source,
                  onHeldChanged: (key) {
                    _activeHeldArrowKey = key;
                  },
                ),
                const SizedBox(width: 8),
                _ArrowHoldButton(
                  icon: Icons.arrow_drop_down,
                  tooltip: 'Scroll Down',
                  keyName: 'ArrowDown',
                  source: widget.source,
                  onHeldChanged: (key) {
                    _activeHeldArrowKey = key;
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Helper widget for Zoomed PC Scroll arrow key controls (SHORT TAP = 1 key press, HOLD = KEY_DOWN, RELEASE = KEY_UP)
class _ArrowHoldButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final String keyName;
  final RemoteScreenSource? source;
  final ValueChanged<String?>? onHeldChanged;

  const _ArrowHoldButton({
    required this.icon,
    required this.tooltip,
    required this.keyName,
    required this.source,
    this.onHeldChanged,
  });

  @override
  State<_ArrowHoldButton> createState() => _ArrowHoldButtonState();
}

class _ArrowHoldButtonState extends State<_ArrowHoldButton> {
  bool _isHeld = false;

  void _onHoldStart() {
    if (!_isHeld) {
      _isHeld = true;
      widget.onHeldChanged?.call(widget.keyName);
      widget.source?.sendKeyDown(widget.keyName);
    }
  }

  void _onHoldEnd() {
    if (_isHeld) {
      _isHeld = false;
      widget.onHeldChanged?.call(null);
      widget.source?.sendKeyUp(widget.keyName);
    }
  }

  @override
  void dispose() {
    _onHoldEnd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _onHoldStart(),
      onPointerUp: (_) => _onHoldEnd(),
      onPointerCancel: (_) => _onHoldEnd(),
      child: Tooltip(
        message: widget.tooltip,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isHeld ? Colors.blueAccent : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHeld ? Colors.white70 : Colors.white12,
              width: 1,
            ),
          ),
          child: Icon(widget.icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// Custom Painter for displaying local touch indicator ⦿
class _TouchIndicatorPainter extends CustomPainter {
  final Rect fitRect;
  final Offset? indicatorLocalPos;

  _TouchIndicatorPainter({
    required this.fitRect,
    required this.indicatorLocalPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (indicatorLocalPos != null) {
      final pos = indicatorLocalPos!;

      final innerPaint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 5.0, innerPaint);

      final outerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(pos, 11.0, outerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TouchIndicatorPainter oldDelegate) {
    return oldDelegate.fitRect != fitRect ||
        oldDelegate.indicatorLocalPos != indicatorLocalPos;
  }
}
