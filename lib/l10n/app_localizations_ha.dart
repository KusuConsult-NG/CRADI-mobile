// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hausa (`ha`).
class AppLocalizationsHa extends AppLocalizations {
  AppLocalizationsHa([String locale = 'ha']) : super(locale);

  @override
  String get appTitle => 'EWER Gargaɗin Farko';

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
  String get pushNotifications => 'Sanarwa Kai Tsaye';

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
  String get settingsTitle => 'Saituna';

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
  String get camera => 'Kyamara';

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
  String get offlineDataSync => 'Daidaita Bayanan da Aka Ajiye';

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
  String get profileUpdated => 'An sabunta bayananka cikin nasara!';

  @override
  String get syncing => 'Ana daidaitawa...';

  @override
  String get offline => 'Babu Intanet';

  @override
  String get offlineModeReady => 'Shirye don Aiki Ba Tare da Intanet ba: ';

  @override
  String get validation_required => 'Ana buƙatar wannan filin';

  @override
  String get validation_invalidEmail =>
      'Don Allah shigar da ingantaccen adireshin imel';

  @override
  String validation_minLength(int length) {
    return 'Dole ya kai aƙalla haruffa $length';
  }

  @override
  String validation_maxLength(int length) {
    return 'Kada ya wuce haruffa $length';
  }

  @override
  String get syncStatus => 'MATSAYIN DAIDAITAWA';

  @override
  String get onlineJustNow => 'Kan Layi • Yanzu';

  @override
  String get active => 'mai aiki';

  @override
  String get pending => 'Ana Jira';

  @override
  String get verified => 'An Tabbatar';

  @override
  String get approved => 'An Amince';

  @override
  String get floodsCategory => 'Ambaliya';

  @override
  String get droughtsCategory => 'Fari';

