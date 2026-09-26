// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hausa (`ha`).
class AppLocalizationsHa extends AppLocalizations {
  AppLocalizationsHa([String locale = 'ha']) : super(locale);

  @override
  String get appTitle => 'EWER Gargadi Na Wuri';

  @override
  String get monitoringZone => 'Yankin Sa Ido';

  @override
  String get toVerify => 'Don Tabbatarwa';

  @override
  String get alerts => 'Faɗakarwa';

  @override
  String get myReports => 'Rahotannina';

  @override
  String get browseCategories => 'Duba Nau\'o\'i';

  @override
  String get noReportsToVerify => 'Babu rahotanni don tabbatarwa';

  @override
  String get noActiveAlerts => 'Babu faɗakarwa a yanzu';

  @override
  String get seeAll => 'Duba Duka';

  @override
  String get notifications => 'SANARWA';

  @override
  String get pushNotifications => 'Sanarwar Tura';

  @override
  String get general => 'GABAƊAYA';

  @override
  String get language => 'Harshe';

  @override
  String get helpFaq => 'Taimako da Tambayoyi';

  @override
  String get aboutApp => 'Game da App';

  @override
  String get logout => 'Fita';

  @override
  String get back => 'Komawa';

  @override
  String get cancel => 'Soke';

  @override
  String get save => 'Ajiye';

  @override
  String get delete => 'Goge';

  @override
  String get edit => 'Gyara';

  @override
  String get continueButton => 'Ci gaba';

  @override
  String get retry => 'Sake Gwadawa';

  @override
  String get close => 'Rufe';

  @override
  String get settingsTitle => 'Saitunan';

  @override
  String get verifyPhoneNumber => 'Tabbatar da Lambar Waya';

  @override
  String get resendCode => 'Sake Aika Lambar';

  @override
  String get verify => 'Tabbatar';

  @override
  String get selectHazard => 'Zaɓi Haɗari';

  @override
  String get whatIncident => 'Wane irin lamari kake bayar da rahoto?';

  @override
  String get erosion => 'Zaizaya';

  @override
  String get howSevereSituation => 'Yaya tsananin lamarin?';

  @override
  String get setSeverity => 'Zaɓi Tsanani';

  @override
  String get nextLocation => 'Na Gaba: Wuri';

  @override
  String get lowMinorImpact => 'Ƙarami - Tasiri kaɗan';

  @override
  String get mediumNoticeableImpact => 'Matsakaici - Tasiri bayyananne';

  @override
  String get highSignificantDamage => 'Babba - Babbar barna';

  @override
  String get criticalLifeThreatening => 'Mai Gaggawa - Barazana ga rayuwa';

  @override
  String get camera => 'Kamara';

  @override
  String get useMyLocationInfo => 'Yi Amfani da Bayanan Wurina';

  @override
  String get myProfile => 'Bayanan Kaina';

  @override
  String get editProfileDetails => 'Gyara Bayanan Kaina';

  @override
  String get fullName => 'Cikakken Suna';

  @override
  String get emailAddress => 'Adireshin Imel';

  @override
  String get biometricLogin => 'Shiga ta Biometric';

  @override
  String get enabled => 'An Kunna';

  @override
  String get disabled => 'An Kashe';

  @override
  String get languagePreference => 'Zaɓin Harshe';

  @override
  String get offlineDataSync => 'Daidaita Bayanai Ba Tare da Yanar Gizo';

  @override
  String get upToDate => 'An sabunta';

  @override
  String get helpSupport => 'Taimako da Goyon Baya';

  @override
  String get biometricsNotAvailable =>
      'Biometric ba ya samuwa akan wannan na\'ura';

  @override
  String get biometricsEnabled => 'An kunna shiga ta biometric';

  @override
  String get biometricsDisabled => 'An kashe shiga ta biometric';

  @override
  String get profileUpdated => 'An sabunta bayanan kaina cikin nasara!';

  @override
  String get syncing => 'Ana daidaitawa...';

  @override
  String get offline => 'Ba Yanar Gizo';

  @override
  String get offlineModeReady => 'Shirye a Yanayin Rashin Intanet: ';

  @override
  String get validation_required => 'Ana buƙatar wannan filin';

  @override
  String get validation_invalidEmail =>
      'Don Allah shigar da ingantaccen adireshin imel';

  @override
  String validation_minLength(int length) {
    return 'Dole ne ya zama aƙalla haruffa $length';
  }

  @override
  String validation_maxLength(int length) {
    return 'Dole ne ya zama ko da yawa haruffa $length';
  }

  @override
  String get syncStatus => 'MATSAYIN DAIDAITAWA';

  @override
  String get onlineJustNow => 'A Yanar Gizo • Yanzu';

  @override
  String get active => 'mai aiki';

  @override
  String get pending => 'Suna Jiran';

  @override
  String get verified => 'An Tabbatar';

  @override
  String get approved => 'An Amince';

  @override
  String get floodsCategory => 'Ambaliya';

  @override
  String get droughtsCategory => 'Fari';

  @override
  String get pestsCategory => 'KWari';

  @override
  String get conflictsCategory => 'Rikici';

  @override
  String get noRecentAlerts => 'Babu sabbin faɗakarwa';

  @override
  String get selectZone => 'Zaɓi Yanki';

  @override
  String get activeZone => 'Mai Aiki';

  @override
  String get notSetZone => 'Ba a Saka Ba';

  @override
  String get reportsStatus => 'Matsayin Rahotanni';

  @override
  String get rejected => 'An Ƙi';

  @override
  String get generateReport => 'Ƙirƙiri Rahoto';

  @override
  String noReportsStatus(String status) {
    return 'Babu Rahotannin $status';
  }

  @override
  String get refresh => 'Sake Sabuntawa';

  @override
  String reportedBy(String name) {
    return 'Rahoton daga $name';
  }

  @override
  String get viewDetails => 'Duba Cikakkun Bayanai';

  @override
  String get reportVerified =>
      'An tantance rahoton kuma an mayar da shi zuwa An Karɓa';

  @override
  String get verifyReport => 'Tantance';

  @override
  String get reportRejectedItem => 'An ƙi rahoton';

  @override
  String get reject => 'Ƙi';

  @override
  String get reportResolvedItem => 'An kimanta rahoton a matsayin An Warware';

  @override
  String get markResolved => 'Kimanta An Warware';

  @override
  String get reportMovedPending => 'An mayar da rahoton baya Suna Jiran';

  @override
  String get reopen => 'Sake buɗewa';

  @override
  String get reportReopenedPending =>
      'Wannan rahoton an sake bude shi kuma yana jiran aiki.';

  @override
  String get reportDetailsTitle => 'Cikakkun Bayanan Rahoto';

  @override
  String get descriptionLabel => 'Bayani';

  @override
  String get describeHazardHint =>
      'Kwatanta hatsarin a nan (misali, ruwan ambaliya ya tashi, gada ta ruguje)...';

  @override
  String get speechNotAvailable => 'Babu tsarin tantance murya gaba daya';

  @override
  String get listeningSpeakNow => 'Ana saurare... Ka yi magana yanzu';

  @override
  String get beSpecificLocationSeverity =>
      'Bayyana wurin da tsananin lamarin sosai.';

  @override
  String get whenDidThisOccur => 'Yaushe hakan ta faru?';

  @override
  String get optionalLabel => 'Zabi ne';

  @override
  String get todayLabel => 'Yau';

  @override
  String get tapToSelectDateTime =>
      'Danna don zabar kwanan wata & lokaci. Idan ba a canza ba, zai nuna yanzu.';

  @override
  String get evidenceLabel => 'Shaida';

  @override
  String get max3Photos => 'Hotuna 3 kacal';

  @override
  String get offlineModeMessage =>
      'Za a rage girman hotunanka kai tsaye. Ana ajiye rahotanni a cikin wayar har sai ka samu intanet.';

  @override
  String get reviewReportBtn => 'Duba Rahoto';

  @override
  String get cameraBtn => 'Kyamara';

  @override
  String get galleryBtn => 'Hotuna';

  @override
  String get submissionFailed => 'An kasa aikawa';

  @override
  String get savedForLater => 'An ajiye don gaba';

  @override
  String get reportSubmittedTitle => 'An aika da rahoto!';

  @override
  String get offlineReportMessage =>
      'Baka da intanet. Za a tura rahoton da zarar ka dawo kan layi.';

  @override
  String get onlineReportMessage =>
      'An samu nasarar aikawa da rahoton ka zuwa cibiyar gudanarwa.';

  @override
  String get statusLabel => 'MATSAYI';

  @override
  String get reportIdLabel => 'LAMBAR RAHOTO';

  @override
  String get queuedStatus => 'A JERE';

  @override
  String get sentStatus => 'AN AIKA';

  @override
  String get returnToDashboard => 'Koma Fuskar Farko';

  @override
  String get reviewReportTitle => 'Duba Rahoto';

  @override
  String get reviewReportDesc =>
      'Da fatan za a duba bayanan da ke ƙasa don tabbatar da ingancin su kafin aikawa cibiyar gudanarwa.';

  @override
  String get hazardDetails => 'Bayanan Hatsari';

  @override
  String get hazardType => 'Nau\'in Hatsari';

  @override
  String get notSelected => 'Ba a zaɓa ba';

  @override
  String get severityLevelLabel => 'Matsayin Tsanani';

  @override
  String get severityDesc => 'Auna girman lamarin.';

  @override
  String get severityLowShort => 'Kaɗan';

