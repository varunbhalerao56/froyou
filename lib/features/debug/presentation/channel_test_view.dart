import 'dart:async';

import 'package:flutter/material.dart';
import 'package:froyou/services/services.dart';

/// Scratch harness for the `app/speech` and `app/nlp` platform channels.
///
/// Not product UI — a diagnostic screen kept because it is the only way to
/// exercise the native layer directly on a device. Reachable by long-pressing
/// the version label in Settings.
class ChannelTestView extends StatefulWidget {
  const ChannelTestView({super.key});

  @override
  State<ChannelTestView> createState() => _ChannelTestViewState();
}

class _ChannelTestViewState extends State<ChannelTestView> {
  final SpeechService _speech = SpeechService.instance;
  final TextEditingController _nlpInput = TextEditingController(
    // Two sentences with opposite sentiment on purpose: good for eyeballing
    // whether embedSentences separates them and whether cosine reflects it.
    text:
        'Today my boss was very annoying and what he said hurt me. '
        'On the bright side I had some really nice food today.',
  );

  StreamSubscription<SpeechTranscript>? _transcriptSub;
  StreamSubscription<SpeechStatus>? _statusSub;
  StreamSubscription<SpeechDownloadProgress>? _downloadSub;

  // Speech state.
  bool _supported = false;
  bool _listening = false;
  bool _busy = false;
  SpeechPermissions? _permissions;
  SpeechModelStatus? _modelStatus;

  /// Non-null only while a model download is in flight, so the bar appears and
  /// disappears with the download rather than sitting at 100%.
  double? _downloadFraction;

  /// Finalized text accumulated so far, plus the in-flight partial shown
  /// separately — that split is what makes it obvious whether volatile results
  /// are actually streaming.
  final List<String> _finals = [];
  String _partial = '';

  // NLP state.
  String _nlpOutput = '';

  @override
  void initState() {
    super.initState();
    _transcriptSub = _speech.transcripts.listen(
      _onTranscript,
      onError: _onSpeechError,
    );
    _statusSub = _speech.status.listen((status) {
      setState(() => _listening = status == SpeechStatus.listening);
      if (status == SpeechStatus.interrupted) {
        _showMessage('Interrupted — the system took the microphone.');
      }
    });
    _downloadSub = _speech.downloadProgress.listen((progress) {
      setState(
        () =>
            _downloadFraction = progress.isComplete ? null : progress.fraction,
      );
    });
    _refreshStatus();
  }