  @override
  String get pestsCategory => 'Kwari';

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
    return 'Rahoto daga $name';
  }

  @override
  String get viewDetails => 'Duba Cikakkun Bayanai';

  @override
  String get reportVerified => 'An tabbatar da rahoton cikin nasara';

  @override
  String get verifyReport => 'Tabbatar';

  @override
  String get reportRejectedItem => 'An ƙi rahoton';

  @override
  String get reject => 'Ƙi';

  @override
  String get reportResolvedItem => 'An amince da rahoton';

  @override
  String get markResolved => 'Amince';

  @override
  String get reportMovedPending => 'An mayar da rahoton zuwa Ana Jira';

  @override
  String get reopen => 'Sake buɗewa';

  @override
  String get reportReopenedPending =>
      'An sake buɗe rahoton kuma an mayar da shi zuwa Ana Jira';

  @override
  String get reportDetailsTitle => 'Cikakkun Bayanan Rahoto';

  @override
  String get descriptionLabel => 'Bayani';

  @override
  String get describeHazardHint =>
      'Bayyana haɗarin a nan (misali, ruwan ambaliya na ƙaruwa, gada ta rushe)...';

  @override
  String get speechNotAvailable => 'Gane murya ba ya samuwa';

  @override
  String get listeningSpeakNow => 'Ana saurare... Ka yi magana yanzu';

  @override
  String get beSpecificLocationSeverity =>
      'Bayyana wurin da tsananin lamarin sosai.';

  @override
  String get whenDidThisOccur => 'Yaushe Wannan Ya Faru?';

  @override
  String get optionalLabel => 'Na zaɓi';

  @override
  String get todayLabel => 'Yau';

  @override
  String get tapToSelectDateTime =>
      'Danna don zaɓar kwanan wata da lokaci. Idan ba ka canza ba, zai kasance lokacin yanzu.';

  @override
  String get evidenceLabel => 'Shaida';

  @override
  String get max3Photos => 'Hotuna 3 kawai';

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
  String get hazardDetails => 'Bayanan Haɗari';

  @override
  String get hazardType => 'Nau\'in Haɗari';

  @override
  String get notSelected => 'Ba a zaɓa ba';

  @override
  String get severityLevelLabel => 'Matsayin Tsanani';

  @override
  String get severityDesc => 'Auna tsananin haɗarin.';

  @override
  String get severityLowShort => 'Ƙarami';

  @override
  String get severityMedShort => 'Tsaka';

  @override
  String get severityHighShort => 'Babba';

  @override
  String get severityCritShort => 'Gaggawa';

  @override
  String get dateTimeLabel => 'Kwanan Wata & Lokaci';

  @override
  String get whenItOccurred => 'Lokacin da ya faru';

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
  String get gpsWeak => 'GPS MARAR ƘARFI';

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
  String get locationUnavailable => 'Ba a samu wuri ba';

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
  String get latitudeLabel => 'Layin Kwance';

  @override
  String get longitudeLabel => 'Layin Tsaye';

  @override
  String get accuracyLabel => 'Daidaito';

  @override
  String get altitudeLabel => 'Tsayi';

  @override
  String get closeBtn => 'Rufe';

  @override
  String get selectStatusExport => 'Zaɓi matsayin don fitarwa:';

  @override
  String get allReports => 'Dukkan Rahotanni';

  @override
  String get pendingOnly => 'Masu Jira Kaɗai';

  @override
  String get verifiedOnly => 'Waɗanda Aka Tabbatar Kaɗai';

  @override
  String get approvedOnly => 'Waɗanda Aka Amince Kaɗai';

  @override
  String get adminPortal => 'Tashar Gudanarwa';

  @override
  String get systemOverview => 'Taƙaitaccen Bayanin Tsari';

  @override
  String get quickActions => 'Ayyuka Masu Sauri';

  @override
  String get userManagement => 'Gudanar da Masu Amfani';

  @override
  String get reportsOverview => 'Taƙaitaccen Bayanin Rahotanni';

  @override
  String get alertsBroadcast => 'Faɗakarwa & Watsawa';

  @override
  String get knowledgeManagement => 'Gudanar da Ilimi';

  @override
  String get systemHealth => 'Lafiyar Tsarin';

  @override
  String get pendingApprovals => 'Masu Jiran Amincewa';

  @override
  String get pendingReports => 'Rahotanni Masu Jira';

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
      'Amince da asusu, ba da matsayi, dakatar da masu amfani';

  @override
  String get reportsOverviewDesc =>
      'Duba, tabbatar, ko ƙi rahotanni a dukkan Ƙananan Hukumomi';

  @override
  String get alertsBroadcastDesc =>
      'Aika faɗakarwa ga masu amfani ko takamaiman wurare';

  @override
  String get knowledgeManagementDesc =>
      'Saka, gyara, ko cire jagororin gaggawa';

  @override
  String get connected => 'An Haɗa';

  @override
  String get none => 'Babu';

  @override
  String get errorNetwork =>
      'Matsalar hanyar sadarwa. Don Allah duba haɗin intanet ɗinka.';

  @override
  String get errorNoPermission => 'Ba ka da izinin yin wannan aiki.';

  @override
  String get errorContactSupport =>
      'An sami matsala. Don Allah sake gwadawa ko tuntuɓi masu taimako.';

  @override
  String get errorUnexpected =>
      'An sami matsalar da ba a zata ba. Don Allah sake gwadawa.';

  @override
  String authEmailNotConfirmed(String email) {
    return 'Don Allah fara tabbatar da imel ɗinka. Mun aika sabuwar lamba zuwa $email.';
  }

  @override
  String get languageSelectTitle => 'Zaɓi Harshe';

  @override
  String get shellAppBarTitle => 'CRADI Gargaɗin Farko';

  @override
  String get shellNotificationsTooltip => 'Sanarwa';

  @override
  String get shellDrawerDefaultName => 'Mai Sa Ido kan Gargaɗin Farko';

  @override
  String get shellDrawerProfile => 'Bayanan Kai';

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
  String get navAdmin => 'Gudanarwa';

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
  String get hazardWildfires => 'Gobarar Daji';

  @override
  String get hazardErosion => 'Zaizaya';

  @override
  String get hazardPestOutbreak => 'Annobar Kwari';

  @override
  String get hazardCropDisease => 'Cutar Amfanin Gona';

  @override
  String get hazardConflict => 'Rikici';

  @override
  String get hazardUnknown => 'Haɗarin da Ba a Sani Ba';

  @override
  String get hazardTitleFlooding => 'Faɗakarwar Ambaliya';

  @override
  String get hazardTitleExtremeTemperatures => 'Tsananin Zafi ko Sanyi';

  @override
  String get hazardTitleDrought => 'Gargaɗin Fari';

  @override
  String get hazardTitleWindstorms => 'Faɗakarwar Iska Mai Ƙarfi';

  @override
  String get hazardTitleWildfires => 'Rahoton Gobarar Daji';

  @override
  String get hazardTitleErosion => 'Rahoton Zaizayar Ƙasa';

  @override
  String get hazardTitlePestOutbreak => 'Annobar Kwari';

  @override
  String get hazardTitleCropDisease => 'Cutar Amfanin Gona';

  @override
  String get hazardTitleConflict => 'Rahoton Rikici';

  @override
  String get timeJustNow => 'Yanzu-yanzu';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'min $count baya',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'awa $count baya',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'kwana $count baya',
    );
    return '$_temp0';
  }

  @override
  String timeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mako $count baya',
    );
    return '$_temp0';
  }

  @override
  String get commonUnknown => 'Ba a sani ba';

  @override
  String get commonUnknownLocation => 'Wurin da Ba a Sani Ba';

  @override
  String get commonAnonymous => 'Ba a Bayyana Suna Ba';

  @override
  String get commonCommunityReport => 'Rahoton Al\'umma';

  @override
  String get reportStatusPending => 'Ana Jira';

  @override
  String get reportStatusVerified => 'An Tabbatar';

  @override
  String get reportStatusApproved => 'An Amince';

  @override
  String get reportStatusRejected => 'An Ƙi';

  @override
  String get verifyErrorOwnReport =>
      'Ba za ka iya tabbatar da rahotonka na kanka ba.';

  @override
  String verifyErrorTooFar(String distanceKm) {
    return 'Dole ne ka kasance cikin nisan km 2 daga wurin rahoton kafin ka tabbatar. Nisanka a yanzu: km $distanceKm.';
  }

  @override
  String get verifyConfirmedMessage => 'An tabbatar da rahoton cikin nasara';

  @override
  String get verifyDisputedMessage => 'An ƙalubalanci rahoton';

  @override
  String get verifyErrorAlreadyVoted =>
      'Ka riga ka kaɗa ƙuri\'a kan wannan rahoton.';

  @override
  String get verifyErrorNotPermitted =>
      'Asusunka ba shi da izinin tabbatar da rahotanni. Tabbatarwa na buƙatar matsayin mai sa ido da aka amince da shi.';

  @override
  String get verifyErrorNoLongerPending => 'Wannan rahoton ba ya jira kuma.';

  @override
  String get verifyErrorSignedOut =>
      'Dole ne ka shiga kafin ka tabbatar da rahotanni.';

  @override
  String get verifyErrorFailed => 'Tabbatarwa ta kasa';

  @override
  String get verifyErrorDisputeReasonRequired =>
      'Don Allah bayyana dalilin da ya sa kake ƙalubalantar wannan rahoton.';

  @override
  String get verifyRequestQueuedOffline =>
      'Babu intanet: an ajiye buƙatar kuma za a aika ta da zarar ka dawo kan layi.';

  @override
  String get reportActionErrorNoPermissionOrGone =>
      'Ba ka da izinin canza wannan rahoton, ko kuma ba ya nan kuma.';

  @override
  String get reportActionErrorAlreadyPending =>
      'Wannan rahoton tuni yana jira.';

  @override
  String get reportActionErrorGone => 'Wannan rahoton ba ya nan kuma.';

  @override
  String get reportActionErrorNoPermission =>
      'Ba ka da izinin canza wannan rahoton.';

  @override
  String get reportsLoadErrorOffline =>
      'An kasa isa ga sabar. Duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get offlineSavedWillSync =>
      'An ajiye ba tare da intanet ba. Za a daidaita da zarar ka dawo kan layi.';

  @override
  String get profileErrorOfflineNotSaved =>
      'Ba ka da intanet — ba a ajiye canje-canjen ba.';

  @override
  String get profileErrorSignedOut =>
      'Dole ne ka shiga kafin ka sabunta bayananka.';

  @override
  String get profileErrorSaveFailed =>
      'An kasa ajiye canje-canjenka. Don Allah duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get profileErrorNameRequired => 'Don Allah shigar da sunanka.';

  @override
  String get profileErrorEmailSignedOut =>
      'Dole ne ka shiga kafin ka canza imel ɗinka.';

  @override
  String profileEmailConfirmationSent(String email) {
    return 'An aika hanyar tabbatarwa zuwa $email. Imel ɗinka zai canza bayan ka tabbatar da shi.';
  }

  @override
  String get profileErrorEmailReauth =>
      'Saboda tsaro, don Allah ka fita sannan ka sake shiga kafin ka canza imel ɗinka.';

  @override
  String get profileErrorEmailInUse =>
      'Wani asusu na daban yana amfani da wannan imel ɗin.';

  @override
  String get profileErrorEmailUpdateFailed =>
      'An kasa sabunta imel. Don Allah sake gwadawa.';

  @override
  String get profileErrorLocationIncomplete =>
      'Don Allah zaɓi jiharka, ƙaramar hukuma da gunduma don sabunta wurinka.';

  @override
  String get profileErrorLocationSignedOut =>
      'Dole ne ka shiga kafin ka canza wurinka.';

  @override
  String get profileErrorLocationManaged =>
      'Mai gudanarwa ne ke kula da wurinka. Don Allah nemi mai gudanarwa ya canza wurin asusun ma\'aikaci.';

  @override
  String get profileErrorLocationFailed =>
      'An kasa sabunta wurinka. Don Allah duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get profileDefaultName => 'Mai Amfani';

  @override
  String get homeVerifyReportsLink => 'Tabbatar da Rahotanni';

  @override
  String get homeTabNearby => 'Na Kusa';

  @override
  String homeZoneStatus(String zone, String status) {
    return '$zone • $status';
  }

  @override
  String get homeEmptyMyReports => 'Har yanzu ba ka aika wani rahoto ba';

  @override
  String get homeOpenNearbyReports => 'Buɗe Rahotannin Kusa';

  @override
  String get homeEmptyNearby => 'Babu rahotanni a kusa';

  @override
  String reportLocationAndTime(String location, String time) {
    return '$location • $time';
  }

  @override
  String get homeZoneSheetTitle => 'Zaɓi Yankin Sa Ido';

  @override
  String get homeZoneAll => 'Dukkan Yankuna (Babu Tacewa)';

  @override
  String get homeZoneAllSelected => 'Ana nuna dukkan yankuna';

  @override
  String homeZoneAllLocalOnly(String error) {
    return 'Ana nuna dukkan yankuna a wannan na\'ura. $error';
  }

  @override
  String homeZoneChanged(String zone) {
    return 'An canza yankin sa ido zuwa $zone';
  }

  @override
  String homeZoneLocalOnly(String zone, String error) {
    return 'Ana nuna $zone a wannan na\'ura. $error';
  }

  @override
  String zoneStateLabel(String state) {
    return 'Jihar $state';
  }

  @override
  String get settingsPushPermissionNeeded =>
      'Ba EWER izinin sanarwa a saitunan wayarka don karɓar faɗakarwa.';

  @override
  String get settingsPushUnavailable =>
      'Sanarwa kai tsaye ba ta samuwa a yanzu. An ajiye zaɓinka kuma zai fara aiki idan ta samu.';

  @override
  String get settingsSectionSecurity => 'TSARO DA SIRRI';

  @override
  String get settingsBiometricSubtitle =>
      'Yi amfani da zanen yatsa ko Face ID don shiga';

  @override
  String get settingsBiometricUnavailable => 'Ba ya samuwa a wannan na\'ura';

  @override
  String get settingsOfflineMode => 'Yanayin Babu Intanet';

  @override
  String get settingsOfflineModeEnabled => 'An kunna yanayin babu intanet';

  @override
  String get settingsOfflineModeRestoring => 'Ana dawo da haɗi...';

  @override
  String get settingsLogoutConfirm => 'Ka tabbata kana so ka fita?';

  @override
  String get settingsFooterSystemName =>
      'Tsarin Gargaɗin Farko kan Yanayi (CEWS)';

  @override
  String get biometricErrorNotEnrolled =>
      'Ba a yi rajistar biometric ba. Don Allah fara ƙara zanen yatsa ko Face ID a Saitunan na\'urarka.';

  @override
  String get biometricErrorUnavailable =>
      'Biometric ba ya samuwa a wannan na\'ura.';

  @override
  String get biometricErrorLockedOut =>
      'Ƙoƙari ya yi yawa. An kulle biometric; buɗe na\'urarka ka sake gwadawa daga baya.';

  @override
  String get biometricErrorFailed =>
      'Tantancewar biometric ta kasa. Don Allah sake gwadawa.';

  @override
  String get biometricPromptDefault => 'Don Allah tantance kanka don ci gaba';

  @override
  String get biometricEnablePrompt => 'Kunna shiga ta biometric don EWER';

  @override
  String get biometricLoginPrompt => 'Tantance kanka don shiga EWER Mobile';

  @override
  String get biometricTypeFace => 'Face ID';

  @override
  String get biometricTypeFingerprint => 'Zanen Yatsa';

  @override
  String get biometricTypeIris => 'Ƙwayar Ido';

  @override
  String get biometricTypeGeneric => 'Tantancewar Jiki';

  @override
  String get authErrorEmailRegistered =>
      'An riga an yi rajistar wannan imel. Don Allah ka shiga.';

  @override
  String get authErrorRegistrationFailed =>
      'Rajista ta kasa. Don Allah sake gwadawa.';

  @override
  String get authErrorNetworkRetry =>
      'Matsalar hanyar sadarwa. Don Allah duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get authErrorWeakPassword =>
      'Kalmar sirri ba ta da ƙarfi. Yi amfani da aƙalla haruffa 8 masu ɗauke da harafi, lamba da alama.';

  @override
  String get authErrorAccountRegistered =>
      'An riga an yi rajistar wannan asusu. Don Allah ka shiga.';

  @override
  String get authErrorRegistrationDisabled =>
      'An dakatar da rajista a yanzu. Don Allah tuntuɓi masu taimako.';

  @override
  String get authErrorTooManyAttempts =>
      'Ƙoƙari ya yi yawa. Don Allah jira \'yan mintuna kafin ka sake gwadawa.';

  @override
  String get authErrorLoginFailed => 'Shiga ya kasa. Don Allah sake gwadawa.';

  @override
  String get authErrorAccountDisabled =>
      'An dakatar da wannan asusu. Don Allah tuntuɓi masu taimako.';

  @override
  String get authErrorLoginConnection =>
      'Shiga ya kasa. Don Allah duba haɗin intanet ɗinka.';

  @override
  String get authErrorInvalidCredentials =>
      'Imel ko kalmar sirri ba daidai ba ne';

  @override
  String get authErrorTooManyLogins =>
      'Ƙoƙarin shiga ya yi yawa. Don Allah jira \'yan mintuna ka sake gwadawa.';

  @override
  String get authErrorLoginUnexpected =>
      'An sami matsalar da ba a zata ba yayin shiga. Don Allah sake gwadawa.';

  @override
  String get authErrorInvalidPhone => 'Lambar waya ba daidai ba ce.';

  @override
  String get authErrorSmsUnavailable =>
      'Sabis ɗin SMS ba ya samuwa. Don Allah tuntuɓi masu taimako.';

  @override
  String get authErrorPhoneNotRegistered =>
      'Ba a sami asusu da wannan lambar ba. Don Allah fara yin rajista.';

  @override
  String get authErrorSmsFailed => 'An kasa aika SMS na tabbatarwa.';

  @override
  String get authErrorCodeSendFailed => 'An kasa aika lambar tabbatarwa.';

  @override
  String get authErrorNoUserContext =>
      'Babu bayanan mai amfani don tabbatarwa. Don Allah sake shiga.';

  @override
  String get authErrorVerificationFailed =>
      'Tabbatarwa ta kasa. Don Allah sake gwadawa.';

  @override
  String get authErrorInvalidCode =>
      'Lambar tabbatarwa ba daidai ba ce ko ta ƙare. Don Allah nemi sabuwa.';

  @override
  String get authErrorTooManyAttemptsRetry =>
      'Ƙoƙari ya yi yawa. Don Allah jira \'yan mintuna ka sake gwadawa.';

  @override
  String get authErrorVerifyCodeFailed => 'An kasa tabbatar da lambar.';

  @override
  String get authErrorNotLoggedIn => 'Mai amfani bai shiga ba';

  @override
  String get authErrorResendFailed =>
      'An kasa sake aika lambar tabbatarwa. Don Allah sake gwadawa.';

  @override
  String get authErrorResetEmailFailed =>
      'An kasa aika imel na sake saita kalmar sirri. Don Allah sake gwadawa.';

  @override
  String get authErrorResetWeakPassword =>
      'Kalmar sirri ba ta da ƙarfi. An riga an yi amfani da lambar, don haka nemi sabuwar lamba ka zaɓi kalmar sirri mai ƙarfi.';

  @override
  String get authErrorResetCodeInvalid =>
      'Wannan lambar sake saitawa ba daidai ba ce ko ta ƙare. Don Allah nemi sabuwa.';

  @override
  String get authErrorResetSamePassword =>
      'Dole ne sabuwar kalmar sirrinka ta bambanta da tsohuwar. An riga an yi amfani da lambar, don haka nemi sabuwar lamba.';

  @override
  String get authErrorResetFailed =>
      'An kasa sake saita kalmar sirri. Don Allah sake gwadawa.';

  @override
  String get rateLimitAccountLocked =>
      'An kulle asusu saboda ƙoƙarin da ya kasa ya yi yawa';

  @override
  String rateLimitWaitSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Don Allah jira daƙiƙa $count kafin ka sake gwadawa',
      one: 'Don Allah jira daƙiƙa 1 kafin ka sake gwadawa',
    );
    return '$_temp0';
  }

  @override
  String rateLimitLockedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ƙoƙarin da ya kasa ya yi yawa. An kulle asusu na mintuna $count.',
      one: 'Ƙoƙarin da ya kasa ya yi yawa. An kulle asusu na minti 1.',
    );
    return '$_temp0';
  }

  @override
  String rateLimitOtpMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Buƙatun OTP sun yi yawa. Don Allah sake gwadawa bayan mintuna $count.',
      one: 'Buƙatun OTP sun yi yawa. Don Allah sake gwadawa bayan minti 1.',
    );
    return '$_temp0';
  }

  @override
  String rateLimitResendSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Don Allah jira daƙiƙa $count kafin ka nemi wata lamba',
      one: 'Don Allah jira daƙiƙa 1 kafin ka nemi wata lamba',
    );
    return '$_temp0';
  }

  @override
  String rateLimitAttemptsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saura ƙoƙari $count',
      one: 'Saura ƙoƙari 1',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitExceeded => 'An wuce iyakar buƙatu';

  @override
  String reportErrorMaxPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hotuna $count kawai aka yarda',
      one: 'Hoto 1 kawai aka yarda',
    );
    return '$_temp0';
  }

  @override
  String get reportErrorMissingHazard => 'Don Allah zaɓi nau\'in haɗari.';

  @override
  String get reportErrorMissingSeverity => 'Don Allah zaɓi matakin tsanani.';

  @override
  String get reportErrorMissingLocation => 'Don Allah ƙara bayanan wuri.';

  @override
  String get reportErrorSignedOut =>
      'Dole ne ka shiga kafin ka aika ko ajiye rahoto.';

  @override
  String get reportSavedAsDraft =>
      'An ajiye a matsayin daftari. Za a daidaita idan akwai intanet.';

  @override
  String get reportSubmittedWithPeers =>
      'An aika rahoto cikin nasara! An aika buƙatun tabbatarwa ga abokan aiki.';

  @override
  String get reportQueuedServerUnreachable =>
      'An kasa isa ga sabar. An ajiye kuma za a daidaita daga baya.';

  @override
  String syncResultSummary(int count, int failed) {
    return 'An daidaita abubuwa $count. $failed sun kasa.';
  }

  @override
  String get reportErrorPhotoProcessing =>
      'An kasa sarrafa wani hoto. Don Allah cire shi ko zaɓi wani hoto.';

  @override
  String get severityLow => 'Ƙarami';

  @override
  String get severityMedium => 'Matsakaici';

  @override
  String get severityHigh => 'Babba';

  @override
  String get severityCritical => 'Mai Gaggawa';

  @override
  String get alertSeverityUnspecified => 'Ba a fayyace tsanani ba';

  @override
  String get alertSeverityInfo => 'Bayani';

  @override
  String get alertSeverityWarning => 'Gargaɗi';

  @override
  String reviewDateTodayAt(String time) {
    return 'Yau da ƙarfe $time';
  }

  @override
  String reviewDateOnAt(String date, String time) {
    return '$date da ƙarfe $time';
  }

  @override
  String get reviewLocationUnknown =>
      'Ba a san ainihin wurin ba - za a yi amfani da yankin da aka zaɓa';

  @override
  String get reviewLocationApproximate =>
      'Wurin kimanin ne (tsakiyar yanki, babu GPS)';

  @override
  String get reportDetailsSpeechError =>
      'Matsala wajen gane murya. Don Allah sake gwadawa.';

  @override
  String get reportDetailsCameraUnavailable =>
      'Kyamara ba ta samuwa. Don Allah gwada amfani da hotuna (gallery).';

  @override
  String get reportDetailsGalleryError =>
      'An kasa buɗe hotuna (gallery). Don Allah sake gwadawa.';

  @override
  String get reportDetailsFutureTime =>
      'Lokacin lamarin ba zai iya zama nan gaba ba. An saita shi zuwa lokacin yanzu.';

  @override
  String get geoErrorServicesOff =>
      'An kashe sabis ɗin wuri. Don Allah kunna GPS.';

  @override
  String get geoErrorPermissionDenied => 'An ƙi bayar da izinin wuri.';

  @override
  String get geoErrorServicesUnavailable =>
      'An kasa samun damar sabis ɗin wuri.';

  @override
  String get geoNoticeLastKnown =>
      'An kasa samun sabon wurin GPS; ana amfani da wurinka na ƙarshe da aka sani.';

  @override
  String get geoErrorTimeout =>
      'Lokaci ya ƙare ana jiran siginar GPS. Matsa zuwa fili ka sake gwadawa, ko zaɓi wurinka da hannu.';

  @override
  String get geoErrorUndetermined =>
      'An kasa gano wurinka. Don Allah sake gwadawa ko zaɓi wurinka da hannu.';

  @override
  String get commonLoading => 'Ana lodawa...';

  @override
  String get locationPickerSeverityLow => 'Ƙaramin Tsanani';

  @override
  String get locationPickerSeverityMedium => 'Matsakaicin Tsanani';

  @override
  String get locationPickerSeverityHigh => 'Babban Tsanani';

  @override
  String get locationPickerSeverityCritical => 'Tsanani Mai Haɗari';

  @override
  String get locationPickerSeverityLowDesc =>
      'Ƙaramar matsala. Babu barazana nan take.';

  @override
  String get locationPickerSeverityMediumDesc =>
      'Matsakaiciyar matsala. A ci gaba da lura da lamarin.';

  @override
  String get locationPickerSeverityHighDesc =>
      'Babbar barazana ga dukiya ko lafiya. Ana buƙatar ɗaukar mataki.';

  @override
  String get locationPickerSeverityCriticalDesc =>
      'Lamari mai barazana ga rayuwa. Ana buƙatar ɗaukar mataki nan take.';

  @override
  String get locationPickerSelectedLevel => 'Matakin da Aka Zaɓa';

  @override
  String get locationPickerGpsApproximate => 'Kimanin Wuri';

  @override
  String get locationPickerLgaHeading => 'Ƙ/HUKUMA';

  @override
  String get locationPickerWardHeading => 'GUNDUMA';

  @override
  String get locationPickerUnknownLga => 'Ƙaramar Hukuma Ba a Sani Ba';

  @override
  String get locationPickerUnknownWard => 'Gunduma Ba a Sani Ba';

  @override
  String get locationPickerAutofilled => 'An cike ta atomatik daga GPS';

  @override
  String locationPickerGpsLgaNotFound(String lga, String state) {
    return 'Ba a sami wurin GPS ($lga) a cikin $state ba';
  }

  @override
  String get locationPickerGpsUnavailable =>
      'Wurin GPS ba ya samuwa ko ba a zaɓi Jiha ba';

  @override
  String locationPickerMeters(String distance) {
    return 'mita $distance';
  }

  @override
  String locationPickerMetersShort(String distance) {
    return '$distance m';
  }

  @override
  String get reportViewSectionDetails => 'Cikakkun Bayanai';

  @override
  String get reportViewReporter => 'Mai Rahoto';

  @override
  String get reportViewReported => 'Lokacin Rahoto';

  @override
  String get reportViewSeverity => 'Tsanani';

  @override
  String get reportViewVerifications => 'Tabbatarwa';

  @override
  String reportViewEvidenceCount(int count) {
    return 'Shaida ($count)';
  }

  @override
  String get reportViewCoordinates => 'Lambobin Wuri';

  @override
  String reportViewRejectedOn(String date) {
    return 'An ƙi rahoton a ranar $date';
  }

  @override
  String get reportViewNoReason => 'Ba a bayar da dalili ba.';

  @override
  String get myReportsTabActive => 'Masu Aiki';

  @override
  String get myReportsTabHistory => 'Tarihi';

  @override
  String get myReportsSignIn => 'Don Allah ka shiga don ganin rahotanninka.';

  @override
  String get myReportsEmptyActiveTitle => 'Babu rahotanni masu aiki';

  @override
  String get myReportsEmptyActiveBody =>
      'Rahotannin da ka aika za su bayyana a nan yayin da ake tabbatar da su.';

  @override
  String get myReportsEmptyHistoryTitle => 'Babu tarihin rahotanni';

  @override
  String get myReportsEmptyHistoryBody =>
      'Rahotanninka da aka amince da su da waɗanda aka ƙi za su bayyana a nan.';

  @override
  String get myReportsNewReport => 'Sabon Rahoto';

  @override
  String myReportsRejectionReason(String reason) {
    return 'Dalili: $reason';
  }

  @override
  String get nearbyTitle => 'Rahotannin Kusa';

  @override
  String get nearbyNotAvailableTitle => 'Ba ya samuwa ga asusunka';

  @override
  String get nearbyNotAvailableBody =>
      'Masu sa ido da aka amince da su da ma\'aikata ne kaɗai ke ganin rahotannin kusa. Kana iya bibiyar rahotanninka a ƙarƙashin Rahotannina.';

  @override
  String get nearbyLocationNotSetTitle => 'Ba a Saka Wuri Ba';

  @override
  String get nearbyLocationNotSetBody =>
      'Saka ƙaramar hukumarka ko yankin sa ido a\nbayananka don ganin rahotanni kusa da kai.';

  @override
  String get nearbyLoadErrorTitle => 'An kasa loda rahotanni';

  @override
  String get nearbyEmptyTitle => 'Babu Rahotanni a Kusa';

  @override
  String get nearbyEmptyBody =>
      'Babu rahotanni daga\nyankinku a wannan lokaci.';

  @override
  String get alertDetailDefaultTitle => 'Faɗakarwa';

  @override
  String get alertDetailNotSpecified => 'Ba a fayyace ba';

  @override
  String get alertStatusActive => 'Mai Aiki';

  @override
  String get alertStatusInactive => 'Ba Ya Aiki';

  @override
  String get alertDetailReportLoadError => 'An kasa loda bayanan rahoton.';

  @override
  String get alertDetailTitle => 'Bayanan Faɗakarwa';

  @override
  String get alertDetailReportedTime => 'Lokacin Rahoto';

  @override
  String get alertDetailStatus => 'Matsayi';

  @override
  String get alertDetailNoDescription =>
      'Babu ƙarin bayani game da wannan faɗakarwa. Don Allah ɗauki matakan kariya da suka dace kuma bi ƙa\'idojin yankinku.';

  @override
  String get alertDetailRecommendedActions => 'Matakan da Ake Ba da Shawara';

  @override
  String get alertDetailAction1 =>
      '1. Ci gaba da samun labarai ta rediyo ko kafofin yaɗa labarai na yanki.';

  @override
  String get alertDetailAction2 => '2. Shirya kayan gaggawa.';

  @override
  String get alertDetailAction3 => '3. Guji zuwa wuraren da abin ya shafa.';

  @override
  String get alertDetailAction4 => '4. Bi umarnin ƙaura idan an bayar.';

  @override
  String get alertDetailPeerVerificationTitle =>
      'Ana Buƙatar Tabbatarwar Abokan Aiki';

  @override
  String get alertDetailPeerVerificationBody =>
      'A matsayinka na EWM a wannan gunduma, don Allah tabbatar ko za ka iya gaskata wannan rahoton bisa abin da ka gani.';

  @override
  String get alertDetailCommentLabel => 'Sharhi (dole idan za ka ƙalubalanta)';

  @override
  String get alertDetailCommentHint => 'Ƙarin bayani game da wannan rahoton...';

  @override
  String get commonSubmitting => 'Ana aikawa...';

  @override
  String get voteConfirm => 'Tabbatar';

  @override
  String get voteDecline => 'Ƙalubalanta';

  @override
  String get alertDetailVerificationSubmitted => 'An Aika Tabbatarwa';

  @override
  String get alertDetailThanks => 'Mun gode da gudummawarka!';

  @override
  String get alertDetailGoBack => 'Koma Baya';

  @override
  String get alertDetailDismiss => 'Rufe';

  @override
  String get alertsFilterAll => 'Duk Faɗakarwa';

  @override
  String get alertsFilterFire => 'Gobara';

  @override
  String get alertsBroadcastTooltip => 'Watsa faɗakarwa';

  @override
  String get alertsSeverityFilterTooltip => 'Tace ta tsanani';

  @override
  String get alertsAllSeverities => 'Duk matakan tsanani';

  @override
  String get alertsTabBroadcasts => 'Sanarwar Hukuma';

  @override
  String get alertsTabReportHistory => 'Tarihin Rahotanni';

  @override
  String get alertsSearchReportsHint => 'Nemi wuri, haɗari, ko ID...';

  @override
  String get alertsSearchAlertsHint => 'Nemi faɗakarwa...';

  @override
  String get alertsClearSearch => 'Share bincike';

  @override
  String get alertsLoadError => 'An kasa loda faɗakarwa';

  @override
  String get alertsNoMatching => 'Babu faɗakarwa da ta dace';

  @override
  String get alertsPullToRetry => 'Ja ƙasa don sake gwadawa.';

  @override
  String get alertsEmptyBody =>
      'Faɗakarwar hukuma ta yankinku za ta bayyana a nan.';

  @override
  String get alertsAllLgas => 'Duk Ƙananan Hukumomi';

  @override
  String get alertsSynchronizing => 'Ana daidaitawa...';

  @override
  String get alertsNoReportsYet => 'Babu Rahotanni Tukuna';

  @override
  String get alertsNoMatchingReports => 'Babu rahotannin da suka dace';

  @override
  String alertsNoReportsForFilter(String filter) {
    return 'Babu $filter';
  }

  @override
  String get alertsNoReportsYetBody =>
      'Idan aka kawo rahoton haɗari a yankinku,\nzai bayyana a nan';

  @override
  String get alertsNoMatchingReportsBody =>
      'Ba a sami rahotannin da suka dace a wannan yanki ba';

  @override
  String get alertsDisputeRecorded => 'An rubuta ƙalubale';

  @override
  String get alertsReportConfirmed => 'An tabbatar da rahoton';

  @override
  String get accessCodeVerified => 'An tabbatar da asusu cikin nasara!';

  @override
  String get accessCodeNotVerified =>
      'Ba a tabbatar ba tukuna. Don Allah shigar da lambar da aka aika zuwa imel ɗinka.';

  @override
  String get accessCodeSent => 'An aika lambar tabbatarwa!';

  @override
  String get accessCodeNoEmail =>
      'Ba a sami imel na wannan asusu ba. Don Allah sake shiga.';

  @override
  String get accessCodeTitle => 'Tabbatar da Imel ɗinka';

  @override
  String get accessCodeEnterCode => 'Shigar da Lamba';

  @override
  String get accessCodeIHaveVerified => 'Na tabbatar da asusuna';

  @override
  String accessCodeBody(String email) {
    return 'Mun aika lambar tabbatarwa mai lambobi 6 zuwa $email.\nShigar da lambar don kunna asusunka.';
  }

  @override
  String get accessCodeBodyNoEmail =>
      'Mun aika lambar tabbatarwa mai lambobi 6 zuwa imel ɗinka.\nShigar da lambar don kunna asusunka.';

  @override
  String get forgotTitle => 'Ka Manta Kalmar Sirri?';

  @override
  String get forgotBody =>
      'Shigar da adireshin imel ɗinka don karɓar lambar sake saita kalmar sirri.';

  @override
  String get authEmailHint => 'Shigar da imel ɗinka';

  @override
  String get authEmailRequired => 'Don Allah shigar da imel ɗinka';

  @override
  String get authEmailInvalid => 'Don Allah shigar da ingantaccen imel';

  @override
  String get forgotSendCode => 'Aika Lambar Sake Saiti';

  @override
  String get forgotEmailSentTitle => 'An Aika Imel!';

  @override
  String forgotEmailSentBody(String email) {
    return 'Idan akwai asusu na $email, mun aika lambar sake saiti mai lambobi 6.\nShigar da ita a shafi na gaba don zaɓar sabuwar kalmar sirri.';
  }

  @override
  String get forgotEnterCode => 'Shigar da Lambar Saiti';

  @override
  String get landingWelcome => 'Barka da zuwa EWER';

  @override
  String get landingSubtitle =>
      'Tsarin Gargaɗin Farko da Ɗaukar Mataki da Wuri';

  @override
  String get landingTagline =>
      'Ƙarfafa al\'umma da bayar da rahoton haɗari nan take da haɗa kai don ɗaukar mataki cikin gaggawa.';

  @override
  String get landingGetStarted => 'Fara Yanzu';

  @override
  String get authSignUp => 'Yi Rajista';

  @override
  String get authLogin => 'Shiga';

  @override
  String get validatorPhoneRequired => 'Ana buƙatar lambar waya';

  @override
  String get validatorPhoneInvalid =>
      'Don Allah shigar da ingantacciyar lambar wayar Najeriya';

  @override
  String get validatorAddressRequired => 'Ana buƙatar adireshi';

  @override
  String validatorAddressTooShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dole adireshi ya kai aƙalla haruffa $count',
    );
    return '$_temp0';
  }

  @override
  String validatorAddressTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Adireshi ya yi tsawo (iyaka haruffa $count)',
    );
    return '$_temp0';
  }

  @override
  String validatorFieldRequired(String field) {
    return 'Ana buƙatar $field';
  }

  @override
  String validatorFieldMinLength(String field, int count) {
    return 'Dole $field ya kai aƙalla haruffa $count';
  }

  @override
  String validatorFieldMaxLength(String field, int count) {
    return 'Kada $field ya wuce haruffa $count';
  }

  @override
  String get validatorInvalidCharacters =>
      'An gano haruffan da ba a yarda da su ba';

  @override
  String validatorFieldInvalidCharacters(String field) {
    return '$field na ɗauke da haruffan da ba a yarda da su ba';
  }

  @override
  String get validatorDescriptionRequired => 'Ana buƙatar bayani';

  @override
  String validatorDescriptionTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kada bayani ya wuce haruffa $count',
    );
    return '$_temp0';
  }

  @override
  String get validatorEmailRequired => 'Ana buƙatar imel';

  @override
  String get validatorPasswordRequired => 'Ana buƙatar kalmar sirri';

  @override
  String validatorPasswordMinLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dole kalmar sirri ta kai aƙalla haruffa $count',
    );
    return '$_temp0';
  }

  @override
  String get validatorPasswordUppercase =>
      'Dole ta ƙunshi aƙalla babban harafi ɗaya';

  @override
  String get validatorPasswordLowercase =>
      'Dole ta ƙunshi aƙalla ƙaramin harafi ɗaya';

  @override
  String get validatorPasswordNumber => 'Dole ta ƙunshi aƙalla lamba ɗaya';

  @override
  String get validatorPasswordSpecial =>
      'Dole ta ƙunshi aƙalla alama ta musamman ɗaya';

  @override
  String get passwordStrengthWeak => 'Rauni';

  @override
  String get passwordStrengthFair => 'Madaidaici';

  @override
  String get passwordStrengthGood => 'Mai Kyau';

  @override
  String get passwordStrengthStrong => 'Mai Ƙarfi';

  @override
  String passwordErrorTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kalmar sirri ta yi tsawo (iyaka haruffa $count)',
    );
    return '$_temp0';
  }

  @override
  String get passwordErrorCommon =>
      'Wannan kalmar sirri ta zama gama-gari. Don Allah zaɓi mai ƙarfi';

  @override
  String get passwordErrorSequential =>
      'Kada kalmar sirri ta ƙunshi haruffa masu bin juna (misali, 123, abc)';

  @override
  String passwordRequirementLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aƙalla haruffa $count',
    );
    return '$_temp0';
  }

  @override
  String get passwordRequirementUppercase => 'Babban harafi';

  @override
  String get passwordRequirementLowercase => 'Ƙaramin harafi';

  @override
  String get passwordRequirementNumber => 'Lamba';

  @override
  String get passwordRequirementSpecial => 'Alama ta musamman';

  @override
  String get passwordRequirementNotCommon => 'Ba kalmar sirri ta gama-gari ba';

  @override
  String get authLoginCheckCredentials =>
      'Shiga ya kasa. Don Allah duba bayanan shigarka.';

  @override
  String get loginWelcomeBack => 'Barka da Dawowa';

  @override
  String get loginSubtitle => 'Shiga cikin asusunka';

  @override
  String get authPhoneNumber => 'Lambar Waya';

  @override
  String get authPassword => 'Kalmar Sirri';

  @override
  String get loginRememberMe => 'Tuna Ni';

  @override
  String get loginNoAccount => 'Ba ka da asusu? ';

  @override
  String get loginDataSecure => 'Bayananka suna ɓoye kuma suna cikin tsaro';

  @override
  String get loginLockedTitle => 'An Kulle CRADI Mobile';

  @override
  String get loginUnlockBiometrics => 'Buɗe da Biometric';

  @override
  String get loginLogoutDifferentAccount => 'Fita ka yi amfani da wani asusu';

  @override
  String get authMethodEmail => 'Imel';

  @override
  String get authMethodPhone => 'Waya';

  @override
  String get loginSendCode => 'Aika Lamba';

  @override
  String get otpSuccess => 'An tabbatar cikin nasara!';

  @override
  String get otpNewCodeSent => 'An aika sabuwar lamba.';

  @override
  String get otpVerifyEmail => 'Tabbatar da Imel';

  @override
  String otpCodeSentTo(String destination) {
    return 'Shigar da lambar mai lambobi 6 da aka aika zuwa\n$destination';
  }

  @override
  String get otpSecureCode => 'Lambar Tsaro';

  @override
  String get otpCodeHint => 'Shigar da lambar mai lambobi 6';

  @override
  String get otpCodeRequired => 'Don Allah shigar da lambar';

  @override
  String get otpCodeInvalidFormat => 'Tsarin lambar ba daidai ba ne';

  @override
  String get otpVerifyAndLogin => 'Tabbatar ka Shiga';

  @override
  String get otpNoCode => 'Ba ka karɓi lamba ba? ';

  @override
  String otpResendIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sake aikawa cikin daƙ. $count',
    );
    return '$_temp0';
  }

  @override
  String get pendingTitle => 'Ana Jiran Amincewa';

  @override
  String get pendingBody =>
      'An ƙirƙiri asusunka cikin nasara amma yana jiran amincewar mai gudanarwa.\n\nZa ka iya amfani da dukkan manhajar da zarar mai gudanarwa ya duba ya amince da asusunka.';

  @override
  String get pendingStillWaiting => 'Asusunka har yanzu yana jiran amincewa.';

  @override
  String get pendingCheckStatus => 'Duba matsayin amincewa';

  @override
  String get pendingContactSupport => 'Tuntuɓi Masu Taimako';

  @override
  String get registrationPrivacyTitle => 'Sanarwar Sirrin Bayanai';

  @override
  String get registrationDecline => 'Ƙi';

  @override
  String get registrationAgree => 'Na Amince';

  @override
  String get registrationMustAccept =>
      'Dole ne ka amince da Sanarwar Sirrin Bayanai kafin ka yi rajista.';

  @override
  String get registrationSelectState => 'Don Allah zaɓi jiha';

  @override
  String get registrationSelectLga => 'Don Allah zaɓi ƙaramar hukuma';

  @override
  String get registrationSelectWard => 'Don Allah zaɓi gunduma';

  @override
  String get registrationVerifyPhoneTitle => 'Tabbatar da Lambar Wayarka';

  @override
  String registrationPhoneCodeSent(String phone) {
    return 'An aika lambar tabbatarwa mai lambobi 6 zuwa $phone.\n\nDon Allah shigar da lambar don kunna asusunka.';
  }

  @override
  String get registrationAccountCreated => 'An ƙirƙiri asusu!';

  @override
  String get registrationVerifyEmailTitle => 'Tabbatar da Adireshin Imel ɗinka';

  @override
  String registrationEmailCodeSent(String email) {
    return 'An ƙirƙiri asusu cikin nasara!\n\nAn aika lambar tabbatarwa mai lambobi 6 zuwa $email.\n\nDon Allah shigar da lambar don kunna asusunka.';
  }

  @override
  String get registrationCreateAccount => 'Ƙirƙiri Asusu';

  @override
  String get registrationJoinNetwork => 'Shiga Cikin Hanyar Sadarwa';

  @override
  String get registrationSelectLocation => 'Zaɓi wurinka don farawa.';

  @override
  String get registrationMethod => 'Hanyar Rajista';

  @override
  String get registrationPersonalInfo => 'Bayanan Kai';

  @override
  String get registrationNameHint => 'Musa Abdullahi';

  @override
  String get registrationNameField => 'Suna';

  @override
  String get registrationAddressLabel => 'Bayanin Adireshi';

  @override
  String get registrationAddressHint => 'misali, Lamba 5, Babban Titi';

  @override
  String get registrationAddressField => 'Adireshi';

  @override
  String get registrationSecurity => 'Tsaro';

  @override
  String get registrationPasswordHint => 'Ƙirƙiri kalmar sirri';

  @override
  String get registrationConfirmPassword => 'Tabbatar da Kalmar Sirri';

  @override
  String get registrationConfirmPasswordHint =>
      'Sake shigar da kalmar sirrinka';

  @override
  String get registrationConfirmPasswordRequired =>
      'Don Allah tabbatar da kalmar sirrinka';

  @override
  String get registrationPasswordsMismatch =>
      'Kalmomin sirri ba su yi daidai ba';

  @override
  String get registrationSendOtp => 'Aika OTP ka Yi Rajista';

  @override
  String get registrationHaveAccount => 'Kana da asusu? ';

  @override
  String get registrationCreating => 'Ana ƙirƙirar asusu...';

  @override
  String get privacyNoticeText =>
      'Dokar Kare Bayanai ta Najeriya (NDPA) — Sanarwar Sarrafa Bayanai\n\nEWER Mobile (sabis na CRADI / KusuConsult-NG) ne ke sarrafa bayananka don gargaɗin farko game da haɗurran yanayi.\n\n• Bayanan da ake tattarawa: suna, waya, imel, wuri (jiha/ƙaramar hukuma/gunduma), rahotannin haɗari, da lambar tantance na\'ura don sanarwa kai tsaye.\n• Manufa: bayar da rahoton haɗari na al\'umma, tabbatarwar abokan aiki, da faɗakarwar gaggawa.\n• Ajiya: rumbun bayanai na gajimare na Supabase (PostgreSQL); ana isar da sanarwa kai tsaye ta OneSignal kuma ana iya aika bayanan matsalolin manhaja zuwa Sentry.\n• Tura bayanai zuwa ƙasashen waje: Bisa Sashe na 24 na NDPA, muna bayyana cewa ana iya tura bayananka zuwa sabobi a wajen Najeriya kuma a ajiye su a can. Wannan tura bayanai ya zama dole don samar da sabis ɗin. Kana da ikon janye amincewarka a kowane lokaci ta hanyar goge asusunka.\n• Tsawon ajiya: Ana ajiye bayanai na tsawon shekaru 5 bayan aikinka na ƙarshe, sannan a cire duk abin da zai iya bayyana ko kai wane ne.\n• Haƙƙoƙinka: samun dama, gyara, gogewa, da ɗaukar bayananka zuwa wani wuri a ƙarƙashin NDPA 2023.\n\nTa danna \"Na Amince\", ka amince da waɗannan sharuɗɗa da kuma tura bayananka na sirri zuwa ƙasashen waje.';

  @override
  String get aboutAppName => 'EWER Mobile';

  @override
  String get aboutTagline => 'Tsarin Gargaɗin Farko';

  @override
  String aboutVersion(String version, String build) {
    return 'Sigar $version (Gini $build)';
  }

  @override
  String aboutCopyright(String year) {
    return '© $year EWER. Dukkan haƙƙoƙi an kiyaye su.';
  }

  @override
  String aboutVersionOnly(String version) {
    return 'Sigar $version';
  }

  @override
  String get aboutPrivacyPolicy => 'Manufar Sirri';

  @override
  String get resetCodeResent => 'Idan akwai asusu, an aika sabuwar lamba.';

  @override
  String get resetTitle => 'Ƙirƙiri Sabuwar Kalmar Sirri';

  @override
  String get resetBody =>
      'Shigar da lambar mai lambobi 6 daga imel ɗin sake saiti kuma zaɓi sabuwar kalmar sirri mai tsaro.';

  @override
  String get resetCodeLabel => 'Lambar Sake Saiti';

  @override
  String get resetSendingCode => 'Ana aikawa…';

  @override
  String get resetSendCode => 'Aika lamba';

  @override
  String get resetCodeRequired => 'Shigar da lambar daga imel';

  @override
  String get resetNewPassword => 'Sabuwar Kalmar Sirri';

  @override
  String get resetSubmit => 'Sake Saita Kalmar Sirri';

  @override
  String get resetSuccessTitle => 'An Sake Saita Kalmar Sirri!';

  @override
  String get resetSuccessBody =>
      'An sake saita kalmar sirrinka cikin nasara. Yanzu za ka iya shiga da sabuwar kalmar sirrinka.';

  @override
  String get resetContinueToLogin => 'Ci gaba zuwa Shiga';

  @override
  String get offlineSyncingPending => 'Ana daidaita bayanan da ke jira...';

  @override
  String get offlineDiscardTitle => 'A watsar da rahoton?';

  @override
  String get offlineDiscardBody =>
      'Ba a aika wannan rahoton ba kuma za a goge shi daga wannan na\'ura.';

  @override
  String get offlineDiscard => 'Watsar';

  @override
  String get offlineActions => 'Ayyuka';

  @override
  String get offlineSubmitAsMe => 'Aika da sunana';

  @override
  String get offlineNoInternet => 'Babu Haɗin Intanet';

  @override
  String get offlineCanViewSaved =>
      'Har yanzu kana iya duba jagororinka da rahotannin da ka ajiye.';

  @override
  String get offlineReconnectToSignIn => 'Sake haɗawa da intanet don shiga.';

  @override
  String get offlineTryReconnect => 'Sake Haɗawa ka Daidaita';

  @override
  String get offlineModeEnabledInSettings =>
      'An kunna Yanayin Babu Intanet a Saituna.';

  @override
  String get offlineGoOnline => 'Koma kan layi';

  @override
  String get offlineStillNoInternet => 'Har yanzu babu haɗin intanet';

  @override
  String get offlineOpenSettings => 'Buɗe Saituna';

  @override
  String get offlineViewSavedGuides => 'Duba Jagororin da Aka Ajiye';

  @override
  String get offlineNoPending => 'Babu rahotanni masu jira';

  @override
  String get offlineStatusOwnerless =>
      'Tsohuwar siga ce ta ajiye shi: aika ko watsar da shi';

  @override
  String get offlineStatusFailed =>
      'Ya kasa, ba za a daidaita shi kai tsaye ba';

  @override
  String offlineStatusFailedWithError(String error) {
    return 'Ya kasa, ba za a daidaita shi kai tsaye ba: $error';
  }

  @override
  String get offlineStatusWaiting => 'Yana jiran daidaitawa';

  @override
  String offlineItemSubtitle(String location, String date, String status) {
    return '$location\n$date • $status';
  }

  @override
  String get roleUser => 'Mai Amfani';

  @override
  String get roleEwm => 'Mai Sa Ido kan Gargaɗin Farko';

  @override
  String get roleEwv => 'Mai Tantance Gargaɗin Farko';

  @override
  String get roleEwr => 'Mai Ɗaukar Mataki kan Gargaɗin Farko';

  @override
  String get roleLdpCoordinator => 'Mai Kula da LDP';

  @override
  String get roleProjectStaff => 'Ma\'aikacin Aiki';

  @override
  String get roleAdmin => 'Mai Gudanarwa';

  @override
  String get roleTechSupport => 'Taimakon Fasaha';

  @override
  String get profilePhotoUpdated => 'An sabunta hoton bayanan kai!';

  @override
  String get profileCameraUnavailable =>
      'Kyamara ba ta samuwa. Don Allah yi amfani da hotuna (gallery).';

  @override
  String get profilePickImageFailed =>
      'An kasa zaɓar hoto. Don Allah sake gwadawa.';

  @override
  String get profileUpdatePhoto => 'Sabunta Hoton Bayanan Kai';

  @override
  String get profileChooseGallery => 'Zaɓa daga Hotuna';

  @override
  String get profileChooseGallerySubtitle => 'Zaɓi hoto daga na\'urarka';

  @override
  String get profileCameraWebUnavailable => 'Kyamara ba ta samuwa a yanar gizo';

  @override
  String get profileUseGallery => 'Don Allah yi amfani da zaɓin hotuna';

  @override
  String get profilePhotoLibrary => 'Ɗakin Hotuna';

  @override
  String get profileEdit => 'Gyara Bayanan Kai';

  @override
  String get profileAskAdminArea => 'Nemi mai gudanarwa ya canza yankinka';

  @override
  String get commonNotAvailable => 'Babu';

  @override
  String profileIdLabel(String code) {
    return 'ID: $code';
  }

  @override
  String get profileVerified => 'An Tabbatar';

  @override
  String get profileUnverified => 'Ba a Tabbatar ba';

  @override
  String get profileStatReports => 'Rahotanni';

  @override
  String get profileDaysActive => 'Kwanakin Aiki';

  @override
  String get profileAccountSettings => 'Saitunan Asusu';

  @override
  String get profileBiometricsEnabled => 'An kunna biometric!';

  @override
  String get profileBiometricChangeFailed => 'An kasa canza shiga ta biometric';

  @override
  String get profileSyncingOffline =>
      'Ana daidaita bayanan da aka ajiye ba tare da intanet ba...';

  @override
  String get profileSyncComplete => 'An kammala daidaitawa!';

  @override
  String get profileSupportChat => 'Hira da Masu Taimako';

  @override
  String get profileSosButton => 'SOS / Kiran Gaggawa';

  @override
  String get sosTitle => 'SOS na Gaggawa';

  @override
  String get sosBody =>
      'Kira don neman taimako kai tsaye. Wannan ba ya aika faɗakarwa ta manhajar.';

  @override
  String sosCallEmergency(String phone) {
    return 'Kira Lambar Gaggawa ($phone)';
  }

  @override
  String get sosNationalNumber => 'Lambar gaggawa ta ƙasa';

  @override
  String get sosContactsLoadError =>
      'An kasa loda lambobinka. Duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get sosNoContacts =>
      'Ba ka ajiye lambobin gaggawa na kanka ba tukuna. Ƙara su a ƙarƙashin Lambobin Gaggawa.';

  @override
  String sosCallContact(String name) {
    return 'Kira $name';
  }

  @override
  String sosContactSubtitle(String role, String phone) {
    return '$role · $phone';
  }

  @override
  String sosDialFailed(String phone) {
    return 'An kasa buɗe manhajar waya. Kira $phone.';
  }

  @override
  String get chatLoginRequired => 'Don Allah ka shiga don yin hira';

  @override
  String get chatLoadError => 'An kasa loda saƙonni.';

  @override
  String get chatMe => 'Ni';

  @override
  String chatRateLimited(String reason) {
    return '$reason. Don Allah jira ɗan lokaci.';
  }

  @override
  String chatSendFailed(String error) {
    return 'Ba a aika saƙon ba. $error';
  }

  @override
  String get chatEmpty => 'Babu saƙonni tukuna';

  @override
  String get chatComposerHint => 'Rubuta saƙo';

  @override
  String get contactsNameRequired => 'Ana buƙatar suna';

  @override
  String get contactsNameTooLong => 'Suna ya yi tsawo';

  @override
  String get contactsPhoneDigitsOnly =>
      'Yi amfani da lambobi kawai (za a iya farawa da +)';

  @override
  String get contactsPhoneInvalid => 'Shigar da ingantacciyar lambar waya';

  @override
  String get contactsLaunchPhoneFailed => 'An kasa buɗe manhajar waya';

  @override
  String get contactsLaunchSmsFailed => 'An kasa buɗe manhajar SMS';

  @override
  String get contactsAdded => 'An ƙara lamba cikin nasara';

  @override
  String get contactsUpdated => 'An sabunta lamba cikin nasara';

  @override
  String get contactsDeleteTitle => 'A goge lambar?';

  @override
  String contactsDeleteBody(String name) {
    return 'A cire $name daga lambobinka na gaggawa?';
  }

  @override
  String get contactsDeleted => 'An goge lamba';

  @override
  String get contactsTitle => 'Lambobin Gaggawa';

  @override
  String get contactsAddTooltip => 'Ƙara lamba';

  @override
  String get contactsSearchHint => 'Nemi suna, ƙaramar hukuma, ko matsayi';

  @override
  String get contactsEmpty => 'Ba a sami lambobi ba';

  @override
  String get contactsEmergencyButton => 'Gaggawa 112';

  @override
  String get contactsMoreActions => 'Ƙarin ayyuka';

  @override
  String get contactsEditTitle => 'Gyara Lambar Gaggawa';

  @override
  String get contactsAddTitle => 'Ƙara Lambar Gaggawa';

  @override
  String get contactsNameLabel => 'Suna *';

  @override
  String get contactsRoleLabel => 'Matsayi';

  @override
  String get contactsPhoneLabel => 'Waya *';

  @override
  String get contactsOrganizationLabel => 'Ƙungiya (Na zaɓi)';

  @override
  String get contactsLgaLabel => 'Ƙaramar Hukuma (Na zaɓi)';

  @override
  String get contactsCategoryLabel => 'Rukuni';

  @override
  String get contactsAdd => 'Ƙara';

  @override
  String get contactsFilterAll => 'Duka';

  @override
  String get contactsFilterCoordinators => 'Masu Kula';

  @override
  String get contactsCategoryCoordinator => 'Mai Kula';

  @override
  String get contactsCategoryEmergency => 'Gaggawa';

  @override
  String get contactsCategoryAgriExtension => 'Jami\'in Gona';

  @override
  String get contactsCategoryOther => 'Wasu';

  @override
  String contactsRoleAndLga(String role, String lga) {
    return '$role • $lga';
  }

  @override
  String get knowledgeCategoryAll => 'Duka';

  @override
  String get knowledgeCategoryFlood => 'Ambaliya';

  @override
  String get knowledgeCategoryFire => 'Gobara';

  @override
  String get knowledgeCategoryErosion => 'Zaizaya';

  @override
  String get knowledgeCategoryStorm => 'Guguwa';

  @override
  String get knowledgeCategoryExtremeHeat => 'Tsananin Zafi';

  @override
  String get knowledgeCategoryEarthquake => 'Girgizar Ƙasa';

  @override
  String get knowledgeCategoryDisease => 'Cuta';

  @override
  String get knowledgeCategoryConflict => 'Rikici';

  @override
  String get knowledgeCategoryAccident => 'Haɗari';

  @override
  String get knowledgeCategorySafety => 'Tsaro';

  @override
  String get knowledgeCategoryGeneral => 'Gabaɗaya';

  @override
  String get knowledgeTagGuide => 'JAGORA';

  @override
  String get knowledgeLoadError =>
      'An kasa samo jagorori. Don Allah sake gwadawa.';

  @override
  String get knowledgeGuidesTitle => 'Jagororin Haɗari';

  @override
  String get knowledgeBaseCaption => 'TASKAR ILIMI';

  @override
  String get knowledgeGuidesSearchHint => 'Nemi jagorori, alamu, ko haɗurra...';

  @override
  String get knowledgeNoGuidesCategory =>
      'Ba a sami jagorori a wannan rukuni ba';

  @override
  String knowledgeNoGuidesMatch(String query) {
    return 'Babu jagorar da ta dace da \"$query\"';
  }

  @override
  String get knowledgeNoTitle => 'Babu Take';

  @override
  String get knowledgeSubtitleManual => 'Littafin Jagora';

  @override
  String get knowledgeNewsLoadError =>
      'An kasa loda labarai. Don Allah sake gwadawa.';

  @override
  String get knowledgeBaseTitle => 'Taskar Ilimi';

  @override
  String get knowledgeBaseSearchHint => 'Nemi jagorori, haɗurra, ko lambobi...';

  @override
  String get knowledgeOfflineActive => 'Yanayin Babu Intanet Yana Aiki';

  @override
  String get knowledgeOfflineAvailable =>
      'Ana Iya Amfani Ba Tare da Intanet ba';

  @override
  String get knowledgeUsingCache => 'Ana amfani da bayanan da aka ajiye';

  @override
  String get knowledgeContentDownloaded => 'An sauke abubuwan cikin nasara';

  @override
  String get knowledgeFeaturedGuides => 'Fitattun Jagorori';

  @override
  String get knowledgeNoGuides => 'Babu jagorori';

  @override
  String get knowledgeHazardIdGuides => 'Jagororin Gane Haɗari';

  @override
  String get knowledgeHazardIdGuidesDesc => 'Gano barazanar yankinku';

  @override
  String get knowledgeFireResponse => 'Ɗaukar Mataki kan Gobara';

  @override
  String get knowledgeFireResponseDesc => 'Ƙa\'idojin gobarar daji';

  @override
  String get knowledgeFloodReadiness => 'Shirin Ambaliya';

  @override
  String get knowledgeFloodReadinessDesc => 'Ruwa da Guguwa';

  @override
  String get knowledgeContactsDirectory => 'Kundin Lambobi';

  @override
  String get knowledgeContactsDirectoryDesc => 'Hukumomin gaggawa';

  @override
  String get knowledgeExternalNews => 'Labarai da Sabbin Bayanai na Waje';

  @override
  String get knowledgeNoNews => 'Ba a sami sabbin labarai ba.';

  @override
  String get knowledgeDetailTitle => 'Bayanan Jagora';

  @override
  String get knowledgeBookmarked => 'An ajiye jagorar';

  @override
  String get knowledgeBookmarkRemoved => 'An cire alamar ajiya';

  @override
  String get knowledgeNoTextToSpeak => 'Babu rubutun da za a karanta';

  @override
  String get knowledgeTtsUnavailable =>
      'Karanta rubutu da murya ba ya samuwa. Don Allah sake gwadawa.';

  @override
  String knowledgeUpdatedOn(String date) {
    return 'An sabunta $date';
  }

  @override
  String get knowledgeUpdatedRecently => 'An sabunta kwanan nan';

  @override
  String knowledgeReadTime(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Karatun minti $count',
      one: 'Karatun minti 1',
    );
    return '$_temp0';
  }

  @override
  String get knowledgeContentComingSoon =>
      'Cikakken bayani na zuwa nan ba da jimawa ba.';

  @override
  String get knowledgeRelatedTopics => 'Batutuwa Masu Alaƙa';

  @override
  String get knowledgeNoRelated => 'Ba a sami batutuwa masu alaƙa ba.';

  @override
  String get knowledgeShareDefaultTitle => 'Jagorar CRADI';

  @override
  String knowledgeShareText(String content) {
    return '$content\n\nAn raba ta manhajar CRADI Gargaɗin Farko';
  }

  @override
  String get helpSupportEmailSubject => 'Buƙatar Taimako daga Manhajar CRADI';

  @override
  String get helpSupportEmailBody => 'Don Allah bayyana matsalarka:\n\n';

  @override
  String helpNoEmailApp(String email) {
    return 'Ba a sami manhajar imel ba. Tuntuɓi $email';
  }

  @override
  String get helpFaqTitle => 'Tambayoyin da Aka Fi Yi';

  @override
  String get helpFaqReportQ => 'Ta yaya zan kawo rahoton haɗari?';

  @override
  String get helpFaqReportA =>
      'Je shafin \"Rahoto\" ko danna maɓallin \"+\" a babban shafi. Zaɓi nau\'in haɗari, ƙara hotuna, sannan ka aika rahotonka. Za ka iya faɗar bayanin da maɓallin makirufo maimakon rubutawa.';

  @override
  String get helpFaqColorsQ => 'Mene ne ma\'anar launukan faɗakarwa?';

  @override
  String get helpFaqColorsA =>
      'Ja na nuna babban tsanani (haɗari nan take), Ruwan lemu matsakaici ne, Rawaya kuma ƙarami. Shuɗi yawanci yana nuna haɗurran da suka shafi ruwa kamar ambaliya.';

  @override
  String get helpFaqOfflineQ => 'Zan iya kawo rahoto ba tare da intanet ba?';

  @override
  String get helpFaqOfflineA =>
      'Ƙwarai! Yi amfani da \"Yanayin Babu Intanet\" a Saituna. Za a ajiye rahotanninka a wayarka kuma za a iya daidaita su idan ka dawo kan layi.';

  @override
  String get helpFaqVerifyQ => 'Ta yaya zan tabbatar da rahotannin wasu?';

  @override
  String get helpFaqVerifyA =>
      'Je shafin \"Faɗakarwa\" ka nemi rahotanni masu jira a kusa da kai. Za ka iya tabbatar da su ko ka ƙi su bisa abin da ka gani.';

  @override
  String get helpStillNeedHelp => 'Har yanzu kana buƙatar taimako?';

  @override
  String get notificationsAllRead =>
      'An yi wa dukkan sanarwa alamar an karanta';

  @override
  String get notificationsClearAll => 'Share Duka';

  @override
  String get notificationsClearConfirm =>
      'Ka tabbata kana so ka goge dukkan sanarwa?';

  @override
  String get notificationsMarkAllRead => 'Yi wa duka alamar an karanta';

  @override
  String get notificationsClearAllMenu => 'Share duka';

  @override
  String get notificationsEmpty => 'Babu sanarwa tukuna';

  @override
  String get notificationsDefaultTitle => 'Sanarwa';

  @override
  String get voteDispute => 'Ƙalubalanta';

  @override
  String get voteDisputeRecorded =>
      'An rubuta ƙalubale. Ma\'aikata za su sake duba rahoton.';

  @override
  String get voteConfirmedThanks => 'An tabbatar da rahoton. Mun gode!';

  @override
  String get exportRejectedOnly => 'Waɗanda Aka Ƙi Kaɗai';

  @override
  String get exportPreparing => 'Ana shirya fitarwa…';

  @override
  String get exportCopied => 'An kwafi CSV zuwa allon kwafi.';

  @override
  String exportSavedTo(String path) {
    return 'An ajiye rahoto a $path';
  }

  @override
  String get exportShareSubject => 'Fitar da rahotannin CRADI';

  @override
  String exportShareFailed(String path) {
    return 'An kasa buɗe zaɓin rabawa. An ajiye rahoton a $path';
  }

  @override
  String get statusBadgeVerified => 'AN TABBATAR';

  @override
  String get statusBadgeApproved => 'AN AMINCE';

  @override
  String get statusBadgeRejected => 'AN ƘI';

  @override
  String get statusBadgePending => 'ANA JIRAN TABBATARWA';

  @override
  String get verificationDetailTitle => 'Tabbatar da Rahoto';

  @override
  String get verificationDetailUnknownTime => 'Ba a san lokaci ba';

  @override
  String get verificationDetailNoLocation => 'Babu bayanan wuri';

  @override
  String get verificationDetailNoMap => 'Babu wuri a taswira';

  @override
  String get verificationDetailQuestion =>
      'Za ka iya tabbatar da wannan rahoton?';

  @override
  String get verificationDetailInstructions =>
      'Don Allah tabbatar ko ka ga wannan haɗarin a wurin da aka ambata.';

  @override
  String get verificationDetailCommentHint =>
      'Ƙara bayani game da abin da kake gani...';

  @override
  String get verificationDetailConfirm => 'Na Tabbatar';

  @override
  String get verificationListRequestTooltip => 'Nemi tabbatarwa';

  @override
  String get verificationListEmpty => 'Babu rahotanni masu jiran tabbatarwa';

  @override
  String get verificationRequestSubmitted =>
      'An aika buƙatar tabbatarwa cikin nasara';

  @override
  String get verificationRequestTitle => 'Nemi Tabbatarwa';

  @override
  String get verificationRequestDescriptionHint =>
      'Bayyana abin da ke buƙatar tabbatarwa...';

  @override
  String get verificationRequestSubmit => 'Aika Buƙata';

  @override
  String get disputeDialogTitle => 'A ƙalubalanci rahoton?';

  @override
  String get disputeDialogLabel => 'Me ke damun wannan rahoton? (dole)';

  @override
  String get staffRejected => 'An ƙi rahoton.';

  @override
  String get staffActionsTitle => 'Ayyukan ma\'aikata';

  @override
  String get staffApproved => 'An amince da rahoton.';

  @override
  String get staffApprove => 'Amince';

  @override
  String get staffReopened => 'An sake buɗe rahoton don tabbatarwa.';

  @override
  String get staffRejectTitle => 'A ƙi rahoton?';

  @override
  String get staffRejectReasonLabel => 'Dalili (dole)';

  @override
  String get staffRejectReasonHint => 'Mai rahoto zai gani';

  @override
  String get staffRejectReasonRequired => 'Don Allah bayar da dalili.';

  @override
  String get verificationsLoadError => 'An kasa loda tabbatarwar abokan aiki.';

  @override
  String get verificationsTitle => 'Tabbatarwar abokan aiki';

  @override
  String get verificationsNone => 'Babu ƙuri\'ar abokan aiki tukuna.';

  @override
  String verificationsSummary(int confirmed, int disputed) {
    return '$confirmed sun tabbatar · $disputed sun ƙalubalanta';
  }

  @override
  String get verificationsYou => 'Kai';

  @override
  String get verificationsPeerVerifier => 'Abokin aiki mai tabbatarwa';

  @override
  String verificationsVoteBy(String kind, String who) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'confirmed': '$who ya tabbatar',
      'other': '$who ya ƙalubalanta',
    });
    return '$_temp0';
  }

  @override
  String verificationsVoteByAt(String kind, String who, String date) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'confirmed': '$who ya tabbatar · $date',
      'other': '$who ya ƙalubalanta · $date',
    });
    return '$_temp0';
  }

  @override
  String get voteQuestion => 'Za ka iya tabbatar da wannan rahoton?';

  @override
  String get adminCountsError => 'An kasa loda ƙididdigar babban shafi';

  @override
  String get adminCountsErrorBody =>
      'Duba haɗin intanet ɗinka da izininka, sannan ka sake gwadawa.';

  @override
  String get adminHealthDatabase => 'Rumbun Bayanai';

  @override
  String adminHealthActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count masu aiki',
    );
    return '$_temp0';
  }

  @override
  String adminHealthReportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'rahotanni $count',
      one: 'rahoto 1',
    );
    return '$_temp0';
  }

  @override
  String get adminAlertBroadcastSuccess => '✅ An watsa faɗakarwa cikin nasara';

  @override
  String adminAlertSendFailed(String error) {
    return 'An kasa aika faɗakarwa: $error';
  }

  @override
  String get adminAlertDismissFailed => 'An kasa kashe faɗakarwa.';

  @override
  String get adminAlertCompose => 'Rubuta Faɗakarwa';

  @override
  String get adminAlertTargetArea => 'Yankin da Ake Nufi';

  @override
  String get adminAlertAllAreas => '🌍 Dukkan Yankuna';

  @override
  String get adminAlertTitleLabel => 'Taken Faɗakarwa';

  @override
  String get adminAlertRequired => 'Dole';

  @override
  String get adminAlertMessageLabel => 'Saƙo';

  @override
  String get adminAlertBroadcastButton => 'Watsa Faɗakarwa';

  @override
  String get adminAlertsLoadError =>
      'An kasa loda faɗakarwa. Wataƙila ba ka da izinin ganin su.';

  @override
  String get adminAlertDismissTooltip => 'Kashe faɗakarwa';

  @override
  String get adminGuideDeleteTitle => 'Goge Jagora';

  @override
  String get adminGuideDeleteBody =>
      'Ka tabbata kana so ka goge wannan jagorar? Ba za a iya dawo da ita ba.';

  @override
  String get adminGuideDeleteDenied =>
      'Ba ka da izinin goge wannan jagorar, ko kuma an riga an cire ta.';

  @override
  String get adminGuideDeleteFailed =>
      'An kasa goge jagora. Duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get adminGuideDeleted => 'An goge jagora';

  @override
  String get adminGuideAdd => 'Ƙara Jagora';

  @override
  String get adminGuidesLoadError => 'Matsala wajen loda jagorori';

  @override
  String get adminGuidesEmpty => 'Ba a sami jagorori ba';

  @override
  String get adminGuideAddFirst => 'Ƙara jagora ta farko';

  @override
  String get adminGuideEditMenu => '✏️ Gyara';

  @override
  String get adminGuideDeleteMenu => '🗑️ Goge';

  @override
  String get adminGuideUpdated => 'An sabunta jagora';

  @override
  String get adminGuideCreated => 'An ƙirƙiri jagora';

  @override
  String get adminGuideEditTitle => 'Gyara Jagora';

  @override
  String get adminGuideNewTitle => 'Sabuwar Jagora';

  @override
  String get adminGuideCategoryLabel => 'Rukuni / Nau\'in Haɗari';

  @override
  String get adminGuideTitleLabel => 'Taken Jagora';

  @override
  String get adminGuideSourceLabel => 'Tushe (misali NEMA, WHO)';

  @override
  String get adminGuideContentLabel => 'Abun ciki (ana karɓar Markdown)';

  @override
  String get adminGuideUpdate => 'Sabunta Jagora';

  @override
  String get adminGuideCreate => 'Ƙirƙiri Jagora';

  @override
  String get adminReportsLoadError =>
      'An kasa loda rahotanni. Wataƙila ba ka da izinin ganin su.';

  @override
  String get adminReportsRejectReasonLabel => 'Dalili (ana ba da shawara)';

  @override
  String get adminReportsRejectReasonHint => 'Me ya sa ake ƙin wannan rahoton?';

  @override
  String adminReportsStatusUpdateFailed(String error) {
    return 'An kasa sabunta matsayin rahoto: $error';
  }

  @override
  String get adminReportsReopened => 'An sake buɗe rahoton don tabbatarwa';

  @override
  String adminReportsMarkedAs(String status) {
    return 'An sanya rahoton a matsayin $status';
  }

  @override
  String get adminReportsDateTime => 'Kwanan Wata/Lokaci';

  @override
  String get adminReportsLga => 'Ƙaramar Hukuma';

  @override
  String get adminReportsLocationDetails => 'Bayanan Wuri';

  @override
  String get adminReportsRejectionReason => 'Dalilin ƙi';

  @override
  String get adminReportsNoReason => 'Ba a bayar da dalili ba';

  @override
  String get adminReportsImages => 'Hotuna';

  @override
  String get adminReportsMarkVerified => 'Sanya An Tabbatar';

  @override
  String get adminReportsReopen => 'Sake buɗewa (ana jira)';

  @override
  String get adminReportsReopenReset => 'Sake buɗewa (mayar zuwa ana jira)';

  @override
  String get adminReportsEmpty => 'Ba a sami rahotanni ba';

  @override
  String get adminReportsLoadMoreError =>
      'An kasa loda ƙari. Danna don sake gwadawa.';

  @override
  String get adminReportsLoadMore => 'Loda ƙari';

  @override
  String get adminUsersLoadError =>
      'An kasa loda masu amfani. Wataƙila ba ka da izinin ganin su.';

  @override
  String get adminUsersEmpty => 'Ba a sami masu amfani ba';

  @override
  String get adminUsersNoPermission =>
      'Ba ka da izinin canza wannan mai amfani.';

  @override
  String get adminUsersUpdateFailed =>
      'Sabuntawa ta kasa. Don Allah sake gwadawa.';

  @override
  String get adminUsersApproved => 'An amince da mai amfani';

  @override
  String get adminUsersRejected => 'An ƙi mai amfani';

  @override
  String get adminUsersChangeRole => 'Canza Matsayi';

  @override
  String get adminUsersRoleUpdated =>
      'An sabunta matsayi. Zai fara aiki da zarar an amince da mai amfani.';

  @override
  String get adminUsersApply => 'Aiwatar';

  @override
  String get adminUsersChangeLocationTitle => 'Canza wuri';

  @override
  String adminUsersLocationUpdated(String ward, String lga, String state) {
    return 'An sabunta wuri zuwa $ward, $lga, $state';
  }

  @override
  String get adminUsersDisabled => 'An dakatar da mai amfani';

  @override
  String get adminUsersReenabled => 'An sake kunna mai amfani';

  @override
  String get adminUsersSearchHint => 'Nemi ta suna ko imel…';

  @override
  String get adminUsersAllRoles => 'Dukkan Matsayi';

  @override
  String get adminUsersShowingPending => 'Ana Nuna Masu Jiran Amincewa';

  @override
  String get adminUsersShowingApproved => 'Ana Nuna Waɗanda Aka Amince';

  @override
  String get adminUsersPendingChip => 'Ana Jira';

  @override
  String get adminUsersApproveMenu => '✅ Amince';

  @override
  String get adminUsersRevokeMenu => '❌ Janye izini';

  @override
  String get adminUsersChangeRoleMenu => '🔄 Canza matsayi';

  @override
  String get adminUsersChangeLocationMenu => '📍 Canza wuri';

  @override
  String get adminUsersReenableMenu => '🔓 Sake kunna mai amfani';

  @override
  String get adminUsersDisableMenu => '🚫 Dakatar da mai amfani';

  @override
  String get onboardingWelcomeBody =>
      'Tsarin Gargaɗin Farko da Ɗaukar Matakin Gaggawa don al\'ummarka';

  @override
  String get onboardingMonitorTitle => 'Sa Ido kan Haɗurra Nan Take';

  @override
  String get onboardingMonitorBody =>
      'Kawo rahoton gaggawa, bibiyi haɗurra, kuma ka kiyaye al\'ummarka';

  @override
  String get onboardingJoinBody => 'Ƙirƙiri asusu ka fara kare al\'ummarka yau';

  @override
  String get onboardingSkip => 'Tsallake';

  @override
  String get onboardingNext => 'Na Gaba';

  @override
  String get splashTagline => 'Gargaɗin Farko & Ɗaukar Matakin Gaggawa';

  @override
  String get connectivityOfflineBanner =>
      'Babu intanet - Wasu fasaloli ba za su yi aiki ba';

  @override
  String get routeReportNotFound => 'Ba a sami rahoton ba';

  @override
  String get routeViewReports => 'Duba rahotanni';

  @override
  String get routeAlertNotFound => 'Ba a sami faɗakarwar ba';

  @override
  String get routeViewAlerts => 'Duba faɗakarwa';

  @override
  String get routeNotFoundTitle => 'Ba a sami shafin ba';

  @override
  String get routeNotFoundBody => 'Shafin da kake nema babu shi.';

  @override
  String get routeTryAgain => 'Sake gwadawa';

  @override
  String get routeGoHome => 'Koma gida';

  @override
  String get routeLoadFailedTitle => 'An kasa lodawa';

  @override
  String get routeLoadFailedBody => 'Duba haɗin intanet ɗinka ka sake gwadawa.';

  @override
  String get routeMissingBody =>
      'Wataƙila an cire shi, ko kuma ba ka da damar ganin sa.';

  @override
  String get forceUpdateStoreFailed =>
      'An kasa buɗe shagon manhajoji. Don Allah sabunta manhajar daga shagon manhajojinka.';

  @override
  String get forceUpdateTitle => 'Ana buƙatar sabuntawa';

  @override
  String get forceUpdateDefaultMessage =>
      'Don Allah sabunta manhajar EWER don ci gaba.';

  @override
  String forceUpdateMinVersion(String version) {
    return 'Mafi ƙarancin siga: $version';
  }

  @override
  String get forceUpdateButton => 'Sabunta';

  @override
  String get forceUpdateCheckAgain => 'Sake dubawa';

  @override
  String formFieldRequiredLabel(String label) {
    return '$label *';
  }

  @override
  String get locationSelectorLgaLabel => 'Ƙaramar Hukuma';

  @override
  String get permissionLocationTitle => 'Izinin Wuri';

  @override
  String get permissionLocationRationale =>
      'EWER na buƙatar wurinka don nuna ainihin wurin haɗurra da kuma faɗakar da masu ɗaukar mataki da ke kusa. Ana amfani da wurinka ne kawai lokacin da ka aika rahoto ko ka yi amfani da taswirar aiki.';

  @override
  String get permissionNotificationsTitle => 'Kunna Faɗakarwa';

  @override
  String get permissionNotificationsRationale =>
      'Samu sabbin bayanai nan take game da haɗurra a yankinka. Muna aika faɗakarwar tsaro masu muhimmanci ne kawai da bayanan matsayin rahotanninka.';

  @override
  String get permissionPhotosTitle => 'Izinin Hotuna';

  @override
  String get permissionPhotosRationale =>
      'EWER na buƙatar izinin hotunanka don ka iya ɗora shaidar haɗurra. Muna ɗora hotunan da ka zaɓa da kanka ne kawai.';

  @override
  String get permissionNotNow => 'Ba Yanzu Ba';

  @override
  String permissionSettingsBody(String reason) {
    return '$reason\n\nDon Allah kunna wannan a saitunan na\'urarka.';
  }

  @override
  String offlineDraftLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Za ka iya ajiye rahotanni $count da ba a aika ba a wannan na\'ura a mafi yawa. Fara daidaita ko watsar da wasu.',
    );
    return '$_temp0';
  }

  @override
  String nearbyReportsInAreaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rahotanni $count a yankinka',
      one: 'Rahoto 1 a yankinka',
    );
    return '$_temp0';
  }

  @override
  String landingCopyright(String year) {
    return '© $year CRADI. Duk haƙƙoƙi an kiyaye su.';
  }

  @override
  String get verificationRequestBadge => 'Buƙatar tabbatarwa';

  @override
  String get reportViewSafetyGuides => 'Jagororin tsaro';

  @override
  String get authAccountRemoved =>
      'An cire asusunka, don haka an fitar da kai. Tuntuɓi mai gudanarwarka idan kana ganin kuskure ne.';

  @override
  String get adminUsersApproveUnconfirmed =>
      'Wannan asusu bai tabbatar da imel ko lambar wayarsa ba tukuna, don haka ba za a iya amince da shi ba.';

  @override
  String get commonSubmittingPleaseWait => 'Ana aikawa, da fatan za a jira';

  @override
  String get commonClearSearch => 'Share bincike';

  @override
  String get authShowPassword => 'Nuna kalmar sirri';

  @override
  String get authHidePassword => 'Ɓoye kalmar sirri';

  @override
  String get knowledgeShareTooltip => 'Raba wannan jagorar';

  @override
  String get knowledgeBookmarkAddTooltip => 'Ajiye wannan jagorar';

  @override
  String get knowledgeBookmarkRemoveTooltip => 'Cire jagorar da aka ajiye';

  @override
  String get knowledgeListenTooltip => 'Saurari wannan jagorar';

  @override
  String a11ySeverityLabel(String severity) {
    return 'Tsanani: $severity';
  }

  @override
  String a11yStatusLabel(String status) {
    return 'Matsayi: $status';
  }

  @override
  String contactsSmsTooltip(String name) {
    return 'Aika saƙon rubutu zuwa $name';
  }

  @override
  String reportRemovePhoto(int number) {
    return 'Cire hoto $number';
  }
}