  @override
  String get severityMedShort => 'Tsakiya';

  @override
  String get severityHighShort => 'Yawa';

  @override
  String get severityCritShort => 'Tsanan';

  @override
  String get dateTimeLabel => 'Kwanan Wata & Lokaci';

  @override
  String get whenItOccurred => 'Sanda ya faru';

  @override
  String get locationLabel => 'Wuri';

  @override
  String get notProvided => 'Ba a bayar ba';

  @override
  String get monitorNotes => 'Bayanan Mai Lura';

  @override
  String get noDescriptionProvided => 'Babu bayanin da aka bayar';

  @override
  String get addPhotoBtn => 'Saka';

  @override
  String get submitReportBtn => 'Aika Rahoto';

  @override
  String get editBtn => 'Gyara';

  @override
  String get locationPermissionDenied => 'An ƙi bayar da damar wurin';

  @override
  String get enableGpsMessage => 'An kasa samun wuri. Da fatan za a kunna GPS.';

  @override
  String get locationError => 'Matsalar Wuri:';

  @override
  String get acquiringGps => 'ANA NEMAN...';

  @override
  String get noSignalGps => 'BABU SIGINAR GPS';

  @override
  String get gpsStrong => 'GPS MAI ƘARFI';

  @override
  String get gpsGood => 'GPS MAI KYAU';

  @override
  String get gpsWeak => 'RASHIN ƘARFIN GPS';

  @override
  String get couldNotFindLocation => 'An kasa samun wuri a kan taswira';

  @override
  String get mapUpdateError => 'Matsalar sabunta taswira:';

  @override
  String get incidentLocation => 'Wurin da Lamarin ya faru';

  @override
  String get gettingLocation => 'Ana neman wuri...';

  @override
  String get noGpsData => 'Babu bayanan GPS';

  @override
  String get locationUnavailable => 'Babu Wuri';

  @override
  String get coordinatesLabel => 'LAMBOBIN WURI';

  @override
  String get viewDetailsBtn => 'Duba Cikakken Bayani';

  @override
  String get wardAndLgaSelection => 'Zaɓin Gunduma da Ƙaramar Hukuma';

  @override
  String get selectWardDropdown => 'Zaɓi gundumarka daga jerin';

  @override
  String get selectLgaWardIncident =>
      'Zaɓi Ƙaramar Hukuma da Gundumar da lamarin ya faru';

  @override
  String get stateLabel => 'Jiha';

  @override
  String get selectState => 'Zaɓi Jiha';

  @override
  String get selectStateFirst => 'Zaɓi Jiha tukuna';

  @override
  String get lgaLabel => 'Ƙaramar Hukuma';

  @override
  String get selectLga => 'Zaɓi Ƙaramar Hukuma';

  @override
  String get selectLgaFirst => 'Zaɓi Ƙaramar Hukuma tukuna';

  @override
  String get wardLabel => 'Gunduma';

  @override
  String get selectWard => 'Zaɓi Gunduma';

  @override
  String get enterLocationManually => 'Shigar da Wuri da Hannu';

  @override
  String get addressOrCoordinates => 'Adireshin ko Lambobin Wuri';

  @override
  String get cancelBtn => 'Soke';

  @override
  String get setLocationBtn => 'Saka';

  @override
  String get manualLocationSet => 'An saka wuri da hannu';

  @override
  String get locationIncorrectManual => 'Wurin ba daidai ba? Shigar da hannu';

  @override
  String get pleaseSelectStateLgaWard =>
      'Da fatan za a zaɓi Jiha, Ƙaramar Hukuma, da Gunduma kafin a ci gaba';

  @override
  String get confirmAndContinue => 'Tabbatar & Ci gaba';

  @override
  String get locationDetailsTitle => 'Bayanan Wuri';

  @override
  String get latitudeLabel => 'Wurin Acha';

  @override
  String get longitudeLabel => 'Wurin Zira';

  @override
  String get accuracyLabel => 'Inganci';

  @override
  String get altitudeLabel => 'Tsawa';

  @override
  String get closeBtn => 'Rufe';

  @override
  String get selectStatusExport => 'Zaɓi matsayin don fitarwa:';

  @override
  String get allReports => 'Dukkan Rahotanni';

  @override
  String get pendingOnly => 'Suna Jiran Kaɗai';

  @override
  String get verifiedOnly => 'Wadanda Aka Tabbatar Kaɗai';

  @override
  String get approvedOnly => 'Wadanda Aka Amince Kaɗai';

  @override
  String get adminPortal => 'Tashar Gudanarwa';

  @override
  String get systemOverview => 'Tsarin Gabaɗaya';

  @override
  String get quickActions => 'Ayyuka Masu Saurin';

  @override
  String get userManagement => 'Gudanar da Masu Amfani';

  @override
  String get reportsOverview => 'Gabaɗaya Rahotanni';

  @override
  String get alertsBroadcast => 'Faɗakarwa & Watsawa';

  @override
  String get knowledgeManagement => 'Gudanar da Ilimi';

  @override
  String get systemHealth => 'Lafiyar Tsarin';

  @override
  String get pendingApprovals => 'Amincewa Masu Jiran';

  @override
  String get pendingReports => 'Rahotanni Masu Jiran';

  @override
  String get verifiedReports => 'Rahotannin Da Aka Tabbatar';

  @override
  String get totalUsers => 'Jimillar Masu Amfani';

  @override
  String get activeAlertsAdmin => 'Faɗakarwa Masu Aiki';

  @override
  String get totalReports => 'Jimillar Rahotanni';

  @override
  String get userManagementDesc =>
      'Amince asusu, sanya matsayi, dakatar da masu amfani';

  @override
  String get reportsOverviewDesc => 'Duba, tabbatar, ko ƙi rahotanni';

  @override
  String get alertsBroadcastDesc =>
      'Aika faɗakarwa ga masu amfani ko takamaiman wurare';

  @override
  String get knowledgeManagementDesc =>
      'Saka, gyara, ko cire jagororin gaggawa';

  @override
  String get connected => 'Haɗe';

  @override
  String get none => 'Babu';

  @override
  String get errorNetwork => 'Network error. Please check your connection.';

  @override
  String get errorNoPermission =>
      'You do not have permission to perform this action.';

  @override
  String get errorContactSupport =>
      'An error occurred. Please try again or contact support.';

  @override
  String get errorUnexpected =>
      'An unexpected error occurred. Please try again.';

  @override
  String authEmailNotConfirmed(String email) {
    return 'Please verify your email first. We sent a new code to $email.';
  }

  @override
  String get languageSelectTitle => 'Select Language';

  @override
  String get shellAppBarTitle => 'CRADI Early Warning';

  @override
  String get shellNotificationsTooltip => 'Notifications';

  @override
  String get shellDrawerDefaultName => 'Early Warning Monitor';

  @override
  String get shellDrawerProfile => 'Profile';

  @override
  String get navHome => 'Gida';

  @override
  String get navAlerts => 'Faɗakarwa';

  @override
  String get navGuides => 'Jagora';

  @override
  String get navReport => 'Rahoto';

  @override
  String get navSettings => 'Saituna';

  @override
  String get navAdmin => 'Admin';

  @override
  String homeGreeting(String name) {
    return 'Sannu, $name';
  }

  @override
  String get hazardFlooding => 'Ambaliya';

  @override
  String get hazardExtremeTemperatures => 'Zafi Mai Tsanani';

  @override
  String get hazardDrought => 'Fari';

  @override
  String get hazardWindstorms => 'Guguwa';

  @override
  String get hazardWildfires => 'Gobara';

  @override
  String get hazardErosion => 'Zaizaya';

  @override
  String get hazardPestOutbreak => 'Annobar Kwari';

  @override
  String get hazardCropDisease => 'Cutar Amfani';

  @override
  String get hazardConflict => 'Rikici';

  @override
  String get hazardUnknown => 'Unknown Hazard';

  @override
  String get hazardTitleFlooding => 'Flood Alert';

  @override
  String get hazardTitleExtremeTemperatures => 'Temperature Extreme';

  @override
  String get hazardTitleDrought => 'Drought Warning';

  @override
  String get hazardTitleWindstorms => 'High Wind Alert';

  @override
  String get hazardTitleWildfires => 'Wildfire Report';

  @override
  String get hazardTitleErosion => 'Erosion Report';

  @override
  String get hazardTitlePestOutbreak => 'Pest Outbreak';

  @override
  String get hazardTitleCropDisease => 'Crop Disease';

