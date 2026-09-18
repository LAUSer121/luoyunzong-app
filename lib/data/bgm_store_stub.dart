/// BGM 文件仓库（Web）：浏览器端不落盘，仅本次会话有效。
library;

bool get bgmStorageSupported => false;

Future<String?> storeAudioFile(String name, List<int> bytes) async => null;

Future<bool> audioFileExists(String name) async => false;

Future<String?> audioFilePath(String name) async => null;

Future<List<String>> listAudioFiles() async => <String>[];

Future<void> deleteAudioFile(String name) async {}
