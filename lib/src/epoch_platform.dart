import 'persistence.dart';
import 'epoch_portable.dart' if (dart.library.io) 'epoch_io.dart' as platform;

BootEpochProvider createPlatformEpochProvider(PersistenceConfig config) =>
    platform.createProvider(config);
