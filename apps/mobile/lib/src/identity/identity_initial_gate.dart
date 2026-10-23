import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_session_controller.dart';
import '../design_system/telegram_theme.dart';
import 'identity_management_controller.dart';
import 'identity_management_screen.dart';

/// Lives in home, beneath the registration recovery-code/Passkey route. A
/// confirmed nonempty directory survives ordinary management load/cancel events
/// only within this exact account/token/authorization window.
class IdentityInitialGate extends StatefulWidget {
  const IdentityInitialGate({
    super.key,
    required this.controller,
    required this.sessions,
    required this.child,
  });
  final IdentityManagementController controller;
  final AuthSessionController sessions;
  final Widget child;
  @override
  State<IdentityInitialGate> createState() => _IdentityInitialGateState();
}

class _IdentityInitialGateState extends State<IdentityInitialGate> {
  Object? _window;
  bool _confirmed = false, _empty = false, _queued = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.sessions.addListener(_changed);
    _observe();
  }

  void _observe() {
    final next = widget.controller.authorityKey;
    if (_window != next) {
      _window = next;
      _confirmed = false;
      _empty = false;
    }
    final directory = widget.controller.directory;
    if (next != null &&
        widget.controller.status == IdentityManagementStatus.ready &&
        directory != null) {
      _confirmed = directory.identities.isNotEmpty;
      _empty = directory.identities.isEmpty;
    }
    if (next != null &&
        !_confirmed &&
        !_empty &&
        !_queued &&
        !widget.controller.busy &&
        widget.controller.status == IdentityManagementStatus.idle &&
        widget.controller.errorMessage == null) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (mounted && _window == next && !widget.controller.busy) {
          unawaited(widget.controller.load());
        }
      });
    }
  }

  void _changed() {
    if (mounted) setState(_observe);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.sessions.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed || widget.controller.entryReady) return widget.child;
    final p = HhTelegramPalette.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            const ModalBarrier(dismissible: false, color: Color(0x33000000)),
            Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              backgroundColor: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: p.line),
              ),
              child: _empty && !widget.controller.hasPending
                  ? IdentityEditor(
                      key: ValueKey(_window),
                      controller: widget.controller,
                      sessions: widget.sessions,
                      requiredInitial: true,
                    )
                  : IdentityPendingPanel(
                      controller: widget.controller,
                      sessions: widget.sessions,
                      requiredInitial: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
