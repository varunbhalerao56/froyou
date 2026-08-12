/// The arrangement of Home's chrome — caption, backdrop and prompt.
///
/// Exists to be switched live on a device from the debug menu. The whole point
/// is judging the motion, which no screenshot settles: how the chrome vacates
/// as compose arrives reads differently in every one of these.
///
/// Whatever the variant, two things are fixed. The pane is always exactly its
/// given height — compose redistributes space, never adds it — and the content
/// insets itself below the status bar, because the shell deliberately isn't in
/// a `SafeArea`.
enum HomeLayout {
  /// What ships: the photo full-bleed, blurred and faded at its edges so it
  /// dissolves into the page, with the caption above and the prompt below.
  classic('Classic'),

  /// Caption and prompt sit on the image itself, over a scrim.
  captionOverImage('Caption over image'),

  /// The image runs the full height of the pane, behind everything.
  fullBleed('Full bleed'),

  /// No image at all. Doubles as a control: it proves the compose transition
  /// doesn't depend on the backdrop being there.
  centred('Centred minimal'),

  /// Prompt first and large, with the image reduced to a strip at the bottom.
  typeFirst('Type first');

  const HomeLayout(this.label);

  final String label;

  /// Tolerant of an unknown or missing name, the same way the theme settings
  /// are: a stored value from a build that had different variants must not
  /// take the app down.
  static HomeLayout fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fullBleed;
  }
}
