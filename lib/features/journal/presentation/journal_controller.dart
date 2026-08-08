import 'package:flutter/foundation.dart';
import 'package:froyou/features/journal/journal.dart';

/// Exposes the log list to the UI and funnels writes through
/// [JournalRepository].
///
/// Kept separate from `ProfileController` so that saving a log doesn't rebuild
/// the themed shell, and changing the theme doesn't rebuild the log list.
class JournalController extends ChangeNotifier {
  JournalController(JournalEntryDb db) {
    _repository = JournalRepository(db, onChanged: refresh);
    _entries = _repository.allEntries();
  }

  late final JournalRepository _repository;
  List<JournalEntry> _entries = const [];

  List<JournalEntry> get entries => _entries;
  int get count => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// True while sentence embedding / clustering is still running for a
  /// recently saved entry. Drives the "still thinking" hint on the newest card.
  bool get isEnriching => _repository.isEnriching;

  void refresh() {
    _entries = _repository.allEntries();
    notifyListeners();
  }

  Future<void> save(String text) => _repository.save(text);

  Future<void> delete(JournalEntry entry) => _repository.deleteEntry(entry);
}
