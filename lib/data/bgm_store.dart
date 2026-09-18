/// BGM 文件仓库：把用户选择的音乐复制到应用数据目录，实现「长期保留」。
///
/// 非 Web 平台用文件系统，Web 端降级为「本次会话有效」。
library;

import 'bgm_store_stub.dart' if (dart.library.io) 'bgm_store_io.dart' as impl;

/// 保存音频文件，返回可播放路径（Web 返回 `null`）。
Future<String?> storeAudioFile(String name, List<int> bytes) =>
    impl.storeAudioFile(name, bytes);

/// 文件是否已存在。
Future<bool> audioFileExists(String name) => impl.audioFileExists(name);

/// 音频文件路径（Web 或不存在时返回 `null`）。
Future<String?> audioFilePath(String name) => impl.audioFilePath(name);

/// 列出已保存的音频文件名。
Future<List<String>> listAudioFiles() => impl.listAudioFiles();

/// 删除音频文件。
Future<void> deleteAudioFile(String name) => impl.deleteAudioFile(name);

/// 是否为 Web 端点。
bool get bgmStorageSupported => impl.bgmStorageSupported;
