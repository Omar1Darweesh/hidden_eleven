import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';

/// Blocks the admin panel until a valid API key is provided (when the server
/// requires one). Local dev without ADMIN_API_KEY passes through immediately.
class AdminAuthGate extends StatefulWidget {
  const AdminAuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<AdminAuthGate> {
  bool _checking = true;
  bool _authenticated = false;
  String? _error;

  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await AdminApi.verifyAdminAccess();
      if (!mounted) return;
      setState(() {
        _authenticated = true;
        _checking = false;
      });
    } on AdminAuthException {
      if (!mounted) return;
      setState(() {
        _authenticated = false;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authenticated = false;
        _checking = false;
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  Future<void> _signIn() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter your admin API key.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    await AdminAuthService.saveToken(key);
    try {
      await AdminApi.verifyAdminAccess();
      if (!mounted) return;
      setState(() {
        _authenticated = true;
        _submitting = false;
      });
    } on AdminAuthException {
      await AdminAuthService.clearToken();
      if (!mounted) return;
      setState(() {
        _error = 'Invalid admin API key.';
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. Check your connection.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: HEColors.background,
        body: Center(child: CircularProgressIndicator(color: HEColors.accent)),
      );
    }
    if (_authenticated) return widget.child;
    return Scaffold(
      backgroundColor: HEColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: HEColors.accent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin sign in',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HEColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the server ADMIN_API_KEY to manage catalog data, '
                  'scoring, and uploads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HEColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _keyController,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: HEColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Admin API key',
                    labelStyle: const TextStyle(color: HEColors.textSecondary),
                    filled: true,
                    fillColor: HEColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HERadius.sm),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: HEColors.textMuted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: HEColors.error, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _signIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: HEColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HERadius.sm),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign in',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
