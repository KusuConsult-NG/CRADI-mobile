// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Nigerian Pidgin (`pcm`).
class AppLocalizationsPcm extends AppLocalizations {
  AppLocalizationsPcm([String locale = 'pcm']) : super(locale);

  @override
  String get appTitle => 'EWER Early Warning';

  @override
  String get monitoringZone => 'Area Wey We Dey Watch';

  @override
  String get toVerify => 'To Confam';

  @override
  String get alerts => 'Alerts';

  @override
  String get myReports => 'My Reports';

  @override
  String get browseCategories => 'Check Categories';

  @override
  String get noReportsToVerify => 'No report dey to confam';

  @override
  String get noActiveAlerts => 'No alert dey now';

  @override
  String get seeAll => 'See Everything';

  @override
  String get notifications => 'NOTIFICATIONS';

  @override
  String get pushNotifications => 'Push Notifications';

  @override
  String get general => 'GENERAL';

  @override
  String get language => 'Language';

  @override
  String get helpFaq => 'Help & Questions';

  @override
  String get aboutApp => 'About Di App';

  @override
  String get logout => 'Log Out';

  @override
  String get back => 'Go Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Change';

  @override
  String get continueButton => 'Continue';

  @override
  String get retry => 'Try Again';

  @override
  String get close => 'Close';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get verifyPhoneNumber => 'Confam Phone Number';

  @override
  String get resendCode => 'Send Code Again';

  @override
  String get verify => 'Confam';

  @override
  String get selectHazard => 'Choose Hazard';

  @override
  String get whatIncident => 'Wetin kind wahala you wan report?';

  @override
  String get erosion => 'Erosion';

  @override
  String get howSevereSituation => 'How bad di matter be?';

  @override
  String get setSeverity => 'Set How Bad E Be';

  @override
  String get nextLocation => 'Next: Location';

  @override
  String get lowMinorImpact => 'Low - E no too bad';

  @override
  String get mediumNoticeableImpact => 'Medium - You go fit notice am';

  @override
  String get highSignificantDamage => 'High - E don scatter plenty tins';

  @override
  String get criticalLifeThreatening => 'Critical - Life dey for danger';

  @override
  String get camera => 'Camera';

  @override
  String get useMyLocationInfo => 'Use My Location';

  @override
  String get myProfile => 'My Profile';

  @override
  String get editProfileDetails => 'Change Profile Details';

  @override
  String get fullName => 'Full Name';

  @override
  String get emailAddress => 'Email Address';

  @override
  String get biometricLogin => 'Biometric Login';

  @override
  String get enabled => 'E dey on';

  @override
  String get disabled => 'E dey off';

  @override
  String get languagePreference => 'Language Wey You Like';

  @override
  String get offlineDataSync => 'Offline Data Sync';

  @override
  String get upToDate => 'E don up to date';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get biometricsNotAvailable => 'Biometrics no dey dis phone';

  @override
  String get biometricsEnabled => 'Biometric login don on';

  @override
  String get biometricsDisabled => 'Biometric login don off';

  @override
  String get profileUpdated => 'Profile don update well well!';

  @override
  String get syncing => 'E dey sync...';

  @override
  String get offline => 'Offline';

  @override
  String get offlineModeReady => 'Offline Mode Don Ready: ';

  @override
  String get validation_required => 'You must fill dis one';

  @override
  String get validation_invalidEmail => 'Abeg put correct email address';

  @override
  String validation_minLength(int length) {
    return 'E must reach at least $length characters';
  }

  @override
  String validation_maxLength(int length) {
    return 'E no fit pass $length characters';
  }

  @override
  String get syncStatus => 'SYNC STATUS';

  @override
  String get onlineJustNow => 'Online • Just now';

  @override
  String get active => 'Active';

  @override
  String get pending => 'Pending';

  @override
  String get verified => 'Don Confam';

  @override
  String get approved => 'Approved';

  @override
  String get floodsCategory => 'Flood';

  @override
  String get droughtsCategory => 'Drought';

  @override
  String get pestsCategory => 'Pests';

  @override
  String get conflictsCategory => 'Clashes';

  @override
  String get noRecentAlerts => 'No new alert';

  @override
  String get selectZone => 'Choose Zone';

  @override
  String get activeZone => 'Active';

  @override
  String get notSetZone => 'E never set';

  @override
  String get reportsStatus => 'Report Status';

  @override
  String get rejected => 'Rejected';

  @override
  String get generateReport => 'Make Report';

