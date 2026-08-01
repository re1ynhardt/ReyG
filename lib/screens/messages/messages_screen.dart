import 'package:flutter/material.dart';
import '../../providers/app_state.dart';

/// List of the signed-in account's DM conversations. Opened from the
/// "messenger" icon in the bottom nav (and eventually from the profile
/// screen's Message button too). There's no chat backend yet, so this is
/// an empty-state placeholder ready to be filled in once conversations
/// exist.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('messages'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 56, color: theme.hintColor),
              const SizedBox(height: 16),
              Text(
                context.tr('no_messages_yet'),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
