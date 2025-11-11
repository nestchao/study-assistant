// lib/services/local_converter_service.dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class LocalConverterService {
  // --- CORE CONVERSION LOGIC ---
  
  // Computes the SHA256 hash of a file's content
  Future<String> getFileHash(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  // Converts a file to a .txt file (best effort)
  Future<void> convertToTxt(File sourceFile, File targetFile) async {
    try {
      final content = await sourceFile.readAsString();
      await targetFile.writeAsString(content);
    } catch (e) {
      // If it fails (likely a binary file), write an error message instead.
      await targetFile.writeAsString('[ERROR: Could not read file as text. It may be a binary file.]');
    }
  }

  // The main sync function
  Future<List<String>> syncDirectory({
    required Directory sourceDir,
    required Directory outputDir,
    required List<String> extensions,
    Map<String, String> existingHashes = const {},
  }) async {
    if (!await sourceDir.exists()) {
      throw Exception("Source directory does not exist.");
    }
    await outputDir.create(recursive: true);

    final logs = <String>[];
    final newHashes = <String, String>{};
    final dotExtensions = extensions.map((e) => '.${e.toLowerCase()}').toList();
    
    // Use listSync(recursive: true) to get all entities
    final allFiles = sourceDir.listSync(recursive: true);

    for (final fileEntity in allFiles) {
      if (fileEntity is File) {
        // Filter by extension
        if (extensions.isNotEmpty && !dotExtensions.contains(p.extension(fileEntity.path).toLowerCase())) {
          continue;
        }
        
        final relativePath = p.relative(fileEntity.path, from: sourceDir.path);
        logs.add('-> Checking: $relativePath');

        final currentHash = await getFileHash(fileEntity);
        final oldHash = existingHashes[relativePath];

        if (currentHash != oldHash) {
          logs.add('   - MODIFIED. Converting...');
          final targetPath = p.join(outputDir.path, p.setExtension(relativePath, '.txt'));
          final targetFile = File(targetPath);
          
          // Ensure parent directory exists
          await targetFile.parent.create(recursive: true);
          
          await convertToTxt(fileEntity, targetFile);
        }
        newHashes[relativePath] = currentHash;
      }
    }
    
    // Here you would save the 'newHashes' map to a file in the outputDir
    // for the next sync. For simplicity, we'll skip this persistence step for now.
    
    return logs;
  }
}