  @override
  String noReportsStatus(String status) {
    return 'No $status Report';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String reportedBy(String name) {
    return '$name report am';
  }

  @override
  String get viewDetails => 'See Details';

  @override
  String get reportVerified => 'Report don confam';

  @override
  String get verifyReport => 'Confam';

  @override
  String get reportRejectedItem => 'Dem don reject di report';

  @override
  String get reject => 'Reject';

  @override
  String get reportResolvedItem => 'Dem don approve di report';

  @override
  String get markResolved => 'Approve';

  @override
  String get reportMovedPending => 'Report don go back to Pending';

  @override
  String get reopen => 'Open Am Again';

  @override
  String get reportReopenedPending => 'Report don open again, e dey Pending';

  @override
  String get reportDetailsTitle => 'Report Details';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get describeHazardHint =>
      'Talk wetin happen here (e.g. flood water dey rise, bridge don fall)...';

  @override
  String get speechNotAvailable => 'Voice-to-text no dey work';

  @override
  String get listeningSpeakNow => 'E dey listen... Talk now';

  @override
  String get beSpecificLocationSeverity =>
      'Talk di exact place and how bad e be.';

  @override
  String get whenDidThisOccur => 'When Dis Tin Happen?';

  @override
  String get optionalLabel => 'If you like';

  @override
  String get todayLabel => 'Today';

  @override
  String get tapToSelectDateTime =>
      'Tap to choose date & time. If you no change am, e go use now-now.';

  @override
  String get evidenceLabel => 'Evidence';

  @override
  String get max3Photos => 'Only 3 photos';

  @override
  String get offlineModeMessage =>
      'Di app go reduce your photo size by itself. Report go dey save for your phone until you get internet.';

  @override
  String get reviewReportBtn => 'Check Report';

  @override
  String get cameraBtn => 'Camera';

  @override
  String get galleryBtn => 'Gallery';

  @override
  String get submissionFailed => 'Sending no work';

  @override
  String get savedForLater => 'E don save for later';

  @override
  String get reportSubmittedTitle => 'Report Don Send!';

  @override
  String get offlineReportMessage =>
      'You no get network now. Di report go send by itself once you get network back.';

  @override
  String get onlineReportMessage =>
      'Your report don reach central command well well.';

  @override
  String get statusLabel => 'STATUS';

  @override
  String get reportIdLabel => 'REPORT ID';

  @override
  String get queuedStatus => 'E DEY WAIT';

  @override
  String get sentStatus => 'E DON SEND';

  @override
  String get returnToDashboard => 'Go Back to Dashboard';

  @override
  String get reviewReportTitle => 'Check Report';

  @override
  String get reviewReportDesc =>
      'Abeg check di details wey dey below make sure say everything correct before you send am to central command.';

  @override
  String get hazardDetails => 'Hazard Details';

  @override
  String get hazardType => 'Hazard Type';

  @override
  String get notSelected => 'You never choose';

  @override
  String get severityLevelLabel => 'How Bad E Be';

  @override
  String get severityDesc => 'Check how strong di hazard be.';

  @override
  String get severityLowShort => 'Low';

  @override
  String get severityMedShort => 'Med';

  @override
  String get severityHighShort => 'High';

  @override
  String get severityCritShort => 'Crit';

  @override
  String get dateTimeLabel => 'Date & Time';

  @override
  String get whenItOccurred => 'When e happen';

  @override
  String get locationLabel => 'Location';

  @override
  String get notProvided => 'Dem no put am';

  @override
  String get monitorNotes => 'Monitor Notes';

  @override
  String get noDescriptionProvided => 'Dem no write description';

  @override
  String get addPhotoBtn => 'Add';

  @override
  String get submitReportBtn => 'Send Report';

  @override
  String get editBtn => 'Change';

  @override
  String get locationPermissionDenied => 'Dem no allow location';

  @override
  String get enableGpsMessage => 'We no fit find location. Abeg on your GPS.';

  @override
  String get locationError => 'Location wahala:';

  @override
  String get acquiringGps => 'E DEY FIND...';

  @override
  String get noSignalGps => 'NO SIGNAL';

  @override
  String get gpsStrong => 'GPS STRONG';

  @override
  String get gpsGood => 'GPS DEY OK';

  @override
  String get gpsWeak => 'GPS WEAK';

  @override
  String get couldNotFindLocation => 'We no fit find di location for map';

  @override
  String get mapUpdateError => 'Map update wahala:';

  @override
  String get incidentLocation => 'Where E Happen';

  @override
  String get gettingLocation => 'E dey find location...';

  @override
  String get noGpsData => 'No GPS data';

  @override
  String get locationUnavailable => 'Location no dey';

  @override
  String get coordinatesLabel => 'COORDINATES';

  @override
  String get viewDetailsBtn => 'See Details';

  @override
  String get wardAndLgaSelection => 'Choose Ward & LGA';

  @override
  String get selectWardDropdown => 'Choose your ward from di list';

  @override
  String get selectLgaWardIncident =>
      'Choose di LGA and Ward wey di tin happen';

  @override
  String get stateLabel => 'State';

  @override
  String get selectState => 'Choose State';

  @override
  String get selectStateFirst => 'Choose State first';

  @override
  String get lgaLabel => 'LGA (Local Government Area)';

  @override
  String get selectLga => 'Choose LGA';

  @override
  String get selectLgaFirst => 'Choose LGA first';

  @override
  String get wardLabel => 'Ward';

  @override
  String get selectWard => 'Choose Ward';

  @override
  String get enterLocationManually => 'Type Location By Hand';

  @override
  String get addressOrCoordinates => 'Address or Coordinates';

  @override
  String get cancelBtn => 'Cancel';

  @override
  String get setLocationBtn => 'Set';

  @override
  String get manualLocationSet => 'Location wey you type don set';

  @override
  String get locationIncorrectManual => 'Location no correct? Type am by hand';

  @override
  String get pleaseSelectStateLgaWard =>
      'Abeg choose State, LGA, and Ward before you continue';

  @override
  String get confirmAndContinue => 'Confam & Continue';

  @override
  String get locationDetailsTitle => 'Location Details';

  @override
  String get latitudeLabel => 'Latitude';

  @override
  String get longitudeLabel => 'Longitude';

  @override
  String get accuracyLabel => 'Accuracy';

  @override
  String get altitudeLabel => 'Altitude';

  @override
  String get closeBtn => 'Close';

  @override
  String get selectStatusExport => 'Choose status wey you wan export:';

  @override
  String get allReports => 'All Reports';

  @override
  String get pendingOnly => 'Only Pending';

  @override
  String get verifiedOnly => 'Only Confam';

  @override
  String get approvedOnly => 'Only Approved';

  @override
  String get adminPortal => 'Admin Portal';

  @override
  String get systemOverview => 'How System Dey';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get userManagement => 'Manage Users';

  @override
  String get reportsOverview => 'Reports Overview';

  @override
  String get alertsBroadcast => 'Alerts & Broadcast';

  @override
  String get knowledgeManagement => 'Manage Knowledge';

  @override
  String get systemHealth => 'System Health';

  @override
  String get pendingApprovals => 'Approvals Wey Dey Wait';

  @override
  String get pendingReports => 'Reports Wey Dey Wait';

  @override
  String get verifiedReports => 'Reports Wey Don Confam';

  @override
  String get totalUsers => 'All Users';

  @override
  String get activeAlertsAdmin => 'Active Alerts';

  @override
  String get totalReports => 'All Reports';

  @override
  String get userManagementDesc => 'Approve accounts, give roles, off users';

  @override
  String get reportsOverviewDesc =>
      'See, confam, or reject reports for all LGAs';

  @override
  String get alertsBroadcastDesc =>
      'Send emergency alerts to users or to some areas';

  @override
  String get knowledgeManagementDesc =>
      'Add, change, or remove emergency knowledge guides';

  @override
  String get connected => 'E don connect';

  @override
  String get none => 'Nothing';

  @override
  String get errorNetwork => 'Network wahala. Abeg check your connection.';

  @override
  String get errorNoPermission => 'You no get permission to do dis tin.';

  @override
  String get errorContactSupport =>
      'Something spoil. Abeg try again or contact support.';

  @override
  String get errorUnexpected =>
      'Something wey we no expect happen. Abeg try again.';

  @override
  String authEmailNotConfirmed(String email) {
    return 'Abeg confam your email first. We don send new code to $email.';
  }

  @override
  String get languageSelectTitle => 'Choose Language';

  @override
  String get shellAppBarTitle => 'CRADI Early Warning';

  @override
  String get shellNotificationsTooltip => 'Notifications';

  @override
  String get shellDrawerDefaultName => 'Early Warning Monitor';

  @override
  String get shellDrawerProfile => 'Profile';

  @override
  String get navHome => 'Home';

  @override
  String get navAlerts => 'Alerts';

  @override
  String get navGuides => 'Guides';

  @override
  String get navReport => 'Report';

  @override
  String get navSettings => 'Settings';

  @override
  String get navAdmin => 'Admin';

  @override
  String homeGreeting(String name) {
    return 'Welcome, $name';
  }

  @override
  String get hazardFlooding => 'Flood';

  @override
  String get hazardExtremeTemperatures => 'Heat or Cold Too Much';

  @override
  String get hazardDrought => 'Drought';

  @override
  String get hazardWindstorms => 'Heavy Wind';

  @override
  String get hazardWildfires => 'Bush Fire';

  @override
  String get hazardErosion => 'Erosion';

  @override
  String get hazardPestOutbreak => 'Pest Don Plenty';

  @override
  String get hazardCropDisease => 'Crop Sickness';

  @override
  String get hazardConflict => 'Clash';

  @override
  String get hazardUnknown => 'Hazard Wey We No Know';

  @override
  String get hazardTitleFlooding => 'Flood Alert';

  @override
  String get hazardTitleExtremeTemperatures => 'Heat/Cold Too Much';

  @override
  String get hazardTitleDrought => 'Drought Warning';

  @override
  String get hazardTitleWindstorms => 'Heavy Wind Alert';

  @override
  String get hazardTitleWildfires => 'Bush Fire Report';

  @override
  String get hazardTitleErosion => 'Erosion Report';

  @override
  String get hazardTitlePestOutbreak => 'Pest Don Plenty';

  @override
  String get hazardTitleCropDisease => 'Crop Sickness';

  @override
  String get hazardTitleConflict => 'Clash Report';

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
  String get commonUnknown => 'We no know';

  @override
  String get commonUnknownLocation => 'Location Wey We No Know';

  @override
  String get commonAnonymous => 'Anonymous';

  @override
  String get commonCommunityReport => 'Community Report';

  @override
  String get reportStatusPending => 'Pending';

  @override
  String get reportStatusVerified => 'Don Confam';

  @override
  String get reportStatusApproved => 'Approved';

  @override
  String get reportStatusRejected => 'Rejected';

  @override
  String get verifyErrorOwnReport => 'You no fit confam your own report.';

  @override
  String verifyErrorTooFar(String distanceKm) {
    return 'You must dey inside 2 km of where di report happen before you fit confam am. How far you dey now: $distanceKm km.';
  }

  @override
  String get verifyConfirmedMessage => 'Report don confam well well';

  @override
  String get verifyDisputedMessage => 'You don dispute di report';

  @override
  String get verifyErrorAlreadyVoted => 'You don already vote for dis report.';

  @override
  String get verifyErrorNotPermitted =>
      'Your account no get permission to confam reports. To confam, you need approved monitor role.';

  @override
  String get verifyErrorNoLongerPending => 'Dis report no dey pending again.';

  @override
  String get verifyErrorSignedOut =>
      'You must sign in before you fit confam reports.';

  @override
  String get verifyErrorFailed => 'Confam no work';

  @override
  String get verifyErrorDisputeReasonRequired =>
      'Abeg explain why you dey dispute dis report.';

  @override
  String get verifyRequestQueuedOffline =>
      'Offline: request don save, e go sync when network come back.';

  @override
  String get reportActionErrorNoPermissionOrGone =>
      'You no get permission to change dis report, or di report no dey again.';

  @override
  String get reportActionErrorAlreadyPending =>
      'Dis report don already dey pending.';

  @override
  String get reportActionErrorGone => 'Dis report no dey again.';

  @override
  String get reportActionErrorNoPermission =>
      'You no get permission to change dis report.';

  @override
  String get reportsLoadErrorOffline =>
      'We no fit reach di server. Check your connection and try again.';

  @override
  String get offlineSavedWillSync =>
      'E don save offline. E go sync when network come back.';

  @override
  String get profileErrorOfflineNotSaved =>
      'You dey offline — di changes no save.';

  @override
  String get profileErrorSignedOut =>
      'You must sign in before you fit update your profile.';

  @override
  String get profileErrorSaveFailed =>
      'We no fit save your changes. Abeg check your connection and try again.';

  @override
  String get profileErrorNameRequired => 'Abeg put your name.';

  @override
  String get profileErrorEmailSignedOut =>
      'You must sign in before you fit change your email.';

  @override
  String profileEmailConfirmationSent(String email) {
    return 'We don send confirmation link to $email. Your email go change after you confam am.';
  }

  @override
  String get profileErrorEmailReauth =>
      'For security, abeg log out and sign in again before you change your email.';

  @override
  String get profileErrorEmailInUse =>
      'Another account dey use dat email already.';

  @override
  String get profileErrorEmailUpdateFailed =>
      'We no fit update di email. Abeg try again.';

  @override
  String get profileErrorLocationIncomplete =>
      'Abeg choose your state, LGA and ward to update your location.';

  @override
  String get profileErrorLocationSignedOut =>
      'You must sign in before you fit change your location.';

  @override
  String get profileErrorLocationManaged =>
      'Na administrator dey manage your location. Abeg tell admin make dem change di location for staff account.';

  @override
  String get profileErrorLocationFailed =>
      'We no fit update your location. Abeg check your connection and try again.';

  @override
  String get profileDefaultName => 'User';

  @override
  String get homeVerifyReportsLink => 'Confam Reports';

  @override
  String get homeTabNearby => 'Near You';

  @override
  String homeZoneStatus(String zone, String status) {
    return '$zone • $status';
  }

  @override
  String get homeEmptyMyReports => 'You never send any report yet';

  @override
  String get homeOpenNearbyReports => 'Open Reports Wey Dey Near';

  @override
  String get homeEmptyNearby => 'No report near you';

  @override
  String reportLocationAndTime(String location, String time) {
    return '$location • $time';
  }

  @override
  String get homeZoneSheetTitle => 'Choose Monitoring Zone';

  @override
  String get homeZoneAll => 'All Zones (No Filter)';

  @override
  String get homeZoneAllSelected => 'E dey show all zones';

  @override
  String homeZoneAllLocalOnly(String error) {
    return 'E dey show all zones for dis phone. $error';
  }

  @override
  String homeZoneChanged(String zone) {
    return 'Monitoring zone don change to $zone';
  }

  @override
  String homeZoneLocalOnly(String zone, String error) {
    return 'E dey show $zone for dis phone. $error';
  }

  @override
  String zoneStateLabel(String state) {
    return '$state State';
  }

  @override
  String get settingsPushPermissionNeeded =>
      'Allow notifications for EWER inside your phone settings so alerts go fit reach you.';

  @override
  String get settingsPushUnavailable =>
      'Push notifications no dey work now. We don save wetin you choose, e go start to work when dem come back.';

  @override
  String get settingsSectionSecurity => 'SECURITY & PRIVACY';

  @override
  String get settingsBiometricSubtitle =>
      'Use fingerprint or Face ID take login';

  @override
  String get settingsBiometricUnavailable => 'E no dey dis phone';

  @override
  String get settingsOfflineMode => 'Offline Mode';

  @override
  String get settingsOfflineModeEnabled => 'Offline mode don on';

  @override
  String get settingsOfflineModeRestoring => 'E dey bring connection back...';

  @override
  String get settingsLogoutConfirm => 'You sure say you wan sign out?';

  @override
  String get settingsFooterSystemName => 'Climate Early Warning System (CEWS)';

  @override
  String get biometricErrorNotEnrolled =>
      'No biometrics dey for dis phone. Abeg add fingerprint or Face ID for your phone Settings first.';

  @override
  String get biometricErrorUnavailable => 'Biometrics no dey dis phone.';

  @override
  String get biometricErrorLockedOut =>
      'You don try too many times. Biometrics don lock; open your phone and try again later.';

  @override
  String get biometricErrorFailed => 'Biometric check no work. Abeg try again.';

  @override
  String get biometricPromptDefault =>
      'Abeg confam say na you before you continue';

  @override
  String get biometricEnablePrompt => 'On biometric login for EWER';

  @override
  String get biometricLoginPrompt =>
      'Confam say na you to login to EWER Mobile';

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
      'Dis email don already register. Abeg login.';

  @override
  String get authErrorRegistrationFailed =>
      'Registration no work. Abeg try again.';

  @override
  String get authErrorNetworkRetry =>
      'Network wahala. Abeg check your connection and try again.';

  @override
  String get authErrorWeakPassword =>
      'Password too weak. Use at least 8 characters wey get letters, numbers and symbols.';

  @override
  String get authErrorAccountRegistered =>
      'Dis account don already register. Abeg login.';

  @override
  String get authErrorRegistrationDisabled =>
      'Registration no dey open now. Abeg contact support.';

  @override
  String get authErrorTooManyAttempts =>
      'You don try too many times. Abeg wait small, some minutes, before you try again.';

  @override
  String get authErrorLoginFailed => 'Login no work. Abeg try again.';

  @override
  String get authErrorAccountDisabled =>
      'Dem don off dis account. Abeg contact support.';

  @override
  String get authErrorLoginConnection =>
      'Login no work. Abeg check your connection.';

  @override
  String get authErrorInvalidCredentials => 'Email or password no correct';

  @override
  String get authErrorTooManyLogins =>
      'You don try login too many times. Abeg wait some minutes and try again.';

  @override
  String get authErrorLoginUnexpected =>
      'Something wey we no expect happen during login. Abeg try again.';

  @override
  String get authErrorInvalidPhone => 'Phone number no correct.';

  @override
  String get authErrorSmsUnavailable =>
      'SMS service no dey work. Abeg contact support.';

  @override
  String get authErrorPhoneNotRegistered =>
      'No account dey for dis number. Abeg register first.';

  @override
  String get authErrorSmsFailed => 'We no fit send di verification SMS.';

  @override
  String get authErrorCodeSendFailed => 'We no fit send di verification code.';

  @override
  String get authErrorNoUserContext =>
      'No user details for dis verification. Abeg login again.';

  @override
  String get authErrorVerificationFailed =>
      'Verification no work. Abeg try again.';

  @override
  String get authErrorInvalidCode =>
      'Di verification code no correct or e don expire. Abeg request new one.';

  @override
  String get authErrorTooManyAttemptsRetry =>
      'You don try too many times. Abeg wait some minutes and try again.';

  @override
  String get authErrorVerifyCodeFailed => 'We no fit confam di code.';

  @override
  String get authErrorNotLoggedIn => 'User never login';

  @override
  String get authErrorResendFailed =>
      'We no fit send di verification code again. Abeg try again.';

  @override
  String get authErrorResetEmailFailed =>
      'We no fit send di reset email. Abeg try again.';

  @override
  String get authErrorResetWeakPassword =>
      'Password too weak. Dem don use di code finish, so abeg request new code and choose stronger password.';

  @override
  String get authErrorResetCodeInvalid =>
      'Dis reset code no correct or e don expire. Abeg request new one.';

  @override
  String get authErrorResetSamePassword =>
      'Your new password must different from di old one. Dem don use di code finish, so abeg request new code.';

  @override
  String get authErrorResetFailed =>
      'We no fit reset di password. Abeg try again.';

  @override
  String get rateLimitAccountLocked =>
      'Account don lock because of too many attempts wey no work';

  @override
  String rateLimitWaitSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abeg wait $count seconds before you try again',
      one: 'Abeg wait 1 second before you try again',
    );
    return '$_temp0';
  }

  @override
  String rateLimitLockedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Too many attempts wey no work. Account don lock for $count minutes.',
      one: 'Too many attempts wey no work. Account don lock for 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String rateLimitOtpMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You don request OTP too many times. Abeg try again after $count minutes.',
      one: 'You don request OTP too many times. Abeg try again after 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String rateLimitResendSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abeg wait $count seconds before you request another code',
      one: 'Abeg wait 1 second before you request another code',
    );
    return '$_temp0';
  }

  @override
  String rateLimitAttemptsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts remain',
      one: '1 attempt remain',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitExceeded => 'You don pass di limit';

  @override
  String reportErrorMaxPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Na only $count pictures you fit add',
      one: 'Na only 1 picture you fit add',
    );
    return '$_temp0';
  }

  @override
  String get reportErrorMissingHazard => 'Abeg choose hazard type.';

  @override
  String get reportErrorMissingSeverity => 'Abeg choose how bad e be.';

  @override
  String get reportErrorMissingLocation => 'Abeg add di location details.';

  @override
  String get reportErrorSignedOut =>
      'You must sign in before you fit send or save report.';

  @override
  String get reportSavedAsDraft =>
      'E don save as draft. E go sync when you dey online.';

  @override
  String get reportSubmittedWithPeers =>
      'Report don send well well! We don send verification request to other monitors.';

  @override
  String get reportQueuedServerUnreachable =>
      'We no fit reach di server. E don save, e go sync later.';

  @override
  String syncResultSummary(int count, int failed) {
    return '$count items don sync. $failed no work.';
  }

  @override
  String get reportErrorPhotoProcessing =>
      'One photo no fit process. Abeg remove am or choose another photo.';

  @override
  String get severityLow => 'Low';

  @override
  String get severityMedium => 'Medium';

  @override
  String get severityHigh => 'High';

  @override
  String get severityCritical => 'Critical';

  @override
  String get alertSeverityUnspecified => 'Dem no talk how bad e be';

  @override
  String get alertSeverityInfo => 'Info';

  @override
  String get alertSeverityWarning => 'Warning';

  @override
  String reviewDateTodayAt(String time) {
    return 'Today by $time';
  }

  @override
  String reviewDateOnAt(String date, String time) {
    return '$date by $time';
  }

  @override
  String get reviewLocationUnknown =>
      'We no sabi di exact location - na di area wey you choose we go use';

  @override
  String get reviewLocationApproximate =>
      'Location na estimate (middle of di area, no GPS)';

  @override
  String get reportDetailsSpeechError =>
      'Voice-to-text get wahala. Abeg try again.';

  @override
  String get reportDetailsCameraUnavailable =>
      'Camera no dey work. Abeg try use gallery.';

  @override
  String get reportDetailsGalleryError =>
      'We no fit open gallery. Abeg try again.';

  @override
  String get reportDetailsFutureTime =>
      'Di time wey e happen no fit be for future. We don set am to di time now.';

  @override
  String get geoErrorServicesOff => 'Location services dey off. Abeg on GPS.';

  @override
  String get geoErrorPermissionDenied => 'Dem no allow location permission.';

  @override
  String get geoErrorServicesUnavailable =>
      'We no fit reach location services.';

  @override
  String get geoNoticeLastKnown =>
      'We no fit get new GPS fix; na di last location wey we know we dey use.';

  @override
  String get geoErrorTimeout =>
      'GPS signal no come on time. Go open place and try again, or choose your location by hand.';

  @override
  String get geoErrorUndetermined =>
      'We no fit know your location. Abeg try again or choose your location by hand.';

  @override
  String get commonLoading => 'E dey load...';

  @override
  String get locationPickerSeverityLow => 'E No Too Bad';

  @override
  String get locationPickerSeverityMedium => 'E Bad Small';

  @override
  String get locationPickerSeverityHigh => 'E Bad Well Well';

  @override
  String get locationPickerSeverityCritical => 'E Don Critical';

  @override
  String get locationPickerSeverityLowDesc =>
      'Small matter. No danger now-now.';

  @override
  String get locationPickerSeverityMediumDesc =>
      'Di matter dey middle. Dey watch am.';

  @override
  String get locationPickerSeverityHighDesc =>
      'Big danger to property or health. Dem need respond.';

  @override
  String get locationPickerSeverityCriticalDesc =>
      'Life dey for danger. Una must act now-now.';

  @override
  String get locationPickerSelectedLevel => 'Level Wey You Choose';

  @override
  String get locationPickerGpsApproximate => 'Estimate';

  @override
  String get locationPickerLgaHeading => 'LGA';

  @override
  String get locationPickerWardHeading => 'WARD';

  @override
  String get locationPickerUnknownLga => 'LGA Wey We No Know';

  @override
  String get locationPickerUnknownWard => 'Ward Wey We No Know';

  @override
  String get locationPickerAutofilled => 'GPS don fill am by itself';

  @override
  String locationPickerGpsLgaNotFound(String lga, String state) {
    return 'GPS Location ($lga) no dey inside $state';
  }

  @override
  String get locationPickerGpsUnavailable =>
      'GPS Location no dey or you never choose State';

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
  String get reportViewReporter => 'Who Report Am';

  @override
  String get reportViewReported => 'Time Wey Dem Report';

  @override
  String get reportViewSeverity => 'How Bad E Be';

  @override
  String get reportViewVerifications => 'Confirmations';

  @override
  String reportViewEvidenceCount(int count) {
    return 'Evidence ($count)';
  }

  @override
  String get reportViewCoordinates => 'Coordinates';

  @override
  String reportViewRejectedOn(String date) {
    return 'Dem reject di report on $date';
  }

  @override
  String get reportViewNoReason => 'Dem no give reason.';

  @override
  String get myReportsTabActive => 'Active';

  @override
  String get myReportsTabHistory => 'History';

  @override
  String get myReportsSignIn => 'Abeg sign in to see your reports.';

  @override
  String get myReportsEmptyActiveTitle => 'No active report';

  @override
  String get myReportsEmptyActiveBody =>
      'Reports wey you send go show here while dem dey confam am.';

  @override
  String get myReportsEmptyHistoryTitle => 'Report history no dey';

  @override
  String get myReportsEmptyHistoryBody =>
      'Your reports wey dem approve or reject go show here.';

  @override
  String get myReportsNewReport => 'New Report';

  @override
  String myReportsRejectionReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get nearbyTitle => 'Reports Wey Dey Near';

  @override
  String get nearbyNotAvailableTitle => 'E no dey for your account';

  @override
  String get nearbyNotAvailableBody =>
      'Na only approved monitors and staff fit see reports wey dey near. You fit follow your own reports for My Reports.';

  @override
  String get nearbyLocationNotSetTitle => 'Location Never Set';

  @override
  String get nearbyLocationNotSetBody =>
      'Set your LGA or monitoring zone for\nyour profile to see reports wey dey near you.';

  @override
  String get nearbyLoadErrorTitle => 'We no fit load reports';

  @override
  String get nearbyEmptyTitle => 'No Report Near You';

  @override
  String get nearbyEmptyBody => 'No report dey from your\narea for now.';

  @override
  String get alertDetailDefaultTitle => 'Alert';

  @override
  String get alertDetailNotSpecified => 'Dem no talk';

  @override
  String get alertStatusActive => 'Active';

  @override
  String get alertStatusInactive => 'E no dey active';

  @override
  String get alertDetailReportLoadError => 'We no fit load di report details.';

  @override
  String get alertDetailTitle => 'Alert Details';

  @override
  String get alertDetailReportedTime => 'Time Wey Dem Report';

  @override
  String get alertDetailStatus => 'Status';

  @override
  String get alertDetailNoDescription =>
      'No extra description for dis alert. Abeg take care and follow wetin local authorities talk.';

  @override
  String get alertDetailRecommendedActions => 'Wetin To Do';

  @override
  String get alertDetailAction1 => '1. Dey follow news for local radio/TV.';

  @override
  String get alertDetailAction2 => '2. Arrange emergency supplies.';

  @override
  String get alertDetailAction3 => '3. No travel go di areas wey e affect.';

  @override
  String get alertDetailAction4 => '4. If dem talk make una comot, comot.';

  @override
  String get alertDetailPeerVerificationTitle => 'You Need Confam Am';

  @override
  String get alertDetailPeerVerificationBody =>
      'As EWM for dis ward, abeg confam if you fit support dis report based on wetin you don see.';

  @override
  String get alertDetailCommentLabel =>
      'Comment (you must write am to dispute)';

  @override
  String get alertDetailCommentHint => 'Extra information about dis report...';

  @override
  String get commonSubmitting => 'E dey send...';

  @override
  String get voteConfirm => 'Confam';

  @override
  String get voteDecline => 'I No Gree';

  @override
  String get alertDetailVerificationSubmitted => 'Verification Don Send';

  @override
  String get alertDetailThanks => 'Thank you for your help!';

  @override
  String get alertDetailGoBack => 'Go Back';

  @override
  String get alertDetailDismiss => 'Dismiss';

  @override
  String get alertsFilterAll => 'All Alerts';

  @override
  String get alertsFilterFire => 'Fire';

  @override
  String get alertsBroadcastTooltip => 'Broadcast alert';

  @override
  String get alertsSeverityFilterTooltip => 'Filter by how bad e be';

  @override
  String get alertsAllSeverities => 'All levels';

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
  String get alertsLoadError => 'We no fit load alerts';

  @override
  String get alertsNoMatching => 'No alert wey match';

  @override
  String get alertsPullToRetry => 'Pull am down to try again.';

  @override
  String get alertsEmptyBody => 'Official alerts for your area go show here.';

  @override
  String get alertsAllLgas => 'All LGAs';

  @override
  String get alertsSynchronizing => 'E dey sync...';

  @override
  String get alertsNoReportsYet => 'No Report Yet';

  @override
  String get alertsNoMatchingReports => 'No report wey match';

  @override
  String alertsNoReportsForFilter(String filter) {
    return 'No $filter';
  }

  @override
  String get alertsNoReportsYetBody =>
      'When pipo report hazard for your area,\ne go show here';

  @override
  String get alertsNoMatchingReportsBody => 'No report wey match for dis area';

  @override
  String get alertsDisputeRecorded => 'Dispute don record';

  @override
  String get alertsReportConfirmed => 'Report don confam';

  @override
  String get accessCodeVerified => 'Account don verify well well!';

  @override
  String get accessCodeNotVerified =>
      'E never verify. Abeg put di code wey we send to your email.';

  @override
  String get accessCodeSent => 'Verification code don send!';

  @override
  String get accessCodeNoEmail =>
      'No email dey for dis account. Abeg log in again.';

  @override
  String get accessCodeTitle => 'Confam Your Email';

  @override
  String get accessCodeEnterCode => 'Put Code';

  @override
  String get accessCodeIHaveVerified => 'I don verify my account';

  @override
  String accessCodeBody(String email) {
    return 'We don send 6-digit verification code to $email.\nPut di code to activate your account.';
  }

  @override
  String get accessCodeBodyNoEmail =>
      'We don send 6-digit verification code to your email.\nPut di code to activate your account.';

  @override
  String get forgotTitle => 'You Forget Password?';

  @override
  String get forgotBody =>
      'Put your email address make we send you password reset code.';

  @override
  String get forgotLegacyLinkExpired =>
      'Dis password reset link na from our old sign-in system, so e no work again. Put your email below and we go send you new one.';

  @override
  String get authEmailHint => 'Put your email';

  @override
  String get authEmailRequired => 'Abeg put your email';

  @override
  String get authEmailInvalid => 'Abeg put correct email';

  @override
  String get forgotSendCode => 'Send Reset Code';

  @override
  String get forgotEmailSentTitle => 'Email Don Send!';

  @override
  String forgotEmailSentBody(String email) {
    return 'If account dey for $email, we don send reset code.\nPut am for di next screen to choose new password.';
  }

  @override
  String get forgotEnterCode => 'Put Reset Code';

  @override
  String get landingWelcome => 'Welcome to EWER';

  @override
  String get landingSubtitle => 'Early Warning and Early Response System';

  @override
  String get landingTagline =>
      'We dey give communities power to report hazard sharp-sharp and arrange quick response.';

  @override
  String get landingGetStarted => 'Make We Start';

  @override
  String get authSignUp => 'Sign Up';

  @override
  String get authLogin => 'Login';

  @override
  String get validatorPhoneRequired => 'You must put phone number';

  @override
  String get validatorPhoneInvalid => 'Abeg put correct Nigerian phone number';

  @override
  String get validatorAddressRequired => 'You must put address';

  @override
  String validatorAddressTooShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Address must reach at least $count characters',
    );
    return '$_temp0';
  }

  @override
  String validatorAddressTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Address too long (max $count characters)',
    );
    return '$_temp0';
  }

  @override
  String validatorFieldRequired(String field) {
    return 'You must fill $field';
  }

  @override
  String validatorFieldMinLength(String field, int count) {
    return '$field must reach at least $count characters';
  }

  @override
  String validatorFieldMaxLength(String field, int count) {
    return '$field no fit pass $count characters';
  }

  @override
  String get validatorInvalidCharacters => 'Some characters no correct';

  @override
  String validatorFieldInvalidCharacters(String field) {
    return '$field get characters wey no correct';
  }

  @override
  String get validatorDescriptionRequired => 'You must write description';

  @override
  String validatorDescriptionTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Description no fit pass $count characters',
    );
    return '$_temp0';
  }

  @override
  String get validatorEmailRequired => 'You must put email';

  @override
  String get validatorPasswordRequired => 'You must put password';

  @override
  String validatorPasswordMinLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Password must reach at least $count characters',
    );
    return '$_temp0';
  }

  @override
  String get validatorPasswordUppercase =>
      'E must get at least one capital letter';

  @override
  String get validatorPasswordLowercase =>
      'E must get at least one small letter';

  @override
  String get validatorPasswordNumber => 'E must get at least one number';

  @override
  String get validatorPasswordSpecial =>
      'E must get at least one special character';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthFair => 'E Manage';

  @override
  String get passwordStrengthGood => 'Good';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String passwordErrorTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Password too long (max $count characters)',
    );
    return '$_temp0';
  }

  @override
  String get passwordErrorCommon =>
      'Plenty pipo dey use dis password. Abeg choose stronger password';

  @override
  String get passwordErrorSequential =>
      'Password no suppose get characters wey follow each other (e.g., 123, abc)';

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
  String get passwordRequirementUppercase => 'Capital letter';

  @override
  String get passwordRequirementLowercase => 'Small letter';

  @override
  String get passwordRequirementNumber => 'Number';

  @override
  String get passwordRequirementSpecial => 'Special character';

  @override
  String get passwordRequirementNotCommon =>
      'No be password wey everybody dey use';

  @override
  String get authLoginCheckCredentials =>
      'Login no work. Abeg check your details.';

  @override
  String get loginWelcomeBack => 'Welcome Back';

  @override
  String get loginSubtitle => 'Sign in enter your account';

  @override
  String get authPhoneNumber => 'Phone Number';

  @override
  String get authPassword => 'Password';

  @override
  String get loginRememberMe => 'Remember Me';

  @override
  String get loginNoAccount => 'You no get account? ';

  @override
  String get loginDataSecure => 'Your data dey encrypted and e dey safe';

  @override
  String get loginLockedTitle => 'CRADI Mobile Don Lock';

  @override
  String get loginUnlockBiometrics => 'Open with Biometrics';

  @override
  String get loginLogoutDifferentAccount => 'Log out and use another account';

  @override
  String get authMethodEmail => 'Email';

  @override
  String get authMethodPhone => 'Phone';

  @override
  String get loginSendCode => 'Send Code';

  @override
  String get otpSuccess => 'Verification don work!';

  @override
  String get otpNewCodeSent => 'We don send new code.';

  @override
  String get otpVerifyEmail => 'Confam Email';

  @override
  String otpCodeSentTo(String destination) {
    return 'Put di 6-digit code wey we send to\n$destination';
  }

  @override
  String get otpSecureCode => 'Secure Code';

  @override
  String get otpCodeHint => 'Put 6-digit code';

  @override
  String get otpCodeRequired => 'Abeg put di code';

  @override
  String get otpCodeInvalidFormat => 'Code format no correct';

  @override
  String get otpVerifyAndLogin => 'Confam & Login';

  @override
  String get otpNoCode => 'Code no reach you? ';

  @override
  String otpResendIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Send again in ${count}s',
    );
    return '$_temp0';
  }

  @override
  String get pendingTitle => 'Approval Dey Wait';

  @override
  String get pendingBody =>
      'Your account don create well well but e dey wait make admin approve am.\n\nYou go fit use di whole app once administrator check and approve your account.';

  @override
  String get pendingStillWaiting => 'Your account still dey wait for approval.';

  @override
  String get pendingCheckStatus => 'Check if dem don approve';

  @override
  String get pendingContactSupport => 'Contact Support';

  @override
  String get registrationPrivacyTitle => 'Data Privacy Notice';

  @override
  String get registrationDecline => 'I No Gree';

  @override
  String get registrationAgree => 'I Gree';

  @override
  String get registrationMustAccept =>
      'You must accept di Data Privacy Notice before you fit register.';

  @override
  String get registrationSelectState => 'Abeg choose state';

  @override
  String get registrationSelectLga => 'Abeg choose LGA';

  @override
  String get registrationSelectWard => 'Abeg choose ward';

  @override
  String get registrationVerifyPhoneTitle => 'Confam Your Phone Number';

  @override
  String registrationPhoneCodeSent(String phone) {
    return 'We don send 6-digit verification code to $phone.\n\nAbeg put di code to activate your account.';
  }

  @override
  String get registrationAccountCreated => 'Account don create!';

  @override
  String get registrationVerifyEmailTitle => 'Confam Your Email Address';

  @override
  String registrationEmailCodeSent(String email) {
    return 'Account don create well well!\n\nWe don send 6-digit verification code to $email.\n\nAbeg put di code to activate your account.';
  }

  @override
  String get registrationCreateAccount => 'Create Account';

  @override
  String get registrationJoinNetwork => 'Join Di Network';

  @override
  String get registrationSelectLocation =>
      'Choose your location make we start.';

  @override
  String get registrationMethod => 'How You Wan Register';

  @override
  String get registrationPersonalInfo => 'Your Personal Information';

  @override
  String get registrationNameHint => 'Chinedu Okafor';

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
  String get registrationPasswordHint => 'Create password';

  @override
  String get registrationConfirmPassword => 'Confam Password';

  @override
  String get registrationConfirmPasswordHint => 'Type your password again';

  @override
  String get registrationConfirmPasswordRequired => 'Abeg confam your password';

  @override
  String get registrationPasswordsMismatch => 'Di two passwords no match';

  @override
  String get registrationSendOtp => 'Send OTP & Register';

  @override
  String get registrationHaveAccount => 'You get account already? ';

  @override
  String get registrationCreating => 'E dey create account...';

  @override
  String get privacyNoticeText =>
      'Nigeria Data Protection Act (NDPA) — Data Processing Notice\n\nEWER Mobile (service from CRADI / KusuConsult-NG) dey use your data for climate hazard early warning.\n\n• Data wey we dey collect: name, phone, email, location (state/LGA/ward), hazard reports, and push-notification device identifier.\n• Why we dey collect am: community hazard reporting, peer verification, and emergency alerts.\n• Where we dey keep am: Supabase (PostgreSQL) cloud database; push notifications dey pass through OneSignal and crash diagnostics fit go Sentry.\n• Sending am outside Nigeria: Based on NDPA Article 24, we dey tell you say your data fit go and stay for servers wey dey outside Nigeria. We need do dis one to give you di service. You get right to withdraw your consent anytime if you delete your account.\n• How long we go keep am: We go keep di data for 5 years after di last time you use di app, then we go remove wetin fit show say na you (anonymise).\n• Your rights: to see your data, correct am, delete am, and carry am go another place (data portability) under NDPA 2023.\n\nIf you tap \"I Gree\", e mean say you agree to dis terms and say make we send your personal data go outside Nigeria.';

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
  String aboutVersionOnly(String version) {
    return 'Version $version';
  }

  @override
  String get aboutPrivacyPolicy => 'Privacy Policy';

  @override
  String get resetCodeResent => 'If account dey, we don send new code.';

  @override
  String get resetTitle => 'Create New Password';

  @override
  String get resetBody =>
      'Put di code wey dey di reset email and choose new strong password.';

  @override
  String get resetRecoveryBody =>
      'Choose new strong password for your CRADI account.';

  @override
  String get resetCodeLabel => 'Reset Code';

  @override
  String get resetSendingCode => 'E dey send…';

  @override
  String get resetSendCode => 'Send code';

  @override
  String get resetCodeRequired => 'Put di code wey dey di email';

  @override
  String get resetNewPassword => 'New Password';

  @override
  String get resetSubmit => 'Reset Password';

  @override
  String get resetSuccessTitle => 'Password Don Reset!';

  @override
  String get resetSuccessBody =>
      'Your password don reset well well. You fit login now with your new password.';

  @override
  String get resetContinueToLogin => 'Continue go Login';

  @override
  String get offlineSyncingPending => 'E dey sync data wey dey wait...';

  @override
  String get offlineDiscardTitle => 'You wan throw dis report away?';

  @override
  String get offlineDiscardBody =>
      'Dis report never send and e go delete from dis phone.';

  @override
  String get offlineDiscard => 'Throw Away';

  @override
  String get offlineActions => 'Actions';

  @override
  String get offlineSubmitAsMe => 'Send am as me';

  @override
  String get offlineNoInternet => 'Internet Connection No Dey';

  @override
  String get offlineCanViewSaved =>
      'You still fit see your saved guides and draft reports.';

  @override
  String get offlineReconnectToSignIn => 'Connect again to sign in.';

  @override
  String get offlineTryReconnect => 'Try Connect Again & Sync';

  @override
  String get offlineModeEnabledInSettings =>
      'Offline Mode dey on for Settings.';

  @override
  String get offlineGoOnline => 'Go online';

  @override
  String get offlineStillNoInternet => 'Internet connection still no dey';

  @override
  String get offlineOpenSettings => 'Open Settings';

  @override
  String get offlineViewSavedGuides => 'See Saved Guides';

  @override
  String get offlineNoPending => 'No report dey wait';

  @override
  String get offlineStatusOwnerless =>
      'Old version of di app save am: send am or throw am away';

  @override
  String get offlineStatusFailed => 'E no work, e no go sync by itself';

  @override
  String offlineStatusFailedWithError(String error) {
    return 'E no work, e no go sync by itself: $error';
  }

  @override
  String get offlineStatusWaiting => 'E dey wait to sync';

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
  String get profilePhotoUpdated => 'Profile photo don update!';

  @override
  String get profileCameraUnavailable =>
      'Camera no dey work. Abeg use gallery.';

  @override
  String get profilePickImageFailed =>
      'We no fit pick di picture. Abeg try again.';

  @override
  String get profileUpdatePhoto => 'Change Profile Photo';

  @override
  String get profileChooseGallery => 'Choose from Gallery';

  @override
  String get profileChooseGallerySubtitle => 'Choose photo from your phone';

  @override
  String get profileCameraWebUnavailable => 'Camera no dey for web';

  @override
  String get profileUseGallery => 'Abeg use gallery option';

  @override
  String get profilePhotoLibrary => 'Photo Library';

  @override
  String get profileEdit => 'Change Profile';

  @override
  String get profileAskAdminArea => 'Tell admin make dem change your area';

  @override
  String get commonNotAvailable => 'N/A';

  @override
  String profileIdLabel(String code) {
    return 'ID: $code';
  }

  @override
  String get profileVerified => 'Don Confam';

  @override
  String get profileUnverified => 'Never Confam';

  @override
  String get profileStatReports => 'Reports';

  @override
  String get profileDaysActive => 'Days Active';

  @override
  String get profileAccountSettings => 'Account Settings';

  @override
  String get profileBiometricsEnabled => 'Biometrics don on!';

  @override
  String get profileBiometricChangeFailed => 'We no fit change biometric login';

  @override
  String get profileSyncingOffline => 'E dey sync offline data...';

  @override
  String get profileSyncComplete => 'Sync don finish!';

  @override
  String get profileSupportChat => 'Support Chat';

  @override
  String get profileSosButton => 'SOS / Emergency Call';

  @override
  String get sosTitle => 'SOS Emergency';

  @override
  String get sosBody =>
      'Call for help direct. Dis one no go send alert through di app.';

  @override
  String sosCallEmergency(String phone) {
    return 'Call Emergency ($phone)';
  }

  @override
  String get sosNationalNumber => 'National emergency number';

  @override
  String get sosContactsLoadError =>
      'We no fit load your contacts. Check your connection and try again.';

  @override
  String get sosNoContacts =>
      'You never save any personal emergency contact. Add dem for Emergency Contacts.';

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
    return 'We no fit open phone app. Dial $phone.';
  }

  @override
  String get chatLoginRequired => 'Abeg login to chat';

  @override
  String get chatLoadError => 'We no fit load messages.';

  @override
  String get chatMe => 'Me';

  @override
  String chatRateLimited(String reason) {
    return '$reason. Abeg wait small.';
  }

  @override
  String chatSendFailed(String error) {
    return 'Message no send. $error';
  }

  @override
  String get chatEmpty => 'No message dey yet';

  @override
  String get chatComposerHint => 'Type message';

  @override
  String get contactsNameRequired => 'You must put name';

  @override
  String get contactsNameTooLong => 'Name too long';

  @override
  String get contactsPhoneDigitsOnly =>
      'Use only numbers (you fit start with +)';

  @override
  String get contactsPhoneInvalid => 'Put correct phone number';

  @override
  String get contactsLaunchPhoneFailed => 'We no fit open phone app';

  @override
  String get contactsLaunchSmsFailed => 'We no fit open SMS app';

  @override
  String get contactsAdded => 'Contact don add well well';

  @override
  String get contactsUpdated => 'Contact don update well well';

  @override
  String get contactsDeleteTitle => 'You wan delete contact?';

  @override
  String contactsDeleteBody(String name) {
    return 'You wan remove $name from your emergency contacts?';
  }

  @override
  String get contactsDeleted => 'Contact don delete';

  @override
  String get contactsTitle => 'Emergency Contacts';

  @override
  String get contactsAddTooltip => 'Add contact';

  @override
  String get contactsSearchHint => 'Search name, LGA, or role';

  @override
  String get contactsEmpty => 'We no see any contact';

  @override
  String get contactsEmergencyButton => 'Emergency 112';

  @override
  String get contactsMoreActions => 'More actions';

  @override
  String get contactsEditTitle => 'Change Emergency Contact';

  @override
  String get contactsAddTitle => 'Add Emergency Contact';

  @override
  String get contactsNameLabel => 'Name *';

  @override
  String get contactsRoleLabel => 'Role';

  @override
  String get contactsPhoneLabel => 'Phone *';

  @override
  String get contactsOrganizationLabel => 'Organization (If You Like)';

  @override
  String get contactsLgaLabel => 'LGA (If You Like)';

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
  String get contactsCategoryOther => 'Others';

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
  String get knowledgeCategoryExtremeHeat => 'Heat Too Much';

  @override
  String get knowledgeCategoryEarthquake => 'Earthquake';

  @override
  String get knowledgeCategoryDisease => 'Sickness';

  @override
  String get knowledgeCategoryConflict => 'Clash';

  @override
  String get knowledgeCategoryAccident => 'Accident';

  @override
  String get knowledgeCategorySafety => 'Safety';

  @override
  String get knowledgeCategoryGeneral => 'General';

  @override
  String get knowledgeTagGuide => 'GUIDE';

  @override
  String get knowledgeLoadError => 'We no fit bring guides. Abeg try again.';

  @override
  String get knowledgeGuidesTitle => 'Hazard Guides';

  @override
  String get knowledgeBaseCaption => 'KNOWLEDGE BASE';

  @override
  String get knowledgeGuidesSearchHint => 'Search guides, signs, or hazards...';

  @override
  String get knowledgeNoGuidesCategory => 'No guide dey for dis category';

  @override
  String knowledgeNoGuidesMatch(String query) {
    return 'No guide match \"$query\"';
  }

  @override
  String get knowledgeNoTitle => 'Title no dey';

  @override
  String get knowledgeSubtitleManual => 'Manual';

  @override
  String get knowledgeNewsLoadError => 'We no fit load news. Abeg try again.';

  @override
  String get knowledgeBaseTitle => 'Knowledge Base';

  @override
  String get knowledgeBaseSearchHint =>
      'Search guides, hazards, or contacts...';

  @override
  String get knowledgeOfflineActive => 'Offline Mode Dey On';

  @override
  String get knowledgeOfflineAvailable => 'Offline Mode Dey Available';

  @override
  String get knowledgeUsingCache => 'E dey use data wey dey saved';

  @override
  String get knowledgeContentDownloaded => 'Content don download well well';

  @override
  String get knowledgeFeaturedGuides => 'Top Guides';

  @override
  String get knowledgeNoGuides => 'No guide dey';

  @override
  String get knowledgeHazardIdGuides => 'Guides to Sabi Hazard';

  @override
  String get knowledgeHazardIdGuidesDesc => 'Sabi di danger wey dey your area';

  @override
  String get knowledgeFireResponse => 'Fire Response';

  @override
  String get knowledgeFireResponseDesc => 'Wetin to do for bush fire';

  @override
  String get knowledgeFloodReadiness => 'Prepare for Flood';

  @override
  String get knowledgeFloodReadinessDesc => 'Water & Storms';

  @override
  String get knowledgeContactsDirectory => 'Contacts Directory';

  @override
  String get knowledgeContactsDirectoryDesc => 'Emergency services';

  @override
  String get knowledgeExternalNews => 'News & Updates from Outside';

  @override
  String get knowledgeNoNews => 'No new news update.';

  @override
  String get knowledgeDetailTitle => 'Guide Details';

  @override
  String get knowledgeBookmarked => 'Guide don bookmark';

  @override
  String get knowledgeBookmarkRemoved => 'Bookmark don comot';

  @override
  String get knowledgeNoTextToSpeak => 'No text to read';

  @override
  String get knowledgeTtsUnavailable =>
      'Read-aloud no dey work. Abeg try again.';

  @override
  String knowledgeUpdatedOn(String date) {
    return 'Dem update am $date';
  }

  @override
  String get knowledgeUpdatedRecently => 'Dem update am recently';

  @override
  String knowledgeReadTime(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min to read',
      one: '1 min to read',
    );
    return '$_temp0';
  }

  @override
  String get knowledgeContentComingSoon => 'Full content dey come soon.';

  @override
  String get knowledgeRelatedTopics => 'Topics Wey Relate';

  @override
  String get knowledgeNoRelated => 'No topic wey relate.';

  @override
  String get knowledgeShareDefaultTitle => 'CRADI Guide';

  @override
  String knowledgeShareText(String content) {
    return '$content\n\nShared from CRADI Early Warning App';
  }

  @override
  String get helpSupportEmailSubject => 'CRADI App Support Request';

  @override
  String get helpSupportEmailBody => 'Abeg explain your problem:\n\n';

  @override
  String helpNoEmailApp(String email) {
    return 'No email app dey. Contact $email';
  }

  @override
  String get helpFaqTitle => 'Questions Wey Pipo Dey Ask';

  @override
  String get helpFaqReportQ => 'How I go report hazard?';

  @override
  String get helpFaqReportA =>
      'Go \"Report\" tab or tap di \"+\" button for dashboard. Choose di hazard type, add photos, and send your report. You fit talk di description with di microphone button instead of typing am.';

  @override
  String get helpFaqColorsQ => 'Wetin di alert colors mean?';

  @override
  String get helpFaqColorsA =>
      'Red mean say e bad well well (danger dey now-now), Orange na medium, and Yellow na low. Blue usually mean hazard wey concern water like flood.';

  @override
  String get helpFaqOfflineQ => 'I fit report without internet?';

  @override
  String get helpFaqOfflineA =>
      'Yes! Use \"Offline Mode\" for Settings. Your reports go save for your phone and dem go sync when you get network.';

  @override
  String get helpFaqVerifyQ => 'How I go confam other pipo reports?';

  @override
  String get helpFaqVerifyA =>
      'Go \"Alerts\" and look for reports wey dey pending near you. You fit confam or reject dem based on wetin you see.';

  @override
  String get helpStillNeedHelp => 'You still need help?';

  @override
  String get notificationsAllRead => 'All notifications don mark as read';

  @override
  String get notificationsClearAll => 'Clear All';

  @override
  String get notificationsClearConfirm =>
      'You sure say you wan delete all notifications?';

  @override
  String get notificationsMarkAllRead => 'Mark all say you don read';

  @override
  String get notificationsClearAllMenu => 'Clear all';

  @override
  String get notificationsEmpty => 'No notification yet';

  @override
  String get notificationsDefaultTitle => 'Notification';

  @override
  String get voteDispute => 'Dispute';

  @override
  String get voteDisputeRecorded =>
      'Dispute don record. Staff go check di report.';

  @override
  String get voteConfirmedThanks => 'Report don confam. Thank you!';

  @override
  String get exportRejectedOnly => 'Only Rejected';

  @override
  String get exportPreparing => 'E dey prepare export…';

  @override
  String get exportCopied => 'CSV don copy to clipboard.';

  @override
  String exportSavedTo(String path) {
    return 'Report don save for $path';
  }

  @override
  String get exportShareSubject => 'CRADI reports export';

  @override
  String exportShareFailed(String path) {
    return 'We no fit open share. Di report don save for $path';
  }

  @override
  String get statusBadgeVerified => 'DON CONFAM';

  @override
  String get statusBadgeApproved => 'APPROVED';

  @override
  String get statusBadgeRejected => 'REJECTED';

  @override
  String get statusBadgePending => 'E DEY WAIT FOR CONFAM';

  @override
  String get verificationDetailTitle => 'Confam Report';

  @override
  String get verificationDetailUnknownTime => 'Time wey we no know';

  @override
  String get verificationDetailNoLocation => 'Location details no dey';

  @override
  String get verificationDetailNoMap => 'No map location';

  @override
  String get verificationDetailQuestion => 'You fit confam dis report?';

  @override
  String get verificationDetailInstructions =>
      'Abeg confam if you don see dis hazard for di place wey dem report am.';

  @override
  String get verificationDetailCommentHint =>
      'Add details about wetin you see...';

  @override
  String get verificationDetailConfirm => 'I Fit Confam Am';

  @override
  String get verificationListRequestTooltip => 'Ask for verification';

  @override
  String get verificationListEmpty => 'No report dey wait for confam';

  @override
  String get verificationRequestSubmitted =>
      'Verification request don send well well';

  @override
  String get verificationRequestTitle => 'Ask for Verification';

  @override
  String get verificationRequestDescriptionHint =>
      'Talk wetin need verification...';

  @override
  String get verificationRequestSubmit => 'Send Request';

  @override
  String get disputeDialogTitle => 'You wan dispute di report?';

  @override
  String get disputeDialogLabel =>
      'Wetin wrong with dis report? (you must write am)';

  @override
  String get staffRejected => 'Report don reject.';

  @override
  String get staffActionsTitle => 'Staff actions';

  @override
  String get staffApproved => 'Report don approve.';

  @override
  String get staffApprove => 'Approve';

  @override
  String get staffReopened => 'Report don open again for verification.';

  @override
  String get staffRejectTitle => 'You wan reject di report?';

  @override
  String get staffRejectReasonLabel => 'Reason (you must write am)';

  @override
  String get staffRejectReasonHint => 'Di person wey report go see am';

  @override
  String get staffRejectReasonRequired => 'Abeg give reason.';

  @override
  String get verificationsLoadError => 'We no fit load peer verifications.';

  @override
  String get verificationsTitle => 'Peer verifications';

  @override
  String get verificationsNone => 'No peer vote yet.';

  @override
  String verificationsSummary(int confirmed, int disputed) {
    return '$confirmed confam · $disputed dispute';
  }

  @override
  String get verificationsYou => 'You';

  @override
  String get verificationsPeerVerifier => 'Peer verifier';

  @override
  String verificationsVoteBy(String kind, String who) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'confirmed': '$who confam am',
      'other': '$who dispute am',
    });
    return '$_temp0';
  }

  @override
  String verificationsVoteByAt(String kind, String who, String date) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'confirmed': '$who confam am · $date',
      'other': '$who dispute am · $date',
    });
    return '$_temp0';
  }

  @override
  String get voteQuestion => 'You fit confam dis report?';

  @override
  String get adminCountsError => 'We no fit load dashboard numbers';

  @override
  String get adminCountsErrorBody =>
      'Check your connection and permissions, then try again.';

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
  String get adminAlertBroadcastSuccess => 'Alert don broadcast well well';

  @override
  String adminAlertSendFailed(String error) {
    return 'Alert no send: $error';
  }

  @override
  String get adminAlertDismissFailed => 'We no fit dismiss alert.';

  @override
  String get adminAlertCompose => 'Write Alert';

  @override
  String get adminAlertTargetArea => 'Area Wey E Go';

  @override
  String get adminAlertAllAreas => 'All Areas';

  @override
  String get adminAlertTitleLabel => 'Alert Title';

  @override
  String get adminAlertRequired => 'You must fill am';

  @override
  String get adminAlertMessageLabel => 'Message';

  @override
  String get adminAlertBroadcastButton => 'Broadcast Alert';

  @override
  String get adminAlertsLoadError =>
      'We no fit load alerts. Maybe you no get permission to see dem.';

  @override
  String get adminAlertDismissTooltip => 'Dismiss alert';

  @override
  String get adminGuideDeleteTitle => 'Delete Guide';

  @override
  String get adminGuideDeleteBody =>
      'You sure say you wan delete dis guide? You no go fit bring am back.';

  @override
  String get adminGuideDeleteDenied =>
      'You no get permission to delete dis guide, or dem don already remove am.';

  @override
  String get adminGuideDeleteFailed =>
      'We no fit delete guide. Check your connection and try again.';

  @override
  String get adminGuideDeleted => 'Guide don delete';

  @override
  String get adminGuideAdd => 'Add Guide';

  @override
  String get adminGuidesLoadError => 'Wahala as we dey load guides';

  @override
  String get adminGuidesEmpty => 'No guide dey';

  @override
  String get adminGuideAddFirst => 'Add di first guide';

  @override
  String get adminGuideEditMenu => 'Change';

  @override
  String get adminGuideDeleteMenu => 'Delete';

  @override
  String get adminGuideUpdated => 'Guide don update';

  @override
  String get adminGuideCreated => 'Guide don create';

  @override
  String get adminGuideEditTitle => 'Change Guide';

  @override
  String get adminGuideNewTitle => 'New Guide';

  @override
  String get adminGuideCategoryLabel => 'Category / Hazard Type';

  @override
  String get adminGuideTitleLabel => 'Guide Title';

  @override
  String get adminGuideSourceLabel => 'Source (e.g. NEMA, WHO)';

  @override
  String get adminGuideContentLabel => 'Content (Markdown dey work)';

  @override
  String get adminGuideUpdate => 'Update Guide';

  @override
  String get adminGuideCreate => 'Create Guide';

  @override
  String get adminReportsLoadError =>
      'We no fit load reports. Maybe you no get permission to see dem.';

  @override
  String get adminReportsRejectReasonLabel =>
      'Reason (e good make you write am)';

  @override
  String get adminReportsRejectReasonHint => 'Why una dey reject dis report?';

  @override
  String adminReportsStatusUpdateFailed(String error) {
    return 'We no fit update report status: $error';
  }

  @override
  String get adminReportsReopened => 'Report don open again for verification';

  @override
  String adminReportsMarkedAs(String status) {
    return 'Report don mark as $status';
  }

  @override
  String get adminReportsDateTime => 'Date/Time';

  @override
  String get adminReportsLga => 'LGA';

  @override
  String get adminReportsLocationDetails => 'Location Details';

  @override
  String get adminReportsRejectionReason => 'Why dem reject am';

  @override
  String get adminReportsNoReason => 'Dem no give reason';

  @override
  String get adminReportsImages => 'Pictures';

  @override
  String get adminReportsMarkVerified => 'Mark am Confam';

  @override
  String get adminReportsReopen => 'Open Again (pending)';

  @override
  String get adminReportsReopenReset => 'Open Again (go back to pending)';

  @override
  String get adminReportsEmpty => 'No report dey';

  @override
  String get adminReportsLoadMoreError =>
      'We no fit load more. Tap to try again.';

  @override
  String get adminReportsLoadMore => 'Load more';

  @override
  String get adminUsersLoadError =>
      'We no fit load users. Maybe you no get permission to see dem.';

  @override
  String get adminUsersEmpty => 'No user dey';

  @override
  String get adminUsersNoPermission =>
      'You no get permission to change dis user.';

  @override
  String get adminUsersUpdateFailed => 'Update no work. Abeg try again.';

  @override
  String get adminUsersApproved => 'User don approve';

  @override
  String get adminUsersRejected => 'User don reject';

  @override
  String get adminUsersChangeRole => 'Change Role';

  @override
  String get adminUsersRoleUpdated =>
      'Role don update. E go start to work once dem approve di user.';

  @override
  String get adminUsersApply => 'Apply';

  @override
  String get adminUsersChangeLocationTitle => 'Change location';

  @override
  String adminUsersLocationUpdated(String ward, String lga, String state) {
    return 'Location don change to $ward, $lga, $state';
  }

  @override
  String get adminUsersDisabled => 'User don off';

  @override
  String get adminUsersReenabled => 'User don on again';

  @override
  String get adminUsersSearchHint => 'Search with name or email…';

  @override
  String get adminUsersAllRoles => 'All Roles';

  @override
  String get adminUsersShowingPending => 'E dey show Approvals Wey Dey Wait';

  @override
  String get adminUsersShowingApproved =>
      'E dey show Users Wey Dem Don Approve';

  @override
  String get adminUsersPendingChip => 'Pending';

  @override
  String get adminUsersApproveMenu => 'Approve';

  @override
  String get adminUsersRevokeMenu => 'Collect access back';

  @override
  String get adminUsersChangeRoleMenu => 'Change role';

  @override
  String get adminUsersChangeLocationMenu => 'Change location';

  @override
  String get adminUsersReenableMenu => 'On user again';

  @override
  String get adminUsersDisableMenu => 'Off user';

  @override
  String get onboardingWelcomeBody =>
      'Early Warning and Emergency Response system for your community';

  @override
  String get onboardingMonitorTitle => 'Dey Watch Hazards As E Dey Happen';

  @override
  String get onboardingMonitorBody =>
      'Report emergency, follow hazards, and keep your community safe';

  @override
  String get onboardingJoinBody =>
      'Create account and start to protect your community today';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get splashTagline => 'Early Warning & Emergency Response';

  @override
  String get connectivityOfflineBanner => 'Offline - Some features fit no work';

  @override
  String get routeReportNotFound => 'We no see di report';

  @override
  String get routeViewReports => 'See reports';

  @override
  String get routeAlertNotFound => 'We no see di alert';

  @override
  String get routeViewAlerts => 'See alerts';

  @override
  String get routeNotFoundTitle => 'We no see di page';

  @override
  String get routeNotFoundBody => 'Di page wey you dey find no dey.';

  @override
  String get routeTryAgain => 'Try again';

  @override
  String get routeGoHome => 'Go home';

  @override
  String get routeLoadFailedTitle => 'E no fit load';

  @override
  String get routeLoadFailedBody => 'Check your connection, then try again.';

  @override
  String get routeMissingBody =>
      'Maybe dem don remove am, or you no get access to am.';

  @override
  String get forceUpdateStoreFailed =>
      'We no fit open di store. Abeg update di app from your app store.';

  @override
  String get forceUpdateTitle => 'You must update';

  @override
  String get forceUpdateDefaultMessage =>
      'Abeg update di EWER app to continue.';

  @override
  String forceUpdateMinVersion(String version) {
    return 'Lowest version: $version';
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
      'EWER need your location to show exactly where hazard dey and to alert responders wey dey near. We go only use your location when you send report or use di tactical map.';

  @override
  String get permissionNotificationsTitle => 'On Alerts';

  @override
  String get permissionNotificationsRationale =>
      'Get updates sharp-sharp about hazards for your area. We go only send important safety alerts and status updates for your reports.';

  @override
  String get permissionPhotosTitle => 'Photo Access';

  @override
  String get permissionPhotosRationale =>
      'EWER need access to your photos so you fit upload evidence of hazards. We go only upload di photos wey you yourself choose.';

  @override
  String get permissionNotNow => 'No Be Now';

  @override
  String permissionSettingsBody(String reason) {
    return '$reason\n\nAbeg on am for your phone settings.';
  }

  @override
  String offlineDraftLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You fit only keep $count reports wey never send for dis phone. Sync or throw some away first.',
    );
    return '$_temp0';
  }

  @override
  String nearbyReportsInAreaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports for your area',
      one: '1 report for your area',
    );
    return '$_temp0';
  }

  @override
  String landingCopyright(String year) {
    return '© $year CRADI. All rights reserved.';
  }

  @override
  String get verificationRequestBadge => 'Verification request';

  @override
  String get reportViewSafetyGuides => 'Safety guides';

  @override
  String get authAccountRemoved =>
      'Dem don remove your account, so we don sign you out. Contact your coordinator if you think say na mistake.';

  @override
  String get adminUsersApproveUnconfirmed =>
      'Dis account never confirm im email or phone yet, so you no fit approve am.';

  @override
  String get commonSubmittingPleaseWait => 'E dey send, abeg wait';

  @override
  String get commonClearSearch => 'Clear search';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get knowledgeShareTooltip => 'Share dis guide';

  @override
  String get knowledgeBookmarkAddTooltip => 'Save dis guide';

  @override
  String get knowledgeBookmarkRemoveTooltip => 'Remove di guide wey you save';

  @override
  String get knowledgeListenTooltip => 'Listen to dis guide';

  @override
  String a11ySeverityLabel(String severity) {
    return 'How bad e be: $severity';
  }

  @override
  String a11yStatusLabel(String status) {
    return 'Status: $status';
  }

  @override
  String contactsSmsTooltip(String name) {
    return 'Send text message give $name';
  }

  @override
  String reportRemovePhoto(int number) {
    return 'Remove photo $number';
  }

  @override
  String get notificationReportStatusTitle => 'Report update';

  @override
  String notificationReportApproved(String hazard) {
    return 'Dem don approve your report ($hazard) and dem don send alert.';
  }

  @override
  String notificationReportVerified(String hazard) {
    return 'Peers don verify your report ($hazard); e dey wait final approval.';
  }

  @override
  String notificationReportRejected(String hazard) {
    return 'Dem reject your report ($hazard). Open am make you see wetin happen.';
  }

  @override
  String notificationReportPending(String hazard) {
    return 'Your report ($hazard) dey wait make peers verify am.';
  }

  @override
  String get notificationAlertBody => 'Dem don send new alert for your area.';

  @override
  String get knowledgeSavedFilter => 'Saved';

  @override
  String get knowledgeNoSavedGuides =>
      'You never save any guide. Tap di bookmark for one guide make you save am.';
}
