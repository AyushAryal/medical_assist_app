import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme_scope.dart';

/// Dial or message a patient straight from the chart or the clinic list.
///
/// Calling a patient is a routine part of the working day — chasing a
/// follow-up, giving a result, checking on someone who did not attend — and
/// having to copy a number into the dialler by hand is the reason it does not
/// get done.
abstract final class ContactActions {
  /// Hands the number to the platform dialler. Deliberately does *not* place
  /// the call: the clinician confirms in the dialler, so a mis-tap in a list
  /// never rings a patient.
  static Future<bool> call(String phone) =>
      _launch(Uri(scheme: 'tel', path: _clean(phone)));

  static Future<bool> sms(String phone, {String? body}) => _launch(
        Uri(
          scheme: 'sms',
          path: _clean(phone),
          queryParameters: body == null ? null : <String, String>{'body': body},
        ),
      );

  static String _clean(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

/// A call button that degrades gracefully when no number is on file.
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.phone,
    this.patientName,
    this.compact = false,
  });

  final String? phone;
  final String? patientName;
  final bool compact;

  bool get _hasNumber => (phone ?? '').trim().isNotEmpty;

  Future<void> _handle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ContactActions.call(phone!);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No dialler available on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (compact) {
      return IconButton(
        tooltip: _hasNumber ? 'Call $phone' : 'No phone number on file',
        icon: Icon(
          Icons.phone_outlined,
          color: _hasNumber ? palette.primary : palette.onSurfaceMuted,
        ),
        onPressed: _hasNumber ? () => _handle(context) : null,
      );
    }

    return OutlinedButton.icon(
      onPressed: _hasNumber ? () => _handle(context) : null,
      icon: const Icon(Icons.phone_outlined, size: 18),
      label: Text(_hasNumber ? 'Call' : 'No number'),
    );
  }
}

/// Call / message row used on the patient chart.
class ContactRow extends StatelessWidget {
  const ContactRow({
    super.key,
    required this.phone,
    required this.patientName,
    this.altPhone,
  });

  final String? phone;
  final String? altPhone;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final numbers = <String>[
      if ((phone ?? '').trim().isNotEmpty) phone!.trim(),
      if ((altPhone ?? '').trim().isNotEmpty) altPhone!.trim(),
    ];

    if (numbers.isEmpty) {
      return Row(
        children: <Widget>[
          Icon(Icons.phone_disabled_outlined,
              size: 16, color: palette.onSurfaceMuted),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(
              'No phone number on file',
              style: context.texts.bodySmall,
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        for (final number in numbers)
          Padding(
            padding: EdgeInsets.only(bottom: m.spaceSm),
            child: Row(
              children: <Widget>[
                Icon(Icons.phone_outlined, size: 16, color: palette.primary),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: Text(
                    number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Call',
                  icon: const Icon(Icons.call, size: 18),
                  onPressed: () => ContactActions.call(number),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Send a message',
                  icon: const Icon(Icons.sms_outlined, size: 18),
                  onPressed: () => ContactActions.sms(number),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
