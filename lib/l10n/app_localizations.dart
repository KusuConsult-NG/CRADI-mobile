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
  /// **'CRADI Early Warning'**
  String get appTitle;

  /// Label for monitoring zone header
  ///
  /// In en, this message translates to:
  /// **'MONITORING ZONE'**
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
  /// **'Offline Mode Ready:'**
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
