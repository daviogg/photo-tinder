import 'package:hive/hive.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photoswipe/shared/services/hive_boxes.dart';

class DeleteFromDeviceResult {
  const DeleteFromDeviceResult({
    required this.failedIds,
  });

  final List<String> failedIds;

  bool get allDeleted => failedIds.isEmpty;
}

class DeleteQueueService {
  DeleteQueueService(this._box);

  final Box<String> _box;

  static Future<DeleteQueueService> create() async {
    final box = await Hive.openBox<String>(HiveBoxes.deleteQueue);
    return DeleteQueueService(box);
  }

  List<String> get ids => _box.values.toList(growable: false);

  bool contains(String assetId) => _box.containsKey(assetId);

  Future<void> enqueue(String assetId) async {
    await _box.put(assetId, assetId);
  }

  Future<void> dequeue(String assetId) async {
    await _box.delete(assetId);
  }

  Future<void> clear() async {
    await _box.clear();
  }

  Future<List<String>> _filterIdsThatStillExist(List<String> candidateIds) async {
    if (candidateIds.isEmpty) return const [];
    final resolved = await Future.wait(candidateIds.map(AssetEntity.fromId));
    final stillExisting = <String>[];
    for (var i = 0; i < candidateIds.length; i++) {
      if (resolved[i] != null) {
        stillExisting.add(candidateIds[i]);
      }
    }
    return stillExisting;
  }

  Future<DeleteFromDeviceResult> deleteAllFromDevice() async {
    final idsToDelete = ids;
    if (idsToDelete.isEmpty) return const DeleteFromDeviceResult(failedIds: []);

    final reportedFailedIds = await PhotoManager.editor.deleteWithIds(idsToDelete);

    // On iOS, the underlying API can sometimes report failures even when the asset
    // is actually gone after the operation. Verify existence and keep only truly
    // still-existing assets in the queue.
    final trulyFailedIds = await _filterIdsThatStillExist(reportedFailedIds);

    final failedSet = trulyFailedIds.toSet();
    final deletedOrGone = idsToDelete.where((id) => !failedSet.contains(id)).toList(growable: false);

    if (deletedOrGone.isNotEmpty) {
      await _box.deleteAll(deletedOrGone);
    }
    await _box.flush();

    return DeleteFromDeviceResult(failedIds: trulyFailedIds);
  }
}

