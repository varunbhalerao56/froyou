import 'package:flutter/material.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/features/home/presentation/home_layout.dart';

/// Switches the Home arrangement, live.
///
/// There is no preview here on purpose. `ProfileController` sits above
/// `MaterialApp`, so choosing a variant rebuilds the real Home already on the
/// navigation stack — pop back and it is simply different. A thumbnail would be
/// a second thing to keep in sync, and it could not show the one thing worth
/// judging, which is how the chrome vacates when compose opens.
class HomeLayoutGalleryView extends StatelessWidget {
  const HomeLayoutGalleryView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.profileOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Home layouts')),
      body: RadioGroup<HomeLayout>(
        groupValue: profile.homeLayout,
        onChanged: (value) {
          if (value != null) profile.setHomeLayout(value);
        },
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Applies immediately. Go back twice and open compose to judge '
                'the transition, which is the part a screenshot cannot settle.',
              ),
            ),
            const Divider(height: 1),
            for (final layout in HomeLayout.values)
              RadioListTile<HomeLayout>(
                value: layout,
                title: Text(layout.label),
              ),
          ],
        ),
      ),
    );
  }
}
