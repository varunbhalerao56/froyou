import 'package:flutter/foundation.dart';
import 'package:froyou/features/home/data/follow_up_service.dart';
import 'package:froyou/features/journal/journal.dart';

/// Exposes the log list to the UI and funnels writes through
/// [JournalRepository].
///
/// Kept separate from `ProfileController` so that saving a log doesn't rebuild
/// the themed shell, and changing the theme doesn't rebuild the log list.
class JournalController extends ChangeNotifier {
  /// Callers pass `followUp:` — the private name is an initializing formal,
  /// which Dart maps to its public form.
  JournalController(
    JournalEntryDb db, {
    this._followUp,
    VoidCallback? onEnriched,
  }) {
    _repository = JournalRepository(
      db,
      onChanged: refresh,
      onEnriched: onEnriched,
    );
    _entries = _repository.allEntries();
  }

  late final JournalRepository _repository;
  final FollowUpService? _followUp;

  /// Exposed for the debug menu's follow-up preview, which needs the same
  /// instance rather than a second one built from a store it has no handle on.
  FollowUpService? get followUp => _followUp;

  List<JournalEntry> _entries = const [];

  List<JournalEntry> get entries => _entries;
  int get count => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// True while sentence embedding / clustering is still running for a
  /// recently saved entry. Drives the "still thinking" hint on the newest card.
  bool get isEnriching => _repository.isEnriching;

  /// The line under the Home image.
  ///
  /// Replaced by a generated follow-up the morning after a rough day; see
  /// [FollowUpService]. Otherwise it's the same open question every time,
  /// which is the point — it asks without presuming.
  static const String defaultPrompt = 'How are you feeling?';

  String _prompt = defaultPrompt;
  String get prompt => _prompt;

  /// True while the prompt is a generated follow-up rather than the default.
  bool get hasFollowUp => _prompt != defaultPrompt;

  /// Asks whether a follow-up is due. Safe to call on every Home build — the
  /// service caches per day and never throws.
  Future<void> refreshPrompt() async {
    final question = await _followUp?.pendingQuestion();
    _setPrompt(question ?? defaultPrompt);
  }

  void _setPrompt(String value) {
    if (_prompt == value) return;
    _prompt = value;
    notifyListeners();
  }

  void refresh() {
    _entries = _repository.allEntries();
    notifyListeners();
  }

  Future<void> save(String text) async {
    await _repository.save(text);
    // The follow-up has done its job the moment they write something, so it
    // reverts immediately rather than lingering until the next launch.
    if (hasFollowUp) {
      await _followUp?.clear();
      _setPrompt(defaultPrompt);
    }
  }

  Future<void> delete(JournalEntry entry) => _repository.deleteEntry(entry);

  /// Wipes every log, sentence and theme. Confirm before calling.
  Future<void> clearAll() async {
    await _repository.clearAll();
    await _followUp?.clear();
    _setPrompt(defaultPrompt);
  }
}
