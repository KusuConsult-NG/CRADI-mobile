import 'package:flutter/material.dart';
import 'package:climate_app/core/services/news_service.dart';
import 'dart:developer' as developer;

class NewsProvider extends ChangeNotifier {
  final NewsService _newsService = NewsService();

  List<Map<String, dynamic>> _newsItems = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get newsItems => _newsItems;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchNews() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _newsItems = await _newsService.fetchLatestNews();
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _error = 'Failed to load news: $e';
      _isLoading = false;
      notifyListeners();
      developer.log('NewsProvider Error: $e');
    }
  }

  void clearNews() {
    _newsItems = [];
    notifyListeners();
  }
}
