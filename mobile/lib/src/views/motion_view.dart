import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sources/motion_source.dart';
import '../transports/pouse_transport.dart';
import '../widgets/shared_utilities_dock.dart';

/// Flutter UI view for V2 Motion Mouse (Air Mouse).
///
/// Houses the hold-to-move touch activation surface, active status indicator,
/// dedicated right-side Motion Scroll Zone, motion & scroll sensitivity sliders,
/// Natural/Reverse scroll toggle, and unified utilities dock via [SharedUtilitiesDock].
class MotionView extends StatefulWidget {
  final MotionSource source;

  const MotionView({
    super.key,
    required this.source,
  });

  @override
  State<MotionView> createState() => _MotionViewState();
}

class _MotionViewState extends State<MotionView> with WidgetsBindingObserver {
  static const String prefScrollSensitivityKey = 'pouse_scroll_sensitivity';
  static const String prefScrollNaturalKey = 'pouse_scroll_natural';

  double _scrollSensitivity = 1.0;
  bool _isNaturalScroll = true;

  // Dedicated Scroll Zone Gesture State
  Offset? _scrollStartPos;
  Offset? _scrollLastPos;
  bool _isScrolling = false;

  PouseTransport get _transport => widget.source.transport;

  bool _isUtilityPanelActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScrollSettings();
  }

  Future<void> _loadScrollSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _scrollSensitivity = prefs.getDouble(prefScrollSensitivityKey) ?? 1.0;
        _isNaturalScroll = prefs.getBool(prefScrollNaturalKey) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _saveScrollSensitivity(double val) async {
    setState(() => _scrollSensitivity = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefScrollSensitivityKey, val);
    } catch (_) {}
  }

  Future<void> _saveScrollNatural(bool val) async {
    setState(() => _isNaturalScroll = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefScrollNaturalKey, val);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Forced release: stop tracking if app is backgrounded or interrupted
    if (state != AppLifecycleState.resumed) {
      widget.source.stopTracking();
    }
  }

  void _onHoldPointerDown(PointerDownEvent event) {
    HapticFeedback.selectionClick();
    widget.source.startTracking();
  }

  void _onHoldPointerUp(PointerUpEvent event) {
    HapticFeedback.lightImpact();
    widget.source.stopTracking();
  }

  void _onHoldPointerCancel(PointerCancelEvent event) {
    HapticFeedback.lightImpact();
    widget.source.stopTracking();
  }

  // Motion Scroll Zone Gesture Handlers (Relative Delta Swipe)
  void _onScrollPointerDown(PointerDownEvent event) {
    _scrollStartPos = event.localPosition;
    _scrollLastPos = event.localPosition;
    _isScrolling = false;
  }

  void _onScrollPointerMove(PointerMoveEvent event) {
    if (_scrollStartPos == null || _scrollLastPos == null) return;
    final pos = event.localPosition;

    if (!_isScrolling) {
      if ((pos - _scrollStartPos!).distance > 8.0) {
        _isScrolling = true;
      }
    }

    if (_isScrolling) {
      final delta = pos - _scrollLastPos!;
      final dirMultiplier = _isNaturalScroll ? 1.0 : -1.0;
      final dx = delta.dx * 0.5 * _scrollSensitivity * dirMultiplier;
      final dy = delta.dy * 0.5 * _scrollSensitivity * dirMultiplier;
      if (dx.abs() > 0.01 || dy.abs() > 0.01) {
        _transport.sendScroll(dx, dy);
      }
    }
    _scrollLastPos = pos;
  }

  void _onScrollPointerUp(PointerUpEvent event) {
    // Cleanly terminate scroll gesture without emitting any click or motion event
    _scrollStartPos = null;
    _scrollLastPos = null;
    _isScrolling = false;
  }

  void _onScrollPointerCancel(PointerCancelEvent event) {
    _scrollStartPos = null;
    _scrollLastPos = null;
    _isScrolling = false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.source,
      builder: (context, _) {
        final isTracking = widget.source.isTracking;
        final isSettling = widget.source.isSettling;

        return Column(
          children: [
            // Status & Active Indicator Header
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTracking
                      ? Colors.cyanAccent
                      : (isSettling ? Colors.amberAccent : Colors.white10),
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
                      color: isTracking
                          ? Colors.cyanAccent
                          : (isSettling ? Colors.amberAccent : Colors.white60),
                      boxShadow: isTracking
                          ? [
                              const BoxShadow(
                                color: Colors.cyanAccent,
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isTracking
                        ? 'TRACKING (Air Mouse Active)'
                        : (isSettling ? 'SETTLING (120ms zeroing)' : 'INACTIVE (Press & Hold Below)'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isTracking
                          ? Colors.cyanAccent
                          : (isSettling ? Colors.amberAccent : Colors.white60),
                    ),
                  ),
                ],
              ),
            ),

            // Main Interactive Area: HOLD TO MOVE (Left) + SCROLL ZONE (Right)
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Left Side: Hold-to-Move Activation Surface Area
                    Expanded(
                      flex: 3,
                      child: Listener(
                        onPointerDown: _onHoldPointerDown,
                        onPointerUp: _onHoldPointerUp,
                        onPointerCancel: _onHoldPointerCancel,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isTracking
                                ? Colors.blueAccent.withValues(alpha: 0.15)
                                : (isSettling
                                    ? Colors.amberAccent.withValues(alpha: 0.1)
                                    : const Color(0xFF1B1B22)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isTracking
                                  ? Colors.blueAccent
                                  : (isSettling ? Colors.amberAccent : Colors.white12),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.screen_rotation,
                                  size: 44,
                                  color: isTracking
                                      ? Colors.cyanAccent
                                      : (isSettling ? Colors.amberAccent : Colors.white30),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  isTracking
                                      ? 'Move Phone to Control Cursor'
                                      : 'HOLD TO MOVE POINTER',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: isTracking
                                        ? Colors.white
                                        : (isSettling ? Colors.amberAccent : Colors.white54),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Touch & hold anywhere inside this area',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Right Side: Dedicated Motion Vertical Scroll Zone Widget
                    SizedBox(
                      width: 72,
                      child: Listener(
                        onPointerDown: _onScrollPointerDown,
                        onPointerMove: _onScrollPointerMove,
                        onPointerUp: _onScrollPointerUp,
                        onPointerCancel: _onScrollPointerCancel,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16161D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.swap_vert, color: Colors.cyanAccent, size: 20),
                                  const SizedBox(height: 6),
                                  RotatedBox(
                                    quarterTurns: 3,
                                    child: Text(
                                      'SCROLL ZONE',
                                      style: TextStyle(
                                        color: Colors.cyanAccent.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Swipe\n↑ / ↓',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.cyanAccent.withValues(alpha: 0.6),
                                      fontSize: 9,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Motion Sensitivity Control Bar & Scroll Sensitivity Controls (Collapse when Utility panel active)
            if (!_isUtilityPanelActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                margin: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Motion Sensitivity',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          '${widget.source.sensitivity.toStringAsFixed(1)} px/°',
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: widget.source.sensitivity,
                      min: 5.0,
                      max: 50.0,
                      divisions: 45,
                      activeColor: Colors.blueAccent,
                      inactiveColor: const Color(0xFF2A2A36),
                      onChanged: (val) {
                        widget.source.setSensitivity(val);
                      },
                      onChangeEnd: (val) {
                        widget.source.saveSensitivity(val);
                      },
                    ),
                  ],
                ),
              ),

              // Shared Scroll Sensitivity & Direction Controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.swap_vert, color: Colors.cyanAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('Scroll', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _scrollSensitivity,
                        min: 0.2,
                        max: 3.0,
                        divisions: 28,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.grey[800],
                        label: '${_scrollSensitivity.toStringAsFixed(1)}x',
                        onChanged: (val) {
                          setState(() => _scrollSensitivity = val);
                        },
                        onChangeEnd: (val) => _saveScrollSensitivity(val),
                      ),
                    ),
                    Text(
                      '${_scrollSensitivity.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    // Natural / Reverse Direction Toggle Switch
                    InkWell(
                      onTap: () => _saveScrollNatural(!_isNaturalScroll),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A36),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isNaturalScroll
                                ? Colors.cyanAccent.withValues(alpha: 0.5)
                                : Colors.orangeAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _isNaturalScroll ? 'Natural' : 'Reverse',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isNaturalScroll ? Colors.cyanAccent : Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Common Action Button Dock (LEFT CLICK   ⋯   RIGHT CLICK)
            SharedUtilitiesDock(
              transport: _transport,
              onPanelStateChanged: (isActive) {
                setState(() => _isUtilityPanelActive = isActive);
              },
              onLeftClick: () {
                HapticFeedback.lightImpact();
                widget.source.sendLeftClick();
              },
              onRightClick: () {
                HapticFeedback.lightImpact();
                widget.source.sendRightClick();
              },
            ),
          ],
        );
      },
    );
  }
}
