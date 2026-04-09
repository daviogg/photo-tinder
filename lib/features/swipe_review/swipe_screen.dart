import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photoswipe/features/gallery_access/gallery_permission_controller.dart';
import 'package:photoswipe/features/favorites/favorites_screen.dart';
import 'package:photoswipe/features/swipe_review/swipe_controller.dart';
import 'package:photoswipe/shared/models/swipe_action.dart';

class SwipeScreen extends ConsumerStatefulWidget {
  const SwipeScreen({super.key});

  @override
  ConsumerState<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends ConsumerState<SwipeScreen> {
  late CardSwiperController _swiperController;
  late final _AppResumeObserver _resumeObserver;
  int _topIndex = 0;

  @override
  void initState() {
    super.initState();
    _swiperController = CardSwiperController();
    _resumeObserver = _AppResumeObserver(onResume: _onAppResumed);
    WidgetsBinding.instance.addObserver(_resumeObserver);
  }

  void _resetSwiperController() {
    _swiperController.dispose();
    _swiperController = CardSwiperController();
    _topIndex = 0;
  }

  Future<void> _reloadPreservingTop({String? assetId}) async {
    await ref.read(swipeControllerProvider.notifier).reload();
    if (!mounted) return;

    final s = ref.read(swipeControllerProvider).asData?.value;
    if (s == null || s.assets.isEmpty) return;

    final targetIndex = assetId == null ? null : s.assets.indexWhere((a) => a.id == assetId);
    if (targetIndex != null && targetIndex >= 0) {
      _topIndex = targetIndex;
      _swiperController.moveTo(targetIndex);
    } else {
      _swiperController.moveTo(_topIndex.clamp(0, s.assets.length - 1));
    }
  }

  Future<void> _onAppResumed() async {
    // When coming back from iOS limited picker / Settings, refresh permission state
    // and reload assets so the UI reflects newly-authorized photos automatically.
    await ref.read(galleryPermissionControllerProvider.notifier).refresh();
    if (!mounted) return;
    setState(_resetSwiperController);
    await ref.read(swipeControllerProvider.notifier).reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_resumeObserver);
    _swiperController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final swipeAsync = ref.watch(swipeControllerProvider);
    final permissionAsync = ref.watch(galleryPermissionControllerProvider);

    ref.listen(galleryPermissionControllerProvider, (prev, next) {
      final prevLevel = prev?.asData?.value.level;
      final nextLevel = next.asData?.value.level;
      if (prevLevel == null || nextLevel == null) return;
      if (prevLevel == nextLevel) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(_resetSwiperController);
        ref.read(swipeControllerProvider.notifier).reload();
      });
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          permissionAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
            data: (p) {
              if (p.level != GalleryAccessLevel.limited) return const SizedBox.shrink();
              return Row(
                children: [
                  IconButton(
                    tooltip: 'Select more photos',
                    onPressed: () async {
                      await ref.read(galleryPermissionControllerProvider.notifier).manageLimitedSelection();
                      if (!mounted) return;
                      await _onAppResumed();
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  IconButton(
                    tooltip: 'Enable Full Access (iOS Settings)',
                    onPressed: () async {
                      await ref.read(galleryPermissionControllerProvider.notifier).openSettings();
                      if (!mounted) return;
                      await _onAppResumed();
                    },
                    icon: const Icon(Icons.lock_open),
                  ),
                ],
              );
            },
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: () async {
              final ok = await ref.read(swipeControllerProvider.notifier).undoLast();
              if (ok) {
                _swiperController.undo();
              }
            },
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Favorites',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              );
            },
            icon: const Icon(Icons.favorite_border),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background inspired by the provided reference: deep navy base with
          // a soft magenta glow and subtle vignette.
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFF0B1020)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.65, -0.85),
                radius: 1.25,
                colors: [
                  Color(0xE0FF49C2), // stronger pink/violet glow
                  Color(0x804B1D6B),
                  Color(0x000B1020),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Extra wide violet wash to make the light purple more predominant.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.15, -0.25),
                radius: 1.55,
                colors: [
                  Color(0xA07C3AED),
                  Color(0x30401050),
                  Color(0x000B1020),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.15, -0.15),
                radius: 1.35,
                colors: [
                  Color(0x503B82F6),
                  Color(0x000B1020),
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0),
                radius: 1.35,
                colors: [
                  Color(0x00000000),
                  Color(0x99000000),
                ],
                stops: [0.55, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: swipeAsync.when(
              loading: () => const Center(child: CupertinoActivityIndicator()),
              error: (e, st) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading photos.\n$e',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (state) {
                if (state.assets.isEmpty) {
                  final isLimited = permissionAsync.asData?.value.level == GalleryAccessLevel.limited;
                  final title = isLimited
                      ? 'No photos available'
                      : (state.showKept ? 'No kept photos' : 'All photos reviewed');
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Icon(Icons.photo_library_outlined, color: Colors.white, size: 26),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isLimited
                                      ? 'No photos found, or none accessible with your current permission level (Limited).'
                                      : (state.showKept
                                          ? 'You have no kept photos to browse.'
                                          : 'Nothing left to review. You can now browse kept photos.'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.78),
                                        height: 1.3,
                                      ),
                                ),
                                const SizedBox(height: 14),
                                if (!isLimited && !state.showKept)
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () async {
                                        await ref.read(swipeControllerProvider.notifier).onDeckEnded();
                                        if (!mounted) return;
                                        setState(_resetSwiperController);
                                      },
                                      child: const Text('Show kept photos'),
                                    ),
                                  )
                                else
                                  permissionAsync.maybeWhen(
                                    data: (p) => p.level == GalleryAccessLevel.limited
                                        ? Column(
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: FilledButton.icon(
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: () async {
                                                    await ref
                                                        .read(galleryPermissionControllerProvider.notifier)
                                                        .manageLimitedSelection();
                                                    if (!mounted) return;
                                                    await _onAppResumed();
                                                  },
                                                  icon: const Icon(Icons.add_photo_alternate_outlined),
                                                  label: const Text('Select more photos'),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.white,
                                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                                                  ),
                                                  onPressed: () async {
                                                    await ref
                                                        .read(galleryPermissionControllerProvider.notifier)
                                                        .openSettings();
                                                    if (!mounted) return;
                                                    await _onAppResumed();
                                                  },
                                                  icon: const Icon(Icons.lock_open),
                                                  label: const Text('Enable full access in Settings'),
                                                ),
                                              ),
                                            ],
                                          )
                                        : const SizedBox.shrink(),
                                    orElse: () => const SizedBox.shrink(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _DeletingZoneBar(
                    count: state.deleteQueueIds.length,
                    onOpen: () => _openDeletingZone(context),
                    onDeleteAll: state.deleteQueueIds.isEmpty
                        ? null
                        : () async {
                            final ok = await _confirmDeleteAll(context, count: state.deleteQueueIds.length);
                            if (!ok) return;
                            final deletedOk = await ref
                                .read(swipeControllerProvider.notifier)
                                .deleteQueuedFromDevice();
                            if (!context.mounted) return;
                            // Keep current deck position: the controller already removes
                            // deleted assets from memory; avoid a full reload/reset here.
                        final current = ref.read(swipeControllerProvider).asData?.value;
                        final topAssetId = (current != null && current.assets.isNotEmpty && _topIndex < current.assets.length)
                            ? current.assets[_topIndex].id
                            : null;
                        await _reloadPreservingTop(assetId: topAssetId);
                        if (!context.mounted) return;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  deletedOk
                                      ? 'Deleted. To free iCloud space: Photos → Recently Deleted → Delete.'
                                      : 'Some items could not be deleted. iCloud space: Photos → Recently Deleted → Delete.',
                                ),
                              ),
                            );
                          },
                    onClear: state.deleteQueueIds.isEmpty
                        ? null
                        : () async {
                            await ref.read(swipeControllerProvider.notifier).clearDeleteQueue();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Deleting zone cleared.')),
                            );
                          },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: CardSwiper(
                      // Avoid resetting the deck when the list size changes (e.g. after bulk delete),
                      // otherwise already-reviewed items can resurface from index 0.
                      key: const ValueKey('swipe-deck'),
                      controller: _swiperController,
                      cardsCount: state.assets.length,
                      numberOfCardsDisplayed: math.min(3, state.assets.length),
                      isLoop: false,
                      onEnd: () async {
                        await ref.read(swipeControllerProvider.notifier).onDeckEnded();
                        if (!context.mounted) return;
                        setState(_resetSwiperController);
                      },
                      allowedSwipeDirection: const AllowedSwipeDirection.only(
                        left: true,
                        right: true,
                        up: true,
                        down: false,
                      ),
                      onSwipe: (previousIndex, currentIndex, direction) async {
                        final action = _mapDirection(direction);
                        if (action == null) return true;

                        // CardSwiper calls `onSwipe` before its internal `_reset()` completes.
                        // Triggering pagination here can change `cardsCount` mid-reset and cause
                        // underlay/next-card "skips". Defer to next frame for coherence.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _topIndex = currentIndex ?? previousIndex + 1;
                          ref.read(swipeControllerProvider.notifier).onSwiped(
                                swipedIndex: previousIndex,
                                action: action,
                                nextIndexHint: currentIndex ?? previousIndex + 1,
                              );
                        });
                        return true;
                      },
                      cardBuilder: (context, index, percentThresholdX, percentThresholdY) {
                        final asset = state.assets[index];
                        return _PhotoCard(asset: asset);
                      },
                    ),
                  ),
                ),
                _SwipeHintBar(
                  onKeep: () => _swiperController.swipe(CardSwiperDirection.right),
                  onDelete: () => _swiperController.swipe(CardSwiperDirection.left),
                  onFavorite: () => _swiperController.swipe(CardSwiperDirection.top),
                ),
                const SizedBox(height: 10),
              ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  SwipeAction? _mapDirection(CardSwiperDirection direction) {
    return switch (direction) {
      CardSwiperDirection.left => SwipeAction.delete,
      CardSwiperDirection.right => SwipeAction.keep,
      CardSwiperDirection.top => SwipeAction.favorite,
      _ => null,
    };
  }

  Future<void> _openDeletingZone(BuildContext context) async {
    final current = ref.read(swipeControllerProvider).asData?.value;
    final topAssetId = (current != null && current.assets.isNotEmpty && _topIndex < current.assets.length)
        ? current.assets[_topIndex].id
        : null;

    final deletedOk = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => const _DeletingZoneSheet(),
    );

    if (!mounted) return;
    if (deletedOk == null) return;

    await _reloadPreservingTop(assetId: topAssetId);
    if (!mounted) return;
    ScaffoldMessenger.of(this.context).clearSnackBars();
    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(
        content: Text(
          deletedOk
              ? 'Deleted. To free iCloud space: Photos → Recently Deleted → Delete.'
              : 'Some items could not be deleted. iCloud space: Photos → Recently Deleted → Delete.',
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteAll(BuildContext context, {required int count}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete photos?'),
        content: Text('This will permanently delete $count photos from your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _AppResumeObserver extends WidgetsBindingObserver {
  _AppResumeObserver({required this.onResume});

  final Future<void> Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AssetEntityImage(
              asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize(900, 900),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CupertinoActivityIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load this photo.\n$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xB0000000),
                  ],
                  stops: [0.55, 1],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      _formatMeta(asset),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMeta(AssetEntity asset) {
    final date = asset.createDateTime;
    final w = asset.width;
    final h = asset.height;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} • $w×$h';
  }
}

class _SwipeHintBar extends StatelessWidget {
  const _SwipeHintBar({
    required this.onDelete,
    required this.onKeep,
    required this.onFavorite,
  });

  final VoidCallback onDelete;
  final VoidCallback onKeep;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundActionButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onDelete();
                },
                icon: Icons.close,
                label: 'Delete',
                color: const Color(0xFFF43F5E),
              ),
              _RoundActionButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onFavorite();
                },
                icon: Icons.star,
                label: 'Fav',
                color: const Color(0xFFF59E0B),
              ),
              _RoundActionButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onKeep();
                },
                icon: Icons.check,
                label: 'Keep',
                color: const Color(0xFF22C55E),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.86),
            foregroundColor: color,
            minimumSize: const Size(64, 64),
            elevation: 2,
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ],
    );
  }
}

