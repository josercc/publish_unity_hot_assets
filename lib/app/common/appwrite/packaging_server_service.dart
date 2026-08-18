import 'package:appwrite/appwrite.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_auth_service.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_config.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';

PackagingServerService get packagingServers =>
    Get.find<PackagingServerService>();

/// 从 Appwrite 查询打包服务器列表。
class PackagingServerService extends GetxService {
  final activeServers = <PackagingServer>[].obs;

  /// 首页手动选中的打包机 id；空表示未选中，任务走自动分配。
  final selectedServerId = RxnString();

  Databases get _databases => Databases(appwriteAuth.client);

  /// 当前手动选中的打包机；未选中时返回 null。
  PackagingServer? get selectedServer {
    final id = selectedServerId.value;
    if (id == null || id.isEmpty) return null;
    return activeServers.firstWhereOrNull((s) => s.id == id);
  }

  /// 单选切换：点已选中则取消，点其他则选中。
  void toggleSelectedServer(String serverId) {
    if (selectedServerId.value == serverId) {
      selectedServerId.value = null;
    } else {
      selectedServerId.value = serverId;
    }
  }

  /// 拉取 `active == true` 的打包服务器，并缓存到 [activeServers]。
  Future<List<PackagingServer>> fetchActiveServers() async {
    final result = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.packagingServersCollectionId,
      queries: [
        Query.equal('active', true),
        Query.limit(100),
      ],
    );

    final servers = result.documents
        .map((doc) => PackagingServer.fromDocument(doc.data, doc.$id))
        .where((e) => e.active && e.url.isNotEmpty)
        .toList();
    activeServers.assignAll(servers);

    // 选中机已不在列表中时清除选中
    final selectedId = selectedServerId.value;
    if (selectedId != null &&
        !servers.any((s) => s.id == selectedId)) {
      selectedServerId.value = null;
    }
    return servers;
  }

  Future<PackagingServerRefreshResult> refreshAndCheckSelection() async {
    final previousSelectedId = selectedServerId.value;
    final previousSelected = selectedServer;
    final servers = await fetchActiveServers();
    final selectionMissing = previousSelectedId != null &&
        previousSelectedId.isNotEmpty &&
        !servers.any((s) => s.id == previousSelectedId);
    return PackagingServerRefreshResult(
      servers: servers,
      selectionMissing: selectionMissing,
      missingSelectedServerName:
          selectionMissing ? previousSelected?.displayName : null,
    );
  }

  void clear() {
    activeServers.clear();
    selectedServerId.value = null;
  }
}

class PackagingServerRefreshResult {
  final List<PackagingServer> servers;
  final bool selectionMissing;
  final String? missingSelectedServerName;

  const PackagingServerRefreshResult({
    required this.servers,
    required this.selectionMissing,
    required this.missingSelectedServerName,
  });
}
