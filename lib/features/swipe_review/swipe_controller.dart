import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photoswipe/shared/models/swipe_action.dart';
import 'package:photoswipe/shared/models/swipe_record.dart';
import 'package:photoswipe/shared/services/service_providers.dart';

class SwipeState {
  const SwipeState({
    required this.assets,
    required this.page,
    required this.isLastPage,
    required this.loadingMore,
    required this.undoStack,
    required this.deleteQueueIds,
    required this.keptIds,
    required this.replayKeeps,
  });

  final List<AssetEntity> assets;
  final int page;
  final bool isLastPage;
  final bool loadingMore;
  final List<SwipeRecord> undoStack;
  /// Ordered list (oldest first) of assets marked for deletion review.
  final List<String> deleteQueueIds;
  /// Assets swiped as "keep" during the current main pass, replayed only after deck ends.
  final List<String> keptIds;
  /// Whether we are currently replaying only kept photos.
  final bool replayKeeps;

  SwipeState copyWith({
    List<AssetEntity>? assets,
    int? page,
    bool? isLastPage,
    bool? loadingMore,
    List<SwipeRecord>? undoStack,
    List<String>? deleteQueueIds,
    List<String>? keptIds,
    bool? replayKeeps,
  }) {
    return SwipeState(
      assets: assets ?? this.assets,
      page: page ?? this.page,
      isLastPage: isLastPage ?? this.isLastPage,
      loadingMore: loadingMore ?? this.loadingMore,
      undoStack: undoStack ?? this.undoStack,
      deleteQueueIds: deleteQueueIds ?? this.deleteQueueIds,
      keptIds: keptIds ?? this.keptIds,
      replayKeeps: replayKeeps ?? this.replayKeeps,
    );
  }
}

final swipeControllerProvider = AsyncNotifierProvider<SwipeController, SwipeState>(
  SwipeController.new,
);

class SwipeController extends AsyncNotifier<SwipeState> {
  static const _pageSize = 60;

  @override
  Future<SwipeState> build() async {
    final photoService = ref.read(photoServiceProvider);
    final first = await photoService.fetchPage(page: 0, pageSize: _pageSize);

    final favorites = await ref.read(favoritesServiceProvider.future);
    final favoriteIds = favorites.ids.toSet();

    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    final queuedIds = deleteQueue.ids;

    return SwipeState(
      assets: first.assets.where((a) => !favoriteIds.contains(a.id)).toList(growable: false),
      page: 0,
      isLastPage: first.isLastPage,
      loadingMore: false,
      undoStack: const [],
      deleteQueueIds: queuedIds,
      keptIds: const [],
      replayKeeps: false,
    );
  }

  Future<void> _maybeLoadMore(int currentIndex) async {
    final s = state.asData?.value;
    if (s == null) return;
    if (s.replayKeeps) return;
    if (s.isLastPage || s.loadingMore) return;

    // Prefetch when near the end.
    final remaining = s.assets.length - currentIndex - 1;
    if (remaining > 12) return;

    state = AsyncData(s.copyWith(loadingMore: true));
    state = await AsyncValue.guard(() async {
      final photoService = ref.read(photoServiceProvider);
      final favorites = await ref.read(favoritesServiceProvider.future);
      final favoriteIds = favorites.ids.toSet();
      final nextPage = s.page + 1;
      final next = await photoService.fetchPage(page: nextPage, pageSize: _pageSize);
      return s.copyWith(
        assets: [
          ...s.assets,
          ...next.assets.where((a) => !favoriteIds.contains(a.id)),
        ],
        page: nextPage,
        isLastPage: next.isLastPage,
        loadingMore: false,
      );
    });
  }

