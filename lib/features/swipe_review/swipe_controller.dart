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
    required this.showKept,
  });

  final List<AssetEntity> assets;
  final int page;
  final bool isLastPage;
  final bool loadingMore;
  final List<SwipeRecord> undoStack;
  /// Ordered list (oldest first) of assets marked for deletion review.
  final List<String> deleteQueueIds;
  /// IDs of assets marked as "keep" (persisted).
  final List<String> keptIds;
  /// If true, show kept photos after all unreviewed are done.
  final bool showKept;

  SwipeState copyWith({
    List<AssetEntity>? assets,
    int? page,
    bool? isLastPage,
    bool? loadingMore,
    List<SwipeRecord>? undoStack,
    List<String>? deleteQueueIds,
    List<String>? keptIds,
    bool? showKept,
  }) {
    return SwipeState(
      assets: assets ?? this.assets,
      page: page ?? this.page,
      isLastPage: isLastPage ?? this.isLastPage,
      loadingMore: loadingMore ?? this.loadingMore,
      undoStack: undoStack ?? this.undoStack,
      deleteQueueIds: deleteQueueIds ?? this.deleteQueueIds,
      keptIds: keptIds ?? this.keptIds,
      showKept: showKept ?? this.showKept,
    );
  }
}

final swipeControllerProvider = AsyncNotifierProvider<SwipeController, SwipeState>(
  SwipeController.new,
);

class SwipeController extends AsyncNotifier<SwipeState> {
  static const _pageSize = 60;
  static const _minInitialDeckSize = 30;

  Future<SwipeState> _loadFirstPage({required bool showKept}) async {
    final photoService = ref.read(photoServiceProvider);
    var page = 0;
    var isLastPage = false;
    final collected = <AssetEntity>[];

    final favorites = await ref.read(favoritesServiceProvider.future);
    final favoriteIds = favorites.ids.toSet();

    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    final queuedIds = deleteQueue.ids;
    final queuedSet = queuedIds.toSet();

    final kept = await ref.read(keptServiceProvider.future);
    final keptIds = kept.ids;
    final keptSet = keptIds.toSet();

    // Phase filtering:
    // - showKept=false: show only unreviewed => exclude favorites, delete-queue, kept
    // - showKept=true: show only kept => exclude favorites, delete-queue and then include only kept
    final baseExclude = {...favoriteIds, ...queuedSet};
    final excludeIds = showKept ? baseExclude : {...baseExclude, ...keptSet};

    while (collected.length < _minInitialDeckSize && !isLastPage) {
      final res = await photoService.fetchPage(page: page, pageSize: _pageSize);
      isLastPage = res.isLastPage;
      final filtered = res.assets.where((a) => !excludeIds.contains(a.id));
      if (showKept) {
        collected.addAll(filtered.where((a) => keptSet.contains(a.id)));
      } else {
        collected.addAll(filtered);
      }
      page += 1;
    }

    // `page` is now the next page index to fetch.
    final ordered = _orderAssets(assets: collected, keptSet: keptSet);

    return SwipeState(
      assets: ordered,
      page: 0,
      isLastPage: isLastPage,
      loadingMore: false,
      undoStack: const [],
      deleteQueueIds: queuedIds,
      keptIds: keptIds,
      showKept: showKept,
    );
  }

  static List<AssetEntity> _orderAssets({
    required List<AssetEntity> assets,
    required Set<String> keptSet,
  }) {
    if (assets.isEmpty) return assets;
    final unreviewed = <AssetEntity>[];
    final kept = <AssetEntity>[];
    for (final a in assets) {
      (keptSet.contains(a.id) ? kept : unreviewed).add(a);
    }
    return [...unreviewed, ...kept];
  }

  @override
  Future<SwipeState> build() async {
    // Default: don't show kept until the deck is finished.
    return _loadFirstPage(showKept: false);
  }

  Future<void> reload() async {
    final s = state.asData?.value;
    if (s == null) return;
    if (s.loadingMore) return;

    state = await AsyncValue.guard(() async {
      final next = await _loadFirstPage(showKept: s.showKept);
      return s.copyWith(
        assets: next.assets,
        page: next.page,
        isLastPage: next.isLastPage,
        loadingMore: next.loadingMore,
        deleteQueueIds: next.deleteQueueIds,
        keptIds: next.keptIds,
        showKept: next.showKept,
      );
    });
  }

