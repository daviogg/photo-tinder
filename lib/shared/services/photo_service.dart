import 'package:collection/collection.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotoPage {
  const PhotoPage({
    required this.assets,
    required this.isLastPage,
  });

  final List<AssetEntity> assets;
  final bool isLastPage;
}

class PhotoService {
  const PhotoService();

  Future<PermissionState> getPermissionState() {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        iosAccessLevel: IosAccessLevel.readWrite,
      ),
    );
  }

  Future<PermissionState> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        iosAccessLevel: IosAccessLevel.readWrite,
      ),
    );
    return state;
  }

  Future<void> presentLimitedPicker() async {
    await PhotoManager.presentLimited();
  }

  Future<AssetPathEntity?> _getRecentsPath() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: const [
          OrderOption(
            type: OrderOptionType.createDate,
            asc: false, // newest first
          ),
        ],
      ),
    );
    return paths.firstOrNull;
  }

  Future<PhotoPage> fetchPage({
    required int page,
    required int pageSize,
  }) async {
    final path = await _getRecentsPath();
    if (path == null) {
      return const PhotoPage(assets: [], isLastPage: true);
    }

    final assets = await path.getAssetListPaged(page: page, size: pageSize);
    final isLastPage = assets.length < pageSize;
    return PhotoPage(assets: assets, isLastPage: isLastPage);
  }
}

