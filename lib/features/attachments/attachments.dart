/// Public surface of the attachments module.
///
/// Capturing and displaying files — photos, audio, documents — inline. Reused
/// by notes, patients and encounters, which import THIS file and nothing else
/// from `features/attachments/`. Internals stay private to the module.
library;

export 'attachment_strip.dart' show AttachmentStrip;
export 'field_attach_bar.dart' show FieldAttachBar;
export 'image_viewer.dart' show ImageViewer;
export 'inline_audio_player.dart' show InlineAudioPlayer;
export 'voice_note_button.dart' show VoiceNoteButton;
