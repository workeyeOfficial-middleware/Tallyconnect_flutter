// Voice search for any search field: the mic at the end of the field (tap
// to listen, tap again to stop) and the listening / error note under it.
// Speech fills the field and runs that field's own search, as typing does
// (AppController.toggleVoiceFor).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';

/// The mic of search field [field] (a 44 px target).
class MicBtn extends ConsumerWidget {
  const MicBtn(this.field, {super.key});
  final String field;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool on = c.voiceOnFor(field);
    return Semantics(
      button: true,
      label: on ? 'Stop voice search' : 'Voice search',
      child: GestureDetector(
        key: ValueKey<String>(
          field == 'q' ? 'voiceSearchBtn' : 'voiceBtn-$field',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: () => c.toggleVoiceFor(field),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Ic(on ? 'micStop' : 'mic', color: on ? p.acc : p.ink3),
          ),
        ),
      ),
    );
  }
}

/// "Listening…" / why voice could not run, under field [field] (nothing
/// when another field is listening or all is well).
class VoiceNote extends ConsumerWidget {
  const VoiceNote(this.field, {super.key, this.padding});
  final String field;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String? note = c.voiceNoteFor(field);
    if (note == null) return const SizedBox.shrink();
    return Padding(
      key: ValueKey<String>(field == 'q' ? 'voiceNote' : 'voiceNote-$field'),
      padding: padding ?? const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Text(
        note,
        style: ts(13, w: w600, c: c.voiceOnFor(field) ? p.acc : p.ink2),
      ),
    );
  }
}

/// A search field with voice: the text field (typing works as before), its
/// mic, and the note under it.
class VoiceSearchField extends ConsumerWidget {
  const VoiceSearchField({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    required this.placeholder,
    this.extra,
  });

  /// The field's key (see [AppController.toggleVoiceFor]).
  final String field;
  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;

  /// Another button after the mic (e.g. close).
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Inp(
          value: value,
          onChanged: onChanged,
          placeholder: c.voiceOnFor(field) ? 'Listening…' : placeholder,
          icon: 'search',
          trailing: extra == null
              ? MicBtn(field)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[MicBtn(field), extra!],
                ),
        ),
        VoiceNote(field),
      ],
    );
  }
}
