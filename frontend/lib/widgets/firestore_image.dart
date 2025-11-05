// lib/widgets/firestore_image.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/services/firestore_image_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';

class FirestoreImage extends StatelessWidget {
  final String mediaId;

  const FirestoreImage({super.key, required this.mediaId});

  @override
  Widget build(BuildContext context) {
    if (mediaId.isEmpty) {
      print("FirestoreImage Error: mediaId is empty.");
      return const Text("[Image Error: Missing ID]");
    }

    final provider = Provider.of<ProjectProvider>(context, listen: false);
    final cacheManager = FirestoreImageCacheManager(
      apiService: provider.apiService,
      projectId: provider.currentProject!.id,
    );

    final imageUrl = 'firestore_media:$mediaId';
    print("FirestoreImage: Building for mediaId: $mediaId (URL: $imageUrl)");

    return FutureBuilder<File>(
      future: cacheManager.getSingleFile(imageUrl),
      builder: (context, snapshot) {
        // --- LOGGING THE FUTUREBUILDER STATE ---
        
        print("FutureBuilder state for $mediaId: ${snapshot.connectionState}");

        if (snapshot.connectionState == ConnectionState.waiting) {
          print(" -> State: Waiting...");
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          // THIS IS THE MOST IMPORTANT LOG. It will tell us WHY it failed.
          print(" -> State: ERROR! ${snapshot.error}");
          print(" -> Stack Trace: ${snapshot.stackTrace}");
          return const Icon(Icons.error, color: Colors.red);
        }

        if (snapshot.hasData) {
          final file = snapshot.data!;

          if (kIsWeb) {
            print("   -> Platform: Web. Reading bytes from file object...");
            return FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (context, bytesSnapshot) {
                if (bytesSnapshot.hasData) {
                  return Image.memory(bytesSnapshot.data!);
                }
                return const Center(child: CircularProgressIndicator());
              },
            );
          } else {
            print("   -> Platform: Mobile/Desktop. Rendering Image.file().");
            return Image.file(file);
          }
        }
        
        // This case means the future completed successfully, but the data was null.
        print(" -> State: Done, but snapshot.data is null.");
        return const Icon(Icons.broken_image, color: Colors.grey);
      },
    );
  }
}