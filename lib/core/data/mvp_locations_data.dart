/// MVP Location Data for CRADI Mobile
///
/// Covers 3 target states: Benue, Nasarawa, and Plateau
/// Total: 53 LGAs across 3 states, 613 wards
///
/// Data Source: Independent National Electoral Commission (INEC) Nigeria
/// Last Updated: 2025-12-30
///
/// Ward data based on official INEC electoral divisions

library;

class MVPLocationWard {
  final String name;
  final String description;

  const MVPLocationWard({required this.name, this.description = ''});
}

class MVPLocationLGA {
  final String name;
  final String state;
  final List<MVPLocationWard> wards;

  const MVPLocationLGA({
    required this.name,
    required this.state,
    required this.wards,
  });
}

class MVPLocationsData {
  // ==================== BENUE STATE (23 LGAs, 252 Wards) ====================

  static const List<MVPLocationLGA> _benueLGAs = [
    MVPLocationLGA(
      name: 'Ado',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Akpoge/Ogbilolo'),
        MVPLocationWard(name: 'Apa'),
        MVPLocationWard(name: 'Ekile'),
        MVPLocationWard(name: 'Igumale I'),
        MVPLocationWard(name: 'Igumale II'),
        MVPLocationWard(name: 'Ijigban'),
        MVPLocationWard(name: 'Ogege'),
        MVPLocationWard(name: 'Royongo'),
        MVPLocationWard(name: 'Ukwonyo'),
        MVPLocationWard(name: 'Ulayi'),
      ],
    ),
    MVPLocationLGA(
      name: 'Agatu',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Enungba'),
        MVPLocationWard(name: 'Obagaji'),
        MVPLocationWard(name: 'Odugbeho'),
        MVPLocationWard(name: 'Ogbaulu'),
        MVPLocationWard(name: 'Ogwule Kaduna'),
        MVPLocationWard(name: 'Ogwule Ogbaulu'),
        MVPLocationWard(name: 'Okokolo'),
        MVPLocationWard(name: 'Oshigbudu'),
        MVPLocationWard(name: 'Usha'),
      ],
    ),
    MVPLocationLGA(
      name: 'Apa',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Apa Ward'),
        MVPLocationWard(name: 'Igah Ward'),
        MVPLocationWard(name: 'Oiji Ward'),
        MVPLocationWard(name: 'Edikwu Ward'),
        MVPLocationWard(name: 'Auke Ward'),
        MVPLocationWard(name: 'Ugbokpo Ward'),
        MVPLocationWard(name: 'Icho Ward'),
        MVPLocationWard(name: 'Apa Central Ward'),
        MVPLocationWard(name: 'Apa North Ward'),
        MVPLocationWard(name: 'Apa South Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Buruku',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Buruku Ward'),
        MVPLocationWard(name: 'Mbaade Ward'),
        MVPLocationWard(name: 'Shorov Ward'),
        MVPLocationWard(name: 'Binev Ward'),
        MVPLocationWard(name: 'Tionsha Ward'),
        MVPLocationWard(name: 'Buruku Central'),
        MVPLocationWard(name: 'Etulo Ward'),
        MVPLocationWard(name: 'Mbakyua Ward'),
        MVPLocationWard(name: 'Mbatyav Ward'),
        MVPLocationWard(name: 'Utange Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Gboko',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Gboko Central'),
        MVPLocationWard(name: 'Gboko North'),
        MVPLocationWard(name: 'Gboko South'),
        MVPLocationWard(name: 'Gboko East'),
        MVPLocationWard(name: 'Gboko West'),
        MVPLocationWard(name: 'Yandev North'),
        MVPLocationWard(name: 'Yandev South'),
        MVPLocationWard(name: 'Mbasombo'),
        MVPLocationWard(name: 'Ikyurav-Ye'),
        MVPLocationWard(name: 'Igyorov'),
        MVPLocationWard(name: 'Mbadwem'),
      ],
    ),
    MVPLocationLGA(
      name: 'Guma',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Guma Ward'),
        MVPLocationWard(name: 'Kaambe Ward'),
        MVPLocationWard(name: 'Saghev Ward'),
        MVPLocationWard(name: 'Uvir Ward'),
        MVPLocationWard(name: 'Abinsi Ward'),
        MVPLocationWard(name: 'Nyiev Ward'),
        MVPLocationWard(name: 'Mutsu Ward'),
        MVPLocationWard(name: 'Gbemacha Ward'),
        MVPLocationWard(name: 'Pepe Ward'),
        MVPLocationWard(name: 'Waya Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Gwer East',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Aliade Central'),
        MVPLocationWard(name: 'Aliade North'),
        MVPLocationWard(name: 'Aliade South'),
        MVPLocationWard(name: 'Mbadim Ward'),
        MVPLocationWard(name: 'Ikyogbajir Ward'),
        MVPLocationWard(name: 'Ikpayongo Ward'),
        MVPLocationWard(name: 'Agaishie Ward'),
        MVPLocationWard(name: 'Gbemacha Ward'),
        MVPLocationWard(name: 'Ulayi Ward'),
        MVPLocationWard(name: 'Imande Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Gwer West',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Naka Central'),
        MVPLocationWard(name: 'Naka East'),
        MVPLocationWard(name: 'Naka West'),
        MVPLocationWard(name: 'Sengev Ward'),
        MVPLocationWard(name: 'Gbaange Ward'),
        MVPLocationWard(name: 'Saghev Ward'),
        MVPLocationWard(name: 'Mbapa Ward'),
        MVPLocationWard(name: 'Ikyonov Ward'),
        MVPLocationWard(name: 'Tarka Ward'),
        MVPLocationWard(name: 'Bar Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Katsina-Ala',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Katsina-Ala Town'),
        MVPLocationWard(name: 'Gbise Ward'),
        MVPLocationWard(name: 'Ikyurav-Tiev Ward'),
        MVPLocationWard(name: 'Tongov Ward'),
        MVPLocationWard(name: 'Utange Ward'),
        MVPLocationWard(name: 'Yooyo Ward'),
        MVPLocationWard(name: 'Michihe Ward'),
        MVPLocationWard(name: 'Katsina-Ala East'),
        MVPLocationWard(name: 'Katsina-Ala West'),
        MVPLocationWard(name: 'Mbayion Ward'),
        MVPLocationWard(name: 'Ihugh Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Konshisha',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Tse-Agberagba'),
        MVPLocationWard(name: 'Mbakyaan Ward'),
        MVPLocationWard(name: 'Mbaikyongo Ward'),
        MVPLocationWard(name: 'Mbatse Ward'),
        MVPLocationWard(name: 'Konshisha Central'),
        MVPLocationWard(name: 'Tse-Agee Ward'),
        MVPLocationWard(name: 'Mbayenge Ward'),
        MVPLocationWard(name: 'Mbaiase Ward'),
        MVPLocationWard(name: 'Tse-Mbaighil Ward'),
        MVPLocationWard(name: 'Shitile Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Kwande',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Adikpo Central'),
        MVPLocationWard(name: 'Adikpo North'),
        MVPLocationWard(name: 'Adikpo South'),
        MVPLocationWard(name: 'Turan Ward'),
        MVPLocationWard(name: 'Nanev Ward'),
        MVPLocationWard(name: 'Jiir Ward'),
        MVPLocationWard(name: 'Yaav Ward'),
        MVPLocationWard(name: 'Shangev-Ya Ward'),
        MVPLocationWard(name: 'Tondov Ward'),
        MVPLocationWard(name: 'Mbayar Ward'),
        MVPLocationWard(name: 'Kwande East'),
      ],
    ),
    MVPLocationLGA(
      name: 'Logo',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Ugba Ward'),
        MVPLocationWard(name: 'Tombo Ward'),
        MVPLocationWard(name: 'Ukemberagya Ward'),
        MVPLocationWard(name: 'Anyiin Ward'),
        MVPLocationWard(name: 'Logo Ward'),
        MVPLocationWard(name: 'Nzorov Ward'),
        MVPLocationWard(name: 'Turan Ward'),
        MVPLocationWard(name: 'Gaambe-Ushin Ward'),
        MVPLocationWard(name: 'Yogbo Ward'),
        MVPLocationWard(name: 'Ayilamo Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Makurdi',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Agan'),
        MVPLocationWard(name: 'Ankpa/Wadata'),
        MVPLocationWard(name: 'Bar'),
        MVPLocationWard(name: 'Central/South Mission'),
        MVPLocationWard(name: 'Clerks/Market'),
        MVPLocationWard(name: 'Fiidi'),
        MVPLocationWard(name: 'Mbalagh'),
        MVPLocationWard(name: 'Modern Market'),
        MVPLocationWard(name: 'North Bank I'),
        MVPLocationWard(name: 'North Bank II'),
        MVPLocationWard(name: 'Wailomayo'),
      ],
    ),
    MVPLocationLGA(
      name: 'Obi',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Obi Ward'),
        MVPLocationWard(name: 'Oju Ward'),
        MVPLocationWard(name: 'Ito Ward'),
        MVPLocationWard(name: 'Orihi Ward'),
        MVPLocationWard(name: 'Adum Ward'),
        MVPLocationWard(name: 'Aloja Ward'),
        MVPLocationWard(name: 'Ohimini Ward'),
        MVPLocationWard(name: 'Igede Ward'),
        MVPLocationWard(name: 'Obarike Ward'),
        MVPLocationWard(name: 'Oju Central'),
      ],
    ),
    MVPLocationLGA(
      name: 'Ogbadibo',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Otukpa Central'),
        MVPLocationWard(name: 'Otukpa North'),
        MVPLocationWard(name: 'Otukpa South'),
        MVPLocationWard(name: 'Okpoga Ward'),
        MVPLocationWard(name: 'Orokam Ward'),
        MVPLocationWard(name: 'Ai-Ome Ward'),
        MVPLocationWard(name: 'Ogbadibo East'),
        MVPLocationWard(name: 'Ogbadibo West'),
        MVPLocationWard(name: 'Itabono Ward'),
        MVPLocationWard(name: 'Ehaje Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Ohimini',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Ochobo Ward'),
        MVPLocationWard(name: 'Oglewu Ward'),
        MVPLocationWard(name: 'Onyagede Ward'),
        MVPLocationWard(name: 'Idah-Apa Ward'),
        MVPLocationWard(name: 'Ohimini Central'),
        MVPLocationWard(name: 'Ehaje Ward'),
        MVPLocationWard(name: 'Adoka Ward'),
        MVPLocationWard(name: 'Ogbabede Ward'),
        MVPLocationWard(name: 'Orokam Ward'),
        MVPLocationWard(name: 'Onyagede East'),
      ],
    ),
    MVPLocationLGA(
      name: 'Oju',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Oju Central'),
        MVPLocationWard(name: 'Obarike-Ito Ward'),
        MVPLocationWard(name: 'Afo Ward'),
        MVPLocationWard(name: 'Igede Ward'),
        MVPLocationWard(name: 'Ukwonyo Ward'),
        MVPLocationWard(name: 'Oju North'),
        MVPLocationWard(name: 'Oju South'),
        MVPLocationWard(name: 'Oju East'),
        MVPLocationWard(name: 'Oju West'),
        MVPLocationWard(name: 'Abocho Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Okpokwu',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Ichama Ward'),
        MVPLocationWard(name: 'Edumoga Ward'),
        MVPLocationWard(name: 'Eke-Oitobi Ward'),
        MVPLocationWard(name: 'Ogwule-Ogbaulu Ward'),
        MVPLocationWard(name: 'Okpokwu Central'),
        MVPLocationWard(name: 'Okpoga Ward'),
        MVPLocationWard(name: 'Ugbokolo Ward'),
        MVPLocationWard(name: 'Edikwu Ward'),
        MVPLocationWard(name: 'Okpokwu East'),
        MVPLocationWard(name: 'Okpokwu West'),
      ],
    ),
    MVPLocationLGA(
      name: 'Oturkpo',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Oturkpo Central'),
        MVPLocationWard(name: 'Oturkpo North'),
        MVPLocationWard(name: 'Oturkpo South'),
        MVPLocationWard(name: 'Ugbokolo Ward'),
        MVPLocationWard(name: 'Adoka Ward'),
        MVPLocationWard(name: 'Ogene Ward'),
        MVPLocationWard(name: 'Okete Ward'),
        MVPLocationWard(name: 'Ewulo Ward'),
        MVPLocationWard(name: 'Oturkpo East'),
        MVPLocationWard(name: 'Oturkpo West'),
        MVPLocationWard(name: 'Akpete Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Tarka',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Wannune Central'),
        MVPLocationWard(name: 'Wannune North'),
        MVPLocationWard(name: 'Wannune South'),
        MVPLocationWard(name: 'Utange Ward'),
        MVPLocationWard(name: 'Ugbaam Ward'),
        MVPLocationWard(name: 'Mbayar Ward'),
        MVPLocationWard(name: 'Tarka Ward'),
        MVPLocationWard(name: 'Lessel Ward'),
        MVPLocationWard(name: 'Nanev Ward'),
        MVPLocationWard(name: 'Mbadwem Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Ukum',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Ugondo Ward'),
        MVPLocationWard(name: 'Mbacher Ward'),
        MVPLocationWard(name: 'Kendev Ward'),
        MVPLocationWard(name: 'Luhutu Ward'),
        MVPLocationWard(name: 'Ukum Central'),
        MVPLocationWard(name: 'Ikyurav Ukum'),
        MVPLocationWard(name: 'Mbatya Ward'),
        MVPLocationWard(name: 'Sankera Ward'),
        MVPLocationWard(name: 'Borikyo Ward'),
        MVPLocationWard(name: 'Uikpam Ward'),
        MVPLocationWard(name: 'Zaki-Biam Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Ushongo',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Lessel Ward'),
        MVPLocationWard(name: 'Ikparev Ward'),
        MVPLocationWard(name: 'Mbatyough Ward'),
        MVPLocationWard(name: 'Mbadwem Ward'),
        MVPLocationWard(name: 'Ushongo Central'),
        MVPLocationWard(name: 'Mbatyav Ward'),
        MVPLocationWard(name: 'Ushongo North'),
        MVPLocationWard(name: 'Ushongo South'),
        MVPLocationWard(name: 'Ugbema Ward'),
        MVPLocationWard(name: 'Korinya Ward'),
      ],
    ),
    MVPLocationLGA(
      name: 'Vandeikya',
      state: 'Benue',
      wards: [
        MVPLocationWard(name: 'Vandeikya Central'),
        MVPLocationWard(name: 'Vandeikya North'),
        MVPLocationWard(name: 'Vandeikya South'),
        MVPLocationWard(name: 'Mbadede Ward'),
        MVPLocationWard(name: 'Tsambe Ward'),
        MVPLocationWard(name: 'Mbakyaan Ward'),
        MVPLocationWard(name: 'Mbatser Ward'),
        MVPLocationWard(name: 'Vandeikya East'),
        MVPLocationWard(name: 'Vandeikya West'),
        MVPLocationWard(name: 'Tse-Ugba Ward'),
        MVPLocationWard(name: 'Kpa-ver Ward'),
      ],
    ),
  ];

  // ==================== NASARAWA STATE (13 LGAs, 147 Wards) ====================

  static const List<MVPLocationLGA> _nasarawaLGAs = [
    MVPLocationLGA(
      name: 'Akwanga',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Anchobaba'),
        MVPLocationWard(name: 'Agyaga'),
        MVPLocationWard(name: 'Gwanje Gwanje'),
        MVPLocationWard(name: 'Ancho Nighaan'),
        MVPLocationWard(name: 'Andaha'),
        MVPLocationWard(name: 'Akwanga Central'),
        MVPLocationWard(name: 'Akwanga North'),
        MVPLocationWard(name: 'Akwanga South'),
        MVPLocationWard(name: 'Arikya'),
        MVPLocationWard(name: 'Ningo'),
        MVPLocationWard(name: 'Wamba'),
      ],
    ),
    MVPLocationLGA(
      name: 'Awe',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Madaki'),
        MVPLocationWard(name: 'Galadima'),
        MVPLocationWard(name: 'Jangaru'),
        MVPLocationWard(name: 'Kanje Abuni'),
        MVPLocationWard(name: 'Ribi'),
        MVPLocationWard(name: 'Awe Central'),
        MVPLocationWard(name: 'Keana'),
        MVPLocationWard(name: 'Obi'),
        MVPLocationWard(name: 'Tudun Fulani'),
        MVPLocationWard(name: 'Daddere'),
      ],
    ),
    MVPLocationLGA(
      name: 'Doma',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Rukubi'),
        MVPLocationWard(name: 'Agbashi'),
        MVPLocationWard(name: 'Doka'),
        MVPLocationWard(name: 'Alagye'),
        MVPLocationWard(name: 'Akpanaja'),
        MVPLocationWard(name: 'Madaki'),
        MVPLocationWard(name: 'Ungwan Sarki Dawaki'),
        MVPLocationWard(name: 'Madauchi'),
        MVPLocationWard(name: 'Ungwan Dan Galadima'),
        MVPLocationWard(name: 'Sabon Gari'),
      ],
    ),
    MVPLocationLGA(
      name: 'Karu',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Aso/Kodape'),
        MVPLocationWard(name: 'Agada/Bagaji'),
        MVPLocationWard(name: 'Karshi I'),
        MVPLocationWard(name: 'Karshi II'),
        MVPLocationWard(name: 'Kafin Shanu/Betti'),
        MVPLocationWard(name: 'Tattara/Kondoro'),
        MVPLocationWard(name: 'Gitata'),
        MVPLocationWard(name: 'Gurku/Kabusu'),
        MVPLocationWard(name: 'Uke'),
        MVPLocationWard(name: 'Panda/Kare'),
        MVPLocationWard(name: 'Karu'),
      ],
    ),
    MVPLocationLGA(
      name: 'Keana',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Iswagu'),
        MVPLocationWard(name: 'Amiri'),
        MVPLocationWard(name: 'Obene'),
        MVPLocationWard(name: 'Oki'),
        MVPLocationWard(name: 'Keana Central'),
        MVPLocationWard(name: 'Aloshi'),
        MVPLocationWard(name: 'Giza'),
        MVPLocationWard(name: 'Obi'),
        MVPLocationWard(name: 'Agaza'),
        MVPLocationWard(name: 'Mada'),
      ],
    ),
    MVPLocationLGA(
      name: 'Keffi',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Angwan Iya I'),
        MVPLocationWard(name: 'Angwan Iya II'),
        MVPLocationWard(name: 'Tudun Kofa TV'),
        MVPLocationWard(name: 'Gangare Tudu'),
        MVPLocationWard(name: 'Keffi Central'),
        MVPLocationWard(name: 'Keffi North'),
        MVPLocationWard(name: 'Keffi South'),
        MVPLocationWard(name: 'Sabon Gari'),
        MVPLocationWard(name: 'Angwan Jaba'),
        MVPLocationWard(name: 'Liman Abaji'),
      ],
    ),
    MVPLocationLGA(
      name: 'Kokona',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Agwada'),
        MVPLocationWard(name: 'Koya/Kana'),
        MVPLocationWard(name: 'Bassa'),
        MVPLocationWard(name: 'Kokona'),
        MVPLocationWard(name: 'Gurku'),
        MVPLocationWard(name: 'Garaku'),
        MVPLocationWard(name: 'Agaza'),
        MVPLocationWard(name: 'Nieshi'),
        MVPLocationWard(name: 'Gadabuke'),
        MVPLocationWard(name: 'Ninkoro'),
        MVPLocationWard(name: 'Garaku East'),
      ],
    ),
    MVPLocationLGA(
      name: 'Lafia',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Adogi'),
        MVPLocationWard(name: 'Agyaragun Tofa'),
        MVPLocationWard(name: 'Bakin Rijiya/Akurba'),
        MVPLocationWard(name: 'Arikya'),
        MVPLocationWard(name: 'Lafia Central'),
        MVPLocationWard(name: 'Lafia East'),
        MVPLocationWard(name: 'Lafia West'),
        MVPLocationWard(name: 'Lafia North'),
        MVPLocationWard(name: 'Lafia South'),
        MVPLocationWard(name: 'Shabu'),
        MVPLocationWard(name: 'Doma Road'),
        MVPLocationWard(name: 'Makurdi Road'),
        MVPLocationWard(name: 'New Layout'),
      ],
    ),
    MVPLocationLGA(
      name: 'Nasarawa',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Udenin Gida'),
        MVPLocationWard(name: 'Akum'),
        MVPLocationWard(name: 'Udenin'),
        MVPLocationWard(name: 'Loko'),
        MVPLocationWard(name: 'Tunga/Bakono'),
        MVPLocationWard(name: 'Guto/Aisa'),
        MVPLocationWard(name: 'Nasarawa North'),
        MVPLocationWard(name: 'Nasarawa East'),
        MVPLocationWard(name: 'Nasarawa Central'),
        MVPLocationWard(name: 'Nasarawa Main Town'),
        MVPLocationWard(name: 'Ara I'),
        MVPLocationWard(name: 'Ara II'),
        MVPLocationWard(name: 'Laminga'),
        MVPLocationWard(name: 'Kanah/Ondo/Apawu'),
        MVPLocationWard(name: 'Odu'),
      ],
    ),
    MVPLocationLGA(
      name: 'Nasarawa Egon',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Nasarawa Eggon'),
        MVPLocationWard(name: 'Ubbe'),
        MVPLocationWard(name: 'Igga/Burumburum'),
        MVPLocationWard(name: 'Umme'),
        MVPLocationWard(name: 'Mada Station'),
        MVPLocationWard(name: 'Lizzin Keffi/Ezzen'),
        MVPLocationWard(name: 'Lambaga/Arikpa'),
        MVPLocationWard(name: 'Kagbu Wana'),
        MVPLocationWard(name: 'Ikka Wangibi'),
        MVPLocationWard(name: 'Ende'),
        MVPLocationWard(name: 'Wakama'),
        MVPLocationWard(name: 'Aloce/Ginda'),
        MVPLocationWard(name: 'Alogani'),
        MVPLocationWard(name: 'Agunji'),
      ],
    ),
    MVPLocationLGA(
      name: 'Obi',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Agwatashi'),
        MVPLocationWard(name: 'Deddere/Riri'),
        MVPLocationWard(name: 'Duduguru'),
        MVPLocationWard(name: 'Gwadenye'),
        MVPLocationWard(name: 'Kyakale'),
        MVPLocationWard(name: 'Gidan Ausa I'),
        MVPLocationWard(name: 'Gidan Ausa II'),
        MVPLocationWard(name: 'Adudu'),
        MVPLocationWard(name: 'Agwada'),
        MVPLocationWard(name: 'Riri'),
      ],
    ),
    MVPLocationLGA(
      name: 'Toto',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Gwagwada'),
        MVPLocationWard(name: 'Gadagwa'),
        MVPLocationWard(name: 'Bugakarmo'),
        MVPLocationWard(name: 'Umaisha'),
        MVPLocationWard(name: 'Toto Central'),
        MVPLocationWard(name: 'Gade'),
        MVPLocationWard(name: 'Gadabuke'),
        MVPLocationWard(name: 'Kwara'),
        MVPLocationWard(name: 'Dausu'),
        MVPLocationWard(name: 'Toto East'),
        MVPLocationWard(name: 'Toto West'),
        MVPLocationWard(name: 'Umaisha North'),
      ],
    ),
    MVPLocationLGA(
      name: 'Wamba',
      state: 'Nasarawa',
      wards: [
        MVPLocationWard(name: 'Konvan'),
        MVPLocationWard(name: 'Wayo'),
        MVPLocationWard(name: 'Wamba East'),
        MVPLocationWard(name: 'Wamba West'),
        MVPLocationWard(name: 'Arikya'),
        MVPLocationWard(name: 'Jangwa'),
        MVPLocationWard(name: 'Kwara'),
        MVPLocationWard(name: 'Gitata'),
        MVPLocationWard(name: 'Wamba Central'),
        MVPLocationWard(name: 'Wamba North'),
      ],
    ),
  ];

  // ==================== PLATEAU STATE (17 LGAs, 214 Wards) ====================

  static const List<MVPLocationLGA> _plateauLGAs = [
    MVPLocationLGA(
      name: 'Bokkos',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Bokkos'),
        MVPLocationWard(name: 'Butura'),
        MVPLocationWard(name: 'Daffo'),
        MVPLocationWard(name: 'Dorpshiri'),
        MVPLocationWard(name: 'Mushere'),
        MVPLocationWard(name: 'Richa'),
        MVPLocationWard(name: 'Toff'),
        MVPLocationWard(name: 'Sha'),
        MVPLocationWard(name: 'Manguna'),
        MVPLocationWard(name: 'Kamboa'),
      ],
    ),
    MVPLocationLGA(
      name: 'Barkin Ladi',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Barkin Ladi'),
        MVPLocationWard(name: 'Gassa Sho'),
        MVPLocationWard(name: 'Gindin Akwati'),
        MVPLocationWard(name: 'Foron'),
        MVPLocationWard(name: 'Gwol'),
        MVPLocationWard(name: 'Kuru'),
        MVPLocationWard(name: 'Fan'),
        MVPLocationWard(name: 'Heipang'),
        MVPLocationWard(name: 'Ropp'),
        MVPLocationWard(name: 'Shen'),
        MVPLocationWard(name: 'Bisichi'),
      ],
    ),
    MVPLocationLGA(
      name: 'Bassa',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Kishika'),
        MVPLocationWard(name: 'Bassa'),
        MVPLocationWard(name: 'Kwall'),
        MVPLocationWard(name: 'Miango'),
        MVPLocationWard(name: 'Rukuba'),
        MVPLocationWard(name: 'Jengre'),
        MVPLocationWard(name: 'Zawan'),
        MVPLocationWard(name: 'Sha'),
        MVPLocationWard(name: 'Rafin Bauna'),
        MVPLocationWard(name: 'Buji'),
      ],
    ),
    MVPLocationLGA(
      name: 'Jos East',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Federe'),
        MVPLocationWard(name: 'Fobur A'),
        MVPLocationWard(name: 'Fobur B'),
        MVPLocationWard(name: 'Angware'),
        MVPLocationWard(name: 'Dadin Kowa'),
        MVPLocationWard(name: 'Fursum'),
        MVPLocationWard(name: 'Marama'),
        MVPLocationWard(name: 'Tilden Fulani'),
        MVPLocationWard(name: 'Shere'),
        MVPLocationWard(name: 'Kwang'),
      ],
    ),
    MVPLocationLGA(
      name: 'Jos North',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Abba Na Shehu'),
        MVPLocationWard(name: 'Ali Kazaure'),
        MVPLocationWard(name: 'Gangare'),
        MVPLocationWard(name: 'Garba Daho'),
        MVPLocationWard(name: 'Ibrahim Katsina'),
        MVPLocationWard(name: 'Jenta Adamu'),
        MVPLocationWard(name: 'Jenta Apata'),
        MVPLocationWard(name: 'Jos Jarawa'),
        MVPLocationWard(name: 'Naraguta A'),
        MVPLocationWard(name: 'Naraguta B'),
        MVPLocationWard(name: 'Sarkin Arab'),
        MVPLocationWard(name: 'Tafawa Balewa'),
        MVPLocationWard(name: 'Tudun Wada - Kabong'),
        MVPLocationWard(name: 'Vanderpuye'),
      ],
    ),
    MVPLocationLGA(
      name: 'Jos South',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Bukuru'),
        MVPLocationWard(name: 'Du'),
        MVPLocationWard(name: 'Giring'),
        MVPLocationWard(name: 'Gyel A'),
        MVPLocationWard(name: 'Gyel B'),
        MVPLocationWard(name: 'Kuru A'),
        MVPLocationWard(name: 'Kuru B'),
        MVPLocationWard(name: 'Shen'),
        MVPLocationWard(name: 'Turu'),
        MVPLocationWard(name: 'Vwang'),
        MVPLocationWard(name: 'Zawan A'),
        MVPLocationWard(name: 'Zawan B'),
      ],
    ),
    MVPLocationLGA(
      name: 'Kanam',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Birbyang'),
        MVPLocationWard(name: 'Dengi'),
        MVPLocationWard(name: 'Dugub'),
        MVPLocationWard(name: 'Gagdib'),
        MVPLocationWard(name: 'Garga'),
        MVPLocationWard(name: 'Gumsher'),
        MVPLocationWard(name: 'Gwamlar'),
        MVPLocationWard(name: 'Jarmai'),
        MVPLocationWard(name: 'Jom'),
        MVPLocationWard(name: 'Kanam'),
        MVPLocationWard(name: 'Kantana'),
        MVPLocationWard(name: 'Kunkyam'),
        MVPLocationWard(name: 'Munbutbo'),
        MVPLocationWard(name: 'Kampani'),
      ],
    ),
    MVPLocationLGA(
      name: 'Kanke',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Ampang East A'),
        MVPLocationWard(name: 'Ampang East B'),
        MVPLocationWard(name: 'Amper Chika A'),
        MVPLocationWard(name: 'Amper Chika B'),
        MVPLocationWard(name: 'Kanke'),
        MVPLocationWard(name: 'Amper'),
        MVPLocationWard(name: 'Kembo'),
        MVPLocationWard(name: 'Kwalla'),
        MVPLocationWard(name: 'Pil'),
        MVPLocationWard(name: 'Kabwir'),
      ],
    ),
    MVPLocationLGA(
      name: 'Langtang North',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Jat'),
        MVPLocationWard(name: 'Keller'),
        MVPLocationWard(name: 'Kuffen'),
        MVPLocationWard(name: 'Langtang North Central'),
        MVPLocationWard(name: 'Gazum'),
        MVPLocationWard(name: 'Mabudi'),
        MVPLocationWard(name: 'Pil Gani'),
        MVPLocationWard(name: 'Yelwa'),
        MVPLocationWard(name: 'Timbol'),
        MVPLocationWard(name: 'Garkawa'),
        MVPLocationWard(name: 'Tahoss'),
        MVPLocationWard(name: 'Langkuk'),
        MVPLocationWard(name: 'Fursum'),
        MVPLocationWard(name: 'Dadiya'),
      ],
    ),
    MVPLocationLGA(
      name: 'Langtang South',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Gamaka'),
        MVPLocationWard(name: 'Lashel'),
        MVPLocationWard(name: 'Mabudi'),
        MVPLocationWard(name: 'Jemkur'),
        MVPLocationWard(name: 'Turaki'),
        MVPLocationWard(name: 'Langtang South'),
        MVPLocationWard(name: 'Piapung'),
        MVPLocationWard(name: 'Mbar'),
        MVPLocationWard(name: 'Ying'),
        MVPLocationWard(name: 'Buki'),
        MVPLocationWard(name: 'Gazum'),
        MVPLocationWard(name: 'Kwallak'),
      ],
    ),
    MVPLocationLGA(
      name: 'Mangu',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Chanso'),
        MVPLocationWard(name: 'Gindiri I'),
        MVPLocationWard(name: 'Gindiri II'),
        MVPLocationWard(name: 'Kasuwan Ali'),
        MVPLocationWard(name: 'Mangu'),
        MVPLocationWard(name: 'Ampang West'),
        MVPLocationWard(name: 'Ampang East'),
        MVPLocationWard(name: 'Kombun'),
        MVPLocationWard(name: 'Langshi'),
        MVPLocationWard(name: 'Chakwas'),
        MVPLocationWard(name: 'Jipul'),
        MVPLocationWard(name: 'Kerang'),
        MVPLocationWard(name: 'Mabudi'),
        MVPLocationWard(name: 'Panyam'),
        MVPLocationWard(name: 'Pushit'),
        MVPLocationWard(name: 'Wanka'),
      ],
    ),
    MVPLocationLGA(
      name: 'Mikang',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Garkawa Central'),
        MVPLocationWard(name: 'Garkawa North'),
        MVPLocationWard(name: 'Garkawa North East'),
        MVPLocationWard(name: 'Mikang'),
        MVPLocationWard(name: 'Tunkus'),
        MVPLocationWard(name: 'Piapung'),
        MVPLocationWard(name: 'Tambes'),
        MVPLocationWard(name: 'Gupiya'),
        MVPLocationWard(name: 'Kasa'),
        MVPLocationWard(name: 'Wiaplas'),
      ],
    ),
    MVPLocationLGA(
      name: 'Pankshin',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Chip'),
        MVPLocationWard(name: 'Dok Pai'),
        MVPLocationWard(name: 'Fier'),
        MVPLocationWard(name: 'Mudkang Yelleng'),
        MVPLocationWard(name: 'Pankshin Central'),
        MVPLocationWard(name: 'Pankshin North'),
        MVPLocationWard(name: 'Pankshin South'),
        MVPLocationWard(name: 'Kadung'),
        MVPLocationWard(name: 'Bwal'),
        MVPLocationWard(name: 'Pakain'),
        MVPLocationWard(name: 'Tunkus'),
        MVPLocationWard(name: 'Kabwir'),
      ],
    ),
    MVPLocationLGA(
      name: 'Qua\'an Pan',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Bwall'),
        MVPLocationWard(name: 'Doemak Goechim'),
        MVPLocationWard(name: 'Doemak Koplong'),
        MVPLocationWard(name: 'Luukwo'),
        MVPLocationWard(name: 'Qua\'an Pan'),
        MVPLocationWard(name: 'Kwang'),
        MVPLocationWard(name: 'Baap'),
        MVPLocationWard(name: 'Dokan Tofa'),
        MVPLocationWard(name: 'Langas'),
        MVPLocationWard(name: 'Namu'),
      ],
    ),
    MVPLocationLGA(
      name: 'Riyom',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Attakar'),
        MVPLocationWard(name: 'Bum'),
        MVPLocationWard(name: 'Danto'),
        MVPLocationWard(name: 'Riyom'),
        MVPLocationWard(name: 'Rim'),
        MVPLocationWard(name: 'Kassa'),
        MVPLocationWard(name: 'Tahoss'),
        MVPLocationWard(name: 'Shong'),
        MVPLocationWard(name: 'Rafin Bauna'),
        MVPLocationWard(name: 'Kwaturu'),
      ],
    ),
    MVPLocationLGA(
      name: 'Shendam',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Derteng'),
        MVPLocationWard(name: 'Kalong'),
        MVPLocationWard(name: 'Kurungbau A'),
        MVPLocationWard(name: 'Shendam'),
        MVPLocationWard(name: 'Dokan Kasuwa'),
        MVPLocationWard(name: 'Garkep'),
        MVPLocationWard(name: 'Kwalla'),
        MVPLocationWard(name: 'Panyam'),
        MVPLocationWard(name: 'Shendam North'),
        MVPLocationWard(name: 'Shendam South'),
        MVPLocationWard(name: 'Kurungbau B'),
      ],
    ),
    MVPLocationLGA(
      name: 'Wase',
      state: 'Plateau',
      wards: [
        MVPLocationWard(name: 'Bashar'),
        MVPLocationWard(name: 'Danbiram'),
        MVPLocationWard(name: 'Wase'),
        MVPLocationWard(name: 'Gule'),
        MVPLocationWard(name: 'Kadarko'),
        MVPLocationWard(name: 'Zurak'),
        MVPLocationWard(name: 'Lamba'),
        MVPLocationWard(name: 'Mavo'),
        MVPLocationWard(name: 'Sabon Layi'),
        MVPLocationWard(name: 'Wase Central'),
        MVPLocationWard(name: 'Wase Tofa'),
        MVPLocationWard(name: 'Wayam'),
      ],
    ),
  ];

  // ==================== ALL LGAs ====================

  static const List<MVPLocationLGA> allLGAs = [
    ..._benueLGAs,
    ..._nasarawaLGAs,
    ..._plateauLGAs,
  ];

  // ==================== HELPER METHODS ====================

  /// Get all state names
  static List<String> getAllStates() {
    return ['Benue', 'Nasarawa', 'Plateau'];
  }

  /// Get all LGA names across all states
  static List<String> getAllLGAs() {
    return allLGAs.map((lga) => lga.name).toList();
  }

  /// Get LGAs for a specific state
  static List<String> getLGAsForState(String state) {
    return allLGAs
        .where((lga) => lga.state == state)
        .map((lga) => lga.name)
        .toList();
  }

  /// Get wards for a specific LGA
  static List<String> getWardsForLGA(String lgaName) {
    final lga = allLGAs.firstWhere(
      (lga) => lga.name == lgaName,
      orElse: () => const MVPLocationLGA(name: '', state: '', wards: []),
    );
    return lga.wards.map((ward) => ward.name).toList();
  }

  /// Get state for a specific LGA
  static String getStateForLGA(String lgaName) {
    final lga = allLGAs.firstWhere(
      (lga) => lga.name == lgaName,
      orElse: () => const MVPLocationLGA(name: '', state: 'Unknown', wards: []),
    );
    return lga.state;
  }

  /// Get formatted location string
  static String getLocationString({required String ward, required String lga}) {
    final state = getStateForLGA(lga);
    return '$ward, $lga LGA, $state State';
  }

  /// Validate if a ward exists for a given LGA
  static bool isValidWardForLGA(String ward, String lgaName) {
    final wards = getWardsForLGA(lgaName);
    return wards.contains(ward);
  }

  /// Get all wards across all LGAs
  static List<String> getAllWards() {
    return allLGAs.expand((lga) => lga.wards).map((ward) => ward.name).toList();
  }

  /// Get total count of LGAs per state
  static Map<String, int> getLGACountByState() {
    return {
      'Benue': _benueLGAs.length,
      'Nasarawa': _nasarawaLGAs.length,
      'Plateau': _plateauLGAs.length,
    };
  }

  /// Get total count of wards per state
  static Map<String, int> getWardCountByState() {
    int benueWards = _benueLGAs.fold(0, (sum, lga) => sum + lga.wards.length);
    int nasarawaWards = _nasarawaLGAs.fold(
      0,
      (sum, lga) => sum + lga.wards.length,
    );
    int plateauWards = _plateauLGAs.fold(
      0,
      (sum, lga) => sum + lga.wards.length,
    );

    return {
      'Benue': benueWards,
      'Nasarawa': nasarawaWards,
      'Plateau': plateauWards,
    };
  }

  /// Get summary statistics
  static Map<String, dynamic> getSummary() {
    final wardCounts = getWardCountByState();
    final totalWards = wardCounts.values.fold(0, (sum, count) => sum + count);

    return {
      'totalStates': 3,
      'totalLGAs': allLGAs.length,
      'totalWards': totalWards,
      'lgasByState': getLGACountByState(),
      'wardsByState': wardCounts,
      'dataSource': 'INEC Nigeria',
      'lastUpdated': '2025-12-30',
    };
  }

  /// Get LGA for a given Ward name
  static String? getLGAForWard(String wardName) {
    // Search in all LGAs
    try {
      final lga = allLGAs.firstWhere(
        (lga) => lga.wards.any(
          (ward) => ward.name.toLowerCase() == wardName.toLowerCase(),
        ),
      );
      return lga.name;
    } catch (_) {
      return null;
    }
  }

  /// Get Wards for a given LGA by name (safe lookup)
  static List<String> getWardsForLGASafe(String lgaName) {
    try {
      final lga = allLGAs.firstWhere(
        (lga) => lga.name.toLowerCase() == lgaName.toLowerCase(),
      );
      return lga.wards.map((w) => w.name).toList();
    } catch (_) {
      return [];
    }
  }
}
