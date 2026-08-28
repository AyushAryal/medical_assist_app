import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/assist/assist_model_catalog.dart';

void main() {
  group('device-class recommendation', () {
    test('every model declares a real memory need and device class', () {
      for (final model in AssistModelCatalog.models) {
        expect(model.runtimeMemoryLabel, isNotEmpty);
        expect(DeviceClass.values, contains(model.minDeviceClass));
      }
    });

    test('an entry device is steered to a model it can actually run', () {
      final pick = AssistModelCatalog.recommendedFor(DeviceClass.entry);
      expect(DeviceClass.entry.meets(pick.minDeviceClass), isTrue,
          reason: 'the recommended model must fit the device it is recommended '
              'for');
    });

    test('a roomier device is steered to a more capable model', () {
      final entry = AssistModelCatalog.recommendedFor(DeviceClass.entry);
      final standard = AssistModelCatalog.recommendedFor(DeviceClass.standard);
      // Models are in quality order, so the better device gets an equal-or-
      // earlier (more capable) pick.
      final entryRank = AssistModelCatalog.models.indexOf(entry);
      final standardRank = AssistModelCatalog.models.indexOf(standard);
      expect(standardRank, lessThanOrEqualTo(entryRank));
    });

    test('there is always a recommendation for every class', () {
      for (final deviceClass in DeviceClass.values) {
        expect(AssistModelCatalog.recommendedFor(deviceClass), isNotNull);
      }
    });

    test('device classes are ordered by how much they can run', () {
      expect(DeviceClass.ample.meets(DeviceClass.standard), isTrue);
      expect(DeviceClass.entry.meets(DeviceClass.standard), isFalse);
      expect(DeviceClass.entry.meets(DeviceClass.entry), isTrue);
    });
  });

  group('the medical model', () {
    final medgemma = AssistModelCatalog.byId('medgemma-4b-it-q4');

    test('is in the catalogue as an ample-class option', () {
      expect(medgemma, isNotNull);
      expect(medgemma!.minDeviceClass, DeviceClass.ample);
    });

    test('is never the automatic recommendation for any device', () {
      // It is an option a clinic opts into, not the default: the rewrite tasks
      // were verified against Qwen and MedGemma costs far more memory.
      for (final deviceClass in DeviceClass.values) {
        expect(
          AssistModelCatalog.recommendedFor(deviceClass).id,
          isNot('medgemma-4b-it-q4'),
        );
      }
    });
  });
}