  Future<void> _loadMore({required int currentIndex}) async {
    final s = state.asData?.value;
    if (s == null) return;
    if (s.isLastPage || s.loadingMore) return;

    // Prefetch when near the end.
    final remaining = s.assets.length - currentIndex - 1;
    if (remaining > 12) return;

    state = AsyncData(s.copyWith(loadingMore: true));
    state = await AsyncValue.guard(() async {
      final photoService = ref.read(photoServiceProvider);
      final favorites = await ref.read(favoritesServiceProvider.future);
      final favoriteIds = favorites.ids.toSet();
      final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
      final queuedIds = deleteQueue.ids.toSet();
      final kept = await ref.read(keptServiceProvider.future);
      final keptSet = kept.ids.toSet();

      final baseExclude = {...favoriteIds, ...queuedIds};
      final excludeIds = s.showKept ? baseExclude : {...baseExclude, ...keptSet};

      var page = s.page + 1;
      var isLastPage = false;
      final added = <AssetEntity>[];

      while (added.isEmpty && !isLastPage) {
        final res = await photoService.fetchPage(page: page, pageSize: _pageSize);
        isLastPage = res.isLastPage;
        final filtered = res.assets.where((a) => !excludeIds.contains(a.id));
        if (s.showKept) {
          added.addAll(filtered.where((a) => keptSet.contains(a.id)));
        } else {
          added.addAll(filtered);
        }
        page += 1;
      }

      final nextAssets = [...s.assets, ...added];
      return s.copyWith(
        assets: nextAssets,
        page: page - 1,
        isLastPage: isLastPage,
        loadingMore: false,
      );
    });
  }

  Future<void> _maybeLoadMore(int currentIndex) async {
    await _loadMore(currentIndex: currentIndex);
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
        final kept = await ref.read(keptServiceProvider.future);
        await kept.keep(asset.id);
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
    if (!s.isLastPage) {
      // There are more photos in the gallery: keep reviewing unreviewed.
      await _loadMore(currentIndex: s.assets.length - 1);
      return;
    }

    if (s.showKept) return;

    // Only when unreviewed is truly exhausted do we switch to kept browsing.
    state = await AsyncValue.guard(() async {
      final next = await _loadFirstPage(showKept: true);
      return s.copyWith(
        assets: next.assets,
        page: next.page,
        isLastPage: next.isLastPage,
        loadingMore: next.loadingMore,
        deleteQueueIds: next.deleteQueueIds,
        keptIds: next.keptIds,
        showKept: true,
      );
    });
  }

  Future<bool> undoLast() async {
    final s = state.asData?.value;
    if (s == null) return false;
    if (s.undoStack.isEmpty) return false;

    final last = s.undoStack.last;
    final asset = await AssetEntity.fromId(last.assetId);
    switch (last.action) {
      case SwipeAction.keep:
        final kept = await ref.read(keptServiceProvider.future);
        await kept.unkeep(last.assetId);
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

    // Re-insert only if eligible for the current phase:
    // - favorites never reappear
    // - delete-queue never reappears
    // - kept reappears only in kept phase
    final favorites = await ref.read(favoritesServiceProvider.future);
    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    final kept = await ref.read(keptServiceProvider.future);
    final excludeIds = <String>{
      ...favorites.ids,
      ...deleteQueue.ids,
      if (!s.showKept) ...kept.ids,
    };
    final canReinsert = asset != null && !excludeIds.contains(last.assetId);

    state = AsyncData(
      s.copyWith(
        assets: !canReinsert
            ? s.assets
            : ([asset, ...s.assets.where((a) => a.id != last.assetId)]),
        undoStack: s.undoStack.sublist(0, s.undoStack.length - 1),
        keptIds: last.action == SwipeAction.keep
            ? (s.keptIds.where((id) => id != last.assetId).toList(growable: false))
            : s.keptIds,
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

    // IMPORTANT: do not mutate `assets` here.
    //
    // CardSwiper tracks the current card by index. Removing items from the backing list
    // (even items that were swiped earlier) shifts indices and makes the "next/underlay"
    // card appear to change or get skipped after bulk delete.
    //
    // We keep the in-memory deck stable and rely on:
    // - `remainingIds` to reflect the queue after deletion (usually failures)
    // - the next `reload()` (or natural pagination) to reflect the device state
    final nextUndo = s.undoStack.where((r) => !deleted.contains(r.assetId)).toList(growable: false);

    // Sync delete queue IDs with what's still pending (usually the failures).
    state = AsyncData(
      s.copyWith(
        undoStack: nextUndo,
        deleteQueueIds: remainingIds,
        // Bulk-delete should never unlock kept browsing automatically.
        // Kept appear only when the unreviewed deck ends.
        showKept: false,
      ),
    );
    return result.allDeleted;
  }
}

