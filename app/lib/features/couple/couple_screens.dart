import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../src/rust/api/crypto.dart';
import '../../src/rust/api/device.dart';
import '../../ui/love.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../backup/backup_service.dart';
import '../chat/home_shell.dart';
import '../chat/chat_service.dart';
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

class _CoupleGateState extends State<CoupleGate> with WidgetsBindingObserver {
  late Future<CoupleState> _state = widget.couple.load();
  CoupleState? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Écran « la clé a changé » : au retour dans l'app, on relit la clé publiée (elle a pu changer encore).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (_last?.keyChanged ?? false)) _reload();
  }

  // Après avoir rejoint par QR code, ce téléphone est déjà vérifié, mais il affiche quand même les symboles :
  // le partenaire en a besoin pour vérifier de son côté.
  bool _showSymbols = false;

  void _joined() {
    if (widget.couple.joinedWithInvitation) {
      // Invitation complète : clés vérifiées des deux côtés, sans symboles. On fête ça.
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
        ),
      );
    } else {
      _showSymbols = true;
    }
    _reload();
  }

  // Le chargement est lancé hors de setState, et l'affectation est dans un bloc : avec une flèche, « _state = next »
  // renverrait le Future lui-même, ce que setState refuse (et l'écran ne se redessinerait pas).
  void _reload() {
    final next = widget.couple.load();
    setState(() {
      _state = next;
    });
  }

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
        _last = s;
        if (!s.hasCouple) {
          return ChoiceScreen(couple: widget.couple, onDone: _reload, onJoined: _joined, auth: widget.auth);
        }
        if (!s.complete || s.partnerIdentity == null) return InviteScreen(couple: widget.couple, onPartner: _reload);
        // Nouvelle clé du partenaire : avant tout le reste, une nouvelle comparaison des symboles.
        if (s.keyChanged) {
          return KeyChangeScreen(
            couple: widget.couple,
            partnerId: s.partnerId!,
            newIdentity: s.partnerIdentity!,
            onDone: _reload,
          );
        }
        if (s.restoreFrom != null) {
          return RestoreScreen(couple: widget.couple, backupDate: s.restoreFrom!, onDone: _reload);
        }
        if (!s.verified || _showSymbols) {
          return VerifyScreen(
            couple: widget.couple,
            partnerId: s.partnerId!,
            partnerIdentity: s.partnerIdentity!,
            alreadyVerified: s.verified,
            onVerified: () {
              _showSymbols = false;
              _reload();
            },
          );
        }
        return _ChatHost(
          key: ValueKey(s.coupleId),
          state: s,
          auth: widget.auth,
          // Rechargé : une clé changée (bandeau de la conversation) mène à la nouvelle vérification.
          onShowSymbols: () {
            _showSymbols = true;
            _reload();
          },
        );
      },
    );
  }
}

/// Crée le service de messagerie pour la durée de l'écran (abonnement temps réel, boîte d'envoi).
class _ChatHost extends StatefulWidget {
  const _ChatHost({super.key, required this.state, required this.auth, required this.onShowSymbols});

  final CoupleState state;
  final AuthService auth;
  final VoidCallback onShowSymbols;

  @override
  State<_ChatHost> createState() => _ChatHostState();
}

class _ChatHostState extends State<_ChatHost> {
  late final ChatService _service = ChatService(
    Supabase.instance.client,
    partnerId: widget.state.partnerId!,
    coupleId: widget.state.coupleId!,
  );
  late final Future<void> _ready = _service.start();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snap) => snap.connectionState != ConnectionState.done
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : HomeShell(
            service: _service,
            since: widget.state.since,
            onShowSymbols: widget.onShowSymbols,
            onSignOut: widget.auth.signOut,
          ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, required this.action});

  final String title;
  final String body;
  final (String, VoidCallback) action;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LoveBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(title, style: _title(context)),
              const SizedBox(height: 10),
              Text(body, style: _soft(context)),
              const Spacer(),
              FilledButton(onPressed: action.$2, child: Text(action.$1)),
            ],
          ),
        ),
      ),
    ),
  );
}

// ===================================================================== choix

class ChoiceScreen extends StatefulWidget {
  const ChoiceScreen({
    super.key,
    required this.couple,
    required this.onDone,
    required this.onJoined,
    required this.auth,
  });

  final CoupleService couple;
  final VoidCallback onDone;
  final VoidCallback onJoined;
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
      body: LoveBackground(
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
                Text('Deux cœurs,\nune seule bulle.', style: _title(context), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'Crée votre bulle et invite la personne que tu aimes, ou rejoins celle qu\'elle a déjà créée.',
                  style: _soft(context),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.favorite_rounded),
                    label: const Text('Créer notre bulle'),
                    onPressed: _create,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('J\'ai reçu une invitation'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => JoinScreen(
                          couple: widget.couple,
                          onJoined: () {
                            Navigator.of(context).pop();
                            widget.onJoined();
                          },
                        ),
                      ),
                    ),
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
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  bool _checking = false;

