import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Intent-driven feedback; never called for individual streaming chunks.
abstract final class InteractionFeedback {
  static DateTime? _last;

  static void _emit(Future<void> Function() effect) {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final now = DateTime.now();
    if (_last != null &&
        now.difference(_last!) < const Duration(milliseconds: 100)) {
      return;
    }
    _last = now;
    // Unsupported platforms and unavailable native channels stay silent.
    unawaited(effect().catchError((Object _) {}));
  }

  static void selection() => _emit(HapticFeedback.selectionClick);
  static void action() => _emit(HapticFeedback.lightImpact);
  static void result() => _emit(HapticFeedback.mediumImpact);
}
