import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../services/site_icons.dart';

/// Iconița reală a site-ului, într-un cerc; până se încarcă (sau dacă nu
/// există) se vede [fallback] (cercul cu inițiala).
class SiteIcon extends StatefulWidget {
  const SiteIcon({
    super.key,
    required this.domain,
    required this.radius,
    required this.fallback,
  });

  final String domain;
  final double radius;
  final Widget fallback;

  @override
  State<SiteIcon> createState() => _SiteIconState();
}

class _SiteIconState extends State<SiteIcon> {
  Future<Uint8List?>? _bytes;

  /// Pe web: sursa încercată acum (direct de pe site, apoi Google).
  int _web = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb) {
      _bytes ??= SiteIcons.load(context.read<NotesStore>(), widget.domain);
    }
  }

  @override
  void didUpdateWidget(SiteIcon old) {
    super.didUpdateWidget(old);
    if (old.domain != widget.domain) {
      _web = 0;
      _bytes = kIsWeb
          ? null
          : SiteIcons.load(context.read<NotesStore>(), widget.domain);
    }
  }

  Widget _circle(Widget image) {
    final r = widget.radius;
    return Container(
      width: r * 2,
      height: r * 2,
      padding: EdgeInsets.all(r * 0.22),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r * 0.3),
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    if (kIsWeb) {
      final sources = SiteIcons.sources(widget.domain);
      if (_web >= sources.length) return widget.fallback;
      // <img> al browserului: merge și pentru site-urile care nu permit
      // citirea imaginii din altă pagină
      return Stack(
        alignment: Alignment.center,
        children: [
          widget.fallback,
          // cercul alb apare doar după ce imaginea s-a încărcat
          Image.network(
            sources[_web],
            key: ValueKey(sources[_web]),
            width: size,
            height: size,
            fit: BoxFit.contain,
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            frameBuilder: (_, child, frame, sync) => frame == null && !sync
                ? const SizedBox.shrink()
                : _circle(child),
            errorBuilder: (_, _, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _web++);
              });
              return const SizedBox.shrink();
            },
          ),
        ],
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (_, snap) {
        final b = snap.data;
        if (b == null) return widget.fallback;
        return _circle(
          Image.memory(
            b,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
      },
    );
  }
}
