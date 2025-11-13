// frontend/lib/models/past_paper.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class PastPaper {
  final String id;
  final String filename;
  final List<QAPair> qaPairs;
  final String analysisMode;
  final DateTime? timestamp;

  PastPaper({
    required this.id,
    required this.filename,
    required this.qaPairs,
    required this.analysisMode,
    this.timestamp,
  });

  factory PastPaper.fromMap(Map<String, dynamic> map) {
    var pairs = (map['qa_pairs'] as List<dynamic>?)
            ?.map((pair) => QAPair.fromMap(pair))
            .toList() ??
        [];

    DateTime? parsedDate;
    final timestampValue = map['timestamp'];
    if (timestampValue is String) {
      parsedDate = DateTime.tryParse(timestampValue);
    } else if (timestampValue is Timestamp) {
      parsedDate = timestampValue.toDate();
    }

    return PastPaper(
      id: map['id'] ?? '',
      filename: map['filename'] ?? 'Unknown Paper',
      qaPairs: pairs,
      analysisMode: map['analysis_mode'] ?? 'text_only',
      timestamp: parsedDate,
    );
  }
}

class QAPair {
  final String question;
  final String answer;

  QAPair({required this.question, required this.answer});

  factory QAPair.fromMap(Map<String, dynamic> map) {
    
    // --- THIS IS THE FIX ---
    String parsedAnswer;
    final dynamic answerValue = map['answer'];

    if (answerValue is String) {
      // If it's already a string, use it directly.
      parsedAnswer = answerValue;
    } else if (answerValue is List) {
      // If it's a list, join its elements with a newline.
      // .map((e) => e.toString()) handles cases where list items might not be strings.
      parsedAnswer = answerValue.map((e) => e.toString()).join('\n');
    } else {
      // Fallback for null or other unexpected types.
      parsedAnswer = 'No answer found';
    }
    // --- END OF FIX ---

    return QAPair(
      question: map['question'] ?? 'No question found',
      answer: parsedAnswer, // <-- Use the safely parsed answer
    );
  }
}