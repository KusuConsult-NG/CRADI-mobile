import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ha.dart';
import 'app_localizations_ig.dart';
import 'app_localizations_pcm.dart';
import 'app_localizations_yo.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ha'),
    Locale('ig'),
    Locale('pcm'),
    Locale('yo'),
  ];

  /// The application title. Used in: main.
  ///
  /// In en, this message translates to:
  /// **'EWER Early Warning'**
  String get appTitle;

  /// Label for monitoring zone header. Used in: home screen.
  ///
  /// In en, this message translates to:
  /// **'Monitoring Zone'**
  String get monitoringZone;

  /// Tab label for reports pending verification. Used in: home screen.
  ///
  /// In en, this message translates to:
  /// **'To Verify'**
  String get toVerify;

  /// Tab label for alerts. Used in: alerts list screen, home screen.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// Tab label for user's own reports. Used in: home screen, my reports screen, user profile screen.
  ///
  /// In en, this message translates to:
  /// **'My Reports'**
  String get myReports;

  /// Section header for hazard categories. Used in: home screen, knowledge base screen.
  ///
  /// In en, this message translates to:
  /// **'Browse Categories'**
  String get browseCategories;

  /// Empty state for verification tab. Used in: home screen.
  ///
  /// In en, this message translates to:
  /// **'No reports to verify'**
  String get noReportsToVerify;

  /// Empty state for alerts tab. Used in: admin alerts screen, alerts list screen.
  ///
  /// In en, this message translates to:
  /// **'No active alerts'**
  String get noActiveAlerts;

  /// Link to view all items in a section. Used in: home screen, knowledge base screen.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// Upper-case caption on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get notifications;

  /// UI text on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotifications;

  /// Upper-case caption on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'GENERAL'**
  String get general;

  /// UI text on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// UI text on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Help & FAQ'**
  String get helpFaq;

  /// UI text on the about app screen, settings screen.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// Button label (keep short, max ~20 chars) on the access code verification screen, main shell screen, pending approval screen.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// Button label (keep short, max ~20 chars) on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Button label (keep short, max ~20 chars) on the admin knowledge screen, admin reports screen, admin users screen.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button label (keep short, max ~20 chars) on the emergency contacts screen, user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Button label (keep short, max ~20 chars) on the admin knowledge screen, emergency contacts screen, notifications screen.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Button label (keep short, max ~20 chars) on the emergency contacts screen.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Button label (keep short, max ~20 chars) on the hazard selection screen, permission service.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// Button label (keep short, max ~20 chars) on the admin reports screen, admin screen, admin users screen.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Button label (keep short, max ~20 chars) on the about app screen, sos sheet.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Settings screen title. Used in: settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// UI text on the otp verification screen.
  ///
  /// In en, this message translates to:
  /// **'Verify Phone Number'**
  String get verifyPhoneNumber;

  /// Button label (keep short, max ~20 chars) on the access code verification screen, otp verification screen.
  ///
  /// In en, this message translates to:
  /// **'Resend Code'**
  String get resendCode;

  /// Button label (keep short, max ~20 chars) on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// UI text on the hazard selection screen.
  ///
  /// In en, this message translates to:
  /// **'Select Hazard'**
  String get selectHazard;

  /// UI text on the hazard selection screen.
  ///
  /// In en, this message translates to:
  /// **'What type of incident are you reporting?'**
  String get whatIncident;

  /// UI text on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Erosion'**
  String get erosion;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'How severe is the situation?'**
  String get howSevereSituation;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'Set Severity'**
  String get setSeverity;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'Next: Location'**
  String get nextLocation;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'Low - Minor impact'**
  String get lowMinorImpact;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'Medium - Noticeable impact'**
  String get mediumNoticeableImpact;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'High - Significant damage'**
  String get highSignificantDamage;

  /// UI text on the severity selection screen.
  ///
  /// In en, this message translates to:
  /// **'Critical - Life threatening'**
  String get criticalLifeThreatening;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Use My Location Info'**
  String get useMyLocationInfo;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile Details'**
  String get editProfileDetails;

  /// UI text on the registration screen, user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// UI text on the forgot password screen, login screen, registration screen.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// UI text on the settings screen, user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Biometric Login'**
  String get biometricLogin;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Language Preference'**
  String get languagePreference;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Offline Data Sync'**
  String get offlineDataSync;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// UI text on the help support screen, user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// UI text on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Biometrics not available on this device'**
  String get biometricsNotAvailable;

  /// UI text on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Biometric login enabled'**
  String get biometricsEnabled;

  /// UI text on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Biometric login disabled'**
  String get biometricsDisabled;

  /// Message on the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully!'**
  String get profileUpdated;

  /// Message on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// UI text on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// UI text on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode Ready: '**
  String get offlineModeReady;

  /// UI text on the validators.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get validation_required;

  /// UI text on the auth provider, profile provider, validators.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get validation_invalidEmail;

  /// Validation message for minimum length. Used in: validators.
  ///
  /// In en, this message translates to:
  /// **'Must be at least {length} characters'**
  String validation_minLength(int length);

  /// Validation message for maximum length. Used in: validators.
  ///
  /// In en, this message translates to:
  /// **'Must be at most {length} characters'**
  String validation_maxLength(int length);

  /// Upper-case caption on the alerts list screen, home screen.
  ///
  /// In en, this message translates to:
  /// **'SYNC STATUS'**
  String get syncStatus;

  /// UI text on the alerts list screen, home screen.
  ///
  /// In en, this message translates to:
  /// **'Online • Just now'**
  String get onlineJustNow;

  /// UI text on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// UI text on the home screen, reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// UI text on the home screen, reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// UI text on the alerts list screen, home screen.
  ///
  /// In en, this message translates to:
  /// **'Floods'**
  String get floodsCategory;

  /// UI text on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Droughts'**
  String get droughtsCategory;

  /// UI text on the alerts list screen, home screen.
  ///
  /// In en, this message translates to:
  /// **'Pests'**
  String get pestsCategory;

  /// UI text on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get conflictsCategory;

  /// UI text on the home screen.
  ///
  /// In en, this message translates to:
  /// **'No recent alerts'**
  String get noRecentAlerts;

  /// UI text on the home screen, settings screen.
  ///
  /// In en, this message translates to:
  /// **'Select Zone'**
  String get selectZone;

  /// UI text on the home screen, settings screen.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeZone;

  /// UI text on the home screen, settings screen.
  ///
  /// In en, this message translates to:
  /// **'Not Set'**
  String get notSetZone;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Reports Status'**
  String get reportsStatus;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get generateReport;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'No {status} Reports'**
  String noReportsStatus(String status);

  /// Button label (keep short, max ~20 chars) on the admin screen, location picker screen, nearby reports screen.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Reported by {name}'**
  String reportedBy(String name);

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Report verified successfully'**
  String get reportVerified;

  /// Button label (keep short, max ~20 chars) on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyReport;

  /// UI text on the peer verification service, report view screen, reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Report rejected'**
  String get reportRejectedItem;

  /// Button label (keep short, max ~20 chars) on the admin reports screen, report staff actions, reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// UI text on the peer verification service, reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Report approved'**
  String get reportResolvedItem;

  /// Button label (keep short, max ~20 chars) on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get markResolved;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Report moved back to Pending'**
  String get reportMovedPending;

  /// Button label (keep short, max ~20 chars) on the report staff actions, reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Report reopened and moved to Pending'**
  String get reportReopenedPending;

  /// Label/heading on the admin reports screen, location picker screen, report details screen.
  ///
  /// In en, this message translates to:
  /// **'Report Details'**
  String get reportDetailsTitle;

  /// Label/heading on the admin reports screen, alert detail screen, report details screen.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// Message on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Describe the hazard here (e.g. flood levels rising, bridge collapsed)...'**
  String get describeHazardHint;

  /// UI text on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition not available'**
  String get speechNotAvailable;

  /// UI text on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Listening... Speak now'**
  String get listeningSpeakNow;

  /// Message on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Be specific about location and severity.'**
  String get beSpecificLocationSeverity;

  /// UI text on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'When Did This Occur?'**
  String get whenDidThisOccur;

  /// Label/heading on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optionalLabel;

  /// Label/heading on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayLabel;

  /// Message on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Tap to select date & time. Defaults to now if not changed.'**
  String get tapToSelectDateTime;

  /// Label/heading on the report details screen, report review screen.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get evidenceLabel;

  /// UI text on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Max 3 photos'**
  String get max3Photos;

  /// Message on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Your photos will be compressed automatically. Reports are saved locally until you have internet.'**
  String get offlineModeMessage;

  /// Button label (keep short, max ~20 chars) on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Review Report'**
  String get reviewReportBtn;

  /// Button label (keep short, max ~20 chars) on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraBtn;

  /// Button label (keep short, max ~20 chars) on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryBtn;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Submission failed'**
  String get submissionFailed;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Saved for Later'**
  String get savedForLater;

  /// Label/heading on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Report Submitted!'**
  String get reportSubmittedTitle;

  /// Message on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'You are offline. The report will be sent automatically when you are back online.'**
  String get offlineReportMessage;

  /// Message on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Your report has been successfully sent to central command.'**
  String get onlineReportMessage;

  /// Label/heading on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get statusLabel;

  /// Label/heading on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'REPORT ID'**
  String get reportIdLabel;

  /// Upper-case caption on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'QUEUED'**
  String get queuedStatus;

  /// Upper-case caption on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'SENT'**
  String get sentStatus;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Return to Dashboard'**
  String get returnToDashboard;

  /// Label/heading on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Review Report'**
  String get reviewReportTitle;

  /// Message on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Please review the details below to ensure accuracy before submitting to the central command.'**
  String get reviewReportDesc;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Hazard Details'**
  String get hazardDetails;

  /// UI text on the admin reports screen, report review screen, verification request screen.
  ///
  /// In en, this message translates to:
  /// **'Hazard Type'**
  String get hazardType;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Not Selected'**
  String get notSelected;

  /// Label/heading on the location picker screen, report review screen.
  ///
  /// In en, this message translates to:
  /// **'Severity Level'**
  String get severityLevelLabel;

  /// Message on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Assess the intensity of the hazard.'**
  String get severityDesc;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get severityLowShort;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Med'**
  String get severityMedShort;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get severityHighShort;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Crit'**
  String get severityCritShort;

  /// Label/heading on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get dateTimeLabel;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'When it occurred'**
  String get whenItOccurred;

  /// Label/heading on the alert detail screen, registration screen, report review screen.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Not Provided'**
  String get notProvided;

  /// UI text on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Monitor Notes'**
  String get monitorNotes;

  /// UI text on the admin reports screen, report review screen.
  ///
  /// In en, this message translates to:
  /// **'No description provided'**
  String get noDescriptionProvided;

  /// Button label (keep short, max ~20 chars) on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addPhotoBtn;

  /// Button label (keep short, max ~20 chars) on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReportBtn;

  /// Button label (keep short, max ~20 chars) on the report review screen.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editBtn;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied'**
  String get locationPermissionDenied;

  /// Message on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Unable to get location. Please enable GPS.'**
  String get enableGpsMessage;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Location error:'**
  String get locationError;

  /// Upper-case caption on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'ACQUIRING...'**
  String get acquiringGps;

  /// Upper-case caption on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'NO SIGNAL'**
  String get noSignalGps;

  /// Upper-case caption on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'GPS STRONG'**
  String get gpsStrong;

  /// Upper-case caption on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'GPS GOOD'**
  String get gpsGood;

  /// Upper-case caption on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'GPS WEAK'**
  String get gpsWeak;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Could not find location on map'**
  String get couldNotFindLocation;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Map update error:'**
  String get mapUpdateError;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Incident Location'**
  String get incidentLocation;

  /// Message on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Getting location...'**
  String get gettingLocation;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'No GPS data'**
  String get noGpsData;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable'**
  String get locationUnavailable;

  /// Label/heading on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'COORDINATES'**
  String get coordinatesLabel;

  /// Button label (keep short, max ~20 chars) on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetailsBtn;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Ward & LGA Selection'**
  String get wardAndLgaSelection;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Select your ward from the dropdown'**
  String get selectWardDropdown;

  /// Message on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Select the LGA and Ward where the incident occurred'**
  String get selectLgaWardIncident;

  /// Label/heading on the location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get stateLabel;

  /// UI text on the location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'Select State'**
  String get selectState;

  /// UI text on the location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'Select State first'**
  String get selectStateFirst;

  /// Label/heading on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'LGA (Local Government Area)'**
  String get lgaLabel;

  /// UI text on the location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'Select LGA'**
  String get selectLga;

  /// UI text on the location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'Select LGA first'**
  String get selectLgaFirst;

  /// Label/heading on the admin reports screen, location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'Ward'**
  String get wardLabel;

  /// UI text on the location picker screen, location selector widget.
  ///
  /// In en, this message translates to:
  /// **'Select Ward'**
  String get selectWard;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Enter Location Manually'**
  String get enterLocationManually;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Address or Coordinates'**
  String get addressOrCoordinates;

  /// Button label (keep short, max ~20 chars) on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelBtn;

  /// Button label (keep short, max ~20 chars) on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get setLocationBtn;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Manual location set'**
  String get manualLocationSet;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Location incorrect? Enter manually'**
  String get locationIncorrectManual;

  /// Message on the location picker screen, reporting provider, verification request screen.
  ///
  /// In en, this message translates to:
  /// **'Please select State, LGA, and Ward before continuing'**
  String get pleaseSelectStateLgaWard;

  /// UI text on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Continue'**
  String get confirmAndContinue;

  /// Label/heading on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Location Details'**
  String get locationDetailsTitle;

  /// Label/heading on the location picker screen, report view screen.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitudeLabel;

  /// Label/heading on the location picker screen, report view screen.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitudeLabel;

  /// Label/heading on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get accuracyLabel;

  /// Label/heading on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get altitudeLabel;

  /// Button label (keep short, max ~20 chars) on the location picker screen.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeBtn;

  /// UI text on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Select status to export:'**
  String get selectStatusExport;

  /// Filter option on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'All Reports'**
  String get allReports;

  /// Filter option on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Pending Only'**
  String get pendingOnly;

  /// Filter option on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Verified Only'**
  String get verifiedOnly;

  /// Filter option on the reports status screen.
  ///
  /// In en, this message translates to:
  /// **'Approved Only'**
  String get approvedOnly;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Admin Portal'**
  String get adminPortal;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'System Overview'**
  String get systemOverview;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// UI text on the admin screen, admin users screen.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// UI text on the admin reports screen, admin screen.
  ///
  /// In en, this message translates to:
  /// **'Reports Overview'**
  String get reportsOverview;

  /// UI text on the admin alerts screen, admin screen.
  ///
  /// In en, this message translates to:
  /// **'Alerts & Broadcast'**
  String get alertsBroadcast;

  /// UI text on the admin knowledge screen, admin screen.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Management'**
  String get knowledgeManagement;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'System Health'**
  String get systemHealth;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Pending Approvals'**
  String get pendingApprovals;

  /// UI text on the admin screen, offline home screen.
  ///
  /// In en, this message translates to:
  /// **'Pending Reports'**
  String get pendingReports;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Verified Reports'**
  String get verifiedReports;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get totalUsers;

  /// UI text on the admin alerts screen, admin screen.
  ///
  /// In en, this message translates to:
  /// **'Active Alerts'**
  String get activeAlertsAdmin;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Total Reports'**
  String get totalReports;

  /// Message on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Approve accounts, assign roles, deactivate users'**
  String get userManagementDesc;

  /// Message on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'View, validate, or reject reports across all LGAs'**
  String get reportsOverviewDesc;

  /// Message on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Send emergency alerts to users or specific areas'**
  String get alertsBroadcastDesc;

  /// Message on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Add, edit, or remove emergency knowledge guides'**
  String get knowledgeManagementDesc;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// UI text on the admin screen.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// Error shown when a request fails because of the network (snackbar/inline).
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection.'**
  String get errorNetwork;

  /// Error shown when the server refuses an action for lack of permission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this action.'**
  String get errorNoPermission;

  /// Generic error for internal server/SDK failures.
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please try again or contact support.'**
  String get errorContactSupport;

  /// Generic fallback error message.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get errorUnexpected;

  /// Login error when the email is not yet confirmed; {email} is the address the new code was sent to.
  ///
  /// In en, this message translates to:
  /// **'Please verify your email first. We sent a new code to {email}.'**
  String authEmailNotConfirmed(String email);

  /// Title of the bottom sheet for choosing the app language.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get languageSelectTitle;

  /// App bar title on the main screens (CRADI is the organisation name; keep it).
  ///
  /// In en, this message translates to:
  /// **'CRADI Early Warning'**
  String get shellAppBarTitle;

  /// Tooltip/accessibility label for the notifications bell in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get shellNotificationsTooltip;

  /// Name shown in the side drawer header when the user has no name set.
  ///
  /// In en, this message translates to:
  /// **'Early Warning Monitor'**
  String get shellDrawerDefaultName;

  /// Side drawer menu item that opens the user's profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get shellDrawerProfile;

  /// Bottom navigation tab label (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation tab label (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get navAlerts;

  /// Navigation label for the hazard guides section (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Guides'**
  String get navGuides;

  /// Bottom navigation tab label for creating a hazard report (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get navReport;

  /// Bottom navigation tab / menu label for settings (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Bottom navigation tab label for the admin portal (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get navAdmin;

  /// Greeting at the top of the home screen; {name} is the user's first name.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String homeGreeting(String name);

  /// Hazard type name (chips, lists, report details). Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Flooding'**
  String get hazardFlooding;

  /// Hazard type name (heat waves / extreme heat or cold). Keep short (max ~22 chars).
  ///
  /// In en, this message translates to:
  /// **'Extreme Temperatures'**
  String get hazardExtremeTemperatures;

  /// Hazard type name. Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Drought'**
  String get hazardDrought;

  /// Hazard type name. Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Windstorms'**
  String get hazardWindstorms;

  /// Hazard type name (bush fires). Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Wildfires'**
  String get hazardWildfires;

  /// Hazard type name (gully erosion, landslides). Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Erosion'**
  String get hazardErosion;

  /// Hazard type name. Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Pest Outbreak'**
  String get hazardPestOutbreak;

  /// Hazard type name. Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Crop Disease'**
  String get hazardCropDisease;

  /// Hazard type name (e.g. farmer-herder clashes). Keep short (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get hazardConflict;

  /// Shown when a report's hazard type is missing.
  ///
  /// In en, this message translates to:
  /// **'Unknown Hazard'**
  String get hazardUnknown;

  /// Headline on report cards for a flooding report.
  ///
  /// In en, this message translates to:
  /// **'Flood Alert'**
  String get hazardTitleFlooding;

  /// Headline on report cards for an extreme-temperature report.
  ///
  /// In en, this message translates to:
  /// **'Temperature Extreme'**
  String get hazardTitleExtremeTemperatures;

  /// Headline on report cards for a drought report.
  ///
  /// In en, this message translates to:
  /// **'Drought Warning'**
  String get hazardTitleDrought;

  /// Headline on report cards for a windstorm report.
  ///
  /// In en, this message translates to:
  /// **'High Wind Alert'**
  String get hazardTitleWindstorms;

  /// Headline on report cards for a wildfire report.
  ///
  /// In en, this message translates to:
  /// **'Wildfire Report'**
  String get hazardTitleWildfires;

  /// Headline on report cards for an erosion report.
  ///
  /// In en, this message translates to:
  /// **'Erosion Report'**
  String get hazardTitleErosion;

  /// Headline on report cards for a pest outbreak report.
  ///
  /// In en, this message translates to:
  /// **'Pest Outbreak'**
  String get hazardTitlePestOutbreak;

  /// Headline on report cards for a crop disease report.
  ///
  /// In en, this message translates to:
  /// **'Crop Disease'**
  String get hazardTitleCropDisease;

  /// Headline on report cards for a conflict report.
  ///
  /// In en, this message translates to:
  /// **'Conflict Report'**
  String get hazardTitleConflict;

  /// Relative time for something that happened less than a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// Compact relative time in minutes (e.g. '5m ago') on report cards. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count}m ago}}'**
  String timeMinutesAgo(int count);

  /// Compact relative time in hours (e.g. '3h ago') on report cards. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count}h ago}}'**
  String timeHoursAgo(int count);

  /// Compact relative time in days (e.g. '2d ago') on report cards. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count}d ago}}'**
  String timeDaysAgo(int count);

  /// Compact relative time in weeks (e.g. '1w ago') on report cards. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count}w ago}}'**
  String timeWeeksAgo(int count);

  /// Placeholder shown when a value (time, name, etc.) is missing.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// Placeholder shown when a report has no location text.
  ///
  /// In en, this message translates to:
  /// **'Unknown Location'**
  String get commonUnknownLocation;

  /// Shown instead of a reporter's name when it is not available.
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get commonAnonymous;

  /// Shown as the reporter name when the reporter is not known (report came from the community).
  ///
  /// In en, this message translates to:
  /// **'Community Report'**
  String get commonCommunityReport;

  /// Status badge for a report awaiting peer verification (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get reportStatusPending;

  /// Status badge for a report verified by peers (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get reportStatusVerified;

  /// Status badge for a report approved by staff (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get reportStatusApproved;

  /// Status badge for a rejected report (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get reportStatusRejected;

  /// Error when a user tries to verify/dispute a report they submitted.
  ///
  /// In en, this message translates to:
  /// **'You cannot verify your own report.'**
  String get verifyErrorOwnReport;

  /// Error when the user is too far from the report to verify it; {distanceKm} is a number with one decimal, e.g. 3.4.
  ///
  /// In en, this message translates to:
  /// **'You must be within 2 km of the report location to verify. Current distance: {distanceKm} km.'**
  String verifyErrorTooFar(String distanceKm);

  /// Snackbar after confirming (voting for) a report.
  ///
  /// In en, this message translates to:
  /// **'Report confirmed successfully'**
  String get verifyConfirmedMessage;

  /// Snackbar after disputing (voting against) a report.
  ///
  /// In en, this message translates to:
  /// **'Report disputed'**
  String get verifyDisputedMessage;

  /// Error when the user already voted on the report.
  ///
  /// In en, this message translates to:
  /// **'You have already voted on this report.'**
  String get verifyErrorAlreadyVoted;

  /// Error when the account role cannot verify reports.
  ///
  /// In en, this message translates to:
  /// **'Your account is not permitted to verify reports. Verification requires an approved monitor role.'**
  String get verifyErrorNotPermitted;

  /// Error when voting on a report that was already verified/rejected.
  ///
  /// In en, this message translates to:
  /// **'This report is no longer pending.'**
  String get verifyErrorNoLongerPending;

  /// Error when verifying while signed out.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to verify reports.'**
  String get verifyErrorSignedOut;

  /// Generic error when a verification vote fails.
  ///
  /// In en, this message translates to:
  /// **'Verification failed'**
  String get verifyErrorFailed;

  /// Error when disputing a report without giving a reason.
  ///
  /// In en, this message translates to:
  /// **'Please explain why you dispute this report.'**
  String get verifyErrorDisputeReasonRequired;

  /// Message when a verification request was saved offline for later upload.
  ///
  /// In en, this message translates to:
  /// **'Offline: request saved and will sync when you are back online.'**
  String get verifyRequestQueuedOffline;

  /// Error when a staff action on a report fails because of permissions or deletion.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change this report, or it no longer exists.'**
  String get reportActionErrorNoPermissionOrGone;

  /// Error when reopening a report that is already pending.
  ///
  /// In en, this message translates to:
  /// **'This report is already pending.'**
  String get reportActionErrorAlreadyPending;

  /// Error when acting on a deleted report.
  ///
  /// In en, this message translates to:
  /// **'This report no longer exists.'**
  String get reportActionErrorGone;

  /// Error when the server refuses a change to a report.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change this report.'**
  String get reportActionErrorNoPermission;

  /// Error shown in report lists when the server cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and retry.'**
  String get reportsLoadErrorOffline;

  /// Message shown when data was saved to the offline queue.
  ///
  /// In en, this message translates to:
  /// **'Saved offline. It will sync when you are back online.'**
  String get offlineSavedWillSync;

  /// Error when a profile edit cannot be saved because the device is offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes not saved.'**
  String get profileErrorOfflineNotSaved;

  /// Error when editing the profile while signed out.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to update your profile.'**
  String get profileErrorSignedOut;

  /// Error when a profile edit fails on the server.
  ///
  /// In en, this message translates to:
  /// **'Could not save your changes. Please check your connection and try again.'**
  String get profileErrorSaveFailed;

  /// Validation error when the name field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name.'**
  String get profileErrorNameRequired;

  /// Error when changing the email while signed out.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to change your email.'**
  String get profileErrorEmailSignedOut;

  /// Message after requesting an email change; {email} is the new address.
  ///
  /// In en, this message translates to:
  /// **'A confirmation link has been sent to {email}. Your email will change after you confirm it.'**
  String profileEmailConfirmationSent(String email);

  /// Error when the server requires a fresh sign-in to change email.
  ///
  /// In en, this message translates to:
  /// **'For security, please log out and sign in again before changing your email.'**
  String get profileErrorEmailReauth;

  /// Error when the new email belongs to another account.
  ///
  /// In en, this message translates to:
  /// **'That email is already in use by another account.'**
  String get profileErrorEmailInUse;

  /// Generic error when changing email fails.
  ///
  /// In en, this message translates to:
  /// **'Could not update email. Please try again.'**
  String get profileErrorEmailUpdateFailed;

  /// Error when the location form is incomplete. LGA = Local Government Area.
  ///
  /// In en, this message translates to:
  /// **'Please select your state, LGA and ward to update your location.'**
  String get profileErrorLocationIncomplete;

  /// Error when changing location while signed out.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to change your location.'**
  String get profileErrorLocationSignedOut;

  /// Error when a staff account tries to change its own location.
  ///
  /// In en, this message translates to:
  /// **'Your location is managed by an administrator. Please ask an admin to change the location of a staff account.'**
  String get profileErrorLocationManaged;

  /// Error when saving the location fails.
  ///
  /// In en, this message translates to:
  /// **'Could not update your location. Please check your connection and try again.'**
  String get profileErrorLocationFailed;

  /// Name shown when the user's name is not known.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get profileDefaultName;

  /// Home screen quick link that opens the peer verification queue.
  ///
  /// In en, this message translates to:
  /// **'Verify Reports'**
  String get homeVerifyReportsLink;

  /// Home feed filter tab showing reports near the user (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get homeTabNearby;

  /// Monitoring zone line in the home header; {zone} is the zone name or 'Select Zone', {status} is 'Active' or 'Not Set'.
  ///
  /// In en, this message translates to:
  /// **'{zone} • {status}'**
  String homeZoneStatus(String zone, String status);

  /// Empty state of the home 'My Reports' feed.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t submitted any reports yet'**
  String get homeEmptyMyReports;

  /// Link above the nearby feed that opens the full nearby reports screen.
  ///
  /// In en, this message translates to:
  /// **'Open Nearby Reports'**
  String get homeOpenNearbyReports;

  /// Empty state of the home 'Nearby' feed.
  ///
  /// In en, this message translates to:
  /// **'No nearby reports'**
  String get homeEmptyNearby;

  /// Subtitle on report cards; {location} is the place, {time} is a relative time like '5m ago'.
  ///
  /// In en, this message translates to:
  /// **'{location} • {time}'**
  String reportLocationAndTime(String location, String time);

  /// Title of the bottom sheet for choosing the monitoring zone.
  ///
  /// In en, this message translates to:
  /// **'Select Monitoring Zone'**
  String get homeZoneSheetTitle;

  /// Option in the monitoring zone sheet that removes the zone filter.
  ///
  /// In en, this message translates to:
  /// **'All Zones (No Filter)'**
  String get homeZoneAll;

  /// Snackbar after removing the monitoring zone filter.
  ///
  /// In en, this message translates to:
  /// **'Showing all zones'**
  String get homeZoneAllSelected;

  /// Snackbar when the 'all zones' choice was applied locally but not saved to the account; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Showing all zones on this device. {error}'**
  String homeZoneAllLocalOnly(String error);

  /// Snackbar after choosing a monitoring zone; {zone} is the zone name.
  ///
  /// In en, this message translates to:
  /// **'Monitoring zone changed to {zone}'**
  String homeZoneChanged(String zone);

  /// Snackbar when the zone was applied locally but not saved to the account; {zone} is the zone, {error} the reason.
  ///
  /// In en, this message translates to:
  /// **'Showing {zone} on this device. {error}'**
  String homeZoneLocalOnly(String zone, String error);

  /// Name of a state-level monitoring zone; {state} is a Nigerian state name, e.g. 'Benue State'.
  ///
  /// In en, this message translates to:
  /// **'{state} State'**
  String zoneStateLabel(String state);

  /// Snackbar when push notifications are turned on but the phone's permission is denied. EWER is the app name.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications for EWER in your phone settings to receive alerts.'**
  String get settingsPushPermissionNeeded;

  /// Snackbar when the push service cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Push notifications are unavailable right now. Your choice is saved and will apply when they are.'**
  String get settingsPushUnavailable;

  /// Section header in Settings (upper case).
  ///
  /// In en, this message translates to:
  /// **'SECURITY & PRIVACY'**
  String get settingsSectionSecurity;

  /// Subtitle of the biometric login switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or Face ID to login'**
  String get settingsBiometricSubtitle;

  /// Shown under 'Biometric Login' when the device has no biometrics.
  ///
  /// In en, this message translates to:
  /// **'Not available on this device'**
  String get settingsBiometricUnavailable;

  /// Settings switch that forces the app offline.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode'**
  String get settingsOfflineMode;

  /// Snackbar after turning Offline Mode on.
  ///
  /// In en, this message translates to:
  /// **'Offline mode enabled'**
  String get settingsOfflineModeEnabled;

  /// Snackbar after turning Offline Mode off.
  ///
  /// In en, this message translates to:
  /// **'Restoring connection...'**
  String get settingsOfflineModeRestoring;

  /// Body of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get settingsLogoutConfirm;

  /// Footer text at the bottom of Settings (system name; CEWS is the acronym).
  ///
  /// In en, this message translates to:
  /// **'Climate Early Warning System (CEWS)'**
  String get settingsFooterSystemName;

  /// Error when the device has no fingerprint/face enrolled.
  ///
  /// In en, this message translates to:
  /// **'No biometrics enrolled. Please add a fingerprint or Face ID in your device Settings first.'**
  String get biometricErrorNotEnrolled;

  /// Error when the device lacks biometric hardware.
  ///
  /// In en, this message translates to:
  /// **'Biometrics are not available on this device.'**
  String get biometricErrorUnavailable;

  /// Error when biometrics are locked after too many failed attempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Biometrics are locked; unlock your device and try again later.'**
  String get biometricErrorLockedOut;

  /// Generic biometric failure.
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication failed. Please try again.'**
  String get biometricErrorFailed;

  /// Text in the system fingerprint/face prompt (fallback).
  ///
  /// In en, this message translates to:
  /// **'Please authenticate to continue'**
  String get biometricPromptDefault;

  /// Text in the system fingerprint/face prompt when turning on biometric login. EWER is the app name.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric login for EWER'**
  String get biometricEnablePrompt;

  /// Text in the system fingerprint/face prompt when unlocking the app. EWER is the app name.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to login to EWER Mobile'**
  String get biometricLoginPrompt;

  /// Name of face-recognition biometrics.
  ///
  /// In en, this message translates to:
  /// **'Face ID'**
  String get biometricTypeFace;

  /// Name of fingerprint biometrics.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get biometricTypeFingerprint;

  /// Name of iris-scan biometrics.
  ///
  /// In en, this message translates to:
  /// **'Iris'**
  String get biometricTypeIris;

  /// Generic name for biometrics.
  ///
  /// In en, this message translates to:
  /// **'Biometric'**
  String get biometricTypeGeneric;

  /// Registration error when the email already has an account.
  ///
  /// In en, this message translates to:
  /// **'Email is already registered. Please login.'**
  String get authErrorEmailRegistered;

  /// Generic registration error.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Please try again.'**
  String get authErrorRegistrationFailed;

  /// Network error during registration/login.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection and try again.'**
  String get authErrorNetworkRetry;

  /// Registration error for a weak password.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak. Use at least 8 characters with letters, numbers and symbols.'**
  String get authErrorWeakPassword;

  /// Registration error when the account already exists.
  ///
  /// In en, this message translates to:
  /// **'This account is already registered. Please login.'**
  String get authErrorAccountRegistered;

  /// Registration error when sign-ups are turned off.
  ///
  /// In en, this message translates to:
  /// **'Registration is currently disabled. Please contact support.'**
  String get authErrorRegistrationDisabled;

  /// Rate-limit error for registration/SMS/code requests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few minutes before trying again.'**
  String get authErrorTooManyAttempts;

  /// Generic login error.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please try again.'**
  String get authErrorLoginFailed;

  /// Login error for a deactivated account.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Please contact support.'**
  String get authErrorAccountDisabled;

  /// Login error when the server cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please check your connection.'**
  String get authErrorLoginConnection;

  /// Login error for wrong email/password.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password'**
  String get authErrorInvalidCredentials;

  /// Rate-limit error for login.
  ///
  /// In en, this message translates to:
  /// **'Too many login attempts. Please wait a few minutes and try again.'**
  String get authErrorTooManyLogins;

  /// Unexpected login failure.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred during login. Please try again.'**
  String get authErrorLoginUnexpected;

  /// Error for an invalid phone number when requesting an SMS code.
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number.'**
  String get authErrorInvalidPhone;

  /// Error when SMS sending is disabled.
  ///
  /// In en, this message translates to:
  /// **'SMS service is not available. Please contact support.'**
  String get authErrorSmsUnavailable;

  /// Error when logging in with an unregistered phone number.
  ///
  /// In en, this message translates to:
  /// **'No account found for this number. Please register first.'**
  String get authErrorPhoneNotRegistered;

  /// Error when the verification SMS cannot be sent.
  ///
  /// In en, this message translates to:
  /// **'Failed to send verification SMS.'**
  String get authErrorSmsFailed;

  /// Error when the verification code email cannot be sent.
  ///
  /// In en, this message translates to:
  /// **'Failed to send verification code.'**
  String get authErrorCodeSendFailed;

  /// Error when verifying a code without a pending sign-in.
  ///
  /// In en, this message translates to:
  /// **'No user context for verification. Please login again.'**
  String get authErrorNoUserContext;

  /// Generic code verification error.
  ///
  /// In en, this message translates to:
  /// **'Verification failed. Please try again.'**
  String get authErrorVerificationFailed;

  /// Error for a wrong/expired verification code.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired verification code. Please request a new one.'**
  String get authErrorInvalidCode;

  /// Rate-limit error when verifying a code.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few minutes and try again.'**
  String get authErrorTooManyAttemptsRetry;

  /// Unexpected error when verifying a code.
  ///
  /// In en, this message translates to:
  /// **'Failed to verify code.'**
  String get authErrorVerifyCodeFailed;

  /// Error when an action needs a signed-in user.
  ///
  /// In en, this message translates to:
  /// **'User not logged in'**
  String get authErrorNotLoggedIn;

  /// Error when resending the verification code fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to resend verification code. Please try again.'**
  String get authErrorResendFailed;

  /// Error when the password reset email cannot be sent.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset email. Please try again.'**
  String get authErrorResetEmailFailed;

  /// Password reset error for a weak new password.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak. The code has been used, so please request a new code and choose a stronger password.'**
  String get authErrorResetWeakPassword;

  /// Password reset error for a wrong/expired code.
  ///
  /// In en, this message translates to:
  /// **'This reset code is invalid or has expired. Please request a new one.'**
  String get authErrorResetCodeInvalid;

  /// Password reset error when the new password equals the old one.
  ///
  /// In en, this message translates to:
  /// **'Your new password must be different from the old one. The code has been used, so please request a new code.'**
  String get authErrorResetSamePassword;

  /// Generic password reset error.
  ///
  /// In en, this message translates to:
  /// **'Failed to reset password. Please try again.'**
  String get authErrorResetFailed;

  /// Error when sign-in is locked after too many failures.
  ///
  /// In en, this message translates to:
  /// **'Account is locked due to too many failed attempts'**
  String get rateLimitAccountLocked;

  /// Error during a sign-in cooldown; {count} is seconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Please wait 1 second before trying again} other{Please wait {count} seconds before trying again}}'**
  String rateLimitWaitSeconds(int count);

  /// Error when sign-in gets locked; {count} is minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Too many failed attempts. Account locked for 1 minute.} other{Too many failed attempts. Account locked for {count} minutes.}}'**
  String rateLimitLockedMinutes(int count);

  /// Error when too many verification codes were requested; {count} is minutes. OTP = one-time password.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Too many OTP requests. Please try again in 1 minute.} other{Too many OTP requests. Please try again in {count} minutes.}}'**
  String rateLimitOtpMinutes(int count);

  /// Error when resending a code too soon; {count} is seconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Please wait 1 second before requesting another code} other{Please wait {count} seconds before requesting another code}}'**
  String rateLimitResendSeconds(int count);

  /// Remaining sign-in attempts before lockout.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attempt remaining} other{{count} attempts remaining}}'**
  String rateLimitAttemptsRemaining(int count);

  /// Generic rate-limit error.
  ///
  /// In en, this message translates to:
  /// **'Rate limit exceeded'**
  String get rateLimitExceeded;

  /// Error when adding more photos than allowed to a report.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Maximum 1 image allowed} other{Maximum {count} images allowed}}'**
  String reportErrorMaxPhotos(int count);

  /// Error when submitting a report without a hazard type.
  ///
  /// In en, this message translates to:
  /// **'Please select a hazard type.'**
  String get reportErrorMissingHazard;

  /// Error when submitting a report without a severity.
  ///
  /// In en, this message translates to:
  /// **'Please select a severity level.'**
  String get reportErrorMissingSeverity;

  /// Error when submitting a report without location details.
  ///
  /// In en, this message translates to:
  /// **'Please add the location details.'**
  String get reportErrorMissingLocation;

  /// Error when submitting a report while signed out.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to submit or save a report.'**
  String get reportErrorSignedOut;

  /// Message when a report is saved offline as a draft.
  ///
  /// In en, this message translates to:
  /// **'Saved as draft. Will sync when online.'**
  String get reportSavedAsDraft;

  /// Message after a report is submitted online.
  ///
  /// In en, this message translates to:
  /// **'Report submitted successfully! Verification requests sent to peers.'**
  String get reportSubmittedWithPeers;

  /// Message when the server was unreachable and the report was queued.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Saved and will sync later.'**
  String get reportQueuedServerUnreachable;

  /// Summary after syncing offline reports; {count} uploaded, {failed} failed.
  ///
  /// In en, this message translates to:
  /// **'Synced {count} items. {failed} failed.'**
  String syncResultSummary(int count, int failed);

  /// Error when a picked photo cannot be re-encoded for upload.
  ///
  /// In en, this message translates to:
  /// **'A photo could not be processed. Please remove it or choose another photo.'**
  String get reportErrorPhotoProcessing;

  /// Severity level label (chips, badges). Max ~10 chars.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get severityLow;

  /// Severity level label (chips, badges). Max ~10 chars.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get severityMedium;

  /// Severity level label (chips, badges). Max ~10 chars.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get severityHigh;

  /// Severity level label (chips, badges). Max ~10 chars.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get severityCritical;

  /// Shown when an alert has no severity.
  ///
  /// In en, this message translates to:
  /// **'Unspecified severity'**
  String get alertSeverityUnspecified;

  /// Severity of an informational staff alert.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get alertSeverityInfo;

  /// Severity of a warning staff alert.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get alertSeverityWarning;

  /// Report review: when the incident happened today; {time} is a formatted time like 3:05 PM.
  ///
  /// In en, this message translates to:
  /// **'Today at {time}'**
  String reviewDateTodayAt(String time);

  /// Report review: when the incident happened; {date} like 'Mar 05, 2026', {time} like '3:05 PM'.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String reviewDateOnAt(String date, String time);

  /// Report review note when there is no GPS fix and no map pin.
  ///
  /// In en, this message translates to:
  /// **'Exact location unknown - the selected area will be used'**
  String get reviewLocationUnknown;

  /// Report review note when the location is the centre of the selected area.
  ///
  /// In en, this message translates to:
  /// **'Location approximate (area centre, no GPS fix)'**
  String get reviewLocationApproximate;

  /// Snackbar when voice input fails on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition error. Please try again.'**
  String get reportDetailsSpeechError;

  /// Snackbar when the camera cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Camera is not available. Please try using the gallery.'**
  String get reportDetailsCameraUnavailable;

  /// Snackbar when the photo gallery cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not access gallery. Please try again.'**
  String get reportDetailsGalleryError;

  /// Snackbar when the chosen incident time is in the future.
  ///
  /// In en, this message translates to:
  /// **'The incident time cannot be in the future. It has been set to the current time.'**
  String get reportDetailsFutureTime;

  /// Error when the phone's location services are off.
  ///
  /// In en, this message translates to:
  /// **'Location services are turned off. Please enable GPS.'**
  String get geoErrorServicesOff;

  /// Error when the app has no location permission.
  ///
  /// In en, this message translates to:
  /// **'Location permission was denied.'**
  String get geoErrorPermissionDenied;

  /// Error when location services cannot be queried.
  ///
  /// In en, this message translates to:
  /// **'Could not access location services.'**
  String get geoErrorServicesUnavailable;

  /// Notice when the app falls back to the last known position.
  ///
  /// In en, this message translates to:
  /// **'Could not get a fresh GPS fix; using your last known location.'**
  String get geoNoticeLastKnown;

  /// Error when no GPS fix arrives in time.
  ///
  /// In en, this message translates to:
  /// **'Timed out waiting for a GPS signal. Move to an open area and try again, or choose your location manually.'**
  String get geoErrorTimeout;

  /// Error when the location cannot be determined.
  ///
  /// In en, this message translates to:
  /// **'Could not determine your location. Please try again or choose your location manually.'**
  String get geoErrorUndetermined;

  /// Placeholder while something loads.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// Location picker severity slider: level 1 title.
  ///
  /// In en, this message translates to:
  /// **'Low Severity'**
  String get locationPickerSeverityLow;

  /// Location picker severity slider: level 2 title.
  ///
  /// In en, this message translates to:
  /// **'Medium Severity'**
  String get locationPickerSeverityMedium;

  /// Location picker severity slider: level 3 title.
  ///
  /// In en, this message translates to:
  /// **'High Severity'**
  String get locationPickerSeverityHigh;

  /// Location picker severity slider: level 4 title.
  ///
  /// In en, this message translates to:
  /// **'Critical Severity'**
  String get locationPickerSeverityCritical;

  /// Description of the low severity level.
  ///
  /// In en, this message translates to:
  /// **'Minor issue. No immediate threat.'**
  String get locationPickerSeverityLowDesc;

  /// Description of the medium severity level.
  ///
  /// In en, this message translates to:
  /// **'Moderate issue. Monitor situation.'**
  String get locationPickerSeverityMediumDesc;

  /// Description of the high severity level.
  ///
  /// In en, this message translates to:
  /// **'Significant threat to property or health. Response required.'**
  String get locationPickerSeverityHighDesc;

  /// Description of the critical severity level.
  ///
  /// In en, this message translates to:
  /// **'Life-threatening situation. Immediate action required.'**
  String get locationPickerSeverityCriticalDesc;

  /// Small caption above the chosen severity level.
  ///
  /// In en, this message translates to:
  /// **'Selected Level'**
  String get locationPickerSelectedLevel;

  /// GPS status chip when the position is an area centre or a tapped point (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Approximate'**
  String get locationPickerGpsApproximate;

  /// Small caption above the detected Local Government Area (upper case, keep short).
  ///
  /// In en, this message translates to:
  /// **'LGA'**
  String get locationPickerLgaHeading;

  /// Small caption above the detected ward (upper case, keep short).
  ///
  /// In en, this message translates to:
  /// **'WARD'**
  String get locationPickerWardHeading;

  /// Shown when the LGA could not be detected from GPS.
  ///
  /// In en, this message translates to:
  /// **'Unknown LGA'**
  String get locationPickerUnknownLga;

  /// Shown when the ward could not be detected from GPS.
  ///
  /// In en, this message translates to:
  /// **'Unknown Ward'**
  String get locationPickerUnknownWard;

  /// Snackbar after filling LGA/ward from the GPS position.
  ///
  /// In en, this message translates to:
  /// **'Auto-filled from GPS'**
  String get locationPickerAutofilled;

  /// Snackbar when the GPS LGA is not in the selected state; {lga} LGA name, {state} state name.
  ///
  /// In en, this message translates to:
  /// **'GPS Location ({lga}) not found in {state}'**
  String locationPickerGpsLgaNotFound(String lga, String state);

  /// Snackbar when GPS auto-fill is not possible.
  ///
  /// In en, this message translates to:
  /// **'GPS Location unavailable or State not selected'**
  String get locationPickerGpsUnavailable;

  /// GPS accuracy in the location details sheet; {distance} is a number like 12.5.
  ///
  /// In en, this message translates to:
  /// **'{distance} meters'**
  String locationPickerMeters(String distance);

  /// Altitude in the location details sheet; {distance} is a number like 350.0. 'm' = metres.
  ///
  /// In en, this message translates to:
  /// **'{distance} m'**
  String locationPickerMetersShort(String distance);

  /// Section heading on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get reportViewSectionDetails;

  /// Label of the reporter's name on the report details screen.
  ///
  /// In en, this message translates to:
  /// **'Reporter'**
  String get reportViewReporter;

  /// Label of the time the report was submitted.
  ///
  /// In en, this message translates to:
  /// **'Reported'**
  String get reportViewReported;

  /// Label of the report severity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get reportViewSeverity;

  /// Label of the number of peer verifications.
  ///
  /// In en, this message translates to:
  /// **'Verifications'**
  String get reportViewVerifications;

  /// Section heading for report photos; {count} is the number of photos.
  ///
  /// In en, this message translates to:
  /// **'Evidence ({count})'**
  String reportViewEvidenceCount(int count);

  /// Section heading for GPS coordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates'**
  String get reportViewCoordinates;

  /// Heading of the rejection card; {date} like 'Mar 5, 2026'.
  ///
  /// In en, this message translates to:
  /// **'Report rejected on {date}'**
  String reportViewRejectedOn(String date);

  /// Shown when a rejected report has no rejection reason.
  ///
  /// In en, this message translates to:
  /// **'No reason was given.'**
  String get reportViewNoReason;

  /// Tab on My Reports listing reports still being verified (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get myReportsTabActive;

  /// Tab on My Reports listing approved/rejected reports (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get myReportsTabHistory;

  /// Shown on My Reports when signed out.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to view your reports.'**
  String get myReportsSignIn;

  /// Empty state title of the Active tab.
  ///
  /// In en, this message translates to:
  /// **'No active reports'**
  String get myReportsEmptyActiveTitle;

  /// Empty state text of the Active tab.
  ///
  /// In en, this message translates to:
  /// **'Reports you submit will appear here while being verified.'**
  String get myReportsEmptyActiveBody;

  /// Empty state title of the History tab.
  ///
  /// In en, this message translates to:
  /// **'No report history'**
  String get myReportsEmptyHistoryTitle;

  /// Empty state text of the History tab.
  ///
  /// In en, this message translates to:
  /// **'Your approved and rejected reports will appear here.'**
  String get myReportsEmptyHistoryBody;

  /// Floating button that starts a new hazard report (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'New Report'**
  String get myReportsNewReport;

  /// Rejection reason on a report card; {reason} is the staff's text.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String myReportsRejectionReason(String reason);

  /// App bar title of the nearby reports screen.
  ///
  /// In en, this message translates to:
  /// **'Nearby Reports'**
  String get nearbyTitle;

  /// Title shown to plain users on the nearby reports screen.
  ///
  /// In en, this message translates to:
  /// **'Not available for your account'**
  String get nearbyNotAvailableTitle;

  /// Explanation shown to plain users on the nearby reports screen.
  ///
  /// In en, this message translates to:
  /// **'Nearby reports are visible to approved monitors and staff. You can follow your own reports under My Reports.'**
  String get nearbyNotAvailableBody;

  /// Title when the user has no LGA/zone set.
  ///
  /// In en, this message translates to:
  /// **'Location Not Set'**
  String get nearbyLocationNotSetTitle;

  /// Text when the user has no LGA/zone set (contains a line break).
  ///
  /// In en, this message translates to:
  /// **'Set your LGA or monitoring zone in\nyour profile to see reports near you.'**
  String get nearbyLocationNotSetBody;

  /// Title when nearby reports failed to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load reports'**
  String get nearbyLoadErrorTitle;

  /// Empty state title of the nearby reports screen.
  ///
  /// In en, this message translates to:
  /// **'No Nearby Reports'**
  String get nearbyEmptyTitle;

  /// Empty state text of the nearby reports screen (contains a line break).
  ///
  /// In en, this message translates to:
  /// **'There are no reports from your\narea at this time.'**
  String get nearbyEmptyBody;

  /// Title of an alert that has no title.
  ///
  /// In en, this message translates to:
  /// **'Alert'**
  String get alertDetailDefaultTitle;

  /// Shown when an alert has no location.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get alertDetailNotSpecified;

  /// Status of a staff alert that is still active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get alertStatusActive;

  /// Status of a staff alert that is no longer active.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get alertStatusInactive;

  /// Snackbar when the report behind an alert cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'Report details could not be loaded.'**
  String get alertDetailReportLoadError;

  /// App bar title of the alert detail screen.
  ///
  /// In en, this message translates to:
  /// **'Alert Details'**
  String get alertDetailTitle;

  /// Label of the time the alert/report was created.
  ///
  /// In en, this message translates to:
  /// **'Reported Time'**
  String get alertDetailReportedTime;

  /// Label of the alert status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get alertDetailStatus;

  /// Shown when an alert has no description.
  ///
  /// In en, this message translates to:
  /// **'No additional description provided for this alert. Please take necessary precautions and follow local guidelines.'**
  String get alertDetailNoDescription;

  /// Heading of the safety advice list on an alert.
  ///
  /// In en, this message translates to:
  /// **'Recommended Actions'**
  String get alertDetailRecommendedActions;

  /// Safety advice item 1 on an alert.
  ///
  /// In en, this message translates to:
  /// **'1. Stay informed via local news/radio.'**
  String get alertDetailAction1;

  /// Safety advice item 2 on an alert.
  ///
  /// In en, this message translates to:
  /// **'2. Prepare emergency supplies.'**
  String get alertDetailAction2;

  /// Safety advice item 3 on an alert.
  ///
  /// In en, this message translates to:
  /// **'3. Avoid travel to affected areas.'**
  String get alertDetailAction3;

  /// Safety advice item 4 on an alert.
  ///
  /// In en, this message translates to:
  /// **'4. Follow evacuation orders if issued.'**
  String get alertDetailAction4;

  /// Heading of the peer vote box on an alert.
  ///
  /// In en, this message translates to:
  /// **'Peer Verification Required'**
  String get alertDetailPeerVerificationTitle;

  /// Text of the peer vote box. EWM = Early Warning Monitor (role name).
  ///
  /// In en, this message translates to:
  /// **'As an EWM in this ward, please verify if you can confirm this report based on what you\'ve observed.'**
  String get alertDetailPeerVerificationBody;

  /// Label of the comment field in the peer vote box.
  ///
  /// In en, this message translates to:
  /// **'Comment (required to dispute)'**
  String get alertDetailCommentLabel;

  /// Hint of the comment field in the peer vote box.
  ///
  /// In en, this message translates to:
  /// **'Additional information about this report...'**
  String get alertDetailCommentHint;

  /// Button text while a submission is in progress.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get commonSubmitting;

  /// Button to confirm (vote for) a report (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get voteConfirm;

  /// Button to dispute (vote against) a report (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get voteDecline;

  /// Heading after the user voted on a report.
  ///
  /// In en, this message translates to:
  /// **'Verification Submitted'**
  String get alertDetailVerificationSubmitted;

  /// Text after the user voted on a report.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your contribution!'**
  String get alertDetailThanks;

  /// Bottom button on the alert detail after voting.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get alertDetailGoBack;

  /// Bottom button on the alert detail.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get alertDetailDismiss;

  /// Hazard filter chip on the report history showing everything (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'All Alerts'**
  String get alertsFilterAll;

  /// Hazard filter chip for fire reports (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get alertsFilterFire;

  /// Tooltip of the button that opens the staff alert broadcast screen.
  ///
  /// In en, this message translates to:
  /// **'Broadcast an alert'**
  String get alertsBroadcastTooltip;

  /// Tooltip of the severity filter menu.
  ///
  /// In en, this message translates to:
  /// **'Filter by severity'**
  String get alertsSeverityFilterTooltip;

  /// Severity filter option that shows every severity.
  ///
  /// In en, this message translates to:
  /// **'All severities'**
  String get alertsAllSeverities;

  /// Tab on the Alerts screen listing official staff alerts (max ~16 chars).
  ///
  /// In en, this message translates to:
  /// **'Broadcasts'**
  String get alertsTabBroadcasts;

  /// Tab on the Alerts screen listing hazard reports (max ~16 chars).
  ///
  /// In en, this message translates to:
  /// **'Report History'**
  String get alertsTabReportHistory;

  /// Search field hint on the report history tab.
  ///
  /// In en, this message translates to:
  /// **'Search location, hazard, or ID...'**
  String get alertsSearchReportsHint;

  /// Search field hint on the broadcasts tab.
  ///
  /// In en, this message translates to:
  /// **'Search alerts...'**
  String get alertsSearchAlertsHint;

  /// Tooltip of the button that clears the search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get alertsClearSearch;

  /// Title when alerts failed to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load alerts'**
  String get alertsLoadError;

  /// Title when no alert matches the search.
  ///
  /// In en, this message translates to:
  /// **'No matching alerts'**
  String get alertsNoMatching;

  /// Hint below a loading error (pull-to-refresh).
  ///
  /// In en, this message translates to:
  /// **'Pull down to try again.'**
  String get alertsPullToRetry;

  /// Empty state text of the broadcasts tab.
  ///
  /// In en, this message translates to:
  /// **'Official alerts for your area will appear here.'**
  String get alertsEmptyBody;

  /// Tag on an alert sent to every Local Government Area.
  ///
  /// In en, this message translates to:
  /// **'All LGAs'**
  String get alertsAllLgas;

  /// Sync status while reports are loading.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing...'**
  String get alertsSynchronizing;

  /// Empty state title of the report history.
  ///
  /// In en, this message translates to:
  /// **'No Reports Yet'**
  String get alertsNoReportsYet;

  /// Title when no report matches the search/filter.
  ///
  /// In en, this message translates to:
  /// **'No matching reports'**
  String get alertsNoMatchingReports;

  /// Title when no report matches the hazard filter; {filter} is the filter name, e.g. 'No Floods'.
  ///
  /// In en, this message translates to:
  /// **'No {filter}'**
  String alertsNoReportsForFilter(String filter);

  /// Empty state text of the report history (contains a line break).
  ///
  /// In en, this message translates to:
  /// **'When hazards are reported in your area,\nthey\'ll appear here'**
  String get alertsNoReportsYetBody;

  /// Text when no report matches the search/filter.
  ///
  /// In en, this message translates to:
  /// **'No matching reports found in this area'**
  String get alertsNoMatchingReportsBody;

  /// Toast after disputing a report from the alerts list.
  ///
  /// In en, this message translates to:
  /// **'Dispute recorded'**
  String get alertsDisputeRecorded;

  /// Toast after confirming a report from the alerts list.
  ///
  /// In en, this message translates to:
  /// **'Report confirmed'**
  String get alertsReportConfirmed;

  /// Toast when the email verification is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Account verified successfully!'**
  String get accessCodeVerified;

  /// Toast when the account is still unverified.
  ///
  /// In en, this message translates to:
  /// **'Not verified yet. Please enter the code sent to your email.'**
  String get accessCodeNotVerified;

  /// Toast after resending the verification code.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent!'**
  String get accessCodeSent;

  /// Toast when the signed-in account has no email.
  ///
  /// In en, this message translates to:
  /// **'No email found for this account. Please log in again.'**
  String get accessCodeNoEmail;

  /// Title of the email verification screen.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Email'**
  String get accessCodeTitle;

  /// Button that opens the code entry screen (max ~16 chars).
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get accessCodeEnterCode;

  /// Button to re-check verification status.
  ///
  /// In en, this message translates to:
  /// **'I have verified my account'**
  String get accessCodeIHaveVerified;

  /// Body of the email verification screen; {email} is the address.
  ///
  /// In en, this message translates to:
  /// **'We have sent a 6-digit verification code to {email}.\nEnter the code to activate your account.'**
  String accessCodeBody(String email);

  /// Body of the email verification screen when the address is unknown.
  ///
  /// In en, this message translates to:
  /// **'We have sent a 6-digit verification code to your email.\nEnter the code to activate your account.'**
  String get accessCodeBodyNoEmail;

  /// Title of the forgot password screen.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotTitle;

  /// Text on the forgot password screen.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address to receive a password reset code.'**
  String get forgotBody;

  /// Hint of email fields on auth screens.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEmailHint;

  /// Validation error when the email field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get authEmailRequired;

  /// Validation error when the email is malformed.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get authEmailInvalid;

  /// Button that sends the password reset code (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Send Reset Code'**
  String get forgotSendCode;

  /// Title after the reset code was requested.
  ///
  /// In en, this message translates to:
  /// **'Email Sent!'**
  String get forgotEmailSentTitle;

  /// Text after the reset code was requested; {email} is the address entered.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, we have sent a reset code.\nEnter it on the next screen to choose a new password.'**
  String forgotEmailSentBody(String email);

  /// Button that opens the reset code screen (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Enter Reset Code'**
  String get forgotEnterCode;

  /// Landing screen heading. EWER is the app name (Early Warning and Early Response); keep it.
  ///
  /// In en, this message translates to:
  /// **'Welcome to EWER'**
  String get landingWelcome;

  /// Landing screen subtitle (expansion of EWER).
  ///
  /// In en, this message translates to:
  /// **'Early Warning and Early Response System'**
  String get landingSubtitle;

  /// Landing screen tagline.
  ///
  /// In en, this message translates to:
  /// **'Empowering communities with real-time hazard reporting and rapid response coordination.'**
  String get landingTagline;

  /// Landing screen caption above the sign-up/login buttons.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get landingGetStarted;

  /// Button/link to create an account (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get authSignUp;

  /// Button/link to sign in (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLogin;

  /// Validation error when the phone field is empty.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get validatorPhoneRequired;

  /// Validation error for a malformed Nigerian phone number.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid Nigerian phone number'**
  String get validatorPhoneInvalid;

  /// Validation error when the address is empty.
  ///
  /// In en, this message translates to:
  /// **'Address is required'**
  String get validatorAddressRequired;

  /// Validation error for a too-short address.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Address must be at least {count} characters}}'**
  String validatorAddressTooShort(int count);

  /// Validation error for a too-long address.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Address is too long (max {count} characters)}}'**
  String validatorAddressTooLong(int count);

  /// Validation error for an empty field; {field} is the field's label, e.g. 'Full Name'.
  ///
  /// In en, this message translates to:
  /// **'{field} is required'**
  String validatorFieldRequired(String field);

  /// Validation error; {field} is the field label, {count} the minimum length.
  ///
  /// In en, this message translates to:
  /// **'{field} must be at least {count} characters'**
  String validatorFieldMinLength(String field, int count);

  /// Validation error; {field} is the field label, {count} the maximum length.
  ///
  /// In en, this message translates to:
  /// **'{field} must not exceed {count} characters'**
  String validatorFieldMaxLength(String field, int count);

  /// Validation error when text contains disallowed characters.
  ///
  /// In en, this message translates to:
  /// **'Invalid characters detected'**
  String get validatorInvalidCharacters;

  /// Validation error; {field} is the field label.
  ///
  /// In en, this message translates to:
  /// **'{field} contains invalid characters'**
  String validatorFieldInvalidCharacters(String field);

  /// Validation error when the description is empty.
  ///
  /// In en, this message translates to:
  /// **'Description is required'**
  String get validatorDescriptionRequired;

  /// Validation error for a too-long description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Description must not exceed {count} characters}}'**
  String validatorDescriptionTooLong(int count);

  /// Validation error when the email is empty.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get validatorEmailRequired;

  /// Validation error when the password is empty.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get validatorPasswordRequired;

  /// Validation error for a too-short password.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Password must be at least {count} characters}}'**
  String validatorPasswordMinLength(int count);

  /// Password rule error.
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one uppercase letter'**
  String get validatorPasswordUppercase;

  /// Password rule error.
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one lowercase letter'**
  String get validatorPasswordLowercase;

  /// Password rule error.
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one number'**
  String get validatorPasswordNumber;

  /// Password rule error.
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one special character'**
  String get validatorPasswordSpecial;

  /// Password strength meter label.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passwordStrengthWeak;

  /// Password strength meter label.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get passwordStrengthFair;

  /// Password strength meter label.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get passwordStrengthGood;

  /// Password strength meter label.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get passwordStrengthStrong;

  /// Validation error for a too-long password.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Password is too long (max {count} characters)}}'**
  String passwordErrorTooLong(int count);

  /// Validation error for a common password.
  ///
  /// In en, this message translates to:
  /// **'This password is too common. Please choose a stronger password'**
  String get passwordErrorCommon;

  /// Validation error for sequential characters.
  ///
  /// In en, this message translates to:
  /// **'Password should not contain sequential characters (e.g., 123, abc)'**
  String get passwordErrorSequential;

  /// Password requirement checklist item.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{At least {count} characters}}'**
  String passwordRequirementLength(int count);

  /// Password requirement checklist item.
  ///
  /// In en, this message translates to:
  /// **'Uppercase letter'**
  String get passwordRequirementUppercase;

  /// Password requirement checklist item.
  ///
  /// In en, this message translates to:
  /// **'Lowercase letter'**
  String get passwordRequirementLowercase;

  /// Password requirement checklist item (a digit).
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get passwordRequirementNumber;

  /// Password requirement checklist item.
  ///
  /// In en, this message translates to:
  /// **'Special character'**
  String get passwordRequirementSpecial;

  /// Password requirement checklist item.
  ///
  /// In en, this message translates to:
  /// **'Not a common password'**
  String get passwordRequirementNotCommon;

  /// Login error when the sign-in was refused.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please check your credentials.'**
  String get authLoginCheckCredentials;

  /// Login screen heading.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get loginWelcomeBack;

  /// Login screen subheading.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account'**
  String get loginSubtitle;

  /// Label of phone number fields.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get authPhoneNumber;

  /// Label of password fields.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// Checkbox on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Remember Me'**
  String get loginRememberMe;

  /// Text before the 'Sign Up' link on the login screen (keep the trailing space).
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get loginNoAccount;

  /// Reassurance note at the bottom of the login screen.
  ///
  /// In en, this message translates to:
  /// **'Your data is encrypted and secure'**
  String get loginDataSecure;

  /// Title of the app lock screen. CRADI is the organisation name.
  ///
  /// In en, this message translates to:
  /// **'CRADI Mobile Locked'**
  String get loginLockedTitle;

  /// Button on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Biometrics'**
  String get loginUnlockBiometrics;

  /// Link on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'Log out and use different account'**
  String get loginLogoutDifferentAccount;

  /// Sign-in/registration method toggle option (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authMethodEmail;

  /// Sign-in method toggle option (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get authMethodPhone;

  /// Login button when signing in by phone (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get loginSendCode;

  /// Toast after a code was verified.
  ///
  /// In en, this message translates to:
  /// **'Verification successful!'**
  String get otpSuccess;

  /// Toast after resending a code.
  ///
  /// In en, this message translates to:
  /// **'A new code has been sent.'**
  String get otpNewCodeSent;

  /// Title of the code entry screen for email codes.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get otpVerifyEmail;

  /// Code entry instructions; {destination} is the email address or phone number.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to\n{destination}'**
  String otpCodeSentTo(String destination);

  /// Label of the verification code field.
  ///
  /// In en, this message translates to:
  /// **'Secure Code'**
  String get otpSecureCode;

  /// Hint of the verification code field.
  ///
  /// In en, this message translates to:
  /// **'Enter 6-digit code'**
  String get otpCodeHint;

  /// Validation error when the code is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter the code'**
  String get otpCodeRequired;

  /// Validation error when the code is too short.
  ///
  /// In en, this message translates to:
  /// **'Invalid code format'**
  String get otpCodeInvalidFormat;

  /// Button that submits the verification code (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Verify & Login'**
  String get otpVerifyAndLogin;

  /// Text before the resend link (keep the trailing space).
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive code? '**
  String get otpNoCode;

  /// Disabled resend link with a countdown; {count} is seconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Resend in {count}s}}'**
  String otpResendIn(int count);

  /// Title of the screen shown while an account awaits admin approval.
  ///
  /// In en, this message translates to:
  /// **'Approval Pending'**
  String get pendingTitle;

  /// Body of the approval pending screen (contains blank line).
  ///
  /// In en, this message translates to:
  /// **'Your account has been created successfully but is waiting for admin approval.\n\nYou will be able to access the full application once an administrator reviews and approves your account.'**
  String get pendingBody;

  /// Snackbar after checking approval status while still pending.
  ///
  /// In en, this message translates to:
  /// **'Your account is still awaiting approval.'**
  String get pendingStillWaiting;

  /// Button on the approval pending screen.
  ///
  /// In en, this message translates to:
  /// **'Check approval status'**
  String get pendingCheckStatus;

  /// Link to help & support.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get pendingContactSupport;

  /// Title of the privacy consent dialog at registration and in About.
  ///
  /// In en, this message translates to:
  /// **'Data Privacy Notice'**
  String get registrationPrivacyTitle;

  /// Button that refuses the privacy notice (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get registrationDecline;

  /// Button that accepts the privacy notice (max ~12 chars). Referenced in the notice text.
  ///
  /// In en, this message translates to:
  /// **'I Agree'**
  String get registrationAgree;

  /// Toast when the privacy notice was declined.
  ///
  /// In en, this message translates to:
  /// **'You must accept the Data Privacy Notice to register.'**
  String get registrationMustAccept;

  /// Toast when no state is chosen at registration.
  ///
  /// In en, this message translates to:
  /// **'Please select a state'**
  String get registrationSelectState;

  /// Toast when no LGA (Local Government Area) is chosen.
  ///
  /// In en, this message translates to:
  /// **'Please select an LGA'**
  String get registrationSelectLga;

  /// Toast when no ward is chosen.
  ///
  /// In en, this message translates to:
  /// **'Please select a ward'**
  String get registrationSelectWard;

  /// Dialog title after registering with a phone number.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Phone Number'**
  String get registrationVerifyPhoneTitle;

  /// Dialog body after registering by phone; {phone} is the number.
  ///
  /// In en, this message translates to:
  /// **'A 6-digit verification code has been sent to {phone}.\n\nPlease enter the code to activate your account.'**
  String registrationPhoneCodeSent(String phone);

  /// Toast after a successful sign-up.
  ///
  /// In en, this message translates to:
  /// **'Account created!'**
  String get registrationAccountCreated;

  /// Dialog title after registering with email.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Email Address'**
  String get registrationVerifyEmailTitle;

  /// Dialog body after registering by email; {email} is the address.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully!\n\nA 6-digit verification code has been sent to {email}.\n\nPlease enter the code to activate your account.'**
  String registrationEmailCodeSent(String email);

  /// Registration screen title and submit button (max ~20 chars).
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registrationCreateAccount;

  /// Registration screen heading.
  ///
  /// In en, this message translates to:
  /// **'Join the Network'**
  String get registrationJoinNetwork;

  /// Registration screen subheading.
  ///
  /// In en, this message translates to:
  /// **'Select your location to get started.'**
  String get registrationSelectLocation;

  /// Section label for choosing email or phone registration.
  ///
  /// In en, this message translates to:
  /// **'Registration Method'**
  String get registrationMethod;

  /// Section label on the registration form.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get registrationPersonalInfo;

  /// Example name shown as hint in the full name field (use a typical local name).
  ///
  /// In en, this message translates to:
  /// **'John Doe'**
  String get registrationNameHint;

  /// Field name used in the 'Name is required' validation message.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get registrationNameField;

  /// Label of the address field on the registration form.
  ///
  /// In en, this message translates to:
  /// **'Address Description'**
  String get registrationAddressLabel;

  /// Example address hint.
  ///
  /// In en, this message translates to:
  /// **'e.g., No 5, Main Street'**
  String get registrationAddressHint;

  /// Field name used in the 'Address is required' validation message.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get registrationAddressField;

  /// Section label for the password fields.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get registrationSecurity;

  /// Hint of the password field at registration.
  ///
  /// In en, this message translates to:
  /// **'Create a password'**
  String get registrationPasswordHint;

  /// Label of the confirm password field.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get registrationConfirmPassword;

  /// Hint of the confirm password field.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get registrationConfirmPasswordHint;

  /// Validation error when the confirm password field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get registrationConfirmPasswordRequired;

  /// Validation error when the two passwords differ.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get registrationPasswordsMismatch;

  /// Submit button when registering by phone (max ~22 chars). OTP = one-time password.
  ///
  /// In en, this message translates to:
  /// **'Send OTP & Register'**
  String get registrationSendOtp;

  /// Text before the 'Login' link (keep the trailing space).
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get registrationHaveAccount;

  /// Loading overlay text while the account is created.
  ///
  /// In en, this message translates to:
  /// **'Creating account...'**
  String get registrationCreating;

  /// Full NDPA (Nigeria Data Protection Act) data-processing notice shown at registration and in About. Legal text: translate faithfully; keep the names EWER, CRADI, KusuConsult-NG, Supabase, OneSignal, Sentry and the "I Agree" button name consistent with registrationAgree.
  ///
  /// In en, this message translates to:
  /// **'Nigeria Data Protection Act (NDPA) — Data Processing Notice\n\nYour data is processed by EWER Mobile (a CRADI / KusuConsult-NG service) for climate hazard early warning purposes.\n\n• Data collected: name, phone, email, location (state/LGA/ward), hazard reports, and a push-notification device identifier.\n• Purpose: community hazard reporting, peer verification, and emergency alerts.\n• Storage: Supabase (PostgreSQL) cloud database; push notifications are delivered via OneSignal and crash diagnostics may be sent to Sentry.\n• International transfer: Pursuant to NDPA Article 24, we disclose that your data may be transferred to and stored on servers outside Nigeria. This transfer is necessary to provide the service. You have the right to withdraw consent at any time by deleting your account.\n• Retention: Data is retained for 5 years after your last activity, then anonymised.\n• Your rights: access, rectification, erasure, and data portability under the NDPA 2023.\n\nBy tapping \"I Agree\", you consent to these terms and the international transfer of your personal data.'**
  String get privacyNoticeText;

  /// App name on the About screen (brand; usually not translated).
  ///
  /// In en, this message translates to:
  /// **'EWER Mobile'**
  String get aboutAppName;

  /// Subtitle under the app name on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Early Warning System'**
  String get aboutTagline;

  /// App version line on the About screen; {version} like 1.0.14, {build} like 22.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (Build {build})'**
  String aboutVersion(String version, String build);

  /// Copyright line on the About screen; {year} is the year.
  ///
  /// In en, this message translates to:
  /// **'© {year} EWER. All rights reserved.'**
  String aboutCopyright(String year);

  /// App version line on the About screen when the platform reports no build number; {version} like 1.0.14.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersionOnly(String version);

  /// Button and dialog title for the privacy notice on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get aboutPrivacyPolicy;

  /// Toast after requesting a new password reset code.
  ///
  /// In en, this message translates to:
  /// **'If an account exists, a new code has been sent.'**
  String get resetCodeResent;

  /// Title of the reset password screen.
  ///
  /// In en, this message translates to:
  /// **'Create New Password'**
  String get resetTitle;

  /// Instructions on the reset password screen.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the reset email and choose a new secure password.'**
  String get resetBody;

  /// Instructions on the reset screen when a recovery link was opened in the app, so no code is needed.
  ///
  /// In en, this message translates to:
  /// **'Choose a new secure password for your CRADI account.'**
  String get resetRecoveryBody;

  /// Label of the reset code field.
  ///
  /// In en, this message translates to:
  /// **'Reset Code'**
  String get resetCodeLabel;

  /// Button text while a reset code is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get resetSendingCode;

  /// Button that (re)sends the reset code (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get resetSendCode;

  /// Validation error when the reset code is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the email'**
  String get resetCodeRequired;

  /// Label of the new password field.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get resetNewPassword;

  /// Submit button of the reset password screen.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetSubmit;

  /// Title after a successful password reset.
  ///
  /// In en, this message translates to:
  /// **'Password Reset!'**
  String get resetSuccessTitle;

  /// Text after a successful password reset.
  ///
  /// In en, this message translates to:
  /// **'Your password has been reset successfully. You can now login with your new password.'**
  String get resetSuccessBody;

  /// Button after a successful password reset.
  ///
  /// In en, this message translates to:
  /// **'Continue to Login'**
  String get resetContinueToLogin;

  /// Snackbar when syncing offline reports starts.
  ///
  /// In en, this message translates to:
  /// **'Syncing pending data...'**
  String get offlineSyncingPending;

  /// Title of the dialog confirming deletion of an unsent report.
  ///
  /// In en, this message translates to:
  /// **'Discard report?'**
  String get offlineDiscardTitle;

  /// Body of the discard confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'This report has not been sent and will be deleted from this device.'**
  String get offlineDiscardBody;

  /// Button/menu item that deletes an unsent report (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get offlineDiscard;

  /// Tooltip of the actions menu on a pending report.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get offlineActions;

  /// Menu item that submits an ownerless draft as the signed-in user.
  ///
  /// In en, this message translates to:
  /// **'Submit as me'**
  String get offlineSubmitAsMe;

  /// Heading of the offline screen.
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection'**
  String get offlineNoInternet;

  /// Text on the offline screen when signed in.
  ///
  /// In en, this message translates to:
  /// **'You can still view your saved guides and draft reports.'**
  String get offlineCanViewSaved;

  /// Text on the offline screen when signed out.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to sign in.'**
  String get offlineReconnectToSignIn;

  /// Button on the offline screen.
  ///
  /// In en, this message translates to:
  /// **'Try Reconnecting & Sync'**
  String get offlineTryReconnect;

  /// Snackbar when the user forced offline mode in Settings.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode is enabled in Settings.'**
  String get offlineModeEnabledInSettings;

  /// Snackbar action that turns offline mode off.
  ///
  /// In en, this message translates to:
  /// **'Go online'**
  String get offlineGoOnline;

  /// Snackbar when reconnecting failed.
  ///
  /// In en, this message translates to:
  /// **'Still no internet connection'**
  String get offlineStillNoInternet;

  /// Button on the offline screen.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get offlineOpenSettings;

  /// Button on the offline screen.
  ///
  /// In en, this message translates to:
  /// **'View Saved Guides'**
  String get offlineViewSavedGuides;

  /// Empty state of the pending reports list.
  ///
  /// In en, this message translates to:
  /// **'No pending reports'**
  String get offlineNoPending;

  /// Status of a draft saved by an older app version without an owner.
  ///
  /// In en, this message translates to:
  /// **'Saved by an earlier version: submit or discard it'**
  String get offlineStatusOwnerless;

  /// Status of a report that permanently failed to upload.
  ///
  /// In en, this message translates to:
  /// **'Failed, will not sync automatically'**
  String get offlineStatusFailed;

  /// Status of a failed report with the (technical) error text; {error} may be English server text.
  ///
  /// In en, this message translates to:
  /// **'Failed, will not sync automatically: {error}'**
  String offlineStatusFailedWithError(String error);

  /// Status of a report waiting to upload.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get offlineStatusWaiting;

  /// Subtitle of a pending report: location, then date and status on the second line.
  ///
  /// In en, this message translates to:
  /// **'{location}\n{date} • {status}'**
  String offlineItemSubtitle(String location, String date, String status);

  /// Role name: a registered user not yet approved as a monitor.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get roleUser;

  /// Role name (EWM): community member who reports hazards.
  ///
  /// In en, this message translates to:
  /// **'Early Warning Monitor'**
  String get roleEwm;

  /// Role name (EWV): validates reports.
  ///
  /// In en, this message translates to:
  /// **'Early Warning Validator'**
  String get roleEwv;

  /// Role name (EWR): responds to reports.
  ///
  /// In en, this message translates to:
  /// **'Early Warning Responder'**
  String get roleEwr;

  /// Role name: Local Development Plan coordinator.
  ///
  /// In en, this message translates to:
  /// **'LDP Coordinator'**
  String get roleLdpCoordinator;

  /// Role name: project staff member.
  ///
  /// In en, this message translates to:
  /// **'Project Staff'**
  String get roleProjectStaff;

  /// Role name: administrator.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get roleAdmin;

  /// Role name: technical support.
  ///
  /// In en, this message translates to:
  /// **'Tech Support'**
  String get roleTechSupport;

  /// Snackbar after uploading a new profile photo.
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated!'**
  String get profilePhotoUpdated;

  /// Snackbar when the camera cannot be opened for a profile photo.
  ///
  /// In en, this message translates to:
  /// **'Camera not available. Please use the gallery.'**
  String get profileCameraUnavailable;

  /// Snackbar when picking a profile photo fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick image. Please try again.'**
  String get profilePickImageFailed;

  /// Title of the profile photo picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Update Profile Photo'**
  String get profileUpdatePhoto;

  /// Option in the profile photo picker.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get profileChooseGallery;

  /// Subtitle of the gallery option.
  ///
  /// In en, this message translates to:
  /// **'Select a photo from your device'**
  String get profileChooseGallerySubtitle;

  /// Shown on web instead of the camera option.
  ///
  /// In en, this message translates to:
  /// **'Camera not available on web'**
  String get profileCameraWebUnavailable;

  /// Subtitle on web instead of the camera option.
  ///
  /// In en, this message translates to:
  /// **'Please use the gallery option'**
  String get profileUseGallery;

  /// Option in the profile photo picker.
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get profilePhotoLibrary;

  /// Title of the edit profile sheet.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEdit;

  /// Note under the locked location fields for staff accounts.
  ///
  /// In en, this message translates to:
  /// **'Ask an admin to change your area'**
  String get profileAskAdminArea;

  /// Shown when a value is not available.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get commonNotAvailable;

  /// The user's registration code on the profile; {code} is the code.
  ///
  /// In en, this message translates to:
  /// **'ID: {code}'**
  String profileIdLabel(String code);

  /// Account verification badge / statistic label (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileVerified;

  /// Account verification badge (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get profileUnverified;

  /// Profile statistic label: number of reports (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get profileStatReports;

  /// Profile statistic label: number of days since the user registered (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Days Active'**
  String get profileDaysActive;

  /// Section header on the profile.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get profileAccountSettings;

  /// Snackbar after enabling biometric login from the profile.
  ///
  /// In en, this message translates to:
  /// **'Biometrics enabled!'**
  String get profileBiometricsEnabled;

  /// Snackbar when changing biometric login fails.
  ///
  /// In en, this message translates to:
  /// **'Could not change biometric login'**
  String get profileBiometricChangeFailed;

  /// Snackbar when syncing offline data from the profile.
  ///
  /// In en, this message translates to:
  /// **'Syncing offline data...'**
  String get profileSyncingOffline;

  /// Snackbar after syncing offline data.
  ///
  /// In en, this message translates to:
  /// **'Sync complete!'**
  String get profileSyncComplete;

  /// Profile menu item that opens the chat.
  ///
  /// In en, this message translates to:
  /// **'Support Chat'**
  String get profileSupportChat;

  /// Button that opens the SOS sheet.
  ///
  /// In en, this message translates to:
  /// **'SOS / Emergency Call'**
  String get profileSosButton;

  /// Title of the SOS bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'SOS Emergency'**
  String get sosTitle;

  /// Explanation at the top of the SOS sheet.
  ///
  /// In en, this message translates to:
  /// **'Call for help directly. This does not send an alert through the app.'**
  String get sosBody;

  /// SOS option that calls the national emergency number; {phone} is e.g. 112.
  ///
  /// In en, this message translates to:
  /// **'Call Emergency ({phone})'**
  String sosCallEmergency(String phone);

  /// Subtitle of the national emergency call option.
  ///
  /// In en, this message translates to:
  /// **'National emergency number'**
  String get sosNationalNumber;

  /// Shown in the SOS sheet when emergency contacts fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your contacts. Check your connection and try again.'**
  String get sosContactsLoadError;

  /// Shown in the SOS sheet when the user has no contacts.
  ///
  /// In en, this message translates to:
  /// **'No personal emergency contacts saved yet. Add them under Emergency Contacts.'**
  String get sosNoContacts;

  /// SOS option that calls one of the user's contacts; {name} is the contact's name.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String sosCallContact(String name);

  /// Subtitle of a contact in the SOS sheet; {role} e.g. 'Brother', {phone} the number.
  ///
  /// In en, this message translates to:
  /// **'{role} · {phone}'**
  String sosContactSubtitle(String role, String phone);

  /// Snackbar when the dialer cannot be opened; {phone} is the number.
  ///
  /// In en, this message translates to:
  /// **'Could not open the phone app. Dial {phone}.'**
  String sosDialFailed(String phone);

  /// Shown on the chat screen when signed out.
  ///
  /// In en, this message translates to:
  /// **'Please login to chat'**
  String get chatLoginRequired;

  /// Shown when chat messages fail to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load messages.'**
  String get chatLoadError;

  /// Name shown for the user's own chat messages.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get chatMe;

  /// Snackbar when sending too many messages; {reason} is the server's (English) reason.
  ///
  /// In en, this message translates to:
  /// **'{reason}. Please wait a moment.'**
  String chatRateLimited(String reason);

  /// Snackbar when a chat message fails to send; {error} is the error description.
  ///
  /// In en, this message translates to:
  /// **'Message not sent. {error}'**
  String chatSendFailed(String error);

  /// Shown in the chat screen when there are no messages yet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmpty;

  /// Placeholder in the chat message composer.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get chatComposerHint;

  /// Validation error for an empty contact name.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get contactsNameRequired;

  /// Validation error for a contact name over 100 characters.
  ///
  /// In en, this message translates to:
  /// **'Name is too long'**
  String get contactsNameTooLong;

  /// Validation error for a phone number with letters.
  ///
  /// In en, this message translates to:
  /// **'Use digits only (optionally starting with +)'**
  String get contactsPhoneDigitsOnly;

  /// Validation error for a phone number with the wrong length.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get contactsPhoneInvalid;

  /// Snackbar when the dialer cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not launch phone app'**
  String get contactsLaunchPhoneFailed;

  /// Snackbar when the SMS app cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not launch SMS app'**
  String get contactsLaunchSmsFailed;

  /// Snackbar after adding a contact.
  ///
  /// In en, this message translates to:
  /// **'Contact added successfully'**
  String get contactsAdded;

  /// Snackbar after editing a contact.
  ///
  /// In en, this message translates to:
  /// **'Contact updated successfully'**
  String get contactsUpdated;

  /// Title of the delete contact dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete contact?'**
  String get contactsDeleteTitle;

  /// Body of the delete contact dialog; {name} is the contact name.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from your emergency contacts?'**
  String contactsDeleteBody(String name);

  /// Snackbar after deleting a contact.
  ///
  /// In en, this message translates to:
  /// **'Contact deleted'**
  String get contactsDeleted;

  /// Title of the emergency contacts screen.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contacts'**
  String get contactsTitle;

  /// Tooltip of the add contact button.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get contactsAddTooltip;

  /// Search hint on the contacts screen.
  ///
  /// In en, this message translates to:
  /// **'Search name, LGA, or role'**
  String get contactsSearchHint;

  /// Empty state of the contacts list.
  ///
  /// In en, this message translates to:
  /// **'No contacts found'**
  String get contactsEmpty;

  /// Floating button that calls 112 (keep the number).
  ///
  /// In en, this message translates to:
  /// **'Emergency 112'**
  String get contactsEmergencyButton;

  /// Tooltip of a contact's actions menu.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get contactsMoreActions;

  /// Title of the contact form when editing.
  ///
  /// In en, this message translates to:
  /// **'Edit Emergency Contact'**
  String get contactsEditTitle;

  /// Title of the contact form when adding.
  ///
  /// In en, this message translates to:
  /// **'Add Emergency Contact'**
  String get contactsAddTitle;

  /// Label of the required name field (asterisk = required).
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get contactsNameLabel;

  /// Label of the contact's role field (e.g. 'Brother', 'Village head').
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get contactsRoleLabel;

  /// Label of the required phone field (asterisk = required).
  ///
  /// In en, this message translates to:
  /// **'Phone *'**
  String get contactsPhoneLabel;

  /// Label of the organization field.
  ///
  /// In en, this message translates to:
  /// **'Organization (Optional)'**
  String get contactsOrganizationLabel;

  /// Label of the LGA field.
  ///
  /// In en, this message translates to:
  /// **'LGA (Optional)'**
  String get contactsLgaLabel;

  /// Label of the category dropdown.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get contactsCategoryLabel;

  /// Submit button of the add contact form (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get contactsAdd;

  /// Contacts category filter chip showing all contacts.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get contactsFilterAll;

  /// Contacts category filter chip.
  ///
  /// In en, this message translates to:
  /// **'Coordinators'**
  String get contactsFilterCoordinators;

  /// Contact category name.
  ///
  /// In en, this message translates to:
  /// **'Coordinator'**
  String get contactsCategoryCoordinator;

  /// Contact category name.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get contactsCategoryEmergency;

  /// Contact category name (agricultural extension workers).
  ///
  /// In en, this message translates to:
  /// **'Agri-Extension'**
  String get contactsCategoryAgriExtension;

  /// Contact category name.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get contactsCategoryOther;

  /// Subtitle of a contact: role and Local Government Area.
  ///
  /// In en, this message translates to:
  /// **'{role} • {lga}'**
  String contactsRoleAndLga(String role, String lga);

  /// Knowledge base category filter chip showing all guides (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get knowledgeCategoryAll;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get knowledgeCategoryFlood;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get knowledgeCategoryFire;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Erosion'**
  String get knowledgeCategoryErosion;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Storm'**
  String get knowledgeCategoryStorm;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Extreme Heat'**
  String get knowledgeCategoryExtremeHeat;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Earthquake'**
  String get knowledgeCategoryEarthquake;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Disease'**
  String get knowledgeCategoryDisease;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get knowledgeCategoryConflict;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get knowledgeCategoryAccident;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get knowledgeCategorySafety;

  /// Knowledge base guide category (max ~14 chars).
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get knowledgeCategoryGeneral;

  /// Generic tag chip on a guide card (upper case, max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'GUIDE'**
  String get knowledgeTagGuide;

  /// Error when knowledge base guides fail to load.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch guides. Please try again.'**
  String get knowledgeLoadError;

  /// Title of the hazard guides screen.
  ///
  /// In en, this message translates to:
  /// **'Hazard Guides'**
  String get knowledgeGuidesTitle;

  /// Small caption under the hazard guides title (upper case).
  ///
  /// In en, this message translates to:
  /// **'KNOWLEDGE BASE'**
  String get knowledgeBaseCaption;

  /// Search hint on the hazard guides screen.
  ///
  /// In en, this message translates to:
  /// **'Search guides, signs, or hazards...'**
  String get knowledgeGuidesSearchHint;

  /// Empty state for a guide category.
  ///
  /// In en, this message translates to:
  /// **'No guides found for this category'**
  String get knowledgeNoGuidesCategory;

  /// Empty state for a guide search; {query} is the search text.
  ///
  /// In en, this message translates to:
  /// **'No guides match \"{query}\"'**
  String knowledgeNoGuidesMatch(String query);

  /// Shown for a guide without a title.
  ///
  /// In en, this message translates to:
  /// **'No Title'**
  String get knowledgeNoTitle;

  /// Subtitle of a guide without a category.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get knowledgeSubtitleManual;

  /// Error when the external news feed fails to load.
  ///
  /// In en, this message translates to:
  /// **'Failed to load news. Please try again.'**
  String get knowledgeNewsLoadError;

  /// Title of the knowledge base screen.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get knowledgeBaseTitle;

  /// Search hint on the knowledge base screen.
  ///
  /// In en, this message translates to:
  /// **'Search guides, hazards, or contacts...'**
  String get knowledgeBaseSearchHint;

  /// Banner title on the knowledge base when offline.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode Active'**
  String get knowledgeOfflineActive;

  /// Banner title on the knowledge base when online.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode Available'**
  String get knowledgeOfflineAvailable;

  /// Banner text when showing cached guides offline.
  ///
  /// In en, this message translates to:
  /// **'Using cached data'**
  String get knowledgeUsingCache;

  /// Banner text when guides are available offline.
  ///
  /// In en, this message translates to:
  /// **'Content downloaded successfully'**
  String get knowledgeContentDownloaded;

  /// Section heading on the knowledge base.
  ///
  /// In en, this message translates to:
  /// **'Featured Guides'**
  String get knowledgeFeaturedGuides;

  /// Empty state of the featured guides.
  ///
  /// In en, this message translates to:
  /// **'No guides available'**
  String get knowledgeNoGuides;

  /// Knowledge base category tile title.
  ///
  /// In en, this message translates to:
  /// **'Hazard ID Guides'**
  String get knowledgeHazardIdGuides;

  /// Knowledge base category tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Identify local threats'**
  String get knowledgeHazardIdGuidesDesc;

  /// Knowledge base category tile title.
  ///
  /// In en, this message translates to:
  /// **'Fire Response'**
  String get knowledgeFireResponse;

  /// Knowledge base category tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Wildfire protocols'**
  String get knowledgeFireResponseDesc;

  /// Knowledge base category tile title.
  ///
  /// In en, this message translates to:
  /// **'Flood Readiness'**
  String get knowledgeFloodReadiness;

  /// Knowledge base category tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Water & Storms'**
  String get knowledgeFloodReadinessDesc;

  /// Knowledge base tile that opens emergency contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts Directory'**
  String get knowledgeContactsDirectory;

  /// Subtitle of the contacts directory tile.
  ///
  /// In en, this message translates to:
  /// **'Emergency services'**
  String get knowledgeContactsDirectoryDesc;

  /// Section heading for the external news feed.
  ///
  /// In en, this message translates to:
  /// **'External News & Updates'**
  String get knowledgeExternalNews;

  /// Empty state of the news feed.
  ///
  /// In en, this message translates to:
  /// **'No recent news updates found.'**
  String get knowledgeNoNews;

  /// App bar title of a guide.
  ///
  /// In en, this message translates to:
  /// **'Guide Detail'**
  String get knowledgeDetailTitle;

  /// Snackbar after bookmarking a guide.
  ///
  /// In en, this message translates to:
  /// **'Guide bookmarked'**
  String get knowledgeBookmarked;

  /// Snackbar after removing a bookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get knowledgeBookmarkRemoved;

  /// Snackbar when read-aloud has no text.
  ///
  /// In en, this message translates to:
  /// **'No text to speak'**
  String get knowledgeNoTextToSpeak;

  /// Snackbar when read-aloud fails.
  ///
  /// In en, this message translates to:
  /// **'Text-to-speech is unavailable. Please try again.'**
  String get knowledgeTtsUnavailable;

  /// When a guide was last updated; {date} like '3 Mar 2026' (or a free-text date).
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String knowledgeUpdatedOn(String date);

  /// Shown when a guide has no update date.
  ///
  /// In en, this message translates to:
  /// **'Updated recently'**
  String get knowledgeUpdatedRecently;

  /// Estimated reading time of a guide.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min read} other{{count} min read}}'**
  String knowledgeReadTime(int count);

  /// Shown when a guide has no content.
  ///
  /// In en, this message translates to:
  /// **'Detailed content coming soon.'**
  String get knowledgeContentComingSoon;

  /// Section heading under a guide.
  ///
  /// In en, this message translates to:
  /// **'Related Topics'**
  String get knowledgeRelatedTopics;

  /// Empty state of related topics.
  ///
  /// In en, this message translates to:
  /// **'No related topics found.'**
  String get knowledgeNoRelated;

  /// Title used when sharing a guide without a title.
  ///
  /// In en, this message translates to:
  /// **'CRADI Guide'**
  String get knowledgeShareDefaultTitle;

  /// Text shared from a guide; {content} is the guide's title, description and content.
  ///
  /// In en, this message translates to:
  /// **'{content}\n\nShared via CRADI Early Warning App'**
  String knowledgeShareText(String content);

  /// Subject of the support email opened from Help & Support.
  ///
  /// In en, this message translates to:
  /// **'CRADI App Support Request'**
  String get helpSupportEmailSubject;

  /// Pre-filled body of the support email (ends with a blank line).
  ///
  /// In en, this message translates to:
  /// **'Please describe your issue:\n\n'**
  String get helpSupportEmailBody;

  /// Snackbar when no email app is installed; {email} is the support address.
  ///
  /// In en, this message translates to:
  /// **'No email app found. Contact {email}'**
  String helpNoEmailApp(String email);

  /// Section heading on Help & Support.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get helpFaqTitle;

  /// FAQ question.
  ///
  /// In en, this message translates to:
  /// **'How do I report a hazard?'**
  String get helpFaqReportQ;

  /// FAQ answer; "Report" is the bottom tab name (navReport).
  ///
  /// In en, this message translates to:
  /// **'Navigate to the \"Report\" tab or tap the \"+\" button on the dashboard. Select the hazard type, add photos, and submit your report. You can dictate the description with the microphone button instead of typing.'**
  String get helpFaqReportA;

  /// FAQ question.
  ///
  /// In en, this message translates to:
  /// **'What do the alert colors mean?'**
  String get helpFaqColorsQ;

  /// FAQ answer.
  ///
  /// In en, this message translates to:
  /// **'Red indicates high severity (immediate danger), Orange is medium, and Yellow is low. Blue typically indicates water-related hazards like floods.'**
  String get helpFaqColorsA;

  /// FAQ question.
  ///
  /// In en, this message translates to:
  /// **'Can I report without internet?'**
  String get helpFaqOfflineQ;

  /// FAQ answer; "Offline Mode" is the Settings switch name (settingsOfflineMode).
  ///
  /// In en, this message translates to:
  /// **'Yes! Use \"Offline Mode\" in Settings. Your reports will be saved locally and can be synced when you go online.'**
  String get helpFaqOfflineA;

  /// FAQ question.
  ///
  /// In en, this message translates to:
  /// **'How do I verify other reports?'**
  String get helpFaqVerifyQ;

  /// FAQ answer; "Alerts" is the bottom tab name (navAlerts).
  ///
  /// In en, this message translates to:
  /// **'Go to \"Alerts\" and look for pending reports nearby. You can confirm or reject them based on your observation.'**
  String get helpFaqVerifyA;

  /// Heading above the contact support button.
  ///
  /// In en, this message translates to:
  /// **'Still need help?'**
  String get helpStillNeedHelp;

  /// Snackbar after marking all notifications read.
  ///
  /// In en, this message translates to:
  /// **'All notifications marked as read'**
  String get notificationsAllRead;

  /// Title of the clear notifications dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get notificationsClearAll;

  /// Body of the clear notifications dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all notifications?'**
  String get notificationsClearConfirm;

  /// Menu item on the notifications screen.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationsMarkAllRead;

  /// Menu item on the notifications screen.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get notificationsClearAllMenu;

  /// Empty state of the notifications screen.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationsEmpty;

  /// Title of a notification without a title.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notificationsDefaultTitle;

  /// Button to dispute (vote against) a report (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get voteDispute;

  /// Snackbar after disputing a report.
  ///
  /// In en, this message translates to:
  /// **'Dispute recorded. Staff will review the report.'**
  String get voteDisputeRecorded;

  /// Snackbar after confirming a report.
  ///
  /// In en, this message translates to:
  /// **'Report confirmed. Thank you!'**
  String get voteConfirmedThanks;

  /// CSV export option.
  ///
  /// In en, this message translates to:
  /// **'Rejected only'**
  String get exportRejectedOnly;

  /// Snackbar while the CSV export is generated.
  ///
  /// In en, this message translates to:
  /// **'Preparing export…'**
  String get exportPreparing;

  /// Snackbar on web after copying the CSV export.
  ///
  /// In en, this message translates to:
  /// **'CSV copied to the clipboard.'**
  String get exportCopied;

  /// Snackbar after saving the CSV export; {path} is the file path.
  ///
  /// In en, this message translates to:
  /// **'Report saved to {path}'**
  String exportSavedTo(String path);

  /// Subject used when sharing the CSV export.
  ///
  /// In en, this message translates to:
  /// **'CRADI reports export'**
  String get exportShareSubject;

  /// Snackbar when sharing the export fails; {path} is the file path.
  ///
  /// In en, this message translates to:
  /// **'Could not open the share sheet. The report is saved to {path}'**
  String exportShareFailed(String path);

  /// Status badge on the verify report screen (upper case).
  ///
  /// In en, this message translates to:
  /// **'VERIFIED'**
  String get statusBadgeVerified;

  /// Status badge on the verify report screen (upper case).
  ///
  /// In en, this message translates to:
  /// **'APPROVED'**
  String get statusBadgeApproved;

  /// Status badge on the verify report screen (upper case).
  ///
  /// In en, this message translates to:
  /// **'REJECTED'**
  String get statusBadgeRejected;

  /// Status badge on the verify report screen (upper case).
  ///
  /// In en, this message translates to:
  /// **'PENDING VERIFICATION'**
  String get statusBadgePending;

  /// App bar title of the verify report screen.
  ///
  /// In en, this message translates to:
  /// **'Verify Report'**
  String get verificationDetailTitle;

  /// Shown when a report has no submission time.
  ///
  /// In en, this message translates to:
  /// **'Unknown time'**
  String get verificationDetailUnknownTime;

  /// Shown when a report has no location text.
  ///
  /// In en, this message translates to:
  /// **'No location details'**
  String get verificationDetailNoLocation;

  /// Shown instead of the map when a report has no coordinates.
  ///
  /// In en, this message translates to:
  /// **'No map location available'**
  String get verificationDetailNoMap;

  /// Heading of the vote section.
  ///
  /// In en, this message translates to:
  /// **'Can you confirm this report?'**
  String get verificationDetailQuestion;

  /// Instructions of the vote section.
  ///
  /// In en, this message translates to:
  /// **'Please verify if you have observed this hazard in the reported location.'**
  String get verificationDetailInstructions;

  /// Hint of the vote comment field.
  ///
  /// In en, this message translates to:
  /// **'Add details about what you see...'**
  String get verificationDetailCommentHint;

  /// Button confirming a report (max ~16 chars).
  ///
  /// In en, this message translates to:
  /// **'I Can Confirm'**
  String get verificationDetailConfirm;

  /// Tooltip of the button that opens the verification request form.
  ///
  /// In en, this message translates to:
  /// **'Request verification'**
  String get verificationListRequestTooltip;

  /// Empty state of the verification queue.
  ///
  /// In en, this message translates to:
  /// **'No reports pending verification'**
  String get verificationListEmpty;

  /// Snackbar after submitting a verification request.
  ///
  /// In en, this message translates to:
  /// **'Verification request submitted successfully'**
  String get verificationRequestSubmitted;

  /// Title of the verification request form.
  ///
  /// In en, this message translates to:
  /// **'Request Verification'**
  String get verificationRequestTitle;

  /// Hint of the description field in the verification request form.
  ///
  /// In en, this message translates to:
  /// **'Describe what needs verification...'**
  String get verificationRequestDescriptionHint;

  /// Submit button of the verification request form.
  ///
  /// In en, this message translates to:
  /// **'Submit Request'**
  String get verificationRequestSubmit;

  /// Title of the dialog asking why a report is disputed.
  ///
  /// In en, this message translates to:
  /// **'Dispute report?'**
  String get disputeDialogTitle;

  /// Label of the dispute reason field.
  ///
  /// In en, this message translates to:
  /// **'What is wrong with this report? (required)'**
  String get disputeDialogLabel;

  /// Snackbar after staff rejected a report.
  ///
  /// In en, this message translates to:
  /// **'Report rejected.'**
  String get staffRejected;

  /// Heading of the staff approve/reject/reopen box on a report.
  ///
  /// In en, this message translates to:
  /// **'Staff actions'**
  String get staffActionsTitle;

  /// Snackbar after staff approved a report.
  ///
  /// In en, this message translates to:
  /// **'Report approved.'**
  String get staffApproved;

  /// Staff button approving a report (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get staffApprove;

  /// Snackbar after staff reopened a report.
  ///
  /// In en, this message translates to:
  /// **'Report reopened for verification.'**
  String get staffReopened;

  /// Title of the reject reason dialog.
  ///
  /// In en, this message translates to:
  /// **'Reject report?'**
  String get staffRejectTitle;

  /// Label of the rejection reason field.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get staffRejectReasonLabel;

  /// Hint of the rejection reason field.
  ///
  /// In en, this message translates to:
  /// **'Shown to the reporter'**
  String get staffRejectReasonHint;

  /// Error when the rejection reason is empty.
  ///
  /// In en, this message translates to:
  /// **'Please give a reason.'**
  String get staffRejectReasonRequired;

  /// Error in the peer verifications box on a report.
  ///
  /// In en, this message translates to:
  /// **'Could not load peer verifications.'**
  String get verificationsLoadError;

  /// Heading of the peer votes box on a report.
  ///
  /// In en, this message translates to:
  /// **'Peer verifications'**
  String get verificationsTitle;

  /// Empty state of the peer votes box.
  ///
  /// In en, this message translates to:
  /// **'No peer votes yet.'**
  String get verificationsNone;

  /// Vote summary; {confirmed} confirmations, {disputed} disputes.
  ///
  /// In en, this message translates to:
  /// **'{confirmed} confirmed · {disputed} disputed'**
  String verificationsSummary(int confirmed, int disputed);

  /// Shown instead of the voter's name for the user's own vote.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get verificationsYou;

  /// Shown when a voter's name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Peer verifier'**
  String get verificationsPeerVerifier;

  /// One peer vote; {kind} is confirmed/disputed (do not translate the select keys), {who} the voter.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, confirmed{Confirmed by {who}} other{Disputed by {who}}}'**
  String verificationsVoteBy(String kind, String who);

  /// One peer vote with its time; {kind} confirmed/disputed (keep keys), {who} voter, {date} like 'Mar 5, 3:05 PM'.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, confirmed{Confirmed by {who} · {date}} other{Disputed by {who} · {date}}}'**
  String verificationsVoteByAt(String kind, String who, String date);

  /// Heading of the peer vote box on a report.
  ///
  /// In en, this message translates to:
  /// **'Can you verify this report?'**
  String get voteQuestion;

  /// Error on the admin dashboard.
  ///
  /// In en, this message translates to:
  /// **'Could not load dashboard counts'**
  String get adminCountsError;

  /// Error details on the admin dashboard.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and permissions, then retry.'**
  String get adminCountsErrorBody;

  /// System health row label on the admin dashboard.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get adminHealthDatabase;

  /// System health: number of active alerts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} active}}'**
  String adminHealthActiveCount(int count);

  /// System health: total number of reports.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 report} other{{count} reports}}'**
  String adminHealthReportCount(int count);

  /// Snackbar after sending a staff alert.
  ///
  /// In en, this message translates to:
  /// **'Alert broadcast successfully'**
  String get adminAlertBroadcastSuccess;

  /// Snackbar when sending a staff alert fails; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Failed to send alert: {error}'**
  String adminAlertSendFailed(String error);

  /// Snackbar when deactivating an alert fails.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss alert.'**
  String get adminAlertDismissFailed;

  /// Section heading of the alert broadcast form.
  ///
  /// In en, this message translates to:
  /// **'Compose Alert'**
  String get adminAlertCompose;

  /// Label of the target LGA selector.
  ///
  /// In en, this message translates to:
  /// **'Target Area'**
  String get adminAlertTargetArea;

  /// Target option sending an alert to every LGA.
  ///
  /// In en, this message translates to:
  /// **'All Areas'**
  String get adminAlertAllAreas;

  /// Label of the alert title field.
  ///
  /// In en, this message translates to:
  /// **'Alert Title'**
  String get adminAlertTitleLabel;

  /// Validation error for a required alert field.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get adminAlertRequired;

  /// Label of the alert message field.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get adminAlertMessageLabel;

  /// Button that sends a staff alert.
  ///
  /// In en, this message translates to:
  /// **'Broadcast Alert'**
  String get adminAlertBroadcastButton;

  /// Error loading active alerts in the admin screen.
  ///
  /// In en, this message translates to:
  /// **'Could not load alerts. You may not have permission to view them.'**
  String get adminAlertsLoadError;

  /// Tooltip of the button that deactivates an alert.
  ///
  /// In en, this message translates to:
  /// **'Dismiss alert'**
  String get adminAlertDismissTooltip;

  /// Title of the delete guide dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Guide'**
  String get adminGuideDeleteTitle;

  /// Body of the delete guide dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this guide? This cannot be undone.'**
  String get adminGuideDeleteBody;

  /// Error when deleting a guide is refused.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to delete this guide, or it was already removed.'**
  String get adminGuideDeleteDenied;

  /// Error when deleting a guide fails.
  ///
  /// In en, this message translates to:
  /// **'Could not delete guide. Check your connection and try again.'**
  String get adminGuideDeleteFailed;

  /// Snackbar after deleting a guide.
  ///
  /// In en, this message translates to:
  /// **'Guide deleted'**
  String get adminGuideDeleted;

  /// Floating button that adds a knowledge base guide.
  ///
  /// In en, this message translates to:
  /// **'Add Guide'**
  String get adminGuideAdd;

  /// Error on the knowledge management screen.
  ///
  /// In en, this message translates to:
  /// **'Error loading guides'**
  String get adminGuidesLoadError;

  /// Empty state of the knowledge management screen.
  ///
  /// In en, this message translates to:
  /// **'No guides found'**
  String get adminGuidesEmpty;

  /// Button in the empty state.
  ///
  /// In en, this message translates to:
  /// **'Add the first guide'**
  String get adminGuideAddFirst;

  /// Menu item editing a guide.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get adminGuideEditMenu;

  /// Menu item deleting a guide.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get adminGuideDeleteMenu;

  /// Snackbar after editing a guide.
  ///
  /// In en, this message translates to:
  /// **'Guide updated'**
  String get adminGuideUpdated;

  /// Snackbar after creating a guide.
  ///
  /// In en, this message translates to:
  /// **'Guide created'**
  String get adminGuideCreated;

  /// Title of the guide editor when editing.
  ///
  /// In en, this message translates to:
  /// **'Edit Guide'**
  String get adminGuideEditTitle;

  /// Title of the guide editor when creating.
  ///
  /// In en, this message translates to:
  /// **'New Guide'**
  String get adminGuideNewTitle;

  /// Label of the guide category dropdown.
  ///
  /// In en, this message translates to:
  /// **'Category / Hazard Type'**
  String get adminGuideCategoryLabel;

  /// Label of the guide title field.
  ///
  /// In en, this message translates to:
  /// **'Guide Title'**
  String get adminGuideTitleLabel;

  /// Label of the guide source field; NEMA and WHO are organisations.
  ///
  /// In en, this message translates to:
  /// **'Source (e.g. NEMA, WHO)'**
  String get adminGuideSourceLabel;

  /// Label of the guide content field.
  ///
  /// In en, this message translates to:
  /// **'Content (Markdown supported)'**
  String get adminGuideContentLabel;

  /// Submit button when editing a guide.
  ///
  /// In en, this message translates to:
  /// **'Update Guide'**
  String get adminGuideUpdate;

  /// Submit button when creating a guide.
  ///
  /// In en, this message translates to:
  /// **'Create Guide'**
  String get adminGuideCreate;

  /// Error on the admin reports overview.
  ///
  /// In en, this message translates to:
  /// **'Could not load reports. You may not have permission to view them.'**
  String get adminReportsLoadError;

  /// Label of the optional rejection reason in the admin reports screen.
  ///
  /// In en, this message translates to:
  /// **'Reason (recommended)'**
  String get adminReportsRejectReasonLabel;

  /// Hint of the rejection reason field.
  ///
  /// In en, this message translates to:
  /// **'Why is this report being rejected?'**
  String get adminReportsRejectReasonHint;

  /// Snackbar when changing a report status fails; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Could not update report status: {error}'**
  String adminReportsStatusUpdateFailed(String error);

  /// Snackbar after reopening a report.
  ///
  /// In en, this message translates to:
  /// **'Report reopened for verification'**
  String get adminReportsReopened;

  /// Snackbar after changing a report status; {status} is the new status name.
  ///
  /// In en, this message translates to:
  /// **'Report marked as {status}'**
  String adminReportsMarkedAs(String status);

  /// Label in the admin report details.
  ///
  /// In en, this message translates to:
  /// **'Date/Time'**
  String get adminReportsDateTime;

  /// Label of the Local Government Area in the admin report details.
  ///
  /// In en, this message translates to:
  /// **'LGA'**
  String get adminReportsLga;

  /// Label in the admin report details.
  ///
  /// In en, this message translates to:
  /// **'Location Details'**
  String get adminReportsLocationDetails;

  /// Label in the admin report details.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason'**
  String get adminReportsRejectionReason;

  /// Shown when a rejected report has no reason.
  ///
  /// In en, this message translates to:
  /// **'No reason given'**
  String get adminReportsNoReason;

  /// Section label for report photos.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get adminReportsImages;

  /// Admin action setting a report to verified.
  ///
  /// In en, this message translates to:
  /// **'Mark Verified'**
  String get adminReportsMarkVerified;

  /// Admin action resetting a report to pending.
  ///
  /// In en, this message translates to:
  /// **'Reopen (pending)'**
  String get adminReportsReopen;

  /// Admin menu action resetting a report to pending.
  ///
  /// In en, this message translates to:
  /// **'Reopen (reset to pending)'**
  String get adminReportsReopenReset;

  /// Empty state of the admin reports overview.
  ///
  /// In en, this message translates to:
  /// **'No reports found'**
  String get adminReportsEmpty;

  /// Error at the end of the admin reports list.
  ///
  /// In en, this message translates to:
  /// **'Could not load more. Tap to retry.'**
  String get adminReportsLoadMoreError;

  /// Button loading more reports.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get adminReportsLoadMore;

  /// Error on the user management screen.
  ///
  /// In en, this message translates to:
  /// **'Could not load users. You may not have permission to view them.'**
  String get adminUsersLoadError;

  /// Empty state of the user management screen.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get adminUsersEmpty;

  /// Error when a user update is refused.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change this user.'**
  String get adminUsersNoPermission;

  /// Error when a user update fails.
  ///
  /// In en, this message translates to:
  /// **'Update failed. Please try again.'**
  String get adminUsersUpdateFailed;

  /// Snackbar after approving a user.
  ///
  /// In en, this message translates to:
  /// **'User approved'**
  String get adminUsersApproved;

  /// Snackbar after revoking a user's approval.
  ///
  /// In en, this message translates to:
  /// **'User rejected'**
  String get adminUsersRejected;

  /// Title of the change role dialog.
  ///
  /// In en, this message translates to:
  /// **'Change Role'**
  String get adminUsersChangeRole;

  /// Snackbar after changing a role.
  ///
  /// In en, this message translates to:
  /// **'Role updated. It takes effect once the user is approved.'**
  String get adminUsersRoleUpdated;

  /// Dialog button applying a change (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get adminUsersApply;

  /// Title of the change location dialog.
  ///
  /// In en, this message translates to:
  /// **'Change location'**
  String get adminUsersChangeLocationTitle;

  /// Snackbar after moving a user; {ward}, {lga} and {state} are place names.
  ///
  /// In en, this message translates to:
  /// **'Location updated to {ward}, {lga}, {state}'**
  String adminUsersLocationUpdated(String ward, String lga, String state);

  /// Snackbar after disabling a user.
  ///
  /// In en, this message translates to:
  /// **'User disabled'**
  String get adminUsersDisabled;

  /// Snackbar after re-enabling a user.
  ///
  /// In en, this message translates to:
  /// **'User re-enabled'**
  String get adminUsersReenabled;

  /// Search hint on the user management screen.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email…'**
  String get adminUsersSearchHint;

  /// Role filter chip showing every role.
  ///
  /// In en, this message translates to:
  /// **'All Roles'**
  String get adminUsersAllRoles;

  /// Caption when the pending approvals filter is on.
  ///
  /// In en, this message translates to:
  /// **'Showing Pending Approvals'**
  String get adminUsersShowingPending;

  /// Caption when the approved users filter is on.
  ///
  /// In en, this message translates to:
  /// **'Showing Approved Users'**
  String get adminUsersShowingApproved;

  /// Chip on a user awaiting approval (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get adminUsersPendingChip;

  /// Menu action approving a user.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get adminUsersApproveMenu;

  /// Menu action revoking a user's approval.
  ///
  /// In en, this message translates to:
  /// **'Revoke access'**
  String get adminUsersRevokeMenu;

  /// Menu action changing a user's role.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get adminUsersChangeRoleMenu;

  /// Menu action changing a user's location.
  ///
  /// In en, this message translates to:
  /// **'Change location'**
  String get adminUsersChangeLocationMenu;

  /// Menu action re-enabling a user.
  ///
  /// In en, this message translates to:
  /// **'Re-enable user'**
  String get adminUsersReenableMenu;

  /// Menu action disabling a user.
  ///
  /// In en, this message translates to:
  /// **'Disable user'**
  String get adminUsersDisableMenu;

  /// Onboarding page 1 text.
  ///
  /// In en, this message translates to:
  /// **'Early Warning and Emergency Response system for your community'**
  String get onboardingWelcomeBody;

  /// Onboarding page 2 title.
  ///
  /// In en, this message translates to:
  /// **'Monitor Hazards in Real-Time'**
  String get onboardingMonitorTitle;

  /// Onboarding page 2 text.
  ///
  /// In en, this message translates to:
  /// **'Report emergencies, track hazards, and keep your community safe'**
  String get onboardingMonitorBody;

  /// Onboarding page 3 text.
  ///
  /// In en, this message translates to:
  /// **'Create an account and start protecting your community today'**
  String get onboardingJoinBody;

  /// Onboarding button skipping the introduction (max ~10 chars).
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// Onboarding button to the next page (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Tagline on the splash screen under the EWER logo.
  ///
  /// In en, this message translates to:
  /// **'Early Warning & Emergency Response'**
  String get splashTagline;

  /// Banner at the top of the app when offline.
  ///
  /// In en, this message translates to:
  /// **'Offline - Some features may be unavailable'**
  String get connectivityOfflineBanner;

  /// Title when a linked report does not exist.
  ///
  /// In en, this message translates to:
  /// **'Report not found'**
  String get routeReportNotFound;

  /// Button on the report-not-found screen.
  ///
  /// In en, this message translates to:
  /// **'View reports'**
  String get routeViewReports;

  /// Title when a linked alert does not exist.
  ///
  /// In en, this message translates to:
  /// **'Alert not found'**
  String get routeAlertNotFound;

  /// Button on the alert-not-found screen.
  ///
  /// In en, this message translates to:
  /// **'View alerts'**
  String get routeViewAlerts;

  /// Title of the unknown-page screen.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get routeNotFoundTitle;

  /// Body of the unknown-page screen.
  ///
  /// In en, this message translates to:
  /// **'The page you were looking for does not exist.'**
  String get routeNotFoundBody;

  /// Retry button on the load-failed screen.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get routeTryAgain;

  /// Button going back to the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get routeGoHome;

  /// Title when a linked item failed to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load'**
  String get routeLoadFailedTitle;

  /// Body when a linked item failed to load.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get routeLoadFailedBody;

  /// Body when a linked item is missing.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed, or you may not have access to it.'**
  String get routeMissingBody;

  /// Snackbar when the app store cannot be opened from the update screen.
  ///
  /// In en, this message translates to:
  /// **'Could not open the store. Please update the app from your app store.'**
  String get forceUpdateStoreFailed;

  /// Title of the blocking update screen.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get forceUpdateTitle;

  /// Default text of the blocking update screen. EWER is the app name.
  ///
  /// In en, this message translates to:
  /// **'Please update the EWER app to continue.'**
  String get forceUpdateDefaultMessage;

  /// Minimum supported app version on the update screen; {version} like 1.2.0.
  ///
  /// In en, this message translates to:
  /// **'Minimum version: {version}'**
  String forceUpdateMinVersion(String version);

  /// Button opening the app store (max ~12 chars).
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get forceUpdateButton;

  /// Button re-checking whether an update is needed.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get forceUpdateCheckAgain;

  /// Label of a required form field; {label} is the field name, the asterisk marks it as required.
  ///
  /// In en, this message translates to:
  /// **'{label} *'**
  String formFieldRequiredLabel(String label);

  /// Label of the LGA dropdown.
  ///
  /// In en, this message translates to:
  /// **'Local Government Area'**
  String get locationSelectorLgaLabel;

  /// Title of the dialog explaining why location permission is needed.
  ///
  /// In en, this message translates to:
  /// **'Location Access'**
  String get permissionLocationTitle;

  /// Explanation before asking for location permission. EWER is the app name.
  ///
  /// In en, this message translates to:
  /// **'EWER needs your location to accurately pinpoint hazards and alert nearby responders. Your location is only used when you submit a report or use the tactical map.'**
  String get permissionLocationRationale;

  /// Title of the dialog explaining why notification permission is needed.
  ///
  /// In en, this message translates to:
  /// **'Enable Alerts'**
  String get permissionNotificationsTitle;

  /// Explanation before asking for notification permission.
  ///
  /// In en, this message translates to:
  /// **'Get real-time updates about hazards in your area. We only send critical safety alerts and status updates for your reports.'**
  String get permissionNotificationsRationale;

  /// Title of the dialog explaining why photo access is needed.
  ///
  /// In en, this message translates to:
  /// **'Photo Access'**
  String get permissionPhotosTitle;

  /// Explanation before asking for photo access.
  ///
  /// In en, this message translates to:
  /// **'EWER needs access to your photos so you can upload evidence of hazards. We only upload photos you explicitly select.'**
  String get permissionPhotosRationale;

  /// Button declining a permission request for now.
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get permissionNotNow;

  /// Dialog shown when a permission was permanently denied; {reason} is the explanation text.
  ///
  /// In en, this message translates to:
  /// **'{reason}\n\nPlease enable this in your device settings.'**
  String permissionSettingsBody(String reason);

  /// Error when the offline draft limit is reached; {count} is the limit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{You can keep at most {count} unsent reports on this device. Sync or discard some first.}}'**
  String offlineDraftLimit(int count);

  /// Count of nearby reports shown above the Nearby Reports list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 report in your area} other{{count} reports in your area}}'**
  String nearbyReportsInAreaCount(int count);

  /// Copyright footer on the landing screen; {year} is the current year.
  ///
  /// In en, this message translates to:
  /// **'© {year} CRADI. All rights reserved.'**
  String landingCopyright(String year);

  /// Badge on reports sent as a verification request (also replaces their stored placeholder location); max ~22 chars.
  ///
  /// In en, this message translates to:
  /// **'Verification request'**
  String get verificationRequestBadge;

  /// Button on the report details screen that opens the safety guides for the report's hazard.
  ///
  /// In en, this message translates to:
  /// **'Safety guides'**
  String get reportViewSafetyGuides;

  /// Shown after the app signs the user out because their account was deleted by an administrator.
  ///
  /// In en, this message translates to:
  /// **'Your account has been removed, so you have been signed out. Contact your coordinator if you think this is a mistake.'**
  String get authAccountRemoved;

  /// Error on the admin users screen when approving an account that has not confirmed its email or phone number.
  ///
  /// In en, this message translates to:
  /// **'This account has not confirmed its email or phone yet, so it cannot be approved.'**
  String get adminUsersApproveUnconfirmed;

  /// Spoken by a screen reader while a button is in its loading state.
  ///
  /// In en, this message translates to:
  /// **'Submitting, please wait'**
  String get commonSubmittingPleaseWait;

  /// Tooltip on the button that clears a search box.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch;

  /// Tooltip on the eye button that reveals the typed password.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// Tooltip on the eye button that hides the typed password.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// Tooltip on the share button in a knowledge-base guide.
  ///
  /// In en, this message translates to:
  /// **'Share this guide'**
  String get knowledgeShareTooltip;

  /// Tooltip on the bookmark button when the guide is not yet saved.
  ///
  /// In en, this message translates to:
  /// **'Save this guide'**
  String get knowledgeBookmarkAddTooltip;

  /// Tooltip on the bookmark button when the guide is already saved.
  ///
  /// In en, this message translates to:
  /// **'Remove saved guide'**
  String get knowledgeBookmarkRemoveTooltip;

  /// Tooltip on the button that reads a knowledge-base guide aloud.
  ///
  /// In en, this message translates to:
  /// **'Listen to this guide'**
  String get knowledgeListenTooltip;

  /// Screen-reader label for a severity indicator shown only as a colour; {severity} is the severity name.
  ///
  /// In en, this message translates to:
  /// **'Severity: {severity}'**
  String a11ySeverityLabel(String severity);

  /// Screen-reader label for a status badge shown only as a colour; {status} is the status name.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String a11yStatusLabel(String status);

  /// Tooltip / screen-reader label on the SMS button beside an emergency contact; {name} is the contact's name.
  ///
  /// In en, this message translates to:
  /// **'Send a text message to {name}'**
  String contactsSmsTooltip(String name);

  /// Screen-reader label and tooltip on the X that removes an attached photo from a report; {number} is the photo's position, starting at 1.
  ///
  /// In en, this message translates to:
  /// **'Remove photo {number}'**
  String reportRemovePhoto(int number);

  /// Title of an in-app notification about the user's own report changing status.
  ///
  /// In en, this message translates to:
  /// **'Report update'**
  String get notificationReportStatusTitle;

  /// In-app notification body when the user's report is approved. {hazard} is the hazard type.
  ///
  /// In en, this message translates to:
  /// **'Your report ({hazard}) was approved and an alert has been issued.'**
  String notificationReportApproved(String hazard);

  /// In-app notification body when peers verify the user's report. {hazard} is the hazard type.
  ///
  /// In en, this message translates to:
  /// **'Your report ({hazard}) was verified by peers and is awaiting approval.'**
  String notificationReportVerified(String hazard);

  /// In-app notification body when the user's report is rejected. {hazard} is the hazard type.
  ///
  /// In en, this message translates to:
  /// **'Your report ({hazard}) was rejected. Open it for details.'**
  String notificationReportRejected(String hazard);

  /// In-app notification body when the user's report goes back to awaiting peer verification. {hazard} is the hazard type.
  ///
  /// In en, this message translates to:
  /// **'Your report ({hazard}) is awaiting peer verification.'**
  String notificationReportPending(String hazard);

  /// In-app notification body for an alert that carries no message text of its own.
  ///
  /// In en, this message translates to:
  /// **'A new alert was issued for your area.'**
  String get notificationAlertBody;

  /// Filter chip (keep short, max ~10 chars) listing the guides the user bookmarked.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get knowledgeSavedFilter;

  /// Empty state of the Saved filter on the hazard guides screen.
  ///
  /// In en, this message translates to:
  /// **'No saved guides yet. Tap the bookmark on a guide to save it.'**
  String get knowledgeNoSavedGuides;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ha', 'ig', 'pcm', 'yo'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ha':
      return AppLocalizationsHa();
    case 'ig':
      return AppLocalizationsIg();
    case 'pcm':
      return AppLocalizationsPcm();
    case 'yo':
      return AppLocalizationsYo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
