import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:photoswipe/shared/services/delete_queue_service.dart';
import 'package:photoswipe/shared/services/favorites_service.dart';
import 'package:photoswipe/shared/services/photo_service.dart';

final photoServiceProvider = Provider<PhotoService>((ref) => const PhotoService());

final hiveInitProvider = FutureProvider<void>((ref) async {
  await Hive.initFlutter();
});

final deleteQueueServiceProvider = FutureProvider<DeleteQueueService>((ref) async {
  await ref.watch(hiveInitProvider.future);
  return DeleteQueueService.create();
});

final favoritesServiceProvider = FutureProvider<FavoritesService>((ref) async {
  await ref.watch(hiveInitProvider.future);
  return FavoritesService.create();
});

