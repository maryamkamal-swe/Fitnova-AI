import 'dart:io';

String recordingPath(String fileName) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName';

Future<List<int>> readRecording(String path) => File(path).readAsBytes();

Future<void> deleteRecording(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
