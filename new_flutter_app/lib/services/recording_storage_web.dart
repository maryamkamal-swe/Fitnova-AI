import 'package:http/http.dart' as http;

String recordingPath(String fileName) => '';

Future<List<int>> readRecording(String path) async {
  final response = await http.get(Uri.parse(path));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Unable to read browser recording.');
  }
  return response.bodyBytes;
}

Future<void> deleteRecording(String path) async {
  // Browser recordings are blob URLs; the browser releases them after use.
}
