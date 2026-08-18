import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.controller,
    required this.onFinished,
    this.requestMicrophonePermission,
    super.key,
  });

  final MeshController controller;
  final Future<void> Function() onFinished;
  final Future<bool> Function()? requestMicrophonePermission;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _nicknameController = TextEditingController();
  var _page = 0;
  var _busy = false;
  var _prepared = false;
  var _microphoneGranted = false;

  @override
  void dispose() {
    _pages.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page == 0) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (_page == 1) {
      setState(() => _busy = true);
      await widget.controller.start();
      if (!mounted) return;
      setState(() => _busy = false);
      final currentNickname = widget.controller.nickname;
      if (_nicknameController.text.isEmpty &&
          currentNickname.isNotEmpty &&
          !isDefaultMeshNickname(currentNickname)) {
        _nicknameController.text = currentNickname;
      }
      await _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() => _busy = true);
    final nickname = _nicknameController.text.trim();
    if (nickname.isNotEmpty && nickname != widget.controller.nickname) {
      await widget.controller.updateNickname(nickname);
    }
    if (!_prepared) {
      await widget.controller.ensureAlwaysLocation();
      final microphoneGranted = await _requestMicrophonePermission();
      if (!widget.controller.ignoringBatteryOptimizations) {
        await widget.controller.requestDisableBatteryOptimizations();
      }
      if (!mounted) return;
      setState(() {
        _microphoneGranted = microphoneGranted;
        _prepared = true;
        _busy = false;
      });
      return;
    }
    await widget.onFinished();
  }

  Future<bool> _requestMicrophonePermission() async {
    final request = widget.requestMicrophonePermission;
    if (request != null) return request();
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission();
    } finally {
      await recorder.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 6,
                      margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                      decoration: BoxDecoration(
                        color: index <= _page
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _OnboardingPage(
                    icon: Icons.cell_tower_outlined,
                    title: context.l10n.onboardingWelcomeTitle,
                    body: context.l10n.onboardingWelcomeBody,
                  ),
                  _OnboardingPage(
                    icon: Icons.hub_outlined,
                    title: context.l10n.onboardingMeshTitle,
                    body: context.l10n.onboardingMeshBody,
                  ),
                  _OnboardingPage(
                    icon: Icons.shield_outlined,
                    title: context.l10n.onboardingReadyTitle,
                    body: context.l10n.onboardingReadyBody,
                    child: Column(
                      children: [
                        TextField(
                          controller: _nicknameController,
                          maxLength: 31,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: context.l10n.onboardingNicknameLabel,
                            hintText: context.l10n.nicknameDialogHint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        _PermissionChecklist(
                          controller: widget.controller,
                          microphoneGranted: _microphoneGranted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.controller.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.controller.lastError!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _next,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _page == 0
                                ? Icons.arrow_forward
                                : _page == 1
                                ? Icons.bluetooth
                                : Icons.check,
                          ),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(switch (_page) {
                        0 => context.l10n.onboardingNext,
                        1 => context.l10n.onboardingAllowMesh,
                        _ =>
                          _prepared
                              ? context.l10n.onboardingFinish
                              : context.l10n.onboardingAllowLocation,
                      }, textAlign: TextAlign.center),
                    ),
                  ),
                  if (_page > 0) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _pages.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                      child: Text(context.l10n.onboardingBack),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionChecklist extends StatelessWidget {
  const _PermissionChecklist({
    required this.controller,
    required this.microphoneGranted,
  });

  final MeshController controller;
  final bool microphoneGranted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PermissionStatus(
          granted: controller.canSend,
          title: context.l10n.onboardingAllowMesh,
          detail: controller.canSend
              ? context.l10n.adaptivePowerNormal
              : controller.lastError ?? context.l10n.errorPermissions,
        ),
        _PermissionStatus(
          granted: controller.backgroundLocationGranted,
          title: context.l10n.onboardingAllowLocation,
          detail: controller.backgroundLocationGranted
              ? context.l10n.powerLocationAndroid
              : context.l10n.rescueModeNoBackgroundLocation,
        ),
        _PermissionStatus(
          granted: controller.ignoringBatteryOptimizations,
          title: context.l10n.powerBatteryOptimization,
          detail: controller.ignoringBatteryOptimizations
              ? context.l10n.adaptivePowerNormal
              : context.l10n.powerSaverAndroid,
        ),
        _PermissionStatus(
          granted: microphoneGranted,
          title: context.l10n.onboardingAllowMicrophone,
          detail: microphoneGranted
              ? context.l10n.onboardingMicrophoneReady
              : context.l10n.onboardingMicrophoneRequired,
        ),
      ],
    );
  }
}

class _PermissionStatus extends StatelessWidget {
  const _PermissionStatus({
    required this.granted,
    required this.title,
    required this.detail,
  });

  final bool granted;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          granted ? Icons.check_circle : Icons.info_outline,
          color: granted ? scheme.primary : scheme.error,
        ),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 96,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    title,
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.5),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (child != null) ...[const SizedBox(height: 24), child!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
