import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoswipe/features/gallery_access/gallery_permission_controller.dart';
import 'package:photoswipe/features/gallery_access/permission_screen.dart';

class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.authorizedBuilder,
  });

  final WidgetBuilder authorizedBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionAsync = ref.watch(galleryPermissionControllerProvider);

    return permissionAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, st) => const PermissionScreen(),
      data: (state) {
        if (state.canRead) {
          return authorizedBuilder(context);
        }
        return const PermissionScreen();
      },
    );
  }
}

