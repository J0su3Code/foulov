import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../theme/foulov_theme.dart';

/// Recadrer une photo avant de l'utiliser : photo à deux (carrée, aperçu rond), couverture (16:9),
/// fond de conversation (format de l'écran). Renvoie le chemin du fichier recadré, ou `null` si annulé.
Future<String?> cropFor(BuildContext context, String slot, String path) async {
  final cs = context.cs;
  final (x, y, title) = switch (slot) {
    'avatar' => (1.0, 1.0, 'Votre photo à deux'),
    'cover' => (16.0, 9.0, 'Votre couverture'),
    _ => (9.0, 19.5, 'Fond de la conversation'),
  };
  final f = await ImageCropper().cropImage(
    sourcePath: path,
    aspectRatio: CropAspectRatio(ratioX: x, ratioY: y),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 95,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: title,
        toolbarColor: cs.surface,
        toolbarWidgetColor: cs.onSurface,
        statusBarLight: !context.night,
        backgroundColor: Colors.black,
        activeControlsWidgetColor: cs.primary,
        cropStyle: slot == 'avatar' ? CropStyle.circle : CropStyle.rectangle,
        lockAspectRatio: true,
        hideBottomControls: false,
        showCropGrid: slot != 'avatar',
      ),
      IOSUiSettings(
        title: title,
        cropStyle: slot == 'avatar' ? CropStyle.circle : CropStyle.rectangle,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        doneButtonTitle: 'Valider',
        cancelButtonTitle: 'Annuler',
      ),
    ],
  );
  return f?.path;
}
