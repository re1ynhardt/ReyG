import 'package:flutter/material.dart';

/// Sent/read indicator for an outgoing message: a single check ("sent,
/// not read yet") or a double check in the accent color ("read"). Used
/// both on message bubbles in [ChatScreen] and on the last-message
/// preview in the Messages conversation list, so both surfaces show the
/// exact same read state.
class MessageReadTicks extends StatelessWidget {
  const MessageReadTicks({super.key, required this.read, this.size = 15, this.readColor, this.unreadColor});

  final bool read;
  final double size;
  final Color? readColor;
  final Color? unreadColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(
      read ? Icons.done_all : Icons.done,
      size: size,
      color: read ? (readColor ?? theme.colorScheme.secondary) : (unreadColor ?? theme.hintColor),
    );
  }
}

/// Small filled dot marking an unread incoming message, shown next to a
/// conversation in the Messages list.
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    );
  }
}
