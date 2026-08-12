import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/journal/presentation/log_card.dart';

/// Search over past logs, by words and by meaning.
///
/// Its own route rather than a field above the list. The logs live inside the
/// shell's single scroll view, which the Home pane shares — putting a field in
/// there would mean the results, the backdrop and the compose box all
/// negotiating one scroll position.
class SearchView extends HookWidget {
  const SearchView({super.key});

  /// Long enough that typing a word doesn't embed three prefixes of it on the
  /// way. The semantic half is a native round trip per query.
  static const Duration _debounce = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final journal = AppScope.journalOf(context);
    final db = AppScope.dbOf(context);

    final search = useMemoized(() => JournalSearch(db.journalEntryDb), [db]);
    final controller = useTextEditingController();
    final hits = useState<List<JournalSearchHit>>(const []);
    final query = useState('');
    final busy = useState(false);

    useEffect(() {
      Timer? timer;
      void onChanged() {
        timer?.cancel();
        final text = controller.text;
        timer = Timer(_debounce, () async {
          query.value = text;
          if (text.trim().isEmpty) {
            hits.value = const [];
            busy.value = false;
            return;
          }
          busy.value = true;
          final results = await search.search(text);
          // The field may have moved on while the embedding was in flight.
          if (controller.text != text) return;
          hits.value = results;
          busy.value = false;
        });
      }

      controller.addListener(onChanged);
      return () {
        timer?.cancel();
        controller.removeListener(onChanged);
      };
    }, [controller, search]);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Search',
          style: AppTypography.headline.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: AppTypography.body.copyWith(color: colors.textPrimary),
                cursorColor: colors.primary,
                decoration: InputDecoration(
                  hintText: 'A word, or what it was about',
                  hintStyle: AppTypography.body.copyWith(
                    color: colors.placeholder,
                  ),
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    color: colors.placeholder,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: colors.textBox,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.mdAll,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (busy.value) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _Results(
                hits: hits.value,
                query: query.value,
                journal: journal,
                colors: colors,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.hits,
    required this.query,
    required this.journal,
    required this.colors,
  });

  final List<JournalSearchHit> hits;
  final String query;
  final JournalController journal;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return _Empty(
        title: 'Search what you’ve written.',
        body:
            'Words are matched literally, and meaning is matched too — so '
            '“sleep” finds the night you couldn’t switch off, even if you '
            'never used the word.',
        colors: colors,
      );
    }
    if (hits.isEmpty) {
      return _Empty(
        title: 'Nothing for “$query”.',
        body: 'Try a different word, or what it was about.',
        colors: colors,
      );
    }

    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Said out loud, because an entry that never contains the word
            // looks like a bug otherwise rather than like the feature working.
            if (hit.byMeaning)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  top: AppSpacing.sm,
                ),
                child: Text(
                  'similar in meaning',
                  style: AppTypography.caption.copyWith(
                    color: colors.placeholder,
                  ),
                ),
              ),
            LogCard(
              entry: hit.entry,
              onDelete: () async => journal.delete(hit.entry),
            ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, required this.colors});

  final String title;
  final String body;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.callout.copyWith(color: colors.textSecondary),
          ),
          AppGap.smV,
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.footnote.copyWith(color: colors.placeholder),
          ),
        ],
      ),
    );
  }
}