class _DeletingZoneBar extends StatelessWidget {
  const _DeletingZoneBar({
    required this.count,
    required this.onOpen,
    required this.onDeleteAll,
    required this.onClear,
  });

  final int count;
  final VoidCallback onOpen;
  final VoidCallback? onDeleteAll;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onOpen,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.delete_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text(
                          '$count',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear zone',
                onPressed: onClear,
                icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: onDeleteAll,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF43F5E),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete all'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeletingZoneSheet extends ConsumerWidget {
  const _DeletingZoneSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swipeAsync = ref.watch(swipeControllerProvider);

    return SafeArea(
      child: swipeAsync.when(
        loading: () => const SizedBox(height: 260, child: Center(child: CupertinoActivityIndicator())),
        error: (e, st) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error.\n$e'),
        ),
        data: (state) {
          final ids = state.deleteQueueIds;
          if (ids.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Deleting zone is empty. Swipe left to add photos here.'),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deleting zone (${ids.length})',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'These photos will be deleted only when you tap “Delete all”.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemCount: ids.length,
                    itemBuilder: (context, index) => _QueuedPhotoTile(
                      assetId: ids[index],
                      onRemove: () async {
                        HapticFeedback.selectionClick();
                        await ref.read(swipeControllerProvider.notifier).removeFromDeleteQueue(ids[index]);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await ref.read(swipeControllerProvider.notifier).clearDeleteQueue();
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                        },
                        child: const Text('Clear zone'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete photos?'),
                              content: Text('This will permanently delete ${ids.length} photos from your device.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;

                          final deletedOk =
                              await ref.read(swipeControllerProvider.notifier).deleteQueuedFromDevice();
                          if (!context.mounted) return;
                          Navigator.of(context).pop(deletedOk);
                        },
                        child: const Text('Delete all'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QueuedPhotoTile extends StatelessWidget {
  const _QueuedPhotoTile({required this.assetId, required this.onRemove});

  final String assetId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(assetId),
      builder: (context, snapshot) {
        final asset = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                ),
                child: asset == null
                    ? const Center(child: CupertinoActivityIndicator())
                    : AssetEntityImage(
                        asset,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize(320, 320),
                        fit: BoxFit.cover,
                      ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    tooltip: 'Remove from zone',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

