import 'dart:math' as math;

import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';

/// 在手機上執行的 BM25 檢索，不需網路。
///
/// - 中文以「單字＋相鄰兩字」切詞，英數字以整個詞為單位；正規化與贅字規則與 [ServiceSearch] 相同。
/// - 名稱、別名、同義詞、說明分欄加權（BM25F 的簡化版）：名稱與別名命中最有份量。
class RagRetriever {
  RagRetriever(this.documents) {
    for (final RagDocument document in documents) {
      final Map<String, double> frequencies = {};
      void addField(String text, double weight) {
        for (final String token in tokenize(text)) {
          frequencies[token] = (frequencies[token] ?? 0) + weight;
        }
      }

      addField(document.title, titleWeight);
      for (final String alias in document.aliases) {
        addField(alias, titleWeight);
      }
      for (final String keyword in document.keywords) {
        addField(keyword, keywordWeight);
      }
      addField(document.body, bodyWeight);

      _termFrequencies.add(frequencies);
      final double length = frequencies.values.fold(0, (sum, value) => sum + value);
      _lengths.add(length);
      for (final String term in frequencies.keys) {
        _documentFrequencies[term] = (_documentFrequencies[term] ?? 0) + 1;
      }
    }
    _averageLength = _lengths.isEmpty ? 0 : _lengths.reduce((a, b) => a + b) / _lengths.length;
  }

  static const double titleWeight = 3;
  static const double keywordWeight = 2;
  static const double bodyWeight = 1;

  /// BM25 參數（常用預設值）。
  static const double k1 = 1.2;
  static const double b = 0.75;

  final List<RagDocument> documents;
  final List<Map<String, double>> _termFrequencies = [];
  final List<double> _lengths = [];
  final Map<String, int> _documentFrequencies = {};
  late final double _averageLength;

  /// 依 BM25 分數由高到低回傳最多 [limit] 筆；分數為 0（完全沒有共同詞）的文件不回傳。
  List<RagHit> retrieve(String query, {int limit = 8}) {
    final Set<String> terms = tokenize(ServiceSearch.normalizeQuery(query)).toSet();
    if (terms.isEmpty || documents.isEmpty) return const [];

    final int count = documents.length;
    final List<RagHit> hits = [];
    for (int i = 0; i < count; i++) {
      final Map<String, double> frequencies = _termFrequencies[i];
      double score = 0;
      for (final String term in terms) {
        final double tf = frequencies[term] ?? 0;
        if (tf == 0) continue;
        final int df = _documentFrequencies[term]!;
        final double idf = math.log(1 + (count - df + 0.5) / (df + 0.5));
        score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * _lengths[i] / _averageLength));
      }
      if (score > 0) hits.add(RagHit(documents[i], score));
    }
    hits.sort((a, c) => c.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  static final RegExp _runs = RegExp(r'\p{Script=Han}+|[a-z0-9]+', unicode: true);

  /// 切詞：中文連續字串取單字與相鄰兩字，英數字取整個詞。輸入會先正規化。
  static List<String> tokenize(String text) {
    final String normalized = ServiceSearch.normalize(text);
    final List<String> tokens = [];
    for (final RegExpMatch match in _runs.allMatches(normalized)) {
      final String run = match.group(0)!;
      if (RegExp(r'^[a-z0-9]+$').hasMatch(run)) {
        tokens.add(run);
        continue;
      }
      final List<String> chars = run.runes.map(String.fromCharCode).toList();
      tokens.addAll(chars);
      for (int i = 0; i < chars.length - 1; i++) {
        tokens.add('${chars[i]}${chars[i + 1]}');
      }
    }
    return tokens;
  }
}
