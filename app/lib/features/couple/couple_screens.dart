import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../src/rust/api/crypto.dart';
import '../../ui/love.dart';
import '../auth/auth_service.dart';
import 'couple_service.dart';

String _pretty(String code) => code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

TextStyle? _title(BuildContext c) =>
    Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.08);
TextStyle? _soft(BuildContext c) =>
    Theme.of(c).textTheme.bodyLarge?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.4);

// ===================================================================== aiguillage

/// Oriente vers le bon écran selon l'état du couple.
class CoupleGate extends StatefulWidget {
  const CoupleGate({super.key, required this.auth, required this.couple});

  final AuthService auth;
  final CoupleService couple;

  @override
  State<CoupleGate> createState() => _CoupleGateState();
}

class _CoupleGateState extends State<CoupleGate> {
  late Future<CoupleState> _state = widget.couple.load();

  void _reload() => setState(() => _state = widget.couple.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoupleState>(
      future: _state,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Message(
            title: 'Petit souci de connexion',
            body: 'Impossible de joindre votre espace pour le moment. Vérifie ta connexion puis réessaie.',
            action: ('Réessayer', _reload),
          );
        }
        final s = snap.data;
        if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (!s.hasCouple) return ChoiceScreen(couple: widget.couple, onDone: _reload, auth: widget.auth);
        if (!s.complete || s.partnerIdentity == null) return InviteScreen(couple: widget.couple, onPartner: _reload);
        if (!s.verified) {
          return VerifyScreen(
            couple: widget.couple,
            partnerId: s.partnerId!,
            partnerIdentity: s.partnerIdentity!,
            onVerified: _reload,
          );
        }
        return GardenHome(auth: widget.auth);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, required this.action});

  final String title;
  final String body;
  final (String, VoidCallback) action;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PetalBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Spacer(),
                Text(title, style: _title(context)),
                const SizedBox(height: 10),
                Text(body, style: _soft(context)),
                const Spacer(),
                FilledButton(onPressed: action.$2, child: Text(action.$1)),
              ]),
            ),
          ),
        ),
      );
}

// ===================================================================== choix

class ChoiceScreen extends StatefulWidget {
  const ChoiceScreen({super.key, required this.couple, required this.onDone, required this.auth});

  final CoupleService couple;
  final VoidCallback onDone;
  final AuthService auth;

  @override
  State<ChoiceScreen> createState() => _ChoiceScreenState();
}