  @override
  String get hazardTitleConflict => 'Conflict Report';

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}m ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}h ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}d ago',
    );
    return '$_temp0';
  }

  @override
  String timeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}w ago',
    );
    return '$_temp0';
  }

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonUnknownLocation => 'Unknown Location';

  @override
  String get commonAnonymous => 'Anonymous';

  @override
  String get commonCommunityReport => 'Community Report';

  @override
  String get reportStatusPending => 'Pending';

  @override
  String get reportStatusVerified => 'Verified';

  @override
  String get reportStatusApproved => 'Approved';

  @override
  String get reportStatusRejected => 'Rejected';

  @override
  String get verifyErrorOwnReport => 'You cannot verify your own report.';

  @override
  String verifyErrorTooFar(String distanceKm) {
    return 'You must be within 2 km of the report location to verify. Current distance: $distanceKm km.';
  }

  @override
  String get verifyConfirmedMessage => 'Report confirmed successfully';

  @override
  String get verifyDisputedMessage => 'Report disputed';

  @override
  String get verifyErrorAlreadyVoted =>
      'You have already voted on this report.';

  @override
  String get verifyErrorNotPermitted =>
      'Your account is not permitted to verify reports. Verification requires an approved monitor role.';

  @override
  String get verifyErrorNoLongerPending => 'This report is no longer pending.';

  @override
  String get verifyErrorSignedOut => 'You must be signed in to verify reports.';

  @override
  String get verifyErrorFailed => 'Verification failed';

  @override
  String get verifyErrorDisputeReasonRequired =>
      'Please explain why you dispute this report.';

  @override
  String get verifyRequestQueuedOffline =>
      'Offline: request saved and will sync when you are back online.';

  @override
  String get reportActionErrorNoPermissionOrGone =>
      'You do not have permission to change this report, or it no longer exists.';

  @override
  String get reportActionErrorAlreadyPending =>
      'This report is already pending.';

  @override
  String get reportActionErrorGone => 'This report no longer exists.';

  @override
  String get reportActionErrorNoPermission =>
      'You do not have permission to change this report.';

  @override
  String get reportsLoadErrorOffline =>
      'Could not reach the server. Check your connection and retry.';

  @override
  String get offlineSavedWillSync =>
      'Saved offline. It will sync when you are back online.';

  @override
  String get profileErrorOfflineNotSaved =>
      'You\'re offline — changes not saved.';

  @override
  String get profileErrorSignedOut =>
      'You must be signed in to update your profile.';

  @override
  String get profileErrorSaveFailed =>
      'Could not save your changes. Please check your connection and try again.';

  @override
  String get profileErrorNameRequired => 'Please enter your name.';

  @override
  String get profileErrorEmailSignedOut =>
      'You must be signed in to change your email.';

  @override
  String profileEmailConfirmationSent(String email) {
    return 'A confirmation link has been sent to $email. Your email will change after you confirm it.';
  }

  @override
  String get profileErrorEmailReauth =>
      'For security, please log out and sign in again before changing your email.';

  @override
  String get profileErrorEmailInUse =>
      'That email is already in use by another account.';

  @override
  String get profileErrorEmailUpdateFailed =>
      'Could not update email. Please try again.';

  @override
  String get profileErrorLocationIncomplete =>
      'Please select your state, LGA and ward to update your location.';

  @override
  String get profileErrorLocationSignedOut =>
      'You must be signed in to change your location.';

  @override
  String get profileErrorLocationManaged =>
      'Your location is managed by an administrator. Please ask an admin to change the location of a staff account.';

  @override
  String get profileErrorLocationFailed =>
      'Could not update your location. Please check your connection and try again.';

  @override
  String get profileDefaultName => 'User';

  @override
  String get homeVerifyReportsLink => 'Verify Reports';

  @override
  String get homeTabNearby => 'Nearby';

  @override
  String homeZoneStatus(String zone, String status) {
    return '$zone • $status';
  }

  @override
  String get homeEmptyMyReports => 'You haven\'t submitted any reports yet';

  @override
  String get homeOpenNearbyReports => 'Open Nearby Reports';

  @override
  String get homeEmptyNearby => 'No nearby reports';

  @override
  String reportLocationAndTime(String location, String time) {
    return '$location • $time';
  }

  @override
  String get homeZoneSheetTitle => 'Select Monitoring Zone';

  @override
  String get homeZoneAll => 'All Zones (No Filter)';

  @override
  String get homeZoneAllSelected => 'Showing all zones';

  @override
  String homeZoneAllLocalOnly(String error) {
    return 'Showing all zones on this device. $error';
  }

  @override
  String homeZoneChanged(String zone) {
    return 'Monitoring zone changed to $zone';
  }

  @override
  String homeZoneLocalOnly(String zone, String error) {
    return 'Showing $zone on this device. $error';
  }

  @override
  String zoneStateLabel(String state) {
    return '$state State';
  }

  @override
  String get settingsPushPermissionNeeded =>
      'Allow notifications for EWER in your phone settings to receive alerts.';

  @override
  String get settingsPushUnavailable =>
      'Push notifications are unavailable right now. Your choice is saved and will apply when they are.';

  @override
  String get settingsSectionSecurity => 'SECURITY & PRIVACY';

  @override
  String get settingsBiometricSubtitle => 'Use fingerprint or Face ID to login';

  @override
  String get settingsBiometricUnavailable => 'Not available on this device';

  @override
  String get settingsOfflineMode => 'Offline Mode';

  @override
  String get settingsOfflineModeEnabled => 'Offline mode enabled';

  @override
  String get settingsOfflineModeRestoring => 'Restoring connection...';

  @override
  String get settingsLogoutConfirm => 'Are you sure you want to sign out?';

  @override
  String get settingsFooterSystemName => 'Climate Early Warning System (CEWS)';

  @override
  String get biometricErrorNotEnrolled =>
      'No biometrics enrolled. Please add a fingerprint or Face ID in your device Settings first.';

  @override
  String get biometricErrorUnavailable =>
      'Biometrics are not available on this device.';

  @override
  String get biometricErrorLockedOut =>
      'Too many attempts. Biometrics are locked; unlock your device and try again later.';

  @override
  String get biometricErrorFailed =>
      'Biometric authentication failed. Please try again.';

  @override
  String get biometricPromptDefault => 'Please authenticate to continue';

  @override
  String get biometricEnablePrompt => 'Enable biometric login for EWER';

  @override
  String get biometricLoginPrompt => 'Authenticate to login to EWER Mobile';

  @override
  String get biometricTypeFace => 'Face ID';

  @override
  String get biometricTypeFingerprint => 'Fingerprint';

  @override
  String get biometricTypeIris => 'Iris';

  @override
  String get biometricTypeGeneric => 'Biometric';

  @override
  String get authErrorEmailRegistered =>
      'Email is already registered. Please login.';

  @override
  String get authErrorRegistrationFailed =>
      'Registration failed. Please try again.';

  @override
  String get authErrorNetworkRetry =>
      'Network error. Please check your connection and try again.';

  @override
  String get authErrorWeakPassword =>
      'Password is too weak. Use at least 8 characters with letters, numbers and symbols.';

  @override
  String get authErrorAccountRegistered =>
      'This account is already registered. Please login.';

  @override
  String get authErrorRegistrationDisabled =>
      'Registration is currently disabled. Please contact support.';

  @override
  String get authErrorTooManyAttempts =>
      'Too many attempts. Please wait a few minutes before trying again.';

  @override
  String get authErrorLoginFailed => 'Login failed. Please try again.';

  @override
  String get authErrorAccountDisabled =>
      'This account has been disabled. Please contact support.';

  @override
  String get authErrorLoginConnection =>
      'Login failed. Please check your connection.';

  @override
  String get authErrorInvalidCredentials => 'Invalid email or password';

  @override
  String get authErrorTooManyLogins =>
      'Too many login attempts. Please wait a few minutes and try again.';

  @override
  String get authErrorLoginUnexpected =>
      'An unexpected error occurred during login. Please try again.';

  @override
  String get authErrorInvalidPhone => 'Invalid phone number.';

  @override
  String get authErrorSmsUnavailable =>
      'SMS service is not available. Please contact support.';

  @override
  String get authErrorPhoneNotRegistered =>
      'No account found for this number. Please register first.';

  @override
  String get authErrorSmsFailed => 'Failed to send verification SMS.';

  @override
  String get authErrorCodeSendFailed => 'Failed to send verification code.';

  @override
  String get authErrorNoUserContext =>
      'No user context for verification. Please login again.';

  @override
  String get authErrorVerificationFailed =>
      'Verification failed. Please try again.';

  @override
  String get authErrorInvalidCode =>
      'Invalid or expired verification code. Please request a new one.';

  @override
  String get authErrorTooManyAttemptsRetry =>
      'Too many attempts. Please wait a few minutes and try again.';

  @override
  String get authErrorVerifyCodeFailed => 'Failed to verify code.';

  @override
  String get authErrorNotLoggedIn => 'User not logged in';

  @override
  String get authErrorResendFailed =>
      'Failed to resend verification code. Please try again.';

  @override
  String get authErrorResetEmailFailed =>
      'Failed to send reset email. Please try again.';

  @override
  String get authErrorResetWeakPassword =>
      'Password is too weak. The code has been used, so please request a new code and choose a stronger password.';

  @override
  String get authErrorResetCodeInvalid =>
      'This reset code is invalid or has expired. Please request a new one.';

  @override
  String get authErrorResetSamePassword =>
      'Your new password must be different from the old one. The code has been used, so please request a new code.';

  @override
  String get authErrorResetFailed =>
      'Failed to reset password. Please try again.';

  @override
  String get rateLimitAccountLocked =>
      'Account is locked due to too many failed attempts';

  @override
  String rateLimitWaitSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Please wait $count seconds before trying again',
      one: 'Please wait 1 second before trying again',
    );
    return '$_temp0';
  }

  @override
  String rateLimitLockedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Too many failed attempts. Account locked for $count minutes.',
      one: 'Too many failed attempts. Account locked for 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String rateLimitOtpMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Too many OTP requests. Please try again in $count minutes.',
      one: 'Too many OTP requests. Please try again in 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String rateLimitResendSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Please wait $count seconds before requesting another code',
      one: 'Please wait 1 second before requesting another code',
    );
    return '$_temp0';
  }

  @override
  String rateLimitAttemptsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts remaining',
      one: '1 attempt remaining',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitExceeded => 'Rate limit exceeded';

  @override
  String reportErrorMaxPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Maximum $count images allowed',
      one: 'Maximum 1 image allowed',
    );
    return '$_temp0';
  }

  @override
  String get reportErrorMissingHazard => 'Please select a hazard type.';

  @override
  String get reportErrorMissingSeverity => 'Please select a severity level.';

  @override
  String get reportErrorMissingLocation => 'Please add the location details.';

  @override
  String get reportErrorSignedOut =>
      'You must be signed in to submit or save a report.';

  @override
  String get reportSavedAsDraft => 'Saved as draft. Will sync when online.';

  @override
  String get reportSubmittedWithPeers =>
      'Report submitted successfully! Verification requests sent to peers.';

  @override
  String get reportQueuedServerUnreachable =>
      'Could not reach the server. Saved and will sync later.';

  @override
  String syncResultSummary(int count, int failed) {
    return 'Synced $count items. $failed failed.';
  }

  @override
  String get reportErrorPhotoProcessing =>
      'A photo could not be processed. Please remove it or choose another photo.';

  @override
  String get severityLow => 'Ƙarami';

  @override
  String get severityMedium => 'Matsakaici';

  @override
  String get severityHigh => 'Babba';

  @override
  String get severityCritical => 'Mai Gaggawa';

  @override
  String get alertSeverityUnspecified => 'Unspecified severity';

  @override
  String get alertSeverityInfo => 'Info';

  @override
  String get alertSeverityWarning => 'Warning';

  @override
  String reviewDateTodayAt(String time) {
    return 'Today at $time';
  }

  @override
  String reviewDateOnAt(String date, String time) {
    return '$date at $time';
  }

  @override
  String get reviewLocationUnknown =>
      'Exact location unknown - the selected area will be used';

  @override
  String get reviewLocationApproximate =>
      'Location approximate (area centre, no GPS fix)';

  @override
  String get reportDetailsSpeechError =>
      'Speech recognition error. Please try again.';

  @override
  String get reportDetailsCameraUnavailable =>
      'Camera is not available. Please try using the gallery.';

  @override
  String get reportDetailsGalleryError =>
      'Could not access gallery. Please try again.';

  @override
  String get reportDetailsFutureTime =>
      'The incident time cannot be in the future. It has been set to the current time.';

  @override
  String get geoErrorServicesOff =>
      'Location services are turned off. Please enable GPS.';

  @override
  String get geoErrorPermissionDenied => 'Location permission was denied.';

  @override
  String get geoErrorServicesUnavailable =>
      'Could not access location services.';

  @override
  String get geoNoticeLastKnown =>
      'Could not get a fresh GPS fix; using your last known location.';

  @override
  String get geoErrorTimeout =>
      'Timed out waiting for a GPS signal. Move to an open area and try again, or choose your location manually.';

  @override
  String get geoErrorUndetermined =>
      'Could not determine your location. Please try again or choose your location manually.';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get locationPickerSeverityLow => 'Low Severity';

  @override
  String get locationPickerSeverityMedium => 'Medium Severity';

  @override
  String get locationPickerSeverityHigh => 'High Severity';

  @override
  String get locationPickerSeverityCritical => 'Critical Severity';

  @override
  String get locationPickerSeverityLowDesc =>
      'Minor issue. No immediate threat.';

  @override
  String get locationPickerSeverityMediumDesc =>
      'Moderate issue. Monitor situation.';

  @override
  String get locationPickerSeverityHighDesc =>
      'Significant threat to property or health. Response required.';

  @override
  String get locationPickerSeverityCriticalDesc =>
      'Life-threatening situation. Immediate action required.';

  @override
  String get locationPickerSelectedLevel => 'Selected Level';

  @override
  String get locationPickerGpsApproximate => 'Approximate';

  @override
  String get locationPickerLgaHeading => 'LGA';

  @override
  String get locationPickerWardHeading => 'WARD';

  @override
  String get locationPickerUnknownLga => 'Unknown LGA';

  @override
  String get locationPickerUnknownWard => 'Unknown Ward';

  @override
  String get locationPickerAutofilled => 'Auto-filled from GPS';

  @override
  String locationPickerGpsLgaNotFound(String lga, String state) {
    return 'GPS Location ($lga) not found in $state';
  }

  @override
  String get locationPickerGpsUnavailable =>
      'GPS Location unavailable or State not selected';

  @override
  String locationPickerMeters(String distance) {
    return '$distance meters';
  }

  @override
  String locationPickerMetersShort(String distance) {
    return '$distance m';
  }

  @override
  String get reportViewSectionDetails => 'Details';

  @override
  String get reportViewReporter => 'Reporter';

  @override
  String get reportViewReported => 'Reported';

  @override
  String get reportViewSeverity => 'Severity';

  @override
  String get reportViewVerifications => 'Verifications';

  @override
  String reportViewEvidenceCount(int count) {
    return 'Evidence ($count)';
  }

  @override
  String get reportViewCoordinates => 'Coordinates';

  @override
  String reportViewRejectedOn(String date) {
    return 'Report rejected on $date';
  }

  @override
  String get reportViewNoReason => 'No reason was given.';

  @override
  String get myReportsTabActive => 'Active';

  @override
  String get myReportsTabHistory => 'History';

  @override
  String get myReportsSignIn => 'Please sign in to view your reports.';

  @override
  String get myReportsEmptyActiveTitle => 'No active reports';

  @override
  String get myReportsEmptyActiveBody =>
      'Reports you submit will appear here while being verified.';

  @override
  String get myReportsEmptyHistoryTitle => 'No report history';

  @override
  String get myReportsEmptyHistoryBody =>
      'Your approved and rejected reports will appear here.';

  @override
  String get myReportsNewReport => 'New Report';

  @override
  String myReportsRejectionReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get nearbyTitle => 'Nearby Reports';

  @override
  String get nearbyNotAvailableTitle => 'Not available for your account';

  @override
  String get nearbyNotAvailableBody =>
      'Nearby reports are visible to approved monitors and staff. You can follow your own reports under My Reports.';

  @override
  String get nearbyLocationNotSetTitle => 'Location Not Set';

  @override
  String get nearbyLocationNotSetBody =>
      'Set your LGA or monitoring zone in\nyour profile to see reports near you.';

  @override
  String get nearbyLoadErrorTitle => 'Could not load reports';

  @override
  String get nearbyEmptyTitle => 'No Nearby Reports';

  @override
  String get nearbyEmptyBody =>
      'There are no reports from your\narea at this time.';

  @override
  String get alertDetailDefaultTitle => 'Alert';

  @override
  String get alertDetailNotSpecified => 'Not specified';

  @override
  String get alertStatusActive => 'Active';

  @override
  String get alertStatusInactive => 'Inactive';

  @override
  String get alertDetailReportLoadError =>
      'Report details could not be loaded.';

  @override
  String get alertDetailTitle => 'Alert Details';

  @override
  String get alertDetailReportedTime => 'Reported Time';

  @override
  String get alertDetailStatus => 'Status';

  @override
  String get alertDetailNoDescription =>
      'No additional description provided for this alert. Please take necessary precautions and follow local guidelines.';

  @override
  String get alertDetailRecommendedActions => 'Recommended Actions';

  @override
  String get alertDetailAction1 => '1. Stay informed via local news/radio.';

  @override
  String get alertDetailAction2 => '2. Prepare emergency supplies.';

  @override
  String get alertDetailAction3 => '3. Avoid travel to affected areas.';

  @override
  String get alertDetailAction4 => '4. Follow evacuation orders if issued.';

  @override
  String get alertDetailPeerVerificationTitle => 'Peer Verification Required';

  @override
  String get alertDetailPeerVerificationBody =>
      'As an EWM in this ward, please verify if you can confirm this report based on what you\'ve observed.';

  @override
  String get alertDetailCommentLabel => 'Comment (required to dispute)';

  @override
  String get alertDetailCommentHint =>
      'Additional information about this report...';

  @override
  String get commonSubmitting => 'Submitting...';

  @override
  String get voteConfirm => 'Confirm';

  @override
  String get voteDecline => 'Decline';

  @override
  String get alertDetailVerificationSubmitted => 'Verification Submitted';

  @override
  String get alertDetailThanks => 'Thank you for your contribution!';

  @override
  String get alertDetailGoBack => 'Go Back';

  @override
  String get alertDetailDismiss => 'Dismiss';

  @override
  String get alertsFilterAll => 'All Alerts';

  @override
  String get alertsFilterFire => 'Fire';

  @override
  String get alertsBroadcastTooltip => 'Broadcast an alert';

  @override
  String get alertsSeverityFilterTooltip => 'Filter by severity';

  @override
  String get alertsAllSeverities => 'All severities';

  @override
  String get alertsTabBroadcasts => 'Broadcasts';

  @override
  String get alertsTabReportHistory => 'Report History';

  @override
  String get alertsSearchReportsHint => 'Search location, hazard, or ID...';

  @override
  String get alertsSearchAlertsHint => 'Search alerts...';

  @override
  String get alertsClearSearch => 'Clear search';

  @override
  String get alertsLoadError => 'Could not load alerts';

  @override
  String get alertsNoMatching => 'No matching alerts';

  @override
  String get alertsPullToRetry => 'Pull down to try again.';

  @override
  String get alertsEmptyBody =>
      'Official alerts for your area will appear here.';

  @override
  String get alertsAllLgas => 'All LGAs';

  @override
  String get alertsSynchronizing => 'Synchronizing...';

  @override
  String get alertsNoReportsYet => 'No Reports Yet';

  @override
  String get alertsNoMatchingReports => 'No matching reports';

  @override
  String alertsNoReportsForFilter(String filter) {
    return 'No $filter';
  }

  @override
  String get alertsNoReportsYetBody =>
      'When hazards are reported in your area,\nthey\'ll appear here';

  @override
  String get alertsNoMatchingReportsBody =>
      'No matching reports found in this area';

  @override
  String get alertsDisputeRecorded => 'Dispute recorded';

  @override
  String get alertsReportConfirmed => 'Report confirmed';

  @override
  String get accessCodeVerified => 'Account verified successfully!';

  @override
  String get accessCodeNotVerified =>
      'Not verified yet. Please enter the code sent to your email.';

  @override
  String get accessCodeSent => 'Verification code sent!';

  @override
  String get accessCodeNoEmail =>
      'No email found for this account. Please log in again.';

  @override
  String get accessCodeTitle => 'Verify Your Email';

  @override
  String get accessCodeEnterCode => 'Enter Code';

  @override
  String get accessCodeIHaveVerified => 'I have verified my account';

  @override
  String accessCodeBody(String email) {
    return 'We have sent a 6-digit verification code to $email.\nEnter the code to activate your account.';
  }

  @override
  String get accessCodeBodyNoEmail =>
      'We have sent a 6-digit verification code to your email.\nEnter the code to activate your account.';

  @override
  String get forgotTitle => 'Forgot Password?';

  @override
  String get forgotBody =>
      'Enter your email address to receive a password reset code.';

  @override
  String get authEmailHint => 'Enter your email';

  @override
  String get authEmailRequired => 'Please enter your email';

  @override
  String get authEmailInvalid => 'Please enter a valid email';

  @override
  String get forgotSendCode => 'Send Reset Code';

  @override
  String get forgotEmailSentTitle => 'Email Sent!';

  @override
  String forgotEmailSentBody(String email) {
    return 'If an account exists for $email, we have sent a 6-digit reset code.\nEnter it on the next screen to choose a new password.';
  }

  @override
  String get forgotEnterCode => 'Enter Reset Code';

  @override
  String get landingWelcome => 'Welcome to EWER';

  @override
  String get landingSubtitle => 'Early Warning and Early Response System';

  @override
  String get landingTagline =>
      'Empowering communities with real-time hazard reporting and rapid response coordination.';

  @override
  String get landingGetStarted => 'Get Started';

  @override
  String get authSignUp => 'Sign Up';

  @override
  String get authLogin => 'Login';

  @override
  String get validatorPhoneRequired => 'Phone number is required';

  @override
  String get validatorPhoneInvalid =>
      'Please enter a valid Nigerian phone number';

  @override
  String get validatorAddressRequired => 'Address is required';

  @override
  String validatorAddressTooShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Address must be at least $count characters',
    );
    return '$_temp0';
  }

  @override
  String validatorAddressTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Address is too long (max $count characters)',
    );
    return '$_temp0';
  }

  @override
  String validatorFieldRequired(String field) {
    return '$field is required';
  }

  @override
  String validatorFieldMinLength(String field, int count) {
    return '$field must be at least $count characters';
  }

  @override
  String validatorFieldMaxLength(String field, int count) {
    return '$field must not exceed $count characters';
  }

  @override
  String get validatorInvalidCharacters => 'Invalid characters detected';

  @override
  String validatorFieldInvalidCharacters(String field) {
    return '$field contains invalid characters';
  }

  @override
  String get validatorDescriptionRequired => 'Description is required';

  @override
  String validatorDescriptionTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Description must not exceed $count characters',
    );
    return '$_temp0';
  }

  @override
  String get validatorEmailRequired => 'Email is required';

  @override
  String get validatorPasswordRequired => 'Password is required';

  @override
  String validatorPasswordMinLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Password must be at least $count characters',
    );
    return '$_temp0';
  }

  @override
  String get validatorPasswordUppercase =>
      'Must contain at least one uppercase letter';

  @override
  String get validatorPasswordLowercase =>
      'Must contain at least one lowercase letter';

  @override
  String get validatorPasswordNumber => 'Must contain at least one number';

  @override
  String get validatorPasswordSpecial =>
      'Must contain at least one special character';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthFair => 'Fair';

  @override
  String get passwordStrengthGood => 'Good';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String passwordErrorTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Password is too long (max $count characters)',
    );
    return '$_temp0';
  }

  @override
  String get passwordErrorCommon =>
      'This password is too common. Please choose a stronger password';

  @override
  String get passwordErrorSequential =>
      'Password should not contain sequential characters (e.g., 123, abc)';

  @override
  String passwordRequirementLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At least $count characters',
    );
    return '$_temp0';
  }

  @override
  String get passwordRequirementUppercase => 'Uppercase letter';

  @override
  String get passwordRequirementLowercase => 'Lowercase letter';

  @override
  String get passwordRequirementNumber => 'Number';

  @override
  String get passwordRequirementSpecial => 'Special character';

  @override
  String get passwordRequirementNotCommon => 'Not a common password';

  @override
  String get authLoginCheckCredentials =>
      'Login failed. Please check your credentials.';

  @override
  String get loginWelcomeBack => 'Welcome Back';

  @override
  String get loginSubtitle => 'Sign in to your account';

  @override
  String get authPhoneNumber => 'Phone Number';

  @override
  String get authPassword => 'Password';

  @override
  String get loginRememberMe => 'Remember Me';

  @override
  String get loginNoAccount => 'Don\'t have an account? ';

  @override
  String get loginDataSecure => 'Your data is encrypted and secure';

  @override
  String get loginLockedTitle => 'CRADI Mobile Locked';

  @override
  String get loginUnlockBiometrics => 'Unlock with Biometrics';

  @override
  String get loginLogoutDifferentAccount => 'Log out and use different account';

  @override
  String get authMethodEmail => 'Email';

  @override
  String get authMethodPhone => 'Phone';

  @override
  String get loginSendCode => 'Send Code';

  @override
  String get otpSuccess => 'Verification successful!';

  @override
  String get otpNewCodeSent => 'A new code has been sent.';

  @override
  String get otpVerifyEmail => 'Verify Email';

  @override
  String otpCodeSentTo(String destination) {
    return 'Enter the 6-digit code sent to\n$destination';
  }

  @override
  String get otpSecureCode => 'Secure Code';

  @override
  String get otpCodeHint => 'Enter 6-digit code';

  @override
  String get otpCodeRequired => 'Please enter the code';

  @override
  String get otpCodeInvalidFormat => 'Invalid code format';

  @override
  String get otpVerifyAndLogin => 'Verify & Login';

  @override
  String get otpNoCode => 'Didn\'t receive code? ';

  @override
  String otpResendIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Resend in ${count}s',
    );
    return '$_temp0';
  }

  @override
  String get pendingTitle => 'Approval Pending';

  @override
  String get pendingBody =>
      'Your account has been created successfully but is waiting for admin approval.\n\nYou will be able to access the full application once an administrator reviews and approves your account.';

  @override
  String get pendingStillWaiting => 'Your account is still awaiting approval.';

  @override
  String get pendingCheckStatus => 'Check approval status';

  @override
  String get pendingContactSupport => 'Contact Support';

  @override
  String get registrationPrivacyTitle => 'Data Privacy Notice';

  @override
  String get registrationDecline => 'Decline';

  @override
  String get registrationAgree => 'I Agree';

  @override
  String get registrationMustAccept =>
      'You must accept the Data Privacy Notice to register.';

  @override
  String get registrationSelectState => 'Please select a state';

  @override
  String get registrationSelectLga => 'Please select an LGA';

  @override
  String get registrationSelectWard => 'Please select a ward';

  @override
  String get registrationVerifyPhoneTitle => 'Verify Your Phone Number';

  @override
  String registrationPhoneCodeSent(String phone) {
    return 'A 6-digit verification code has been sent to $phone.\n\nPlease enter the code to activate your account.';
  }

  @override
  String get registrationAccountCreated => 'Account created!';

  @override
  String get registrationVerifyEmailTitle => 'Verify Your Email Address';

  @override
  String registrationEmailCodeSent(String email) {
    return 'Account created successfully!\n\nA 6-digit verification code has been sent to $email.\n\nPlease enter the code to activate your account.';
  }

  @override
  String get registrationCreateAccount => 'Create Account';

  @override
  String get registrationJoinNetwork => 'Join the Network';

  @override
  String get registrationSelectLocation =>
      'Select your location to get started.';

  @override
  String get registrationMethod => 'Registration Method';

  @override
  String get registrationPersonalInfo => 'Personal Information';

  @override
  String get registrationNameHint => 'John Doe';

  @override
  String get registrationNameField => 'Name';

  @override
  String get registrationAddressLabel => 'Address Description';

  @override
  String get registrationAddressHint => 'e.g., No 5, Main Street';

  @override
  String get registrationAddressField => 'Address';

  @override
  String get registrationSecurity => 'Security';

  @override
  String get registrationPasswordHint => 'Create a password';

  @override
  String get registrationConfirmPassword => 'Confirm Password';

  @override
  String get registrationConfirmPasswordHint => 'Re-enter your password';

  @override
  String get registrationConfirmPasswordRequired =>
      'Please confirm your password';

  @override
  String get registrationPasswordsMismatch => 'Passwords do not match';

  @override
  String get registrationSendOtp => 'Send OTP & Register';

  @override
  String get registrationHaveAccount => 'Already have an account? ';

  @override
  String get registrationCreating => 'Creating account...';

  @override
  String get privacyNoticeText =>
      'Nigeria Data Protection Act (NDPA) — Data Processing Notice\n\nYour data is processed by EWER Mobile (a CRADI / KusuConsult-NG service) for climate hazard early warning purposes.\n\n• Data collected: name, phone, email, location (state/LGA/ward), hazard reports, and a push-notification device identifier.\n• Purpose: community hazard reporting, peer verification, and emergency alerts.\n• Storage: Supabase (PostgreSQL) cloud database; push notifications are delivered via OneSignal and crash diagnostics may be sent to Sentry.\n• International transfer: Pursuant to NDPA Article 24, we disclose that your data may be transferred to and stored on servers outside Nigeria. This transfer is necessary to provide the service. You have the right to withdraw consent at any time by deleting your account.\n• Retention: Data is retained for 5 years after your last activity, then anonymised.\n• Your rights: access, rectification, erasure, and data portability under the NDPA 2023.\n\nBy tapping \"I Agree\", you consent to these terms and the international transfer of your personal data.';

  @override
  String get aboutAppName => 'EWER Mobile';

  @override
  String get aboutTagline => 'Early Warning System';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version (Build $build)';
  }

  @override
  String aboutCopyright(String year) {
    return '© $year EWER. All rights reserved.';
  }

  @override
  String get aboutPrivacyPolicy => 'Privacy Policy';

  @override
  String get resetCodeResent =>
      'If an account exists, a new code has been sent.';

  @override
  String get resetTitle => 'Create New Password';

  @override
  String get resetBody =>
      'Enter the 6-digit code from the reset email and choose a new secure password.';

  @override
  String get resetCodeLabel => 'Reset Code';

  @override
  String get resetSendingCode => 'Sending…';

  @override
  String get resetSendCode => 'Send code';

  @override
  String get resetCodeRequired => 'Enter the code from the email';

  @override
  String get resetNewPassword => 'New Password';

  @override
  String get resetSubmit => 'Reset Password';

  @override
  String get resetSuccessTitle => 'Password Reset!';

  @override
  String get resetSuccessBody =>
      'Your password has been reset successfully. You can now login with your new password.';

  @override
  String get resetContinueToLogin => 'Continue to Login';

  @override
  String get offlineSyncingPending => 'Syncing pending data...';

  @override
  String get offlineDiscardTitle => 'Discard report?';

  @override
  String get offlineDiscardBody =>
      'This report has not been sent and will be deleted from this device.';

  @override
  String get offlineDiscard => 'Discard';

  @override
  String get offlineActions => 'Actions';

  @override
  String get offlineSubmitAsMe => 'Submit as me';

  @override
  String get offlineNoInternet => 'No Internet Connection';

  @override
  String get offlineCanViewSaved =>
      'You can still view your saved guides and draft reports.';

  @override
  String get offlineReconnectToSignIn => 'Reconnect to sign in.';

  @override
  String get offlineTryReconnect => 'Try Reconnecting & Sync';

  @override
  String get offlineModeEnabledInSettings =>
      'Offline Mode is enabled in Settings.';

  @override
  String get offlineGoOnline => 'Go online';

  @override
  String get offlineStillNoInternet => 'Still no internet connection';

  @override
  String get offlineOpenSettings => 'Open Settings';

  @override
  String get offlineViewSavedGuides => 'View Saved Guides';

  @override
  String get offlineNoPending => 'No pending reports';

  @override
  String get offlineStatusOwnerless =>
      'Saved by an earlier version: submit or discard it';

  @override
  String get offlineStatusFailed => 'Failed, will not sync automatically';

  @override
  String offlineStatusFailedWithError(String error) {
    return 'Failed, will not sync automatically: $error';
  }

  @override
  String get offlineStatusWaiting => 'Waiting to sync';

  @override
  String offlineItemSubtitle(String location, String date, String status) {
    return '$location\n$date • $status';
  }

  @override
  String get roleUser => 'User';

  @override
  String get roleEwm => 'Early Warning Monitor';

  @override
  String get roleEwv => 'Early Warning Validator';

  @override
  String get roleEwr => 'Early Warning Responder';

  @override
  String get roleLdpCoordinator => 'LDP Coordinator';

  @override
  String get roleProjectStaff => 'Project Staff';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleTechSupport => 'Tech Support';

  @override
  String get profilePhotoUpdated => 'Profile photo updated!';

  @override
  String get profileCameraUnavailable =>
      'Camera not available. Please use the gallery.';

  @override
  String get profilePickImageFailed =>
      'Failed to pick image. Please try again.';

  @override
  String get profileUpdatePhoto => 'Update Profile Photo';

  @override
  String get profileChooseGallery => 'Choose from Gallery';

  @override
  String get profileChooseGallerySubtitle => 'Select a photo from your device';

  @override
  String get profileCameraWebUnavailable => 'Camera not available on web';

  @override
  String get profileUseGallery => 'Please use the gallery option';

  @override
  String get profilePhotoLibrary => 'Photo Library';

  @override
  String get profileEdit => 'Edit Profile';

  @override
  String get profileAskAdminArea => 'Ask an admin to change your area';

  @override
  String get profileVerifyAccount => 'Verify Account';

  @override
  String get profileVerifyAccountBody =>
      'Enter the Access Code sent to your email to verify your account.';

  @override
  String get profileAccessCode => 'Access Code';

  @override
  String get profileAccessCodeHint => 'e.g., ABC-123';

  @override
  String get commonNotAvailable => 'N/A';

  @override
  String profileIdLabel(String code) {
    return 'ID: $code';
  }

  @override
  String get profileVerified => 'Verified';

  @override
  String get profileUnverified => 'Unverified';

  @override
  String get profileVerifyNow => 'Verify Now';

  @override
  String get profileStatReports => 'Reports';

  @override
  String get profileAccountSettings => 'Account Settings';

  @override
  String get profileBiometricsEnabled => 'Biometrics enabled!';

  @override
  String get profileBiometricChangeFailed => 'Could not change biometric login';

  @override
  String get profileSyncingOffline => 'Syncing offline data...';

  @override
  String get profileSyncComplete => 'Sync complete!';

  @override
  String get profileSupportChat => 'Support Chat';

  @override
  String get profileSosButton => 'SOS / Emergency Call';

  @override
  String get sosTitle => 'SOS Emergency';

  @override
  String get sosBody =>
      'Call for help directly. This does not send an alert through the app.';

  @override
  String sosCallEmergency(String phone) {
    return 'Call Emergency ($phone)';
  }

  @override
  String get sosNationalNumber => 'National emergency number';

  @override
  String get sosContactsLoadError =>
      'Couldn\'t load your contacts. Check your connection and try again.';

  @override
  String get sosNoContacts =>
      'No personal emergency contacts saved yet. Add them under Emergency Contacts.';

  @override
  String sosCallContact(String name) {
    return 'Call $name';
  }

  @override
  String sosContactSubtitle(String role, String phone) {
    return '$role · $phone';
  }

  @override
  String sosDialFailed(String phone) {
    return 'Could not open the phone app. Dial $phone.';
  }

  @override
  String get chatLoginRequired => 'Please login to chat';

  @override
  String get chatLoadError => 'Could not load messages.';

  @override
  String get chatMe => 'Me';

  @override
  String chatRateLimited(String reason) {
    return '$reason. Please wait a moment.';
  }

  @override
  String chatSendFailed(String error) {
    return 'Message not sent. $error';
  }

  @override
  String get contactsNameRequired => 'Name is required';

  @override
  String get contactsNameTooLong => 'Name is too long';

  @override
  String get contactsPhoneDigitsOnly =>
      'Use digits only (optionally starting with +)';

  @override
  String get contactsPhoneInvalid => 'Enter a valid phone number';

  @override
  String get contactsLaunchPhoneFailed => 'Could not launch phone app';

  @override
  String get contactsLaunchSmsFailed => 'Could not launch SMS app';

  @override
  String get contactsAdded => 'Contact added successfully';

  @override
  String get contactsUpdated => 'Contact updated successfully';

  @override
  String get contactsDeleteTitle => 'Delete contact?';

  @override
  String contactsDeleteBody(String name) {
    return 'Remove $name from your emergency contacts?';
  }

  @override
  String get contactsDeleted => 'Contact deleted';

  @override
  String get contactsTitle => 'Emergency Contacts';

  @override
  String get contactsAddTooltip => 'Add contact';

  @override
  String get contactsSearchHint => 'Search name, LGA, or role';

  @override
  String get contactsEmpty => 'No contacts found';

  @override
  String get contactsEmergencyButton => 'Emergency 112';

  @override
  String get contactsMoreActions => 'More actions';

  @override
  String get contactsEditTitle => 'Edit Emergency Contact';

  @override
  String get contactsAddTitle => 'Add Emergency Contact';

  @override
  String get contactsNameLabel => 'Name *';

  @override
  String get contactsRoleLabel => 'Role';

  @override
  String get contactsPhoneLabel => 'Phone *';

  @override
  String get contactsOrganizationLabel => 'Organization (Optional)';

  @override
  String get contactsLgaLabel => 'LGA (Optional)';

  @override
  String get contactsCategoryLabel => 'Category';

  @override
  String get contactsAdd => 'Add';

  @override
  String get contactsFilterAll => 'All';

  @override
  String get contactsFilterCoordinators => 'Coordinators';

  @override
  String get contactsCategoryCoordinator => 'Coordinator';

  @override
  String get contactsCategoryEmergency => 'Emergency';

  @override
  String get contactsCategoryAgriExtension => 'Agri-Extension';

  @override
  String get contactsCategoryOther => 'Other';

  @override
  String contactsRoleAndLga(String role, String lga) {
    return '$role • $lga';
  }

  @override
  String get knowledgeCategoryAll => 'All';

  @override
  String get knowledgeCategoryFlood => 'Flood';

  @override
  String get knowledgeCategoryFire => 'Fire';

  @override
  String get knowledgeCategoryErosion => 'Erosion';

  @override
  String get knowledgeCategoryStorm => 'Storm';

  @override
  String get knowledgeCategoryExtremeHeat => 'Extreme Heat';

  @override
  String get knowledgeCategoryEarthquake => 'Earthquake';

  @override
  String get knowledgeCategoryDisease => 'Disease';

  @override
  String get knowledgeCategoryConflict => 'Conflict';

  @override
  String get knowledgeCategoryAccident => 'Accident';

  @override
  String get knowledgeCategorySafety => 'Safety';

  @override
  String get knowledgeCategoryGeneral => 'General';

  @override
  String get knowledgeTagGuide => 'GUIDE';

  @override
  String get knowledgeLoadError => 'Failed to fetch guides. Please try again.';

  @override
  String get knowledgeGuidesTitle => 'Hazard Guides';

  @override
  String get knowledgeBaseCaption => 'KNOWLEDGE BASE';

  @override
  String get knowledgeGuidesSearchHint => 'Search guides, signs, or hazards...';

  @override
  String get knowledgeNoGuidesCategory => 'No guides found for this category';

  @override
  String knowledgeNoGuidesMatch(String query) {
    return 'No guides match \"$query\"';
  }

  @override
  String get knowledgeNoTitle => 'No Title';

  @override
  String get knowledgeSubtitleManual => 'Manual';

  @override
  String get knowledgeNewsLoadError => 'Failed to load news. Please try again.';

  @override
  String get knowledgeBaseTitle => 'Knowledge Base';

  @override
  String get knowledgeBaseSearchHint =>
      'Search guides, hazards, or contacts...';

  @override
  String get knowledgeOfflineActive => 'Offline Mode Active';

  @override
  String get knowledgeOfflineAvailable => 'Offline Mode Available';

  @override
  String get knowledgeUsingCache => 'Using cached data';

  @override
  String get knowledgeContentDownloaded => 'Content downloaded successfully';

  @override
  String get knowledgeFeaturedGuides => 'Featured Guides';

  @override
  String get knowledgeNoGuides => 'No guides available';

  @override
  String get knowledgeHazardIdGuides => 'Hazard ID Guides';

  @override
  String get knowledgeHazardIdGuidesDesc => 'Identify local threats';

  @override
  String get knowledgeFireResponse => 'Fire Response';

  @override
  String get knowledgeFireResponseDesc => 'Wildfire protocols';

  @override
  String get knowledgeFloodReadiness => 'Flood Readiness';

  @override
  String get knowledgeFloodReadinessDesc => 'Water & Storms';

  @override
  String get knowledgeContactsDirectory => 'Contacts Directory';

  @override
  String get knowledgeContactsDirectoryDesc => 'Emergency services';

  @override
  String get knowledgeExternalNews => 'External News & Updates';

  @override
  String get knowledgeNoNews => 'No recent news updates found.';

  @override
  String get knowledgeDetailTitle => 'Guide Detail';

  @override
  String get knowledgeBookmarked => 'Guide bookmarked';

  @override
  String get knowledgeBookmarkRemoved => 'Bookmark removed';

  @override
  String get knowledgeNoTextToSpeak => 'No text to speak';

  @override
  String get knowledgeTtsUnavailable =>
      'Text-to-speech is unavailable. Please try again.';

  @override
  String knowledgeUpdatedOn(String date) {
    return 'Updated $date';
  }

  @override
  String get knowledgeUpdatedRecently => 'Updated recently';

  @override
  String knowledgeReadTime(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min read',
      one: '1 min read',
    );
    return '$_temp0';
  }

  @override
  String get knowledgeContentComingSoon => 'Detailed content coming soon.';

  @override
  String get knowledgeRelatedTopics => 'Related Topics';

  @override
  String get knowledgeNoRelated => 'No related topics found.';

  @override
  String get knowledgeShareDefaultTitle => 'CRADI Guide';

  @override
  String knowledgeShareText(String content) {
    return '$content\n\nShared via CRADI Early Warning App';
  }

  @override
  String get helpSupportEmailSubject => 'CRADI App Support Request';

  @override
  String get helpSupportEmailBody => 'Please describe your issue:\n\n';

  @override
  String helpNoEmailApp(String email) {
    return 'No email app found. Contact $email';
  }

  @override
  String get helpFaqTitle => 'Frequently Asked Questions';

  @override
  String get helpFaqReportQ => 'How do I report a hazard?';

  @override
  String get helpFaqReportA =>
      'Navigate to the \"Report\" tab or tap the \"+\" button on the dashboard. Select the hazard type, add photos/videos, and submit your report.';

  @override
  String get helpFaqColorsQ => 'What do the alert colors mean?';

  @override
  String get helpFaqColorsA =>
      'Red indicates high severity (immediate danger), Orange is medium, and Yellow is low. Blue typically indicates water-related hazards like floods.';

  @override
  String get helpFaqOfflineQ => 'Can I report without internet?';

  @override
  String get helpFaqOfflineA =>
      'Yes! Use \"Offline Mode\" in Settings. Your reports will be saved locally and can be synced when you go online.';

  @override
  String get helpFaqVerifyQ => 'How do I verify other reports?';

  @override
  String get helpFaqVerifyA =>
      'Go to \"Alerts\" and look for pending reports nearby. You can confirm or reject them based on your observation.';

  @override
  String get helpStillNeedHelp => 'Still need help?';

  @override
  String get notificationsAllRead => 'All notifications marked as read';

  @override
  String get notificationsClearAll => 'Clear All';

  @override
  String get notificationsClearConfirm =>
      'Are you sure you want to delete all notifications?';

  @override
  String get notificationsMarkAllRead => 'Mark all as read';

  @override
  String get notificationsClearAllMenu => 'Clear all';

  @override
  String get notificationsEmpty => 'No notifications yet';

  @override
  String get notificationsDefaultTitle => 'Notification';

  @override
  String get voteDispute => 'Dispute';

  @override
  String get voteDisputeRecorded =>
      'Dispute recorded. Staff will review the report.';

  @override
  String get voteConfirmedThanks => 'Report confirmed. Thank you!';

  @override
  String get exportRejectedOnly => 'Rejected only';

  @override
  String get exportPreparing => 'Preparing export…';

  @override
  String get exportCopied => 'CSV copied to the clipboard.';

  @override
  String exportSavedTo(String path) {
    return 'Report saved to $path';
  }

  @override
  String get exportShareSubject => 'CRADI reports export';

  @override
  String exportShareFailed(String path) {
    return 'Could not open the share sheet. The report is saved to $path';
  }

  @override
  String get statusBadgeVerified => 'VERIFIED';

  @override
  String get statusBadgeApproved => 'APPROVED';

  @override
  String get statusBadgeRejected => 'REJECTED';

  @override
  String get statusBadgePending => 'PENDING VERIFICATION';

  @override
  String get verificationDetailTitle => 'Verify Report';

  @override
  String get verificationDetailUnknownTime => 'Unknown time';

  @override
  String get verificationDetailNoLocation => 'No location details';

  @override
  String get verificationDetailNoMap => 'No map location available';

  @override
  String get verificationDetailQuestion => 'Can you confirm this report?';

  @override
  String get verificationDetailInstructions =>
      'Please verify if you have observed this hazard in the reported location.';

  @override
  String get verificationDetailCommentHint =>
      'Add details about what you see...';

  @override
  String get verificationDetailConfirm => 'I Can Confirm';

  @override
  String get verificationListRequestTooltip => 'Request verification';

  @override
  String get verificationListEmpty => 'No reports pending verification';

  @override
  String get verificationRequestSubmitted =>
      'Verification request submitted successfully';

  @override
  String get verificationRequestTitle => 'Request Verification';

  @override
  String get verificationRequestDescriptionHint =>
      'Describe what needs verification...';

  @override
  String get verificationRequestSubmit => 'Submit Request';

  @override
  String get disputeDialogTitle => 'Dispute report?';

  @override
  String get disputeDialogLabel => 'What is wrong with this report? (required)';

  @override
  String get staffRejected => 'Report rejected.';

  @override
  String get staffActionsTitle => 'Staff actions';

  @override
  String get staffApproved => 'Report approved.';

  @override
  String get staffApprove => 'Approve';

  @override
  String get staffReopened => 'Report reopened for verification.';

  @override
  String get staffRejectTitle => 'Reject report?';

  @override
  String get staffRejectReasonLabel => 'Reason (required)';

  @override
  String get staffRejectReasonHint => 'Shown to the reporter';

  @override
  String get staffRejectReasonRequired => 'Please give a reason.';

  @override
  String get verificationsLoadError => 'Could not load peer verifications.';

  @override
  String get verificationsTitle => 'Peer verifications';

  @override
  String get verificationsNone => 'No peer votes yet.';

  @override
  String verificationsSummary(int confirmed, int disputed) {
    return '$confirmed confirmed · $disputed disputed';
  }

  @override
  String get verificationsYou => 'You';

  @override
  String get verificationsPeerVerifier => 'Peer verifier';

  @override
  String verificationsVoteBy(String kind, String who) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'confirmed': 'Confirmed by $who',
      'other': 'Disputed by $who',
    });
    return '$_temp0';
  }

  @override
  String verificationsVoteByAt(String kind, String who, String date) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'confirmed': 'Confirmed by $who · $date',
      'other': 'Disputed by $who · $date',
    });
    return '$_temp0';
  }

  @override
  String get voteQuestion => 'Can you verify this report?';

  @override
  String get adminCountsError => 'Could not load dashboard counts';

  @override
  String get adminCountsErrorBody =>
      'Check your connection and permissions, then retry.';

  @override
  String get adminHealthDatabase => 'Database';

  @override
  String adminHealthActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active',
    );
    return '$_temp0';
  }

  @override
  String adminHealthReportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports',
      one: '1 report',
    );
    return '$_temp0';
  }

  @override
  String get adminAlertBroadcastSuccess => '✅ Alert broadcast successfully';

  @override
  String adminAlertSendFailed(String error) {
    return 'Failed to send alert: $error';
  }

  @override
  String get adminAlertDismissFailed => 'Could not dismiss alert.';

  @override
  String get adminAlertCompose => 'Compose Alert';

  @override
  String get adminAlertTargetArea => 'Target Area';

  @override
  String get adminAlertAllAreas => '🌍 All Areas';

  @override
  String get adminAlertTitleLabel => 'Alert Title';

  @override
  String get adminAlertRequired => 'Required';

  @override
  String get adminAlertMessageLabel => 'Message';

  @override
  String get adminAlertBroadcastButton => 'Broadcast Alert';

  @override
  String get adminAlertsLoadError =>
      'Could not load alerts. You may not have permission to view them.';

  @override
  String get adminAlertDismissTooltip => 'Dismiss alert';

  @override
  String get adminGuideDeleteTitle => 'Delete Guide';

  @override
  String get adminGuideDeleteBody =>
      'Are you sure you want to delete this guide? This cannot be undone.';

  @override
  String get adminGuideDeleteDenied =>
      'You do not have permission to delete this guide, or it was already removed.';

  @override
  String get adminGuideDeleteFailed =>
      'Could not delete guide. Check your connection and try again.';

  @override
  String get adminGuideDeleted => 'Guide deleted';

  @override
  String get adminGuideAdd => 'Add Guide';

  @override
  String get adminGuidesLoadError => 'Error loading guides';

  @override
  String get adminGuidesEmpty => 'No guides found';

  @override
  String get adminGuideAddFirst => 'Add the first guide';

  @override
  String get adminGuideEditMenu => '✏️ Edit';

  @override
  String get adminGuideDeleteMenu => '🗑️ Delete';

  @override
  String get adminGuideUpdated => 'Guide updated';

  @override
  String get adminGuideCreated => 'Guide created';

  @override
  String get adminGuideEditTitle => 'Edit Guide';

  @override
  String get adminGuideNewTitle => 'New Guide';

  @override
  String get adminGuideCategoryLabel => 'Category / Hazard Type';

  @override
  String get adminGuideTitleLabel => 'Guide Title';

  @override
  String get adminGuideSourceLabel => 'Source (e.g. NEMA, WHO)';

  @override
  String get adminGuideContentLabel => 'Content (Markdown supported)';

  @override
  String get adminGuideUpdate => 'Update Guide';

  @override
  String get adminGuideCreate => 'Create Guide';

  @override
  String get adminReportsLoadError =>
      'Could not load reports. You may not have permission to view them.';

  @override
  String get adminReportsRejectReasonLabel => 'Reason (recommended)';

  @override
  String get adminReportsRejectReasonHint =>
      'Why is this report being rejected?';

  @override
  String adminReportsStatusUpdateFailed(String error) {
    return 'Could not update report status: $error';
  }

  @override
  String get adminReportsReopened => 'Report reopened for verification';

  @override
  String adminReportsMarkedAs(String status) {
    return 'Report marked as $status';
  }

  @override
  String get adminReportsDateTime => 'Date/Time';

  @override
  String get adminReportsLga => 'LGA';

  @override
  String get adminReportsLocationDetails => 'Location Details';

  @override
  String get adminReportsRejectionReason => 'Rejection reason';

  @override
  String get adminReportsNoReason => 'No reason given';

  @override
  String get adminReportsImages => 'Images';

  @override
  String get adminReportsMarkVerified => 'Mark Verified';

  @override
  String get adminReportsReopen => 'Reopen (pending)';

  @override
  String get adminReportsReopenReset => 'Reopen (reset to pending)';

  @override
  String get adminReportsEmpty => 'No reports found';

  @override
  String get adminReportsLoadMoreError => 'Could not load more. Tap to retry.';

  @override
  String get adminReportsLoadMore => 'Load more';

  @override
  String get adminUsersLoadError =>
      'Could not load users. You may not have permission to view them.';

  @override
  String get adminUsersEmpty => 'No users found';

  @override
  String get adminUsersNoPermission =>
      'You do not have permission to change this user.';

  @override
  String get adminUsersUpdateFailed => 'Update failed. Please try again.';

  @override
  String get adminUsersApproved => 'User approved';

  @override
  String get adminUsersRejected => 'User rejected';

  @override
  String get adminUsersChangeRole => 'Change Role';

  @override
  String get adminUsersRoleUpdated =>
      'Role updated. It takes effect once the user is approved.';

  @override
  String get adminUsersApply => 'Apply';

  @override
  String get adminUsersChangeLocationTitle => 'Change location';

  @override
  String adminUsersLocationUpdated(String ward, String lga, String state) {
    return 'Location updated to $ward, $lga, $state';
  }

  @override
  String get adminUsersDisabled => 'User disabled';

  @override
  String get adminUsersReenabled => 'User re-enabled';

  @override
  String get adminUsersSearchHint => 'Search by name or email…';

  @override
  String get adminUsersAllRoles => 'All Roles';

  @override
  String get adminUsersShowingPending => 'Showing Pending Approvals';

  @override
  String get adminUsersShowingApproved => 'Showing Approved Users';

  @override
  String get adminUsersPendingChip => 'Pending';

  @override
  String get adminUsersApproveMenu => '✅ Approve';

  @override
  String get adminUsersRevokeMenu => '❌ Revoke access';

  @override
  String get adminUsersChangeRoleMenu => '🔄 Change role';

  @override
  String get adminUsersChangeLocationMenu => '📍 Change location';

  @override
  String get adminUsersReenableMenu => '🔓 Re-enable user';

  @override
  String get adminUsersDisableMenu => '🚫 Disable user';

  @override
  String get onboardingWelcomeBody =>
      'Early Warning and Emergency Response system for your community';

  @override
  String get onboardingMonitorTitle => 'Monitor Hazards in Real-Time';

  @override
  String get onboardingMonitorBody =>
      'Report emergencies, track hazards, and keep your community safe';

  @override
  String get onboardingJoinBody =>
      'Create an account and start protecting your community today';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get splashTagline => 'Early Warning & Emergency Response';

  @override
  String get connectivityOfflineBanner =>
      'Offline - Some features may be unavailable';

  @override
  String get routeReportNotFound => 'Report not found';

  @override
  String get routeViewReports => 'View reports';

  @override
  String get routeAlertNotFound => 'Alert not found';

  @override
  String get routeViewAlerts => 'View alerts';

  @override
  String get routeNotFoundTitle => 'Page not found';

  @override
  String get routeNotFoundBody =>
      'The page you were looking for does not exist.';

  @override
  String get routeTryAgain => 'Try again';

  @override
  String get routeGoHome => 'Go home';

  @override
  String get routeLoadFailedTitle => 'Could not load';

  @override
  String get routeLoadFailedBody => 'Check your connection and try again.';

  @override
  String get routeMissingBody =>
      'It may have been removed, or you may not have access to it.';

  @override
  String get forceUpdateStoreFailed =>
      'Could not open the store. Please update the app from your app store.';

  @override
  String get forceUpdateTitle => 'Update required';

  @override
  String get forceUpdateDefaultMessage =>
      'Please update the EWER app to continue.';

  @override
  String forceUpdateMinVersion(String version) {
    return 'Minimum version: $version';
  }

  @override
  String get forceUpdateButton => 'Update';

  @override
  String get forceUpdateCheckAgain => 'Check again';

  @override
  String formFieldRequiredLabel(String label) {
    return '$label *';
  }

  @override
  String get locationSelectorLgaLabel => 'Local Government Area';

  @override
  String get permissionLocationTitle => 'Location Access';

  @override
  String get permissionLocationRationale =>
      'EWER needs your location to accurately pinpoint hazards and alert nearby responders. Your location is only used when you submit a report or use the tactical map.';

  @override
  String get permissionNotificationsTitle => 'Enable Alerts';

  @override
  String get permissionNotificationsRationale =>
      'Get real-time updates about hazards in your area. We only send critical safety alerts and status updates for your reports.';

  @override
  String get permissionPhotosTitle => 'Photo Access';

  @override
  String get permissionPhotosRationale =>
      'EWER needs access to your photos so you can upload evidence of hazards. We only upload photos you explicitly select.';

  @override
  String get permissionNotNow => 'Not Now';

  @override
  String permissionSettingsBody(String reason) {
    return '$reason\n\nPlease enable this in your device settings.';
  }

  @override
  String offlineDraftLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You can keep at most $count unsent reports on this device. Sync or discard some first.',
    );
    return '$_temp0';
  }
}
