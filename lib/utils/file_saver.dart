import 'file_saver_io.dart' if (dart.library.html) 'file_saver_web.dart' as saver_impl;

Future<void> saveBytes(String filename, String mime, List<int> bytes) =>
    saver_impl.saveBytes(filename, mime, bytes);


