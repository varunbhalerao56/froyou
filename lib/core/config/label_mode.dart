/// Turns every statistical fallback off, so the only words that can appear
/// anywhere are ones the language model produced.
///
/// **Temporary, and a diagnostic rather than a feature.** The app's normal
/// contract is the opposite of this — `ClusterLabeler` is the floor and the
/// model is the upgrade, so a device without Apple Intelligence still gets
/// keywords and theme names. That also makes it impossible to tell by looking
/// whether the model ran at all: the fallback fills in silently and the UI
/// looks the same either way.
///
/// With this on, it doesn't. No model means no keywords under a log card and
/// no theme label in Analytics — blank is the signal.
///
/// Off with `--dart-define=MODEL_ONLY_LABELS=false`, which restores the
/// shipping behaviour. Mutable only so tests can pin it; nothing in the app
/// writes to it.
bool kModelOnlyLabels = const bool.fromEnvironment(
  'MODEL_ONLY_LABELS',
  defaultValue: true,
);