class _ChoiceScreenState extends State<ChoiceScreen> {
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await widget.couple.createCouple();
      HapticFeedback.mediumImpact();
      widget.onDone();
    } catch (e, st) {
      // Journal technique en mode développement uniquement (aucune donnée personnelle).
      if (kDebugMode) debugPrint('[FOULOVE] création de l\'espace : $e\n$st');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La création de votre espace n\'a pas abouti. Réessaie dans un instant.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PetalBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: widget.auth.signOut, child: const Text('Se déconnecter')),
                ),
                const Spacer(),
                const Center(child: EntwinedHeart(size: 230)),
                const SizedBox(height: 18),
                Text('Deux tiges,\nun seul jardin.', style: _title(context), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'Crée votre espace et invite la personne que tu aimes, ou rejoins celui qu\'elle a déjà planté.',
                  style: _soft(context),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.spa_outlined),
                    label: const Text('Créer notre espace'),
                    onPressed: _create,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('J\'ai reçu une invitation'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => JoinScreen(couple: widget.couple, onJoined: () {
                        Navigator.of(context).pop();
                        widget.onDone();
                      }),
                    )),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== invitation (côté créateur)

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.couple, required this.onPartner});

  final CoupleService couple;
  final VoidCallback onPartner;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  String? _code;
  String? _qr;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _newCode();
    // Toutes les 3 secondes : Malik a-t-il rejoint ?
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      final s = await widget.couple.load();
      if (s.complete && s.partnerIdentity != null) {
        _poll?.cancel();
        await widget.couple.receiveHello(s.partnerId!);
        HapticFeedback.heavyImpact();
        widget.onPartner();
      }
    });
  }

  Future<void> _newCode({bool forceNew = false}) async {
    try {
      final code = await widget.couple.currentInvitation(forceNew: forceNew);
      final qr = await widget.couple.qrPayload(code);
      if (mounted) {
        setState(() {
          _code = code;
          _qr = qr;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: PetalBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Text('Invite ton amour', style: _title(context)),
              const SizedBox(height: 8),
              Text('Montre-lui ce code à scanner, ou envoie-lui les 10 caractères.', style: _soft(context)),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [BoxShadow(color: cs.secondary.withValues(alpha: .28), blurRadius: 40, spreadRadius: 2)],
                  ),
                  child: _qr == null
                      ? const SizedBox.square(dimension: 220, child: Center(child: CircularProgressIndicator()))
                      : QrImageView(
                          data: _qr!,
                          size: 220,
                          backgroundColor: cs.surfaceContainer,
                          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: cs.primary),
                          dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: cs.onSurface),
                          semanticsLabel: 'QR code d\'invitation',
                        ),
                ),
              ),
              const SizedBox(height: 22),
              if (_code != null) ...[
                Center(
                  child: SelectableText(
                    _pretty(_code!),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(child: Text('Valable 24 h, une seule fois', style: _soft(context)?.copyWith(fontSize: 13))),
                Center(
                  child: TextButton(
                    onPressed: () => _newCode(forceNew: true),
                    child: const Text('Générer un nouveau code'),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copier'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _pretty(_code!)));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié')));
                      },
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Envoyer'),
                      onPressed: () => SharePlus.instance.share(ShareParams(
                        text: 'Rejoins-moi sur FouLove 💞\nCode d\'invitation : ${_pretty(_code!)}',
                      )),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              const Center(child: BeatingHeart(size: 46)),
              Center(child: Text('En attente de ton amour…', style: _soft(context))),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================== rejoindre

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.couple, required this.onJoined});

  final CoupleService couple;
  final VoidCallback onJoined;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  bool _scan = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit(String input) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.couple.join(input);
      switch (r) {
        case JoinResult.joined:
          HapticFeedback.heavyImpact();
          widget.onJoined();
          return;
        case JoinResult.invalidCode:
          _error = 'Ce code ne fonctionne pas. Il a peut-être expiré ou déjà servi : demande un nouveau code.';
        case JoinResult.keyMismatch:
          _error = 'Les clés reçues ne correspondent pas au QR code. Par sécurité, l\'appairage est arrêté. '
              'Recommencez ensemble avec un nouveau code.';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] rejoindre : $e');
      final m = e.toString();
      _error = m.contains('trop de tentatives')
          ? 'Trop de tentatives. Patiente une heure avant de réessayer.'
          : 'Impossible de rejoindre pour le moment. Réessaie dans un instant.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final normalized = _code.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Rejoindre')),
      body: PetalBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.qr_code_scanner), label: Text('Scanner')),
                    ButtonSegment(value: false, icon: Icon(Icons.keyboard_outlined), label: Text('Saisir le code')),
                  ],
                  selected: {_scan},
                  onSelectionChanged: (v) => setState(() => _scan = v.first),
                ),
                const SizedBox(height: 20),
                if (_scan)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(fit: StackFit.expand, children: [
                        MobileScanner(
                          controller: MobileScannerController(formats: const [BarcodeFormat.qrCode]),
                          onDetect: (cap) {
                            final v = cap.barcodes.firstOrNull?.rawValue;
                            if (v != null && v.startsWith(CoupleService.qrPrefix)) _submit(v);
                          },
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 230,
                              height: 230,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(color: cs.secondary, width: 3),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  )
                else ...[
                  Text('Le code que ton amour t\'a envoyé', style: _soft(context)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 11,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(hintText: 'K7Q4M-9XHPT', border: OutlineInputBorder(), counterText: ''),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => normalized.length == 10 ? _submit(normalized) : null,
                  ),
                  const Spacer(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
                const SizedBox(height: 14),
                if (_busy)
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                else if (!_scan)
                  FilledButton(onPressed: normalized.length == 10 ? () => _submit(normalized) : null, child: const Text('Rejoindre')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== vérification des 7 symboles

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.couple, required this.partnerId, required this.partnerIdentity, required this.onVerified});

  final CoupleService couple;
  final String partnerId;
  final Uint8List partnerIdentity;
  final VoidCallback onVerified;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> with SingleTickerProviderStateMixin {
  late final Future<List<SasSymbol>> _symbols = widget.couple.symbols(widget.partnerIdentity);
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  bool _mismatch = false;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _same() async {
    await widget.couple.confirmSymbols(widget.partnerId);
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
    ));
    widget.onVerified();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: PetalBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Scellez votre lien', style: _title(context)),
                const SizedBox(height: 8),
                Text(
                  'Vos deux téléphones affichent ces 7 symboles. Lisez-les ensemble, à voix haute ou en appel vidéo.',
                  style: _soft(context),
                ),
                const SizedBox(height: 26),
                FutureBuilder<List<SasSymbol>>(
                  future: _symbols,
                  builder: (context, snap) {
                    final s = snap.data;
                    if (s == null) return const Center(child: CircularProgressIndicator());
                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < s.length; i++)
                          AnimatedBuilder(
                            animation: _in,
                            builder: (context, child) {
                              final t = Curves.easeOutBack.transform(((_in.value - i * .08) / .44).clamp(0.0, 1.0));
                              return Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: .6 + .4 * t, child: child));
                            },
                            child: Container(
                              width: 92,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainer,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [BoxShadow(color: cs.secondary.withValues(alpha: .15), blurRadius: 18)],
                              ),
                              child: Column(children: [
                                Text(s[i].emoji, style: const TextStyle(fontSize: 38)),
                                const SizedBox(height: 4),
                                Text(s[i].name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const Spacer(),
                if (_mismatch)
                  Text(
                    'N\'allez pas plus loin. Quelqu\'un pourrait s\'être glissé entre vous. Supprimez cet espace et '
                    'recommencez ensemble, de préférence côte à côte avec le QR code.',
                    style: TextStyle(color: cs.error),
                  )
                else ...[
                  Row(children: [
                    Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Ils prouvent que personne ne s\'est glissé entre vous.',
                          style: _soft(context)?.copyWith(fontSize: 13)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  FilledButton.icon(icon: const Icon(Icons.favorite), label: const Text('Ce sont les mêmes'), onPressed: _same),
                  TextButton(onPressed: () => setState(() => _mismatch = true), child: const Text('Un symbole est différent')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== célébration

class CelebrationScreen extends StatelessWidget {
  const CelebrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PetalBackground(
        count: 24,
        child: Stack(children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Center(child: EntwinedHeart(size: 240)),
                  const SizedBox(height: 18),
                  Text('Votre jardin est né.', style: _title(context), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    'Désormais, tout ce que vous vous envoyez est chiffré sur vos deux téléphones. Rien que vous deux.',
                    style: _soft(context),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entrer dans notre jardin')),
                ],
              ),
            ),
          ),
          const Positioned.fill(child: PetalBurst()),
        ]),
      ),
    );
  }
}

// ===================================================================== accueil (provisoire)

class GardenHome extends StatelessWidget {
  const GardenHome({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PetalBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: auth.signOut, child: const Text('Se déconnecter')),
                ),
                const Spacer(),
                const Center(child: EntwinedHeart(size: 200)),
                const SizedBox(height: 16),
                Text('Jour 1', style: _title(context), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Votre jardin vient d\'être planté. Les messages arrivent bientôt.', style: _soft(context), textAlign: TextAlign.center),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
