import 'dart:io';
import 'package:flutter/material.dart';

class ImagenZoomDialog extends StatelessWidget {
  final String imagePath;

  const ImagenZoomDialog({super.key, required this.imagePath});

  static Future<void> show(BuildContext context, String imagePath) {
    return showDialog(
      context: context,
      builder: (_) => ImagenZoomDialog(imagePath: imagePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: file.existsSync()
                ? InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5.0,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                    ),
                  )
                : const Text(
                    'No se encontró el archivo de imagen.',
                    style: TextStyle(color: Colors.white70),
                  ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
