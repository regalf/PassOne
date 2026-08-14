import 'package:flutter/material.dart';

import '../../state/session.dart';

/// Small cloud indicator reflecting the server reachability, shown next to the
/// username on the unlock screen and in the vault header.
class CloudStatusIcon extends StatelessWidget {
  final ServerStatus status;
  final double size;

  const CloudStatusIcon({super.key, required this.status, this.size = 18});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ServerStatus.online:
        return Icon(Icons.cloud_done,
            size: size, color: Colors.green.shade600);
      case ServerStatus.offline:
        return Icon(Icons.cloud_off,
            size: size, color: Theme.of(context).colorScheme.error);
      case ServerStatus.checking:
        return SizedBox(
          width: size - 4,
          height: size - 4,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }
}
