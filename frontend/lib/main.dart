import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/screens/dashboard_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Add this line to ensure plugins are initialized
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => ProjectProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'AI Study Assistant',
      home: DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}