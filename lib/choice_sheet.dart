import 'package:flutter/material.dart';

import 'theme.dart';

/// One option in a [showChoiceSheet]: what it does and what it is for.
class Choice<T> {
  final T value;
  final IconData icon;
  final String title, purpose;
  const Choice(this.value, this.icon, this.title, this.purpose);
}

/// A bottom sheet of titled options, each with a one-line purpose, so the
/// rarely used exports and backups explain themselves. Null = dismissed.
Future<T?> showChoiceSheet<T>(BuildContext context, String title, List<Choice<T>> choices) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // tall at a large font: scroll instead of clipping
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpace.unit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.unit),
                child: Text(title, style: Theme.of(c).textTheme.titleMedium),
              ),
              for (final ch in choices)
                ListTile(
                  leading: Icon(ch.icon),
                  title: Text(ch.title),
                  subtitle: Text(ch.purpose),
                  onTap: () => Navigator.pop(c, ch.value),
                ),
            ],
          ),
        ),
      ),
    );
