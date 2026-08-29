import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../data/services/ocr/text_scanner.dart';

/// Reads text off a captured image and hands it back.
///
/// The recognised text is *extracted*, not authored — the screen shows exactly
/// what was on the page and lets the clinician use it or not. It never files
/// anything itself; it returns the text to whoever opened it (a note field,
/// the clipboard) so the record only ever changes by an explicit action.
class ScanTextScreen extends StatefulWidget {
  const ScanTextScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ScanTextScreen> createState() => _ScanTextScreenState();
}

class _ScanTextScreenState extends State<ScanTextScreen>
    with SingleTickerProviderStateMixin {
  final TextScanner _scanner = MlKitTextScanner();
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  ScannedText? _result;
  bool _busy = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!_sweep.isAnimating) _sweep.repeat();
    try {
      final result = await _scanner.scan(widget.imagePath);
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _sweep.stop();
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final result = _result;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Scan text')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              m.spaceLg, m.spaceLg, m.spaceLg, m.spaceLg * 3),
          children: <Widget>[
            _ImageWithSweep(
              imagePath: widget.imagePath,
              sweep: _sweep,
              scanning: _busy,
            ),
            SizedBox(height: m.spaceLg),
            if (_busy)
              Row(
                children: <Widget>[
                  const AiSparkleIcon(size: 18),
                  SizedBox(width: m.spaceSm),
                  Text('Reading text…', style: context.texts.bodyMedium),
                ],
              )
            else if (_error != null)
              Text('Could not read this image. Try again with a clearer, '
                  'well-lit photo.\n\n$_error',
                  style: context.texts.bodySmall)
            else if (result == null || result.isEmpty)
              const EmptyState(
                icon: Icons.document_scanner_outlined,
                title: 'No text found',
                message: 'Try a straighter, brighter photo of the page.',
              )
            else
              SectionCard(
                title: 'Found ${result.blockCount} '
                    '${result.blockCount == 1 ? 'block' : 'blocks'} of text',
                child: SelectableText(
                  result.text,
                  style: context.texts.bodyMedium,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: (result != null && !result.isEmpty)
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.all(m.spaceLg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _run,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rescan'),
                      ),
                    ),
                    SizedBox(width: m.spaceMd),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop<String>(result.text),
                        icon: const Icon(Icons.check),
                        label: const Text('Use text'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// The captured image with an animated scan line sweeping over it while text is
/// being read — the "something is happening" cue that makes the wait feel like
/// work rather than a hang.
class _ImageWithSweep extends StatelessWidget {
  const _ImageWithSweep({
    required this.imagePath,
    required this.sweep,
    required this.scanning,
  });

  final String imagePath;
  final Animation<double> sweep;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return ClipRRect(
      borderRadius: BorderRadius.circular(m.radiusLg),
      child: Stack(
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340, minHeight: 180),
            child: SizedBox(
              width: double.infinity,
              child: Image.file(File(imagePath), fit: BoxFit.cover),
            ),
          ),
          if (scanning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: sweep,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(sweep.value);
                  return Align(
                    alignment: Alignment(0, -1 + 2 * t),
                    child: Container(
                      height: 2.5,
                      // A glowing accent line sweeping the page — the "reading"
                      // cue. Solid, not a gradient (the design layer owns
                      // gradients); the glow does the work.
                      decoration: BoxDecoration(
                        color: palette.accent,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.7),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
