import 'package:app/config/dependencies.dart';
import 'package:app/config/features.dart';
import 'package:app/data/approvals/approval_service.dart';
import 'package:app/data/push/push_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'minimal dependency boot constructs PushService without ApprovalService',
    () async {
      expect(perchFullFeatures, isFalse);
      FlutterSecureStorage.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Perch',
        packageName: 'dev.zhangjiajia.perch',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      await setupDependencies();
      try {
        expect(injector.get<PushService>(), isA<PushService>());
        expect(() => injector.get<ApprovalService>(), throwsA(anything));
      } finally {
        disposeDependencies();
      }
    },
  );
}
