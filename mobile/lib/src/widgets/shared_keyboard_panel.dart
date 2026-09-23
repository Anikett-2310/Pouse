import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../websocket_service.dart';

/// Reusable soft keyboard panel widget shared across Pouse mouse modes.
///
/// Houses text input synchronization, multiline support with blue action key
/// handling, hardware key event interception (Esc),
/// and quick action buttons.
class SharedKeyboardPanel extends StatefulWidget {
  final WebSocketService wsService;

  const SharedKeyboardPanel({
    super.key,
    required this.wsService,
  });

  @override
  State<SharedKeyboardPanel> createState() => _SharedKeyboardPanelState();
}

class _SharedKeyboardPanelState extends State<SharedKeyboardPanel> {
  late final TextEditingController _textController;
  late final FocusNode _keyboardFocusNode;
  late final FocusNode _listenerFocusNode;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _keyboardFocusNode = FocusNode();
    _listenerFocusNode = FocusNode();

    // Auto-request focus when panel is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _keyboardFocusNode.dispose();
    _listenerFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (text == _lastText) return;

    // Calculate common prefix length
    int prefixLen = 0;
    final minLen = text.length < _lastText.length ? text.length : _lastText.length;
    while (prefixLen < minLen && text[prefixLen] == _lastText[prefixLen]) {
      prefixLen++;
    }

    // Determine how many characters were deleted from _lastText
    final backspaceCount = _lastText.length - prefixLen;
    for (int i = 0; i < backspaceCount; i++) {
      widget.wsService.sendKeyPress('backspace');
    }

    // Determine inserted text
    if (text.length > prefixLen) {
      final inserted = text.substring(prefixLen);
      widget.wsService.sendTextInput(inserted);
    }

    _lastText = text;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1E1E24),
      child: Row(
        children: [
          Expanded(
            child: KeyboardListener(
              focusNode: _listenerFocusNode,
              onKeyEvent: (KeyEvent event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.wsService.sendKeyPress('escape');
                  }
                }
              },
              child: TextField(
                controller: _textController,
                focusNode: _keyboardFocusNode,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type here to send text to PC...',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF2A2A36),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onTextChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Quick Esc Key Control
          ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.wsService.sendKeyPress('escape');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A36),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Esc', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 6),
          // Quick Enter Key Control
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.wsService.sendKeyPress('enter');
            },
            icon: const Icon(Icons.keyboard_return, size: 16),
            label: const Text('Enter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

