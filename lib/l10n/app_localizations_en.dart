// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'EWER Early Warning';

  @override
  String get monitoringZone => 'Monitoring Zone';

  @override
  String get toVerify => 'To Verify';

  @override
  String get alerts => 'Alerts';

  @override
  String get myReports => 'My Reports';

  @override
  String get browseCategories => 'Browse Categories';

  @override
  String get noReportsToVerify => 'No reports to verify';

  @override
  String get noActiveAlerts => 'No active alerts';

  @override
  String get seeAll => 'See All';

  @override
  String get notifications => 'NOTIFICATIONS';

  @override
  String get pushNotifications => 'Push Notifications';

  @override
  String get general => 'GENERAL';

  @override
  String get language => 'Language';

  @override
  String get helpFaq => 'Help & FAQ';

  @override
  String get aboutApp => 'About App';

  @override
  String get logout => 'Log Out';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get continueButton => 'Continue';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get verifyPhoneNumber => 'Verify Phone Number';

  @override
  String get resendCode => 'Resend Code';

  @override
  String get verify => 'Verify';

  @override
  String get selectHazard => 'Select Hazard';

  @override
  String get whatIncident => 'What type of incident are you reporting?';

  @override
  String get erosion => 'Erosion';

  @override
  String get howSevereSituation => 'How severe is the situation?';

  @override
  String get setSeverity => 'Set Severity';

  @override
  String get nextLocation => 'Next: Location';

  @override
  String get lowMinorImpact => 'Low - Minor impact';

  @override
  String get mediumNoticeableImpact => 'Medium - Noticeable impact';

  @override
  String get highSignificantDamage => 'High - Significant damage';

  @override
  String get criticalLifeThreatening => 'Critical - Life threatening';

  @override
  String get camera => 'Camera';

  @override
  String get useMyLocationInfo => 'Use My Location Info';

  @override
  String get myProfile => 'My Profile';

  @override
  String get editProfileDetails => 'Edit Profile Details';

  @override
  String get fullName => 'Full Name';

  @override
  String get emailAddress => 'Email Address';

  @override
  String get biometricLogin => 'Biometric Login';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get languagePreference => 'Language Preference';

  @override
  String get offlineDataSync => 'Offline Data Sync';

  @override
  String get upToDate => 'Up to date';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get biometricsNotAvailable =>
      'Biometrics not available on this device';

  @override
  String get biometricsEnabled => 'Biometric login enabled';

  @override
  String get biometricsDisabled => 'Biometric login disabled';

  @override
  String get profileUpdated => 'Profile updated successfully!';

  @override
  String get syncing => 'Syncing...';

  @override
  String get offline => 'Offline';

  @override
  String get offlineModeReady => 'Offline Mode Ready: ';

  @override
  String get validation_required => 'This field is required';

  @override
  String get validation_invalidEmail => 'Please enter a valid email address';

  @override
  String validation_minLength(int length) {
    return 'Must be at least $length characters';
  }

  @override
  String validation_maxLength(int length) {
    return 'Must be at most $length characters';
  }

  @override
  String get syncStatus => 'SYNC STATUS';

  @override
  String get onlineJustNow => 'Online • Just now';

  @override
  String get active => 'active';

  @override
  String get pending => 'Pending';

  @override
  String get verified => 'Verified';

  @override
  String get approved => 'Approved';

  @override
  String get floodsCategory => 'Floods';

  @override
  String get droughtsCategory => 'Droughts';

  @override
  String get pestsCategory => 'Pests';

  @override
  String get conflictsCategory => 'Conflicts';

  @override
  String get noRecentAlerts => 'No recent alerts';

  @override
  String get selectZone => 'Select Zone';

  @override
  String get activeZone => 'Active';

  @override
  String get notSetZone => 'Not Set';

  @override
  String get reportsStatus => 'Reports Status';

  @override
  String get rejected => 'Rejected';

  @override
  String get generateReport => 'Generate Report';

  @override
  String noReportsStatus(String status) {
    return 'No $status Reports';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String reportedBy(String name) {
    return 'Reported by $name';
  }

  @override
  String get viewDetails => 'View Details';

  @override
  String get reportVerified => 'Report verified successfully';

  @override
  String get verifyReport => 'Verify';

  @override
  String get reportRejectedItem => 'Report rejected';

  @override
  String get reject => 'Reject';

  @override
  String get reportResolvedItem => 'Report approved';

  @override
  String get markResolved => 'Approve';

  @override
  String get reportMovedPending => 'Report moved back to Pending';

  @override
  String get reopen => 'Reopen';

  @override
  String get reportReopenedPending => 'Report reopened and moved to Pending';

  @override
  String get reportDetailsTitle => 'Report Details';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get describeHazardHint =>
      'Describe the hazard here (e.g. flood levels rising, bridge collapsed)...';

  @override
  String get speechNotAvailable => 'Speech recognition not available';

  @override
  String get listeningSpeakNow => 'Listening... Speak now';

  @override
  String get beSpecificLocationSeverity =>
      'Be specific about location and severity.';

  @override
  String get whenDidThisOccur => 'When Did This Occur?';

  @override
  String get optionalLabel => 'Optional';

  @override
  String get todayLabel => 'Today';

  @override
  String get tapToSelectDateTime =>
      'Tap to select date & time. Defaults to now if not changed.';

  @override
  String get evidenceLabel => 'Evidence';

  @override
  String get max3Photos => 'Max 3 photos';

  @override
  String get offlineModeMessage =>
      'Your photos will be compressed automatically. Reports are saved locally until you have internet.';

  @override
  String get reviewReportBtn => 'Review Report';

  @override
  String get cameraBtn => 'Camera';

  @override
  String get galleryBtn => 'Gallery';

  @override
  String get submissionFailed => 'Submission failed';

  @override
  String get savedForLater => 'Saved for Later';

  @override
  String get reportSubmittedTitle => 'Report Submitted!';

  @override
  String get offlineReportMessage =>
      'You are offline. The report will be sent automatically when you are back online.';

  @override
  String get onlineReportMessage =>
      'Your report has been successfully sent to central command.';

  @override
  String get statusLabel => 'STATUS';

  @override
  String get reportIdLabel => 'REPORT ID';

  @override
  String get queuedStatus => 'QUEUED';

  @override
  String get sentStatus => 'SENT';

  @override
  String get returnToDashboard => 'Return to Dashboard';

  @override
  String get reviewReportTitle => 'Review Report';

  @override
  String get reviewReportDesc =>
      'Please review the details below to ensure accuracy before submitting to the central command.';

  @override
  String get hazardDetails => 'Hazard Details';

  @override
  String get hazardType => 'Hazard Type';

  @override
  String get notSelected => 'Not Selected';

  @override
  String get severityLevelLabel => 'Severity Level';

  @override
  String get severityDesc => 'Assess the intensity of the hazard.';

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
  String get whenItOccurred => 'When it occurred';

  @override
  String get locationLabel => 'Location';

  @override
  String get notProvided => 'Not Provided';

  @override
  String get monitorNotes => 'Monitor Notes';

  @override
  String get noDescriptionProvided => 'No description provided';

  @override
  String get addPhotoBtn => 'Add';

  @override
  String get submitReportBtn => 'Submit Report';

  @override
  String get editBtn => 'Edit';

  @override
  String get locationPermissionDenied => 'Location permission denied';

  @override
  String get enableGpsMessage => 'Unable to get location. Please enable GPS.';

  @override
  String get locationError => 'Location error:';

  @override
  String get acquiringGps => 'ACQUIRING...';

  @override
  String get noSignalGps => 'NO SIGNAL';

  @override
  String get gpsStrong => 'GPS STRONG';

  @override
  String get gpsGood => 'GPS GOOD';

  @override
  String get gpsWeak => 'GPS WEAK';

  @override
  String get couldNotFindLocation => 'Could not find location on map';

  @override
  String get mapUpdateError => 'Map update error:';

  @override
  String get incidentLocation => 'Incident Location';

  @override
  String get gettingLocation => 'Getting location...';

  @override
  String get noGpsData => 'No GPS data';

  @override
  String get locationUnavailable => 'Location unavailable';

  @override
  String get coordinatesLabel => 'COORDINATES';

  @override
  String get viewDetailsBtn => 'View Details';

  @override
  String get wardAndLgaSelection => 'Ward & LGA Selection';

  @override
  String get selectWardDropdown => 'Select your ward from the dropdown';

  @override
  String get selectLgaWardIncident =>
      'Select the LGA and Ward where the incident occurred';

  @override
  String get stateLabel => 'State';

  @override
  String get selectState => 'Select State';

  @override
  String get selectStateFirst => 'Select State first';

  @override
  String get lgaLabel => 'LGA (Local Government Area)';

  @override
  String get selectLga => 'Select LGA';

  @override
  String get selectLgaFirst => 'Select LGA first';

  @override
  String get wardLabel => 'Ward';

  @override
  String get selectWard => 'Select Ward';

  @override
  String get enterLocationManually => 'Enter Location Manually';

  @override
  String get addressOrCoordinates => 'Address or Coordinates';

  @override
  String get cancelBtn => 'Cancel';

  @override
  String get setLocationBtn => 'Set';

  @override
  String get manualLocationSet => 'Manual location set';

  @override
  String get locationIncorrectManual => 'Location incorrect? Enter manually';

  @override
  String get pleaseSelectStateLgaWard =>
      'Please select State, LGA, and Ward before continuing';

  @override
  String get confirmAndContinue => 'Confirm & Continue';

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
  String get selectStatusExport => 'Select status to export:';

  @override
  String get allReports => 'All Reports';

  @override
  String get pendingOnly => 'Pending Only';

  @override
  String get verifiedOnly => 'Verified Only';

  @override
  String get approvedOnly => 'Approved Only';

  @override
  String get adminPortal => 'Admin Portal';

  @override
  String get systemOverview => 'System Overview';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get userManagement => 'User Management';

  @override
  String get reportsOverview => 'Reports Overview';

  @override
  String get alertsBroadcast => 'Alerts & Broadcast';

  @override
  String get knowledgeManagement => 'Knowledge Management';

  @override
  String get systemHealth => 'System Health';

  @override
  String get pendingApprovals => 'Pending Approvals';

  @override
  String get pendingReports => 'Pending Reports';

  @override
  String get verifiedReports => 'Verified Reports';

  @override
  String get totalUsers => 'Total Users';

  @override
  String get activeAlertsAdmin => 'Active Alerts';

  @override
  String get totalReports => 'Total Reports';

  @override
  String get userManagementDesc =>
      'Approve accounts, assign roles, deactivate users';

  @override
  String get reportsOverviewDesc =>
      'View, validate, or reject reports across all LGAs';

  @override
  String get alertsBroadcastDesc =>
      'Send emergency alerts to users or specific areas';

  @override
  String get knowledgeManagementDesc =>
      'Add, edit, or remove emergency knowledge guides';

  @override
  String get connected => 'Connected';

  @override
  String get none => 'None';

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
    return 'Hello, $name';
  }

  @override
  String get hazardFlooding => 'Flooding';

  @override
  String get hazardExtremeTemperatures => 'Extreme Temperatures';

  @override
  String get hazardDrought => 'Drought';

  @override
  String get hazardWindstorms => 'Windstorms';

  @override
  String get hazardWildfires => 'Wildfires';

  @override
  String get hazardErosion => 'Erosion';

  @override
  String get hazardPestOutbreak => 'Pest Outbreak';

  @override
  String get hazardCropDisease => 'Crop Disease';

  @override
  String get hazardConflict => 'Conflict';

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
  String get severityLow => 'Low';

  @override
  String get severityMedium => 'Medium';

  @override
  String get severityHigh => 'High';

  @override
  String get severityCritical => 'Critical';

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
