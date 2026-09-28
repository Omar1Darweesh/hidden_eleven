import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/app.dart';

void main() {
  // In debug/profile, show full widget error text for developers. In release,
  // show a generic message — never stack traces on player screens.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return Material(
        color: const Color(0xFF2A0E0E),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'WIDGET ERROR:\n\n${details.exceptionAsString()}\n\n'
            '${details.stack}',
            style: const TextStyle(
              color: Color(0xFFFF6B6B),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      );
    }
    return const Material(
      color: Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong. Please refresh the page or return to the home screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB0B0C0), fontSize: 14),
          ),
        ),
      ),
    );
  };

  // Minified release JS gives an unreadable stack (symbol names, no source
  // locations) for anything that reaches the browser console unhandled. This
  // surfaces the actual Dart exception message/stack via print instead, which
  // isn't minified — it's data the exception carries, not compiled code.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print(
      'UNHANDLED FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // ignore: avoid_print
    print('UNHANDLED PLATFORM ERROR: $error\n$stack');
    return true;
  };

  runApp(const ProviderScope(child: HiddenElevenApp()));
}
