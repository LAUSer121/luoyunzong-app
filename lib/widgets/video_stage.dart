/// 视频播放舞台：非 Web 平台用 media_kit 播放 base64 视频，Web 端给出降级提示。
///
/// 通过条件导入区分实现，保证 Web 构建不引入原生媒体依赖。
library;

export 'video_stage_stub.dart' if (dart.library.io) 'video_stage_io.dart';
