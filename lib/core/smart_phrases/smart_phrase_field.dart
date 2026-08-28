import 'package:flutter/material.dart';

import '../design/design.dart';
import 'smart_phrase.dart';

/// Wraps a text field with the `\`-macro menu.
///
/// Deliberately a *wrapper*, not a replacement `TextField`: the caller keeps its
/// own field — its styling, its keyboard type, its decoration — and passes it as
/// [child], sharing the [SmartPhraseController]. This is what lets the same
/// mechanism sit inside the assistant composer, a note field, or anywhere else
/// without each of those surrendering their look. The menu floats above the
/// field in an overlay, so it never reflows the layout beneath it.
class SmartPhraseField extends StatefulWidget {
  const SmartPhraseField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.registry,
    required this.child,
    this.scope = const SmartPhraseScope(),
  });

  final SmartPhraseController controller;
  final FocusNode focusNode;
  final SmartPhraseRegistry registry;
  final Widget child;

  /// What the surrounding screen already knows — mainly the patient in view.
  final SmartPhraseScope scope;

  @override
  State<SmartPhraseField> createState() => _SmartPhraseFieldState();
}

class _SmartPhraseFieldState extends State<SmartPhraseField> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  List<SmartPhrase> _matches = const <SmartPhrase>[];
  String _query = '';
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    widget.focusNode.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    widget.focusNode.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    // While a picker is open the field loses focus; don't fight it.
    if (_resolving) return;

    final active = widget.controller.activeQuery;
    final show = widget.focusNode.hasFocus && active != null;
    final matches = show ? widget.registry.matching(active.query) : const <SmartPhrase>[];

    if (!show || matches.isEmpty) {
      if (_portal.isShowing) _portal.hide();
      return;
    }
    setState(() {
      _matches = matches;
      _query = active.query;
    });
    if (!_portal.isShowing) _portal.show();
  }

  Future<void> _choose(SmartPhrase phrase) async {
    _resolving = true;
    _portal.hide();
    final value = await phrase.resolve(context, widget.scope);
    _resolving = false;
    if (!mounted) return;
    if (value != null) widget.controller.insertResolved(value);
    // Back to the field so typing continues where it left off.
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildMenu,
        child: widget.child,
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Positioned(
      width: 360,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: Offset(0, -m.spaceXs),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
            child: GlassPanel(
              padding: EdgeInsets.symmetric(vertical: m.spaceXs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        m.spaceMd, m.spaceXs, m.spaceMd, m.spaceXs),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.bolt_outlined,
                            size: 13, color: palette.accent),
                        SizedBox(width: m.spaceXs),
                        Text(
                          _query.isEmpty ? 'Smart phrases' : '\\$_query',
                          style: context.texts.labelSmall
                              ?.copyWith(color: palette.onSurfaceMuted),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _matches.length,
                      itemBuilder: (context, i) {
                        final phrase = _matches[i];
                        return InkWell(
                          onTap: () => _choose(phrase),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: m.spaceMd,
                              vertical: m.spaceSm,
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(phrase.icon,
                                    size: 18, color: palette.accent),
                                SizedBox(width: m.spaceSm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text.rich(
                                        TextSpan(
                                          style: context.texts.labelLarge,
                                          children: <InlineSpan>[
                                            TextSpan(
                                              text: '\\${phrase.trigger}',
                                              style: TextStyle(
                                                  color: palette.accent),
                                            ),
                                            TextSpan(text: '  ${phrase.title}'),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        phrase.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.texts.labelSmall
                                            ?.copyWith(
                                                color: palette.onSurfaceMuted),
                                      ),
                                    ],
                                  ),
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
            ),
          ),
        ),
      ),
    );
  }
}
