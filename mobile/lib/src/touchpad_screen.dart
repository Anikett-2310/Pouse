import 'package:flutter/material.dart';
import 'main_screen.dart';

/// Legacy screen entrypoint alias for backward compatibility.
///
/// Delegates to [MainScreen].
class TouchpadScreen extends StatelessWidget {
  const TouchpadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainScreen();
  }
}
