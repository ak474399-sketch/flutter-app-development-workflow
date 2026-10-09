import 'dart:async';
import 'package:flutter/material.dart';
import 'subscription.dart';

/// Supply localized text/status widgets and real store products; never fabricate prices.
class SubscriptionPaywall extends StatefulWidget {
  final SubscriptionController controller;
  final Widget hero;
  final String title, purchaseLabel, restoreLabel, closeLabel;
  final String Function(StoreProduct) planLabel;
  final Widget Function(SubscriptionState) status;
  final List<Widget> legalLinks;
  final VoidCallback onClose, onSuccess;
  final Duration closeDelay;
  const SubscriptionPaywall({
    super.key,
    required this.controller,
    required this.hero,
    required this.title,
    required this.purchaseLabel,
    required this.restoreLabel,
    required this.closeLabel,
    required this.planLabel,
    required this.status,
    required this.legalLinks,
    required this.onClose,
    required this.onSuccess,
    this.closeDelay = const Duration(seconds: 2),
  });
  @override
  State<SubscriptionPaywall> createState() => _SubscriptionPaywallState();
}

class _SubscriptionPaywallState extends State<SubscriptionPaywall> {
  Timer? _timer;
  bool _canClose = false, _finished = false;
  String? _selected;
  late int _initialRevision;
  @override
  void initState() {
    super.initState();
    _initialRevision = widget.controller.successRevision;
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(widget.closeDelay, () {
        if (mounted) setState(() => _canClose = true);
      });
    });
  }

  void _changed() {
    if (!mounted) return;
    if (widget.controller.state == SubscriptionState.active &&
        widget.controller.successRevision > _initialRevision &&
        !_finished) {
      _finished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSuccess();
      });
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(SubscriptionPaywall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _initialRevision = widget.controller.successRevision;
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _close() {
    if (!_finished && _canClose) {
      _finished = true;
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.products.any((p) => p.id == _selected))
      _selected = c.products.firstOrNull?.id;
    return Scaffold(
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 720 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.2;
            final heroHeight = constraints.maxHeight * (compact ? .28 : .5);
            return Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: heroHeight,
                      width: double.infinity,
                      child: widget.hero,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 16),
                                for (final p in c.products)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Semantics(
                                      selected: p.id == _selected,
                                      button: true,
                                      child: InkWell(
                                        onTap: c.busy
                                            ? null
                                            : () => setState(
                                                () => _selected = p.id,
                                              ),
                                        borderRadius: BorderRadius.circular(18),
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: p.id == _selected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primaryContainer
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainer,
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              width: 2,
                                              color: p.id == _selected
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(widget.planLabel(p)),
                                              Text(p.price),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                widget.status(c.state),
                                FilledButton(
                                  onPressed:
                                      c.busy || _selected == null || _finished
                                      ? null
                                      : () => c.purchase(_selected!),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(48, 52),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Text(widget.purchaseLabel),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  children: widget.legalLinks,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: MediaQuery.paddingOf(context).top + 6,
                  child: Row(
                    children: [
                      _canClose
                          ? IconButton(
                              key: const ValueKey('subscription_close'),
                              tooltip: widget.closeLabel,
                              onPressed: _finished ? null : _close,
                              icon: const Icon(Icons.close_rounded, size: 32),
                              color: Colors.white,
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                            )
                          : const SizedBox(width: 48, height: 48),
                      const Spacer(),
                      Flexible(
                        child: TextButton(
                          onPressed: c.busy || _finished ? null : c.restore,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(72, 48),
                            textStyle: const TextStyle(
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          child: Text(widget.restoreLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
