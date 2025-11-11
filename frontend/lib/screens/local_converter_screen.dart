// lib/screens/local_converter_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:study_assistance/services/local_converter_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LocalConverterScreen extends StatefulWidget {
  const LocalConverterScreen({super.key});

  @override
  State<LocalConverterScreen> createState() => _LocalConverterScreenState();
}

class _LocalConverterScreenState extends State<LocalConverterScreen> {
  final _converterService = LocalConverterService();
  final _extensionsController = TextEditingController(text: 'dart, py, kt, md, txt');

  String? _sourcePath;
  String? _outputPath;
  bool _isSyncing = false;
  List<String> _syncLogs = [];

  Future<void> _pickSourceDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Please select a source folder',
    );
    if (selectedDirectory != null) {
      setState(() {
        _sourcePath = selectedDirectory;
      });
    }
  }

  Future<void> _pickOutputDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Please select an output folder',
    );
    if (selectedDirectory != null) {
      setState(() {
        _outputPath = selectedDirectory;
      });
    }
  }
  
  Future<void> _runSync() async {
    if (_sourcePath == null || _outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both source and output directories.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncLogs = ['Sync started...'];
    });

    try {
      final extensions = _extensionsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final logs = await _converterService.syncDirectory(
        sourceDir: Directory(_sourcePath!),
        outputDir: Directory(_outputPath!),
        extensions: extensions,
      );
      setState(() {
        _syncLogs.addAll(logs);
        _syncLogs.add('\nSync complete!');
      });
    } catch (e) {
      setState(() {
        _syncLogs.add('\nERROR: $e');
      });
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Disable this feature on Web and Mobile
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('Local Code Converter')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'This feature is only available on desktop platforms (Windows, macOS, Linux).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(title: const Text('Local Code Converter')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Directory Pickers
            _buildDirectoryPicker('Source Directory', _sourcePath, _pickSourceDirectory),
            const SizedBox(height: 16),
            _buildDirectoryPicker('Output Directory', _outputPath, _pickOutputDirectory),
            const SizedBox(height: 16),
            
            // File Type Filter
            TextField(
              controller: _extensionsController,
              decoration: const InputDecoration(
                labelText: 'File Extensions (comma-separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            
            // Sync Button
            ElevatedButton.icon(
              onPressed: _isSyncing ? null : _runSync,
              icon: _isSyncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()) : const Icon(Icons.sync),
              label: Text(_isSyncing ? 'Syncing...' : 'Synchronize Files'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const Divider(height: 32),
            
            // Log Viewer
            const Text('Logs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[200],
                child: ListView.builder(
                  itemCount: _syncLogs.length,
                  itemBuilder: (context, index) {
                    return Text(_syncLogs[index], style: const TextStyle(fontFamily: 'monospace'));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryPicker(String label, String? path, VoidCallback onPressed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_open),
                const SizedBox(width: 8),
                Expanded(child: Text(path ?? 'No directory selected')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}