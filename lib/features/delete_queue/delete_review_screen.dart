import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photoswipe/shared/services/service_providers.dart';

class DeleteReviewScreen extends ConsumerWidget {
  const DeleteReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(deleteQueueServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review deletion'),
      ),
      body: SafeArea(
        child: queueAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, st) => Center(child: Text('Error loading delete queue.\n$e')),
          data: (queue) {
            return FutureBuilder<List<AssetEntity>>(
              future: _resolveAssets(queue.ids),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CupertinoActivityIndicator());
                }
                final assets = snapshot.data!;
                if (assets.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Deletion queue is empty.'),
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: assets.length,
                        itemBuilder: (context, index) {
                          final asset = assets[index];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize: const ThumbnailSize(260, 260),
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.low,
                                ),
                                Align(
                                  alignment: Alignment.topRight,
                                  child: IconButton(
                                    tooltip: 'Remove from queue',
                                    onPressed: () async {
                                      await queue.dequeue(asset.id);
                                      // Rebuild: easiest is to pop/push or trigger a provider refresh.
                                      ref.invalidate(deleteQueueServiceProvider);
                                    },
                                    icon: const Icon(Icons.close, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Confirm deletion'),
                                content: Text(
                                  'This will permanently delete ${assets.length} photo(s) from your iPhone.\n\n'
                                  'This cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed != true) return;

                            final result = await queue.deleteAllFromDevice();
                            if (!context.mounted) return;

                            ref.invalidate(deleteQueueServiceProvider);

                            if (!result.allDeleted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Some items could not be deleted. Check photo permissions (limited/full) and try again.',
                                  ),
                                ),
                              );
                              return;
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Deleted successfully.')),
                            );
                            Navigator.of(context).pop();
                          },
                          child: Text('Confirm deletion (${assets.length})'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<List<AssetEntity>> _resolveAssets(List<String> ids) async {
    final futures = ids.map(AssetEntity.fromId);
    final resolved = await Future.wait(futures);
    return resolved.whereType<AssetEntity>().toList(growable: false);
  }
}

