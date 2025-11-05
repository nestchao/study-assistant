class PastPaper {
  final String id;
  final String filename;
  final List<QAPair> qaPairs;

  PastPaper({
    required this.id,
    required this.filename,
    required this.qaPairs,
  });

  factory PastPaper.fromMap(Map<String, dynamic> map) {
    var pairs = (map['qa_pairs'] as List<dynamic>?)
            ?.map((pair) => QAPair.fromMap(pair))
            .toList() ??
        [];

    return PastPaper(
      id: map['id'] ?? '',
      filename: map['filename'] ?? 'Unknown Paper',
      qaPairs: pairs,
    );
  }
}

class QAPair {
  final String question;
  final String answer;

  QAPair({required this.question, required this.answer});

  factory QAPair.fromMap(Map<String, dynamic> map) {
    return QAPair(
      question: map['question'] ?? 'No question found',
      answer: map['answer'] ?? 'No answer found',
    );
  }
}