  @override
  void dispose() {
    _transcriptSub?.cancel();
    _statusSub?.cancel();
    _downloadSub?.cancel();
    _nlpInput.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Speech
  // ---------------------------------------------------------------------------

  void _onTranscript(SpeechTranscript transcript) {
    setState(() {
      if (transcript.isFinal) {
        _finals.add(transcript.text);
        _partial = '';
      } else {
        _partial = transcript.text;
      }
    });
  }

  void _onSpeechError(Object error) {
    _showMessage('$error');
  }

  Future<void> _refreshStatus() async {
    final supported = await _speech.isSupported();
    if (!mounted) return;
    setState(() => _supported = supported);
    if (!supported) return;

    await _run(() async {
      final permissions = await _speech.permissions();
      final status = await _speech.modelStatus();
      if (!mounted) return;
      setState(() {
        _permissions = permissions;
        _modelStatus = status;
      });
    });
  }

  Future<void> _requestPermissions() => _run(() async {
    final permissions = await _speech.requestPermissions();
    if (!mounted) return;
    setState(() => _permissions = permissions);
  });

  Future<void> _ensureModel() => _run(() async {
    // Progress arrives on the event channel and is rendered by the bar below;
    // it may never fire at all when the model is already installed.
    try {
      await _speech.ensureModel();
      final status = await _speech.modelStatus();
      if (!mounted) return;
      setState(() => _modelStatus = status);
    } finally {
      if (mounted) setState(() => _downloadFraction = null);
    }
  });

  Future<void> _toggleListening() => _run(() async {
    if (_speech.isListening) {
      await _speech.stop();
    } else {
      setState(() {
        _finals.clear();
        _partial = '';
      });
      await _speech.start();
    }
  });

  // ---------------------------------------------------------------------------
  // NLP
  // ---------------------------------------------------------------------------

  Future<void> _runSentences() => _run(() async {
    final sentences = await NlpService.splitSentences(_nlpInput.text);
    _setOutput(
      sentences.isEmpty
          ? '(no sentences)'
          : sentences
                .asMap()
                .entries
                .map((e) => '${e.key + 1}. ${e.value}')
                .join('\n'),
    );
  });

  Future<void> _runSentiment() => _run(() async {
    final score = await NlpService.sentimentScore(_nlpInput.text);
    final label = score > 0.1
        ? 'positive'
        : score < -0.1
        ? 'negative'
        : 'neutral';
    _setOutput('score: ${score.toStringAsFixed(3)}  ($label)');
  });

  Future<void> _runEntities() => _run(() async {
    final entities = await NlpService.extractEntities(_nlpInput.text);
    if (entities.isEmpty) {
      _setOutput('(no entities)');
      return;
    }
    final source = _nlpInput.text;
    _setOutput(
      entities
          .map((e) {
            // Verifies the UTF-16 -> Dart offset conversion end to end. If this
            // ever prints "MISMATCH", the NSRange handling in NlpChannel is wrong.
            final slice = source.substring(e.start, e.end);
            final check = slice == e.text ? 'ok' : 'MISMATCH ("$slice")';
            return '${e.type.name}: "${e.text}" @ ${e.start}-${e.end}  [$check]';
          })
          .join('\n'),
    );
  });

  Future<void> _runEmbed() => _run(() async {
    final vector = await NlpService.embed(_nlpInput.text, normalize: true);
    if (vector.isEmpty) {
      _setOutput('(empty vector)');
      return;
    }
    final magnitude = vector.fold<double>(0, (sum, v) => sum + v * v);
    final preview = vector.take(6).map((v) => v.toStringAsFixed(4)).join(', ');
    _setOutput(
      'dimension: ${vector.length}\n'
      'L2 norm: ${magnitude.toStringAsFixed(4)} (should be ~1.0)\n'
      'first 6: [$preview, ...]',
    );
  });

  Future<void> _runEmbedSentences() => _run(() async {
    final results = await NlpService.embedSentences(
      _nlpInput.text,
      normalize: true,
    );
    if (results.isEmpty) {
      _setOutput('(no sentences)');
      return;
    }

    final source = _nlpInput.text;
    final lines = <String>[];
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      // Same offset round-trip check as extractEntities.
      final check = source.substring(r.start, r.end) == r.sentence
          ? 'ok'
          : 'MISMATCH';
      lines.add('${i + 1}. "${r.sentence}"  [${r.vector.length}d, $check]');
    }

    // Pairwise cosine — with normalized vectors this is just a dot product.
    // Sentences with opposite sentiment should score noticeably lower than
    // sentences about the same thing.
    if (results.length > 1) {
      lines.add('');
      lines.add('cosine similarity:');
      for (var i = 0; i < results.length; i++) {
        for (var j = i + 1; j < results.length; j++) {
          var dot = 0.0;
          for (var k = 0; k < results[i].vector.length; k++) {
            dot += results[i].vector[k] * results[j].vector[k];
          }
          lines.add('  ${i + 1}↔${j + 1}: ${dot.toStringAsFixed(4)}');
        }
      }
    }

    _setOutput(lines.join('\n'));
  });

  void _setOutput(String value) {
    if (!mounted) return;
    setState(() => _nlpOutput = value);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Runs [action] with a busy flag and turns any channel exception into a
  /// SnackBar instead of an unhandled error — this is a test harness, so a
  /// legible failure is more useful than a crash.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel test'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('app/speech', [
            Text(
              _supported
                  ? 'Supported on this device.'
                  : 'Not supported — needs a physical device on iOS 26+. '
                        'The Simulator cannot download speech models.',
            ),
            const SizedBox(height: 8),
            Text('Permissions: ${_permissions ?? 'unknown'}'),
            Text('Model: ${_modelStatus?.name ?? 'unknown'}'),
            if (_downloadFraction case final fraction?) ...[
              const SizedBox(height: 8),
              Text(
                'Downloading model — ${(fraction * 100).toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: fraction),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _requestPermissions,
                  child: const Text('Request permissions'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _ensureModel,
                  child: const Text('Ensure model'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _refreshStatus,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (_supported && !_busy) ? _toggleListening : null,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_listening ? 'Stop' : 'Start listening'),
            ),
            const SizedBox(height: 12),
            _transcriptView(),
          ]),
          const SizedBox(height: 24),
          _section('app/nlp', [
            TextField(
              controller: _nlpInput,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Input text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _runSentences,
                  child: const Text('splitSentences'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runSentiment,
                  child: const Text('sentimentScore'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runEntities,
                  child: const Text('extractEntities'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runEmbed,
                  child: const Text('embed'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runEmbedSentences,
                  child: const Text('embedSentences'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _outputBox(_nlpOutput.isEmpty ? '(no output yet)' : _nlpOutput),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _transcriptView() {
    final settled = _finals.join(' ');
    if (settled.isEmpty && _partial.isEmpty) {
      return _outputBox('(nothing transcribed yet)');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      // Partial text is greyed so it's visually obvious which parts are still
      // volatile and which have been finalized.
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: settled),
            if (settled.isNotEmpty && _partial.isNotEmpty)
              const TextSpan(text: ' '),
            TextSpan(
              text: _partial,
              style: TextStyle(color: Theme.of(context).disabledColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outputBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontFamily: 'monospace')),
    );
  }
}
