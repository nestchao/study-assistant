
import 'package:flutter/material.dart';
import 'package:study_assistance/api/api_service.dart';

class HomeScreen extends StatelessWidget {
  final ApiService api = ApiService();

  HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Study Assistant")),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await api.hello();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'])),
            );
          },
          child: const Text("Call Backend"),
        ),
      ),
    );
  }
}