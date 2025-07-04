import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveFaceVector(List<double> vector) async {
    await _storage.write(key: 'face_vector', value: jsonEncode(vector));
  }

  Future<List<double>?> getFaceVector() async {
    final json = await _storage.read(key: 'face_vector');
    if (json == null) return null;
    return List<double>.from(jsonDecode(json));
  }

  Future<void> clearFaceVector() async {
    await _storage.delete(key: 'face_vector');
  }
}
