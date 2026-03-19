import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ha.dart';

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
  ];

  /// The application title
  ///
  /// In en, this message translates to:
  /// **'EWER Early Warning'**
  String get appTitle;

  /// Label for monitoring zone header
  ///
  /// In en, this message translates to:
  /// **'Monitoring Zone'**
  String get monitoringZone;

  /// Tab label for reports pending verification
  ///
  /// In en, this message translates to:
  /// **'To Verify'**
  String get toVerify;

  /// Tab label for alerts
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// Tab label for user's own reports
  ///
  /// In en, this message translates to:
  /// **'My Reports'**
  String get myReports;

  /// Section header for hazard categories
  ///
  /// In en, this message translates to:
  /// **'Browse Categories'**
  String get browseCategories;

  /// Section header for recent updates
  ///
  /// In en, this message translates to:
  /// **'Recently Updated'**
  String get recentlyUpdated;

  /// Empty state message when no reports exist
  ///
  /// In en, this message translates to:
  /// **'No reports yet'**
  String get noReportsYet;

  /// Empty state for verification tab
  ///
  /// In en, this message translates to:
  /// **'No reports to verify'**
  String get noReportsToVerify;

  /// Empty state for alerts tab
  ///
  /// In en, this message translates to:
  /// **'No active alerts'**
  String get noActiveAlerts;

  /// Button label for reporting a hazard
  ///
  /// In en, this message translates to:
  /// **'REPORT HAZARD'**
  String get reportHazard;

  /// Link to view all items in a section
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// Message shown when user is not logged in
  ///
  /// In en, this message translates to:
  /// **'Please log in to view reports'**
  String get pleaseLoginToViewReports;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get notifications;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotifications;

  /// No description provided for @criticalAlerts.
  ///
  /// In en, this message translates to:
  /// **'Critical Alerts'**
  String get criticalAlerts;

  /// No description provided for @dnd.
  ///
  /// In en, this message translates to:
  /// **'Do Not Disturb'**
  String get dnd;

  /// No description provided for @dataStorage.
  ///
  /// In en, this message translates to:
  /// **'DATA & STORAGE'**
  String get dataStorage;

  /// No description provided for @wifiOnly.
  ///
  /// In en, this message translates to:
  /// **'WiFi Only Sync'**
  String get wifiOnly;

  /// No description provided for @lowData.
  ///
  /// In en, this message translates to:
  /// **'Low Data Mode'**
  String get lowData;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'GENERAL'**
  String get general;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @helpFaq.
  ///
  /// In en, this message translates to:
  /// **'Help & FAQ'**
  String get helpFaq;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Currently selected language name
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get selectedLanguage;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @verifyPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Verify Phone Number'**
  String get verifyPhoneNumber;

  /// No description provided for @enterOtpCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the 4-digit code sent to your phone'**
  String get enterOtpCode;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend Code'**
  String get resendCode;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @codeExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Code expires in'**
  String get codeExpiresIn;

  /// No description provided for @neverShareCode.
  ///
  /// In en, this message translates to:
  /// **'Never share your verification code with anyone'**
  String get neverShareCode;

  /// No description provided for @selectHazard.
  ///
  /// In en, this message translates to:
  /// **'Select Hazard'**
  String get selectHazard;

  /// No description provided for @whatIncident.
  ///
  /// In en, this message translates to:
  /// **'What type of incident are you reporting?'**
  String get whatIncident;

  /// No description provided for @flooding.
  ///
  /// In en, this message translates to:
  /// **'Flooding'**
  String get flooding;

  /// No description provided for @extremeHeat.
  ///
  /// In en, this message translates to:
  /// **'Extreme Heat'**
  String get extremeHeat;

  /// No description provided for @drought.
  ///
  /// In en, this message translates to:
  /// **'Drought'**
  String get drought;

  /// No description provided for @windstorms.
  ///
  /// In en, this message translates to:
  /// **'Windstorms'**
  String get windstorms;

  /// No description provided for @wildfires.
  ///
  /// In en, this message translates to:
  /// **'Wildfires'**
  String get wildfires;

  /// No description provided for @erosion.
  ///
  /// In en, this message translates to:
  /// **'Erosion'**
  String get erosion;

  /// No description provided for @pestOutbreak.
  ///
  /// In en, this message translates to:
  /// **'Pest Outbreak'**
  String get pestOutbreak;

  /// No description provided for @cropDisease.
  ///
  /// In en, this message translates to:
  /// **'Crop Disease'**
  String get cropDisease;

  /// No description provided for @conflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get conflict;

  /// No description provided for @selectSeverity.
  ///
  /// In en, this message translates to:
  /// **'Select Severity'**
  String get selectSeverity;

  /// No description provided for @howSevere.
  ///
  /// In en, this message translates to:
  /// **'How severe is the hazard?'**
  String get howSevere;

  /// No description provided for @howSevereSituation.
  ///
  /// In en, this message translates to:
  /// **'How severe is the situation?'**
  String get howSevereSituation;

  /// No description provided for @setSeverity.
  ///
  /// In en, this message translates to:
  /// **'Set Severity'**
  String get setSeverity;

  /// No description provided for @nextLocation.
  ///
  /// In en, this message translates to:
  /// **'Next: Location'**
  String get nextLocation;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @moderate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get moderate;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @critical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get critical;

  /// No description provided for @lowMinorImpact.
  ///
  /// In en, this message translates to:
  /// **'Low - Minor impact'**
  String get lowMinorImpact;

  /// No description provided for @mediumNoticeableImpact.
  ///
  /// In en, this message translates to:
  /// **'Medium - Noticeable impact'**
  String get mediumNoticeableImpact;

  /// No description provided for @highSignificantDamage.
  ///
  /// In en, this message translates to:
  /// **'High - Significant damage'**
  String get highSignificantDamage;

  /// No description provided for @criticalLifeThreatening.
  ///
  /// In en, this message translates to:
  /// **'Critical - Life threatening'**
  String get criticalLifeThreatening;

  /// No description provided for @reportDetails.
  ///
  /// In en, this message translates to:
  /// **'Report Details'**
  String get reportDetails;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @describeHazard.
  ///
  /// In en, this message translates to:
  /// **'Describe the hazard here (e.g. flood levels rising, bridge collapsed)...'**
  String get describeHazard;

  /// No description provided for @whenDidOccur.
  ///
  /// In en, this message translates to:
  /// **'When Did This Occur?'**
  String get whenDidOccur;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @evidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get evidence;

  /// No description provided for @maxPhotos.
  ///
  /// In en, this message translates to:
  /// **'Max 3 photos'**
  String get maxPhotos;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @reviewReport.
  ///
  /// In en, this message translates to:
  /// **'Review Report'**
  String get reviewReport;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening... Speak now'**
  String get listening;

  /// No description provided for @beSpecific.
  ///
  /// In en, this message translates to:
  /// **'Be specific about location and severity.'**
  String get beSpecific;

  /// No description provided for @locationPicker.
  ///
  /// In en, this message translates to:
  /// **'Location Picker'**
  String get locationPicker;

  /// No description provided for @selectLocation.
  ///
  /// In en, this message translates to:
  /// **'Select your current location or search for a place'**
  String get selectLocation;

  /// No description provided for @useCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Use Current Location'**
  String get useCurrentLocation;

  /// No description provided for @useMyLocationInfo.
  ///
  /// In en, this message translates to:
  /// **'Use My Location Info'**
  String get useMyLocationInfo;

  /// No description provided for @searchPlaces.
  ///
  /// In en, this message translates to:
  /// **'Search for places...'**
  String get searchPlaces;

  /// No description provided for @confirmLocation.
  ///
  /// In en, this message translates to:
  /// **'Confirm Location'**
  String get confirmLocation;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @editProfileDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile Details'**
  String get editProfileDetails;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @biometricLogin.
  ///
  /// In en, this message translates to:
  /// **'Biometric Login'**
  String get biometricLogin;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @languagePreference.
  ///
  /// In en, this message translates to:
  /// **'Language Preference'**
  String get languagePreference;

  /// No description provided for @offlineDataSync.
  ///
  /// In en, this message translates to:
  /// **'Offline Data Sync'**
  String get offlineDataSync;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @contactSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Contact Supervisor / SOS'**
  String get contactSupervisor;

  /// No description provided for @errorOccurred.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorOccurred;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again'**
  String get tryAgain;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection'**
  String get networkError;

  /// No description provided for @invalidOtp.
  ///
  /// In en, this message translates to:
  /// **'Invalid OTP code. Please try again.'**
  String get invalidOtp;

  /// No description provided for @otpExpired.
  ///
  /// In en, this message translates to:
  /// **'OTP has expired. Please request a new code.'**
  String get otpExpired;

  /// No description provided for @biometricsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics not available on this device'**
  String get biometricsNotAvailable;

  /// No description provided for @biometricsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric login enabled'**
  String get biometricsEnabled;

  /// No description provided for @biometricsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric login disabled'**
  String get biometricsDisabled;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully!'**
  String get profileUpdated;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted successfully!'**
  String get reportSubmitted;

  /// No description provided for @reportQueued.
  ///
  /// In en, this message translates to:
  /// **'Report queued for submission when online'**
  String get reportQueued;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @syncComplete.
  ///
  /// In en, this message translates to:
  /// **'Sync complete'**
  String get syncComplete;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offlineModeReady.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode Ready: '**
  String get offlineModeReady;

  /// No description provided for @offlineModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Your photos will be compressed automatically. Reports are saved locally until you have internet.'**
  String get offlineModeDescription;

  /// No description provided for @validation_required.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get validation_required;

  /// No description provided for @validation_invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get validation_invalidEmail;

  /// No description provided for @validation_invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid phone number'**
  String get validation_invalidPhone;

  /// Validation message for minimum length
  ///
  /// In en, this message translates to:
  /// **'Must be at least {length} characters'**
  String validation_minLength(int length);

  /// Validation message for maximum length
  ///
  /// In en, this message translates to:
  /// **'Must be at most {length} characters'**
  String validation_maxLength(int length);

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'SYNC STATUS'**
  String get syncStatus;

  /// No description provided for @onlineJustNow.
  ///
  /// In en, this message translates to:
  /// **'Online • Just now'**
  String get onlineJustNow;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get active;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get resolved;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @floodsCategory.
  ///
  /// In en, this message translates to:
  /// **'Floods'**
  String get floodsCategory;

  /// No description provided for @droughtsCategory.
  ///
  /// In en, this message translates to:
  /// **'Droughts'**
  String get droughtsCategory;

  /// No description provided for @pestsCategory.
  ///
  /// In en, this message translates to:
  /// **'Pests'**
  String get pestsCategory;

  /// No description provided for @conflictsCategory.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get conflictsCategory;

  /// No description provided for @noRecentAlerts.
  ///
  /// In en, this message translates to:
  /// **'No recent alerts'**
  String get noRecentAlerts;

  /// No description provided for @selectZone.
  ///
  /// In en, this message translates to:
  /// **'Select Zone'**
  String get selectZone;

  /// No description provided for @activeZone.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeZone;

  /// No description provided for @notSetZone.
  ///
  /// In en, this message translates to:
  /// **'Not Set'**
  String get notSetZone;

  /// No description provided for @noNewNotifications.
  ///
  /// In en, this message translates to:
  /// **'No new notifications'**
  String get noNewNotifications;

  /// No description provided for @reportsStatus.
  ///
  /// In en, this message translates to:
  /// **'Reports Status'**
  String get reportsStatus;

  /// No description provided for @acknowledged.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged'**
  String get acknowledged;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @generateReport.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get generateReport;

  /// No description provided for @noReportsStatus.
  ///
  /// In en, this message translates to:
  /// **'No {status} Reports'**
  String noReportsStatus(String status);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @reportedBy.
  ///
  /// In en, this message translates to:
  /// **'Reported by {name}'**
  String reportedBy(String name);

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @reportVerified.
  ///
  /// In en, this message translates to:
  /// **'Report verified successfully'**
  String get reportVerified;

  /// No description provided for @verifyReport.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyReport;

  /// No description provided for @reportRejectedItem.
  ///
  /// In en, this message translates to:
  /// **'Report rejected'**
  String get reportRejectedItem;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @reportResolvedItem.
  ///
  /// In en, this message translates to:
  /// **'Report approved'**
  String get reportResolvedItem;

  /// No description provided for @markResolved.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get markResolved;

  /// No description provided for @reportMovedPending.
  ///
  /// In en, this message translates to:
  /// **'Report moved back to Pending'**
  String get reportMovedPending;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @reportReopenedPending.
  ///
  /// In en, this message translates to:
  /// **'Report reopened and moved to Pending'**
  String get reportReopenedPending;

  /// No description provided for @reportDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Report Details'**
  String get reportDetailsTitle;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @describeHazardHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the hazard here (e.g. flood levels rising, bridge collapsed)...'**
  String get describeHazardHint;

  /// No description provided for @speechNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition not available'**
  String get speechNotAvailable;

  /// No description provided for @listeningSpeakNow.
  ///
  /// In en, this message translates to:
  /// **'Listening... Speak now'**
  String get listeningSpeakNow;

  /// No description provided for @beSpecificLocationSeverity.
  ///
  /// In en, this message translates to:
  /// **'Be specific about location and severity.'**
  String get beSpecificLocationSeverity;

  /// No description provided for @whenDidThisOccur.
  ///
  /// In en, this message translates to:
  /// **'When Did This Occur?'**
  String get whenDidThisOccur;

  /// No description provided for @optionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optionalLabel;

  /// No description provided for @todayLabel.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayLabel;

  /// No description provided for @tapToSelectDateTime.
  ///
  /// In en, this message translates to:
  /// **'Tap to select date & time. Defaults to now if not changed.'**
  String get tapToSelectDateTime;

  /// No description provided for @evidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get evidenceLabel;

  /// No description provided for @max3Photos.
  ///
  /// In en, this message translates to:
  /// **'Max 3 photos'**
  String get max3Photos;

  /// No description provided for @offlineModeMessage.
  ///
  /// In en, this message translates to:
  /// **'Your photos will be compressed automatically. Reports are saved locally until you have internet.'**
  String get offlineModeMessage;

  /// No description provided for @reviewReportBtn.
  ///
  /// In en, this message translates to:
  /// **'Review Report'**
  String get reviewReportBtn;

  /// No description provided for @cameraBtn.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraBtn;

  /// No description provided for @galleryBtn.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryBtn;

  /// No description provided for @submissionFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed'**
  String get submissionFailed;

  /// No description provided for @savedForLater.
  ///
  /// In en, this message translates to:
  /// **'Saved for Later'**
  String get savedForLater;

  /// No description provided for @reportSubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Report Submitted!'**
  String get reportSubmittedTitle;

  /// No description provided for @offlineReportMessage.
  ///
  /// In en, this message translates to:
  /// **'You are offline. The report will be sent automatically when you are back online.'**
  String get offlineReportMessage;

  /// No description provided for @onlineReportMessage.
  ///
  /// In en, this message translates to:
  /// **'Your report has been successfully sent to central command.'**
  String get onlineReportMessage;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get statusLabel;

  /// No description provided for @reportIdLabel.
  ///
  /// In en, this message translates to:
  /// **'REPORT ID'**
  String get reportIdLabel;

  /// No description provided for @queuedStatus.
  ///
  /// In en, this message translates to:
  /// **'QUEUED'**
  String get queuedStatus;

  /// No description provided for @sentStatus.
  ///
  /// In en, this message translates to:
  /// **'SENT'**
  String get sentStatus;

  /// No description provided for @returnToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Return to Dashboard'**
  String get returnToDashboard;

  /// No description provided for @reviewReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Review Report'**
  String get reviewReportTitle;

  /// No description provided for @reviewReportDesc.
  ///
  /// In en, this message translates to:
  /// **'Please review the details below to ensure accuracy before submitting to the central command.'**
  String get reviewReportDesc;

  /// No description provided for @hazardDetails.
  ///
  /// In en, this message translates to:
  /// **'Hazard Details'**
  String get hazardDetails;

  /// No description provided for @hazardType.
  ///
  /// In en, this message translates to:
  /// **'Hazard Type'**
  String get hazardType;

  /// No description provided for @notSelected.
  ///
  /// In en, this message translates to:
  /// **'Not Selected'**
  String get notSelected;

  /// No description provided for @severityLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Severity Level'**
  String get severityLevelLabel;

  /// No description provided for @severityDesc.
  ///
  /// In en, this message translates to:
  /// **'Assess the intensity of the hazard.'**
  String get severityDesc;

  /// No description provided for @severityLowShort.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get severityLowShort;

  /// No description provided for @severityMedShort.
  ///
  /// In en, this message translates to:
  /// **'Med'**
  String get severityMedShort;

  /// No description provided for @severityHighShort.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get severityHighShort;

  /// No description provided for @severityCritShort.
  ///
  /// In en, this message translates to:
  /// **'Crit'**
  String get severityCritShort;

  /// No description provided for @dateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get dateTimeLabel;

  /// No description provided for @whenItOccurred.
  ///
  /// In en, this message translates to:
  /// **'When it occurred'**
  String get whenItOccurred;

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today at'**
  String get todayAt;

  /// No description provided for @atTime.
  ///
  /// In en, this message translates to:
  /// **'at'**
  String get atTime;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @notProvided.
  ///
  /// In en, this message translates to:
  /// **'Not Provided'**
  String get notProvided;

  /// No description provided for @monitorNotes.
  ///
  /// In en, this message translates to:
  /// **'Monitor Notes'**
  String get monitorNotes;

  /// No description provided for @noDescriptionProvided.
  ///
  /// In en, this message translates to:
  /// **'No description provided'**
  String get noDescriptionProvided;

  /// No description provided for @addPhotoBtn.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addPhotoBtn;

  /// No description provided for @submitReportBtn.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReportBtn;

  /// No description provided for @editBtn.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editBtn;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied'**
  String get locationPermissionDenied;

  /// No description provided for @enableGpsMessage.
  ///
  /// In en, this message translates to:
  /// **'Unable to get location. Please enable GPS.'**
  String get enableGpsMessage;

  /// No description provided for @locationError.
  ///
  /// In en, this message translates to:
  /// **'Location error:'**
  String get locationError;

  /// No description provided for @acquiringGps.
  ///
  /// In en, this message translates to:
  /// **'ACQUIRING...'**
  String get acquiringGps;

  /// No description provided for @noSignalGps.
  ///
  /// In en, this message translates to:
  /// **'NO SIGNAL'**
  String get noSignalGps;

  /// No description provided for @gpsStrong.
  ///
  /// In en, this message translates to:
  /// **'GPS STRONG'**
  String get gpsStrong;

  /// No description provided for @gpsGood.
  ///
  /// In en, this message translates to:
  /// **'GPS GOOD'**
  String get gpsGood;

  /// No description provided for @gpsWeak.
  ///
  /// In en, this message translates to:
  /// **'GPS WEAK'**
  String get gpsWeak;

  /// No description provided for @couldNotFindLocation.
  ///
  /// In en, this message translates to:
  /// **'Could not find location on map'**
  String get couldNotFindLocation;

  /// No description provided for @mapUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Map update error:'**
  String get mapUpdateError;

  /// No description provided for @incidentLocation.
  ///
  /// In en, this message translates to:
  /// **'Incident Location'**
  String get incidentLocation;

  /// No description provided for @gettingLocation.
  ///
  /// In en, this message translates to:
  /// **'Getting location...'**
  String get gettingLocation;

  /// No description provided for @noGpsData.
  ///
  /// In en, this message translates to:
  /// **'No GPS data'**
  String get noGpsData;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable'**
  String get locationUnavailable;

  /// No description provided for @coordinatesLabel.
  ///
  /// In en, this message translates to:
  /// **'COORDINATES'**
  String get coordinatesLabel;

  /// No description provided for @viewDetailsBtn.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetailsBtn;

  /// No description provided for @wardAndLgaSelection.
  ///
  /// In en, this message translates to:
  /// **'Ward & LGA Selection'**
  String get wardAndLgaSelection;

  /// No description provided for @selectWardDropdown.
  ///
  /// In en, this message translates to:
  /// **'Select your ward from the dropdown'**
  String get selectWardDropdown;

  /// No description provided for @selectLgaWardIncident.
  ///
  /// In en, this message translates to:
  /// **'Select the LGA and Ward where the incident occurred'**
  String get selectLgaWardIncident;

  /// No description provided for @stateLabel.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get stateLabel;

  /// No description provided for @selectState.
  ///
  /// In en, this message translates to:
  /// **'Select State'**
  String get selectState;

  /// No description provided for @selectStateFirst.
  ///
  /// In en, this message translates to:
  /// **'Select State first'**
  String get selectStateFirst;

  /// No description provided for @lgaLabel.
  ///
  /// In en, this message translates to:
  /// **'LGA (Local Government Area)'**
  String get lgaLabel;

  /// No description provided for @selectLga.
  ///
  /// In en, this message translates to:
  /// **'Select LGA'**
  String get selectLga;

  /// No description provided for @selectLgaFirst.
  ///
  /// In en, this message translates to:
  /// **'Select LGA first'**
  String get selectLgaFirst;

  /// No description provided for @wardLabel.
  ///
  /// In en, this message translates to:
  /// **'Ward'**
  String get wardLabel;

  /// No description provided for @selectWard.
  ///
  /// In en, this message translates to:
  /// **'Select Ward'**
  String get selectWard;

  /// No description provided for @enterLocationManually.
  ///
  /// In en, this message translates to:
  /// **'Enter Location Manually'**
  String get enterLocationManually;

  /// No description provided for @addressOrCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Address or Coordinates'**
  String get addressOrCoordinates;

  /// No description provided for @cancelBtn.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelBtn;

  /// No description provided for @setLocationBtn.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get setLocationBtn;

  /// No description provided for @manualLocationSet.
  ///
  /// In en, this message translates to:
  /// **'Manual location set'**
  String get manualLocationSet;

  /// No description provided for @locationIncorrectManual.
  ///
  /// In en, this message translates to:
  /// **'Location incorrect? Enter manually'**
  String get locationIncorrectManual;

  /// No description provided for @pleaseSelectStateLgaWard.
  ///
  /// In en, this message translates to:
  /// **'Please select State, LGA, and Ward before continuing'**
  String get pleaseSelectStateLgaWard;

  /// No description provided for @confirmAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Continue'**
  String get confirmAndContinue;

  /// No description provided for @locationDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Location Details'**
  String get locationDetailsTitle;

  /// No description provided for @latitudeLabel.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitudeLabel;

  /// No description provided for @longitudeLabel.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitudeLabel;

  /// No description provided for @accuracyLabel.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get accuracyLabel;

  /// No description provided for @altitudeLabel.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get altitudeLabel;

  /// No description provided for @closeBtn.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeBtn;

  /// No description provided for @selectStatusExport.
  ///
  /// In en, this message translates to:
  /// **'Select status to export:'**
  String get selectStatusExport;

  /// No description provided for @allReports.
  ///
  /// In en, this message translates to:
  /// **'All Reports'**
  String get allReports;

  /// No description provided for @pendingOnly.
  ///
  /// In en, this message translates to:
  /// **'Pending Only'**
  String get pendingOnly;

  /// No description provided for @acknowledgedOnly.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged Only'**
  String get acknowledgedOnly;

  /// No description provided for @resolvedOnly.
  ///
  /// In en, this message translates to:
  /// **'Resolved Only'**
  String get resolvedOnly;

  /// No description provided for @verifiedOnly.
  ///
  /// In en, this message translates to:
  /// **'Verified Only'**
  String get verifiedOnly;

  /// No description provided for @approvedOnly.
  ///
  /// In en, this message translates to:
  /// **'Approved Only'**
  String get approvedOnly;

  /// No description provided for @csvExportWeb.
  ///
  /// In en, this message translates to:
  /// **'CSV export available on web version'**
  String get csvExportWeb;

  /// Generic error message suggesting the user check their connection
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please check your connection and try again.'**
  String get errorGenericCheckConnection;

  /// No description provided for @adminPortal.
  ///
  /// In en, this message translates to:
  /// **'Admin Portal'**
  String get adminPortal;

  /// No description provided for @systemOverview.
  ///
  /// In en, this message translates to:
  /// **'System Overview'**
  String get systemOverview;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// No description provided for @reportsOverview.
  ///
  /// In en, this message translates to:
  /// **'Reports Overview'**
  String get reportsOverview;

  /// No description provided for @alertsBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Alerts & Broadcast'**
  String get alertsBroadcast;

  /// No description provided for @knowledgeManagement.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Management'**
  String get knowledgeManagement;

  /// No description provided for @systemHealth.
  ///
  /// In en, this message translates to:
  /// **'System Health'**
  String get systemHealth;

  /// No description provided for @pendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'Pending Approvals'**
  String get pendingApprovals;

  /// No description provided for @pendingReports.
  ///
  /// In en, this message translates to:
  /// **'Pending Reports'**
  String get pendingReports;

  /// No description provided for @escalatedReports.
  ///
  /// In en, this message translates to:
  /// **'Escalated Reports'**
  String get escalatedReports;

  /// No description provided for @verifiedReports.
  ///
  /// In en, this message translates to:
  /// **'Verified Reports'**
  String get verifiedReports;

  /// No description provided for @totalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get totalUsers;

  /// No description provided for @activeAlertsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Active Alerts'**
  String get activeAlertsAdmin;

  /// No description provided for @totalReports.
  ///
  /// In en, this message translates to:
  /// **'Total Reports'**
  String get totalReports;

  /// No description provided for @userManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Approve accounts, assign roles, deactivate users'**
  String get userManagementDesc;

  /// No description provided for @reportsOverviewDesc.
  ///
  /// In en, this message translates to:
  /// **'View, validate, or reject reports across all LGAs'**
  String get reportsOverviewDesc;

  /// No description provided for @alertsBroadcastDesc.
  ///
  /// In en, this message translates to:
  /// **'Send emergency alerts to users or specific areas'**
  String get alertsBroadcastDesc;

  /// No description provided for @knowledgeManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Add, edit, or remove emergency knowledge guides'**
  String get knowledgeManagementDesc;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'reports'**
  String get reports;
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
      <String>['en', 'ha'].contains(locale.languageCode);

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
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
