import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

abstract interface class PhotoLibrary {
  Future<String?> pickPhoto();
  Future<Uint8List> readPhoto(String path);
  Future<void> saveToGallery(String path);
}

abstract interface class RecoverablePhotoLibrary {
  Future<String?> recoverLostPhoto();
}

class DevicePhotoLibrary implements PhotoLibrary, RecoverablePhotoLibrary {
  DevicePhotoLibrary({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  @override
  Future<String?> recoverLostPhoto() async {
    if (!Platform.isAndroid) return null;
    final result = await _picker.retrieveLostData();
    if (result.exception != null) throw StateError('上次选择照片未完成，请重新选择。');
    return result.files?.firstOrNull?.path;
  }

  @override
  Future<String?> pickPhoto() async => (await _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 4096,
    maxHeight: 4096,
    imageQuality: 90,
  ))?.path;

  @override
  Future<Uint8List> readPhoto(String path) => File(path).readAsBytes();

  @override
  Future<void> saveToGallery(String path) async {
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    if (!await Gal.hasAccess()) throw StateError('请在系统设置中允许添加照片后重试');
    await Gal.putImage(path);
  }
}
