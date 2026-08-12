import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/features/debug/presentation/channel_test_view.dart';
import 'package:froyou/features/debug/presentation/home_layout_gallery_view.dart';

/// What the hidden long-press on the version label opens.
///
/// Not product UI, and deliberately unthemed — stock Material, like
/// [ChannelTestView]. A diagnostic screen that looked like the app would be
/// mistaken for it in a screenshot.
///
/// This ships in release, like the long-press that reaches it: the channel
/// harness is the only way to diagnose the native layer on a real device.
class DebugMenuView extends StatelessWidget {
  const DebugMenuView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Channel test'),
            subtitle: const Text('Exercise app/speech, app/nlp and app/genai'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(builder: (_) => const ChannelTestView()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Home layouts'),
            subtitle: const Text('Switch the Home arrangement, live'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => const HomeLayoutGalleryView(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
