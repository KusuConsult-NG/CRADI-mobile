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
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _newsItems = await _newsService.fetchLatestNews();
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      // Live feed, curated links and the device cache all failed.
      _newsItems = [];
      _error = (l) => l.knowledgeNewsLoadError;
      _isLoading = false;
      notifyListeners();
      developer.log('NewsProvider Error: $e', name: 'NewsProvider');
    }
  }

  void clearNews() {
    _newsItems = [];
    notifyListeners();
  }
}
