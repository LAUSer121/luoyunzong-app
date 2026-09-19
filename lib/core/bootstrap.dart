/// 启动装配：挑数据源、装好云同步通道。
///
/// 抽成独立文件（而不是写在 `main.dart` 里）是为了可测：
/// 尤其是「云端连不上时整机仍能纯本地用，同时保留同步通道等恢复」这条底线。
library;

import '../data/api_client.dart';
import '../data/api_repository.dart';
import '../data/local_repository.dart';
import '../data/settings_store.dart';
import '../domain/repository.dart';
import '../state/app_state.dart';
import '../state/sync_manager.dart';
import 'app_config.dart';

/// 数据源装配结果。
typedef ResolvedRepository = ({
  /// 实际使用的仓储：云端可用时是 [ApiRepository]，否则本地仓储。
  LuoyunRepository repository,

  /// 本地仓储（同步快照固定写在它这儿）。
  LocalRepository local,

  /// 云端通道：即使启动时探测失败也会保留，供自动/手动同步稍后重试。
  ApiRepository? cloud,
});

/// 选择数据源：
/// 1) 构建期注入的候选地址能连通 → 云端 + 本地兜底；
/// 2) 都不通 → 先用本地存档，同时保留云端通道（[ResolvedRepository.cloud]），
///    打开自动同步后会定时重试，恢复即自动补齐；
/// 3) 没有任何候选 → 纯本地，无云同步。
///
/// 全过程不在界面展示任何服务端/数据库信息。
Future<ResolvedRepository> resolveRepository({
  List<String>? candidates,
  String? token,
  LocalRepository? local,
}) async {
  final LocalRepository localRepo = local ?? LocalRepository();
  final List<String> list = candidates ?? AppConfig.apiCandidates;
  final String apiToken = token ?? AppConfig.apiToken;

  ApiRepository? offlineCloud;
  for (final String base in list) {
    final String trimmed = base.trim();
    if (trimmed.isEmpty) continue;
    final ApiClient client = ApiClient(baseUrl: trimmed, token: apiToken);
    final ApiRepository api = ApiRepository(
      client: client,
      fallback: localRepo,
    );
    if (await client.ping()) {
      return (repository: api, local: localRepo, cloud: api);
    }
    // 第一个候选留作离线重试通道（复用已建好的 client，不再多开连接）。
    offlineCloud ??= api;
  }
  if (offlineCloud == null) {
    return (repository: localRepo, local: localRepo, cloud: null);
  }
  return (repository: localRepo, local: localRepo, cloud: offlineCloud);
}

/// 按「构建期注入 + 用户设置」挑候选地址（真机启动走这条）。
///
/// - 构建期地址（可多个）优先，桌面/网页端再兜底本机回环；
/// - 只有允许显示服务端配置的调试包，才把用户手填的地址也算作候选。
Future<ResolvedRepository> resolveRepositoryFromSettings(
  SettingsStore settings,
) async {
  final String savedBase = (await settings.apiBaseUrl()).trim();
  final String savedToken = (await settings.apiToken()).trim();
  final bool savedEnabled = await settings.useRemote();
  final bool allowSaved = AppConfig.showServerConfig && savedEnabled;
  final String bakedToken = AppConfig.apiToken.trim();

  return resolveRepository(
    candidates: <String>[
      ...AppConfig.apiCandidates,
      if (allowSaved && savedBase.isNotEmpty) savedBase,
    ],
    token: bakedToken.isNotEmpty ? bakedToken : savedToken,
  );
}

/// 把云同步引擎接到 [AppState] 上（`cloud` 为空时引擎只报「未启用云端」）。
Future<SyncManager> attachSync(
  AppState state, {
  required SettingsStore settings,
  ApiRepository? cloud,
}) async {
  final SyncManager sync = SyncManager(
    gateway: cloud == null
        ? null
        : RepositoryCloudGateway(repository: cloud, client: cloud.client),
    readArchive: () => state.archive,
    applyArchive: state.applyRemoteArchive,
    readLocalChangeAt: () => state.lastLocalChangeAt,
    markLocalSynced: state.markSyncedAt,
    writeSnapshot: state.writeSyncSnapshot,
    readSnapshot: state.readSyncSnapshot,
    persistAutoSync: settings.setAutoSync,
    persistLastSyncAt: settings.setLastSyncAt,
  );
  state.sync = sync;
  // 设置页里的管理员操作（对象存储配置等）复用同一个客户端。
  state.cloudClient = cloud?.client;
  state.restoreLocalChangeAt(await settings.lastLocalChangeAt());
  sync.restore(
    autoSync: await settings.autoSync(),
    lastSyncAt: await settings.lastSyncAt(),
  );
  return sync;
}
