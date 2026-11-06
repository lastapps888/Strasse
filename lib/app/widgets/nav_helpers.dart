import 'package:flutter/material.dart';

/// Ouvre une page avec une transition douce (fondu + léger glissement).
/// [reduce] supprime l'animation (réglage « réduire les animations »).
Future<T?> pushPage<T>(BuildContext context, Widget page, {bool reduce = false, bool fullscreenDialog = false}) {
  return Navigator.of(context).push<T>(
    reduce
        ? PageRouteBuilder<T>(pageBuilder: (_, __, ___) => page, transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero, fullscreenDialog: fullscreenDialog)
        : PageRouteBuilder<T>(
            fullscreenDialog: fullscreenDialog,
            transitionDuration: const Duration(milliseconds: 260),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (_, __, ___) => page,
            transitionsBuilder: (_, animation, __, child) {
              final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved), child: child),
              );
            },
          ),
  );
}

/// Remplace la page courante (utilisé pour passer de l'aperçu d'itinéraire à la navigation).
Future<T?> replacePage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).pushReplacement<T, void>(
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    ),
  );
}

/// Pile d'onglets avec fondu entre les pages. Les onglets déjà visités restent en vie (la carte n'est pas recréée).
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children, this.duration = const Duration(milliseconds: 180)});
  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration, value: 1);
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(covariant FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _visited.add(widget.index);
      if (widget.duration == Duration.zero) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Offstage(
              offstage: i != widget.index,
              child: TickerMode(
                enabled: i == widget.index,
                // Un onglet jamais visité n'est pas construit : démarrage plus rapide.
                child: _visited.contains(i) ? widget.children[i] : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
