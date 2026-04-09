import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photoswipe/shared/models/swipe_action.dart';
import 'package:photoswipe/shared/models/swipe_record.dart';
import 'package:photoswipe/shared/services/service_providers.dart';

/// Result of bulk delete from device + in-memory deck trim.
class DeleteQueuedOutcome {
  const DeleteQueuedOutcome({required this.allDeleted, required this.swiperIndex});
  final bool allDeleted;
  /// New top index after trimming deleted assets (also written to [SwipeState.deckTopIndex]).
  final int swiperIndex;
}

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
    required this.deckTopIndex,
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
  /// Index of the top card in [assets] (matches CardSwiper after each swipe).
  final int deckTopIndex;

  SwipeState copyWith({
    List<AssetEntity>? assets,
    int? page,
    bool? isLastPage,
    bool? loadingMore,
    List<SwipeRecord>? undoStack,
    List<String>? deleteQueueIds,
    List<String>? keptIds,
    bool? showKept,
    int? deckTopIndex,
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
      deckTopIndex: deckTopIndex ?? this.deckTopIndex,
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

    // `page` = count of fetch calls; last fetched album page index is `page - 1`.
    // Must match `_loadMore` (which stores last fetched index) or we re-fetch the same pages.
    final lastFetchedPage = page > 0 ? page - 1 : 0;
    final ordered = _orderAssets(assets: collected, keptSet: keptSet);

    return SwipeState(
      assets: ordered,
      page: lastFetchedPage,
      isLastPage: isLastPage,
      loadingMore: false,
      undoStack: const [],
      deleteQueueIds: queuedIds,
      keptIds: keptIds,
      showKept: showKept,
      deckTopIndex: 0,
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

  Future<void> reload({bool force = false}) async {
    final s = state.asData?.value;
    if (s == null) return;
    if (!force && s.loadingMore) return;

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
        deckTopIndex: 0,
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

      final existingIds = s.assets.map((a) => a.id).toSet();
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

      final uniqueAdded = added.where((a) => !existingIds.contains(a.id)).toList(growable: false);
      final nextAssets = [...s.assets, ...uniqueAdded];
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

  /// Call when the CardSwiper widget is recreated at index 0 (e.g. deck ended / full reset).
  void resetDeckCursorToZero() {
    final s = state.asData?.value;
    if (s == null) return;
    state = AsyncData(s.copyWith(deckTopIndex: 0));
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
    final maxI = s.assets.isEmpty ? 0 : s.assets.length - 1;
    final nextTop = nextIndexHint.clamp(0, maxI);

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
        deckTopIndex: nextTop,
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
        deckTopIndex: 0,
      );
    });
  }

  Future<bool> undoLast() async {
    final s = state.asData?.value;
    if (s == null) return false;
    if (s.undoStack.isEmpty) return false;

    final last = s.undoStack.last;
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

    // Do not mutate `assets`: the deck list stays stable; CardSwiper.undo() moves the index back.
    // Prepending here duplicated entries because swiped items were never removed from `assets`.
    final maxI = s.assets.isEmpty ? 0 : s.assets.length - 1;
    final prevTop = (s.deckTopIndex - 1).clamp(0, maxI);
    state = AsyncData(
      s.copyWith(
        undoStack: s.undoStack.sublist(0, s.undoStack.length - 1),
        deckTopIndex: prevTop,
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

  /// Removes successfully deleted assets from [SwipeState.assets] so thumbnails are not stale.
  Future<DeleteQueuedOutcome> deleteQueuedFromDevice() async {
    final s = state.asData?.value;
    if (s == null) {
      return const DeleteQueuedOutcome(allDeleted: true, swiperIndex: 0);
    }

    final deleteQueue = await ref.read(deleteQueueServiceProvider.future);
    final idsBeforeList = List<String>.from(deleteQueue.ids);
    if (idsBeforeList.isEmpty) {
      final mx = s.assets.isEmpty ? 0 : s.assets.length - 1;
      return DeleteQueuedOutcome(allDeleted: true, swiperIndex: s.deckTopIndex.clamp(0, mx));
    }
    final result = await deleteQueue.deleteAllFromDevice();

    // Re-read queue from a fresh provider so UI and Hive stay in sync (avoids stale counts).
    ref.invalidate(deleteQueueServiceProvider);
    final syncedQueue = await ref.read(deleteQueueServiceProvider.future);
    final remainingIds = List<String>.from(syncedQueue.ids);
    final remainingSet = remainingIds.toSet();
    final deleted = idsBeforeList.where((id) => !remainingSet.contains(id)).toSet();

    final nextAssets = s.assets.where((a) => !deleted.contains(a.id)).toList(growable: false);
    final swiperIndex = _swiperIndexAfterRemovingIds(
      oldAssets: s.assets,
      oldTopIndex: s.deckTopIndex,
      removedIds: deleted,
      nextAssets: nextAssets,
    );
    final nextUndo = s.undoStack.where((r) => !deleted.contains(r.assetId)).toList(growable: false);

    state = AsyncData(
      s.copyWith(
        assets: nextAssets,
        undoStack: nextUndo,
        deleteQueueIds: remainingIds,
        showKept: false,
        deckTopIndex: swiperIndex,
      ),
    );
    return DeleteQueuedOutcome(allDeleted: result.allDeleted, swiperIndex: swiperIndex);
  }

  static int _swiperIndexAfterRemovingIds({
    required List<AssetEntity> oldAssets,
    required int oldTopIndex,
    required Set<String> removedIds,
    required List<AssetEntity> nextAssets,
  }) {
    if (nextAssets.isEmpty) return 0;
    final i = oldTopIndex.clamp(0, oldAssets.isEmpty ? 0 : oldAssets.length - 1);
    final currentId = oldAssets.isEmpty ? null : oldAssets[i].id;

    if (currentId != null && !removedIds.contains(currentId)) {
      final idx = nextAssets.indexWhere((a) => a.id == currentId);
      if (idx >= 0) return idx;
    }
    for (var j = i + 1; j < oldAssets.length; j++) {
      final id = oldAssets[j].id;
      if (!removedIds.contains(id)) {
        final idx = nextAssets.indexWhere((a) => a.id == id);
        if (idx >= 0) return idx;
      }
    }
    return 0;
  }
}

