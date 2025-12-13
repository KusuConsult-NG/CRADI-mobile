import 'package:flutter/material.dart';

enum HazardType { flood, drought, temp, wind, erosion, fire, pest }
enum SeverityLevel { low, medium, high, critical }

class ReportingProvider extends ChangeNotifier {
  String? _hazardType;
  String? _severity;
  String? _locationDetails;
  String? _description;
  DateTime _reportDateTime = DateTime.now();
  // List<XFile> _photos = []; // Pending ImagePicker implementation

  String? get hazardType => _hazardType;
  String? get severity => _severity;
  String? get locationDetails => _locationDetails;
  String? get description => _description;
  DateTime get reportDateTime => _reportDateTime;

  void setHazardType(String type) {
    _hazardType = type;
    notifyListeners();
  }

  void setSeverity(String level) {
    _severity = level;
    notifyListeners();
  }

  void setLocationDetails(String details) {
    _locationDetails = details;
    notifyListeners();
  }

  void setDescription(String desc) {
    _description = desc;
    notifyListeners();
  }

  void setReportDateTime(DateTime dateTime) {
    _reportDateTime = dateTime;
    notifyListeners();
  }

  void reset() {
    _hazardType = null;
    _severity = null;
    _locationDetails = null;
    _description = null;
    _reportDateTime = DateTime.now();
    notifyListeners();
  }
}
