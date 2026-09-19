/// 云端资源存储配置：只有管理员解锁后才显示、默认空、保存走服务端（存 MySQL）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luoyunzong/core/constants.dart';
import 'package:luoyunzong/data/api_client.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/features/settings/settings_page.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

/// 假的服务端：记录收到的配置，不真的发请求。
class FakeApiClient extends ApiClient {
  FakeApiClient({this.saved = false, this.testOk = true})
    : super(baseUrl: 'http://127.0.0.1:9');

  bool saved;
  bool testOk;
  Map<String, Object?>? lastSaved;
  int testCalls = 0;

  @override
  Future<Map<String, Object?>> fetchStorageConfig() async => <String, Object?>{
    'driver': saved ? 's3' : 'local',
    'endpoint': saved ? 'https://s3.bitiful.net' : '',
    'region': saved ? 'cn-east-1' : '',
    'bucket': saved ? 'my-media' : '',
    'accessKey': saved ? 'AK-FROM-SERVER' : '',
    'publicBase': '',
    'secretKeySet': saved,
    'upyunOperator': '',
    'upyunPasswordSet': false,
    'drivers': <String>['local', 's3', 'upyun'],
  };

  @override
  Future<Map<String, Object?>> saveStorageConfig(
    Map<String, Object?> config,
  ) async {
    lastSaved = config;
    saved = true;
    return <String, Object?>{...config, 'secretKeySet': true};
  }

  @override
  Future<({bool ok, String message})> testStorage() async {
    testCalls++;
    return (ok: testOk, message: testOk ? 's3 上传并回读成功' : '对象存储上传失败 403 权限不足');
  }
}

AppState _state({required bool unlocked, ApiClient? client}) {
  final AppState state = AppState(
    repository: LocalRepository(backend: MemoryBackend()),
  );
  if (unlocked) state.unlock(kDefaultAdminPassword);
  state.cloudClient = client;
  return state;
}

Future<void> _pump(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: SettingsPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('只读模式：不显示资源存储配置（也就看不到任何密钥）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, _state(unlocked: false, client: FakeApiClient()));

    expect(find.text('云端资源存储'), findsNothing);
    expect(find.text('Access Key'), findsNothing);
  });

  testWidgets('管理员解锁后：显示配置且默认是空的', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, _state(unlocked: true, client: FakeApiClient()));

    final Finder title = find.text('云端资源存储');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    expect(find.text('保存到服务器'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    // 默认是「服务端本地磁盘」：对象存储字段先不显示。
    expect(find.widgetWithText(TextField, 'Endpoint'), findsNothing);

    // 切到缤纷云/S3 后字段出现，且默认全空（服务端没配过）。
    await tester.ensureVisible(find.text('存储位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务端本地磁盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('缤纷云 / S3 兼容对象存储').last);
    await tester.pumpAndSettle();

    final TextField endpoint = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Endpoint'),
    );
    expect(endpoint.controller?.text, isEmpty);
    final TextField accessKey = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Access Key'),
    );
    expect(accessKey.controller?.text, isEmpty);
  });

  testWidgets('管理员填缤纷云并保存：配置发给服务端，密钥留空则不下发', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final FakeApiClient client = FakeApiClient();
    final AppState state = _state(unlocked: true, client: client);
    await _pump(tester, state);

    // 切到「缤纷云 / S3」
    await tester.ensureVisible(find.text('存储位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务端本地磁盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('缤纷云 / S3 兼容对象存储').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Endpoint'),
      'https://s3.bitiful.net',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Region'),
      'cn-east-1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '桶名 Bucket'),
      'my-media',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Access Key'),
      'MK-TEST',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Secret Key'),
      'SK-TEST',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存到服务器'));
    await tester.pumpAndSettle();

    expect(client.lastSaved, isNotNull);
    expect(client.lastSaved!['driver'], 's3');
    expect(client.lastSaved!['endpoint'], 'https://s3.bitiful.net');
    expect(client.lastSaved!['region'], 'cn-east-1');
    expect(client.lastSaved!['bucket'], 'my-media');
    expect(client.lastSaved!['accessKey'], 'MK-TEST');
    expect(client.lastSaved!['secretKey'], 'SK-TEST');
    // 保存成功后输入框清空（密钥不回显），状态提示改成「已保存到服务器」
    expect(find.textContaining('已保存到服务器'), findsOneWidget);
    final TextField secret = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Secret Key'),
    );
    expect(secret.controller?.text, isEmpty);
  });

  testWidgets('测试连接：把服务端返回的失败原因原样显示出来', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final FakeApiClient client = FakeApiClient(testOk: false);
    await _pump(tester, _state(unlocked: true, client: client));

    await tester.ensureVisible(find.text('测试连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(client.testCalls, 1);
    expect(find.textContaining('403'), findsOneWidget);
  });
}
