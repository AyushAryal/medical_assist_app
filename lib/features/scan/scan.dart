import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/design.dart';
import 'scan_text_screen.dart';

export 'scan_text_screen.dart' show ScanTextScreen;

/// Captures or picks an image, reads the text off it on-device, and returns the
/// text the clinician chose to use — or null if they cancelled.
///
/// The one public entry to the scan feature: a caller (a note field, say) awaits
/// this and decides what to do with the result. The feature files nothing
/// itself, so it stays a tool the rest of the app composes rather than a place
/// records are written.
Future<String?> scanTextFrom(BuildContext context) async {
  final source = await _pickSource(context);
  if (source == null || !context.mounted) return null;

  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    imageQuality: 92,
    maxWidth: 2400,
  );
  if (file == null || !context.mounted) return null;

  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => ScanTextScreen(imagePath: file.path),
    ),
  );
}

Future<ImageSource?> _pickSource(BuildContext context) {
  final m = context.metrics;
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(m.spaceLg),
            child: Text('Scan text from…', style: context.texts.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo library'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          SizedBox(height: m.spaceSm),
        ],
      ),
    ),
  );
}