  /// Une seule vérification à la fois : une requête lente ne doit pas en lancer une seconde en parallèle.
  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final s = await widget.couple.load();
      if (s.complete && s.partnerIdentity != null) {
        _poll?.cancel();
        await widget.couple.receiveHello(s.partnerId!);
        // Invitation complète : la preuve reçue vérifie sa clé, sans symboles.
        final verified = await widget.couple.verifyJoinProof(s.partnerId!);
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        if (verified) {
          await Navigator.of(context).push(
            PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 700),
              pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
            ),
          );
        }
        if (mounted) widget.onPartner();
      }
    } catch (e) {
      // Réseau momentané : on réessaie au passage suivant.
      if (kDebugMode) debugPrint('[FOULOVE] attente du partenaire : $e');
    } finally {
      _checking = false;
    }
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
      body: LoveBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Text('Invite ton amour', style: _title(context)),
              const SizedBox(height: 8),
              Text(
                'À distance : envoie-lui l\'invitation (WhatsApp, SMS…). À côté de toi : fais-lui scanner ce QR code. '
                'Dans les deux cas, vos clés se vérifient toutes seules.',
                style: _soft(context),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.send_rounded),
                label: const Text('Envoyer l\'invitation'),
                onPressed: _code == null
                    ? null
                    : () async =>
                          SharePlus.instance.share(ShareParams(text: await widget.couple.invitationText(_code!))),
              ),
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
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: cs.onSurface,
                          ),
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
                Center(
                  child: Text(
                    'Le code seul, à taper, marche aussi (il faudra alors comparer 7 symboles). Valable 24 h, une fois.',
                    textAlign: TextAlign.center,
                    style: _soft(context)?.copyWith(fontSize: 13),
                  ),
                ),
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
                      label: const Text('Copier l\'invitation'),
                      onPressed: () async {
                        final text = await widget.couple.invitationText(_code!);
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('Invitation copiée')));
                        }
                      },
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
  // Créé une seule fois : le recréer à chaque reconstruction relancerait la caméra.
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _scan = true;
  bool _busy = false;
  // Le scanner signale le même QR code plusieurs fois par seconde : on ne le traite qu'une fois.
  // Après un échec, il faut appuyer sur « Scanner à nouveau » (chaque essai compte dans la limite de 10 par heure).
  String? _scanned;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    final v = cap.barcodes.firstOrNull?.rawValue;
    if (v == null || !v.startsWith('foulove:') || _scanned != null) return;
    _scanned = v;
    _camera.stop();
    _submit(v);
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (CoupleService.parseInvitation(t) == null || !t.contains('foulove:')) {
      setState(() => _error = 'Aucune invitation dans le presse-papiers. Copie d\'abord tout le message reçu.');
      return;
    }
    await _submit(t);
  }

  void _rescan() {
    setState(() {
      _scanned = null;
      _error = null;
    });
    _camera.start();
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
          _error =
              'Les clés reçues ne correspondent pas au QR code. Par sécurité, l\'appairage est arrêté. '
              'Recommencez ensemble avec un nouveau code.';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] rejoindre : $e');
      final m = e.toString();
      if (m.contains('déjà dans un couple')) {
        // Ce compte a déjà un espace : l'aiguillage affiche le bon écran.
        widget.onJoined();
        return;
      }
      _error = m.contains('trop de tentatives')
          ? 'Trop de tentatives. Patiente une heure avant de réessayer.'
          : 'Impossible de rejoindre pour le moment. Vérifie ta connexion puis réessaie.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final normalized = _code.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Rejoindre')),
      body: LoveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.qr_code_scanner), label: Text('Scanner')),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.content_paste_rounded),
                      label: Text('Coller ou saisir'),
                    ),
                  ],
                  selected: {_scan},
                  onSelectionChanged: (v) => setState(() => _scan = v.first),
                ),
                const SizedBox(height: 20),
                if (_scan)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(controller: _camera, onDetect: _onDetect),
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
                        ],
                      ),
                    ),
                  )
                else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Coller l\'invitation'),
                    onPressed: _busy ? null : _paste,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Copie le message que ton amour t\'a envoyé, puis touche ce bouton. Ou tape juste le code :',
                    style: _soft(context),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 11,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'K7Q4M-9XHPT',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => normalized.length == 10 ? _submit(normalized) : null,
                  ),
                  const Spacer(),
                ],
                if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: cs.error))],
                const SizedBox(height: 14),
                if (_busy)
                  const Center(
                    child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
                  )
                else if (_scan && _scanned != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scanner à nouveau'),
                    onPressed: _rescan,
                  )
                else if (!_scan)
                  FilledButton(
                    onPressed: normalized.length == 10 ? () => _submit(normalized) : null,
                    child: const Text('Rejoindre'),
                  ),
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
  const VerifyScreen({
    super.key,
    required this.couple,
    required this.partnerId,
    required this.partnerIdentity,
    required this.onVerified,
    this.alreadyVerified = false,
  });

  final CoupleService couple;
  final String partnerId;
  final Uint8List partnerIdentity;
  final VoidCallback onVerified;

  /// Vrai si ce téléphone a déjà vérifié la clé du partenaire grâce au QR code.
  final bool alreadyVerified;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> with SingleTickerProviderStateMixin {
  late final Future<List<SasSymbol>> _symbols = widget.couple.symbols(widget.partnerIdentity);
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..forward();
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
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
      ),
    );
    widget.onVerified();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: LoveBackground(
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
                if (widget.alreadyVerified) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_outlined, size: 18, color: cs.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Le QR code a déjà confirmé la clé de ton amour sur ce téléphone. Montre-lui ces symboles : '
                          'ils doivent être identiques sur son écran.',
                          style: _soft(context)?.copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
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
                              return Opacity(
                                opacity: t.clamp(0.0, 1.0),
                                child: Transform.scale(scale: .6 + .4 * t, child: child),
                              );
                            },
                            child: Container(
                              width: 92,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainer,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [BoxShadow(color: cs.secondary.withValues(alpha: .15), blurRadius: 18)],
                              ),
                              child: Column(
                                children: [
                                  Text(s[i].emoji, style: const TextStyle(fontSize: 38)),
                                  const SizedBox(height: 4),
                                  Text(s[i].name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
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
                  Row(
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ils prouvent que personne ne s\'est glissé entre vous.',
                          style: _soft(context)?.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    icon: const Icon(Icons.favorite),
                    label: const Text('Ce sont les mêmes'),
                    onPressed: _same,
                  ),
                  TextButton(
                    onPressed: () => setState(() => _mismatch = true),
                    child: const Text('Un symbole est différent'),
                  ),
                  if (!widget.alreadyVerified)
                    LinkExchange(
                      couple: widget.couple,
                      partnerId: widget.partnerId,
                      identity: widget.partnerIdentity,
                      onVerified: _same,
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

/// À distance, sans appel : chacun envoie son « lien de retrouvailles » (l'empreinte de sa clé) par une autre
/// messagerie, et colle celui de l'autre. S'il correspond à la clé reçue, elle est vérifiée sans symboles.
class LinkExchange extends StatelessWidget {
  const LinkExchange({
    super.key,
    required this.couple,
    required this.partnerId,
    required this.identity,
    required this.onVerified,
    this.keyChange = false,
  });

  final CoupleService couple;
  final String partnerId;
  final Uint8List identity;
  final bool keyChange;
  final Future<void> Function() onVerified;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: cs.outline)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('ou à distance, par vos liens', style: _soft(context)?.copyWith(fontSize: 12.5)),
              ),
              Expanded(child: Divider(color: cs.outline)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Envoyer mon lien'),
                  onPressed: () async => SharePlus.instance.share(ShareParams(text: await couple.fingerprintLink())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Coller son lien'),
                  onPressed: () async {
                    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
                    final ok = await couple.acceptByLink(partnerId, identity, t, keyChange: keyChange);
                    if (!context.mounted) return;
                    if (ok) {
                      HapticFeedback.heavyImpact();
                      await onVerified();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            t.contains(CoupleService.idPrefix)
                                ? 'Ce lien ne correspond pas à la clé reçue. N\'allez pas plus loin : parlez-en de vive voix.'
                                : 'Copie d\'abord tout le message de ton amour, puis touche « Coller son lien ».',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
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
      body: LoveBackground(
        count: 24,
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const Center(child: EntwinedHeart(size: 240)),
                    const SizedBox(height: 18),
                    Text('Votre bulle est née.', style: _title(context), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    Text(
                      'Désormais, tout ce que vous vous envoyez est chiffré sur vos deux téléphones. Rien que vous deux.',
                      style: _soft(context),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Entrer dans notre bulle'),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned.fill(child: HeartBurst()),
          ],
        ),
      ),
    );
  }
}

// ===================================================================== nouveau téléphone du partenaire

/// La clé publiée par le partenaire a changé. Ses nouveaux messages restent en attente, illisibles, jusqu'à ce que
/// vous compariez les 7 symboles de cette nouvelle clé.
class KeyChangeScreen extends StatefulWidget {
  const KeyChangeScreen({
    super.key,
    required this.couple,
    required this.partnerId,
    required this.newIdentity,
    required this.onDone,
  });

  final CoupleService couple;
  final String partnerId;
  final Uint8List newIdentity;
  final VoidCallback onDone;

  @override
  State<KeyChangeScreen> createState() => _KeyChangeScreenState();
}

class _KeyChangeScreenState extends State<KeyChangeScreen> {
  late final Future<List<SasSymbol>> _symbols = deviceSasWith(partnerIdentity: widget.newIdentity);
  bool _mismatch = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.phonelink_lock_rounded, size: 44, color: cs.secondary),
              const SizedBox(height: 12),
              Text('La clé de ton amour a changé', style: _title(context)),
              const SizedBox(height: 8),
              Text(
                'C\'est normal après un nouveau téléphone ou une réinstallation. Pour être sûrs que personne ne s\'est '
                'glissé entre vous : comparez ces 7 symboles en appel vidéo, ou envoyez-vous vos liens par une autre '
                'messagerie. Ses nouveaux messages attendent, chiffrés, jusque-là.',
                style: _soft(context),
              ),
              const SizedBox(height: 22),
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
                      for (final x in s)
                        Container(
                          width: 92,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            children: [
                              Text(x.emoji, style: const TextStyle(fontSize: 38)),
                              const SizedBox(height: 4),
                              Text(x.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Spacer(),
              if (_mismatch)
                Text(
                  'N\'acceptez pas cette clé. Quelqu\'un pourrait s\'être glissé entre vous : parlez-en de vive voix et '
                  'refaites la comparaison quand vous êtes côte à côte.',
                  style: TextStyle(color: cs.error),
                )
              else ...[
                FilledButton.icon(
                  icon: const Icon(Icons.favorite),
                  label: const Text('Ce sont les mêmes'),
                  onPressed: () async {
                    await widget.couple.acceptPartnerKey(widget.partnerId, widget.newIdentity);
                    HapticFeedback.heavyImpact();
                    widget.onDone();
                  },
                ),
                TextButton(
                  onPressed: () => setState(() => _mismatch = true),
                  child: const Text('Un symbole est différent'),
                ),
                LinkExchange(
                  couple: widget.couple,
                  partnerId: widget.partnerId,
                  identity: widget.newIdentity,
                  keyChange: true,
                  onVerified: () async => widget.onDone(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================== restauration

/// Nouveau téléphone : retrouver ses échanges avec sa phrase de 24 mots.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key, required this.couple, required this.backupDate, required this.onDone});

  final CoupleService couple;
  final DateTime backupDate;
  final VoidCallback onDone;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _phrase = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // La phrase s'affiche pendant qu'on la tape : ni capture d'écran, ni aperçu dans les apps récentes.
    _secure(true);
  }

  @override
  void dispose() {
    _secure(false);
    _phrase.dispose();
    super.dispose();
  }

  static Future<void> _secure(bool on) async {
    try {
      await const MethodChannel('foulove/notifications').invokeMethod<void>('secure', on);
    } catch (_) {}
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sum = await BackupService.instance.restore(_phrase.text, Supabase.instance.client);
      await widget.couple.restoreDone();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sum.messages} messages et ${sum.media} photos, vidéos ou vocaux retrouvés.')),
      );
      widget.onDone();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] restauration : $e');
      final m = e.toString();
      setState(() {
        _busy = false;
        _error = m.contains('phrase de récupération invalide')
            ? 'Cette phrase n\'est pas valable : vérifie chaque mot et leur ordre.'
            : m.contains('illisible')
            ? 'Cette phrase ne correspond pas à ta sauvegarde.'
            : 'La restauration n\'a pas abouti. Vérifie ta connexion puis réessaie.';
      });
    }
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continuer sans restaurer ?'),
        content: const Text(
          'Tes anciens échanges ne seront pas sur ce téléphone. Tu ne pourras plus les restaurer ensuite.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.couple.restoreDone();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.backupDate;
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
        '${d.hour.toString().padLeft(2, '0')} h ${d.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            Icon(Icons.cloud_download_outlined, size: 44, color: cs.secondary),
            const SizedBox(height: 12),
            Text('Retrouver vos échanges', style: _title(context)),
            const SizedBox(height: 8),
            Text(
              'Une sauvegarde chiffrée existe (du $when). Tape ta phrase de 24 mots pour la retrouver sur ce téléphone. '
              'Les accents sont facultatifs.',
              style: _soft(context),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _phrase,
              minLines: 4,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'mot1 mot2 mot3 … mot24'),
            ),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: cs.error))],
            const SizedBox(height: 18),
            FilledButton(onPressed: _busy ? null : _restore, child: Text(_busy ? 'Restauration…' : 'Restaurer')),
            TextButton(onPressed: _busy ? null : _skip, child: const Text('Continuer sans restaurer')),
          ],
        ),
      ),
    );
  }
}
