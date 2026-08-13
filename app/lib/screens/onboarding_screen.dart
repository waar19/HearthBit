import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.controller,
    required this.onFinished,
    super.key,
  });

  final MeshController controller;
  final Future<void> Function() onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _nicknameController = TextEditingController();
  var _page = 0;
  var _busy = false;

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
    await widget.controller.ensureAlwaysLocation();
    if (!widget.controller.ignoringBatteryOptimizations) {
      await widget.controller.requestDisableBatteryOptimizations();
    }
    await widget.onFinished();
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
                    child: TextField(
                      controller: _nicknameController,
                      maxLength: 31,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: context.l10n.onboardingNicknameLabel,
                        hintText: context.l10n.nicknameDialogHint,
                        border: const OutlineInputBorder(),
                      ),
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
                        _ => context.l10n.onboardingFinish,
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
