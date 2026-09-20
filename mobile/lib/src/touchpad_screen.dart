import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_service.dart';

class TouchpadScreen extends StatefulWidget {
  const TouchpadScreen({super.key});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  final WebSocketService _wsService = WebSocketService();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();

  double _sensitivity = 1.2;
  int _pointerCount = 0;
  bool _isKeyboardVisible = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
    _wsService.errorNotifier.addListener(_onErrorChanged);
  }

  void _onErrorChanged() {
    final error = _wsService.errorNotifier.value;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('pouse_pc_ip') ?? '';
    _ipController.text = savedIp;
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pouse_pc_ip', ip);
  }

  void _toggleConnection() {
    setState(() {
      _pointerCount = 0;
      _isDragging = false;
    });
    if (_wsService.status == ConnectionStatus.connected) {
      _wsService.disconnect();
    } else {
      final ip = _ipController.text.trim();
      if (ip.isNotEmpty) {
        _saveIp(ip);
        _wsService.connect(ip);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your PC IP address')),
        );
      }
    }
  }

  @override
  void dispose() {
    _wsService.errorNotifier.removeListener(_onErrorChanged);
    _wsService.disconnect();
    _ipController.dispose();
    _textController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.mouse, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text(
              'Pouse Touchpad',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E24),
        elevation: 0,
        actions: [
          ValueListenableBuilder<ConnectionStatus>(
            valueListenable: _wsService.statusNotifier,
            builder: (context, status, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Chip(
                  avatar: CircleAvatar(
                    radius: 5,
                    backgroundColor: _getStatusColor(status),
                  ),
                  label: Text(
                    status.name.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: const Color(0xFF2A2A36),
                  side: BorderSide.none,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1E1E24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'PC IP Address (e.g. 192.168.1.100)',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF2A2A36),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.wifi, color: Colors.blueAccent, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder<ConnectionStatus>(
                  valueListenable: _wsService.statusNotifier,
                  builder: (context, status, child) {
                    final isConnected = status == ConnectionStatus.connected;
                    final isConnecting = status == ConnectionStatus.connecting;

                    return ElevatedButton(
                      onPressed: isConnecting ? null : _toggleConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected ? Colors.redAccent : Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isConnecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              isConnected ? 'Disconnect' : 'Connect',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Hidden Keyboard Listener TextField
          Offstage(
            offstage: !_isKeyboardVisible,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (KeyEvent event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.enter) {
                      _wsService.sendKeyPress('enter');
                    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
                      _wsService.sendKeyPress('backspace');
                    }
                  }
                },
                child: TextField(
                  controller: _textController,
                  focusNode: _keyboardFocusNode,
                  autofocus: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Type here to send text to PC...',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onChanged: (text) {
                    if (text.isNotEmpty) {
                      _wsService.sendTextInput(text);
                      _textController.clear();
                    }
                  },
                ),
              ),
            ),
          ),

          // Main Interactive Touchpad Surface
          Expanded(
            child: Listener(
              onPointerDown: (event) {
                setState(() => _pointerCount++);
              },
              onPointerUp: (event) {
                setState(() {
                  _pointerCount = (_pointerCount > 0) ? _pointerCount - 1 : 0;
                  if (_isDragging) {
                    _isDragging = false;
                    _wsService.sendButtonUp('left');
                  }
                });
              },
              onPointerCancel: (event) {
                setState(() {
                  _pointerCount = 0;
                  if (_isDragging) {
                    _isDragging = false;
                    _wsService.sendButtonUp('left');
                  }
                });
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_pointerCount <= 1) {
                    _wsService.sendLeftClick();
                  }
                },
                onDoubleTap: () {
                  _wsService.sendDoubleClick();
                },
                onSecondaryTap: () {
                  _wsService.sendRightClick();
                },
                onLongPressStart: (_) {
                  _isDragging = true;
                  _wsService.sendButtonDown('left');
                  HapticFeedback.heavyImpact();
                },
                onLongPressEnd: (_) {
                  if (_isDragging) {
                    _isDragging = false;
                    _wsService.sendButtonUp('left');
                  }
                },
                onLongPressCancel: () {
                  if (_isDragging) {
                    _isDragging = false;
                    _wsService.sendButtonUp('left');
                  }
                },
                onScaleUpdate: (ScaleUpdateDetails details) {
                  final count = details.pointerCount;
                  if (count == 2 || _pointerCount == 2) {
                    // Two-finger gesture = Scroll
                    final dy = details.focalPointDelta.dy * 0.5;
                    final dx = details.focalPointDelta.dx * 0.5;
                    if (dy.abs() > 0.1 || dx.abs() > 0.1) {
                      _wsService.sendScroll(dx, dy);
                    }
                  } else if (count == 1 || _pointerCount <= 1) {
                    // One-finger gesture = Move Cursor
                    final dx = details.focalPointDelta.dx * _sensitivity;
                    final dy = details.focalPointDelta.dy * _sensitivity;
                    if (dx != 0 || dy != 0) {
                      _wsService.sendMove(dx, dy);
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2E2E3E), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'TOUCHPAD SURFACE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.2),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '1 Finger Move  •  Tap Left Click\n2 Finger Scroll  •  2 Finger Tap Right Click',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.15),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Control Dock & Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E1E24),
            child: Column(
              children: [
                // Sensitivity Slider
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 8),
                    const Text('Sensitivity', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _sensitivity,
                        min: 0.5,
                        max: 3.0,
                        divisions: 25,
                        activeColor: Colors.blueAccent,
                        inactiveColor: Colors.grey[800],
                        label: '${_sensitivity.toStringAsFixed(1)}x',
                        onChanged: (val) {
                          setState(() => _sensitivity = val);
                        },
                      ),
                    ),
                    Text(
                      '${_sensitivity.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Mouse Buttons Bar (Left Click, Keyboard Toggle, Right Click)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _wsService.sendLeftClick(),
                        icon: const Icon(Icons.mouse_outlined, size: 18),
                        label: const Text('Left Click'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A36),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        setState(() {
                          _isKeyboardVisible = !_isKeyboardVisible;
                        });
                        if (_isKeyboardVisible) {
                          _keyboardFocusNode.requestFocus();
                        } else {
                          _keyboardFocusNode.unfocus();
                        }
                      },
                      icon: Icon(_isKeyboardVisible ? Icons.keyboard_hide : Icons.keyboard),
                      style: IconButton.styleFrom(
                        backgroundColor: _isKeyboardVisible ? Colors.blueAccent : const Color(0xFF2A2A36),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _wsService.sendRightClick(),
                        icon: const Icon(Icons.mouse_outlined, size: 18),
                        label: const Text('Right Click'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A36),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.greenAccent;
      case ConnectionStatus.connecting:
        return Colors.orangeAccent;
      case ConnectionStatus.error:
        return Colors.redAccent;
      case ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }
}