  Future<void> onSwiped({
    required int swipedIndex,
    required SwipeAction action,
    required int nextIndexHint,
  }) async {
    final s = state.asData?.value;
    if (s == null) return;
    if (swipedIndex < 0 || swipedIndex >= s.assets.length) return;

    final asset = s.assets[swipedIndex];
    final record = SwipeRecord(assetId: asset.id, action: action);

    // Side-effects.
    switch (action) {
      case SwipeAction.keep:
        break;
      case SwipeAction.delete:
        final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
        await deleteQueue.enqueue(asset.id);
        break;
      case SwipeAction.favorite:
        final favorites = await ref.read(favoritesServiceProvider.future);
        await favorites.add(asset.id);
        break;
    }

    state = AsyncData(
      s.copyWith(
        undoStack: [...s.undoStack, record],
        keptIds: action == SwipeAction.keep
            ? (s.keptIds.contains(asset.id) ? s.keptIds : [...s.keptIds, asset.id])
            : s.keptIds,
        deleteQueueIds: action == SwipeAction.delete
            ? (s.deleteQueueIds.contains(asset.id) ? s.deleteQueueIds : [...s.deleteQueueIds, asset.id])
            : s.deleteQueueIds,
      ),
    );

    _maybeLoadMore(nextIndexHint);
  }

  Future<void> onDeckEnded() async {
    final s = state.asData?.value;
    if (s == null) return;

    // Only replay keeps after finishing the main pass.
    if (!s.replayKeeps && s.keptIds.isNotEmpty) {
      final keptSet = s.keptIds.toSet();
      final keptAssets = s.assets.where((a) => keptSet.contains(a.id)).toList(growable: false);
      state = AsyncData(
        s.copyWith(
          assets: keptAssets,
          page: 0,
          isLastPage: true,
          loadingMore: false,
          keptIds: const [],
          replayKeeps: true,
        ),
      );
    }
  }

  Future<bool> undoLast() async {
    final s = state.asData?.value;
    if (s == null) return false;
    if (s.undoStack.isEmpty) return false;

    final last = s.undoStack.last;
    switch (last.action) {
      case SwipeAction.keep:
        break;
      case SwipeAction.delete:
        final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
        await deleteQueue.dequeue(last.assetId);
        break;
      case SwipeAction.favorite:
        final favorites = await ref.read(favoritesServiceProvider.future);
        await favorites.remove(last.assetId);
        break;
    }

    state = AsyncData(
      s.copyWith(
        undoStack: s.undoStack.sublist(0, s.undoStack.length - 1),
        deleteQueueIds: last.action == SwipeAction.delete
            ? (s.deleteQueueIds.where((id) => id != last.assetId).toList(growable: false))
            : s.deleteQueueIds,
      ),
    );
    return true;
  }

  Future<void> removeFromDeleteQueue(String assetId) async {
    final s = state.asData?.value;
    if (s == null) return;
    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    await deleteQueue.dequeue(assetId);
    state = AsyncData(
      s.copyWith(
        deleteQueueIds: s.deleteQueueIds.where((id) => id != assetId).toList(growable: false),
      ),
    );
  }

  Future<void> clearDeleteQueue() async {
    final s = state.asData?.value;
    if (s == null) return;
    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    await deleteQueue.clear();
    state = AsyncData(s.copyWith(deleteQueueIds: const []));
  }

  Future<bool> deleteQueuedFromDevice() async {
    final s = state.asData?.value;
    if (s == null) return false;

    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    final idsBefore = deleteQueue.ids;
    if (idsBefore.isEmpty) return true;

    final result = await deleteQueue.deleteAllFromDevice();

    // Compute deletions based on queue after operation (more reliable on iOS).
    final remainingIds = deleteQueue.ids;
    final remainingSet = remainingIds.toSet();
    final deleted = idsBefore.where((id) => !remainingSet.contains(id)).toSet();

    final nextAssets = s.assets.where((a) => !deleted.contains(a.id)).toList(growable: false);
    final nextUndo = s.undoStack.where((r) => !deleted.contains(r.assetId)).toList(growable: false);

    // Sync delete queue IDs with what's still pending (usually the failures).
    state = AsyncData(
      s.copyWith(
        assets: nextAssets,
        undoStack: nextUndo,
        deleteQueueIds: remainingIds,
      ),
    );
    return result.allDeleted;
  }
}

