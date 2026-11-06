import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/strasse_logo.dart';
import 'package:strasse/data/providers/providers.dart';

/// Présentation au premier lancement. Aucune permission n'est demandée ici :
/// la localisation est expliquée puis demandée seulement quand on en a besoin.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_Slide>[
    _Slide(logo: true, title: 'Explorez. Naviguez. Découvrez.', text: 'Une application de navigation gratuite, sans publicité, qui s\'appuie sur des données ouvertes.'),
    _Slide(icon: Icons.shield_outlined, title: 'Votre vie privée d\'abord', text: 'Pas de traceurs, pas de télémétrie. Votre position reste sur votre téléphone. Le compte est facultatif.'),
    _Slide(icon: Icons.map_outlined, title: 'Des cartes, même hors connexion', text: 'Téléchargez des zones pour afficher la carte sans réseau. Le calcul d\'un nouvel itinéraire dépend du serveur d\'itinéraires configuré.'),
    _Slide(icon: Icons.dns_outlined, title: 'Vos services', text: 'Strasse n\'embarque aucun serveur : renseignez vos services de cartes, d\'itinéraires et de recherche dans Réglages > Services (voir la documentation).'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() => ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true));

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    final cs = context.cs;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Passer')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (p.logo)
                          Column(children: [
                            const StrasseLogo(size: 140),
                            const SizedBox(height: 16),
                            Text('STRASSE', style: context.tt.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2)),
                          ])
                        else
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(color: cs.primary.withOpacity(0.12), shape: BoxShape.circle),
                            child: Icon(p.icon, size: 56, color: cs.primary),
                          ),
                        const SizedBox(height: 32),
                        Text(p.title, textAlign: TextAlign.center, style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        Text(p.text, textAlign: TextAlign.center, style: context.tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(color: i == _page ? cs.primary : cs.outlineVariant, borderRadius: BorderRadius.circular(4)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: last ? _finish : () => _controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
                  child: Text(last ? 'Commencer' : 'Suivant'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({this.logo = false, this.icon = Icons.circle, required this.title, required this.text});
  final bool logo;
  final IconData icon;
  final String title;
  final String text;
}
