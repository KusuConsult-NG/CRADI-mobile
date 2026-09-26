import 'package:flutter/material.dart';
import 'package:climate_app/core/services/news_service.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';

class NewsProvider extends ChangeNotifier {
  NewsProvider({NewsService? newsService})
    : _newsService = newsService ?? NewsService();

  final NewsService _newsService;

  List<Map<String, dynamic>> _newsItems = [];
  bool _isLoading = false;
  LocalizedText? _error;

  List<Map<String, dynamic>> get newsItems => _newsItems;
  bool get isLoading => _isLoading;

  /// Load failure, resolved in the current language by the UI.
  LocalizedText? get error => _error;

  Future<void> fetchNews() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _newsItems = await _newsService.fetchLatestNews();
    } on Object catch (e) {
      // Live feed, curated links and the device cache all failed (or a
      // source failed in an unexpected way): show the error state rather
      // than a spinner that never ends.
      _newsItems = [];
      _error = (l) => l.knowledgeNewsLoadError;
      developer.log('NewsProvider Error: $e', name: 'NewsProvider');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearNews() {
    _newsItems = [];
    notifyListeners();
  }
}
