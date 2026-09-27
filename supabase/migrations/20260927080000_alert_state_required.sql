-- Alerts must name the state of the LGA they target.
--
-- 20260927050000 added alerts.target_state but left it nullable, so an alert
-- could still name an LGA and no state — and 6 of the 770 LGA names are not
-- unique, so that alert had no single meaning:
--
--   Bassa      Kogi, Plateau      Nasarawa   Kano, Nasarawa
--   Ifelodun   Kwara, Osun        Obi        Benue, Nasarawa
--   Irepodun   Kwara, Osun        Surulere   Lagos, Oyo
--
-- (derived from lib/core/data/nigeria_locations_data.dart, the app's canonical
-- 37 states / 770 LGAs; lib/core/data/mvp_locations_data.dart's 53 LGAs for
-- Benue, Nasarawa and Plateau are a spelling-identical subset of it.)
--
-- From here on the database rejects that shape outright. The four targetings
-- that remain expressible are exactly the four the push filter builder
-- (backend/src/notifications.js alertTarget) and the app's alert list
-- (lib/features/alerts/providers/alerts_provider.dart targetsLga) understand:
--
--   target_state NULL, target_lga 'All'  -> everyone, everywhere
--   target_state S,    target_lga 'All'  -> every LGA of S
--   target_state S,    target_lga X      -> X in S only
--   target_state NULL, target_lga X      -> REJECTED (which X?)
--
-- Why two reference tables rather than a literal list in the CHECK
--   A CHECK can only hold a constant expression, so pinning 770 (state, LGA)
--   pairs into one would mean a 770-entry IN list repeated in every future
--   migration that touched it — exactly the unmaintainable literal list to
--   avoid. 20260927070000 already carries that list once as an inline VALUES
--   list, usable only by that one UPDATE. Persisting it instead as
--   public.nigeria_states / public.nigeria_lgas lets a plain FOREIGN KEY do
--   the validation, and leaves the same canonical data available to future
--   migrations, admin queries and RPCs (it is the only copy of it in the
--   database). Both tables are seeded from nigeria_locations_data.dart and are
--   client-read-only.

-- ── Canonical Nigerian states and LGAs ──────────────────────────────────────

create table public.nigeria_states (
  name text primary key check (name = btrim(name) and name <> '')
);

create table public.nigeria_lgas (
  state text not null references public.nigeria_states (name),
  lga   text not null check (lga = btrim(lga) and lga <> ''),
  primary key (state, lga)
);

-- Lookups by LGA name alone (used by the backfill below and by anything that
-- needs "which states have an LGA called X").
create index nigeria_lgas_lga_idx on public.nigeria_lgas (lower(lga));

insert into public.nigeria_states (name) values
  ('Abia'),
  ('Adamawa'),
  ('Akwa Ibom'),
  ('Anambra'),
  ('Bauchi'),
  ('Bayelsa'),
  ('Benue'),
  ('Borno'),
  ('Cross River'),
  ('Delta'),
  ('Ebonyi'),
  ('Edo'),
  ('Ekiti'),
  ('Enugu'),
  ('FCT'),
  ('Gombe'),
  ('Imo'),
  ('Jigawa'),
  ('Kaduna'),
  ('Kano'),
  ('Katsina'),
  ('Kebbi'),
  ('Kogi'),
  ('Kwara'),
  ('Lagos'),
  ('Nasarawa'),
  ('Niger'),
  ('Ogun'),
  ('Ondo'),
  ('Osun'),
  ('Oyo'),
  ('Plateau'),
  ('Rivers'),
  ('Sokoto'),
  ('Taraba'),
  ('Yobe'),
  ('Zamfara');

insert into public.nigeria_lgas (state, lga) values
  ('Abia', 'Aba North'),
  ('Abia', 'Aba South'),
  ('Abia', 'Arochukwu'),
  ('Abia', 'Bende'),
  ('Abia', 'Ikwuano'),
  ('Abia', 'Isiala Ngwa North'),
  ('Abia', 'Isiala Ngwa South'),
  ('Abia', 'Isuikwuato'),
  ('Abia', 'Obi Ngwa'),
  ('Abia', 'Ohafia'),
  ('Abia', 'Osisioma'),
  ('Abia', 'Ugwunagbo'),
  ('Abia', 'Ukwa East'),
  ('Abia', 'Ukwa West'),
  ('Abia', 'Umuahia North'),
  ('Abia', 'Umuahia South'),
  ('Abia', 'Umu Nneochi'),
  ('Adamawa', 'Demsa'),
  ('Adamawa', 'Fufure'),
  ('Adamawa', 'Ganye'),
  ('Adamawa', 'Gayuk'),
  ('Adamawa', 'Gombi'),
  ('Adamawa', 'Grie'),
  ('Adamawa', 'Hong'),
  ('Adamawa', 'Jada'),
  ('Adamawa', 'Lamurde'),
  ('Adamawa', 'Madagali'),
  ('Adamawa', 'Maiha'),
  ('Adamawa', 'Mayo Belwa'),
  ('Adamawa', 'Michika'),
  ('Adamawa', 'Mubi North'),
  ('Adamawa', 'Mubi South'),
  ('Adamawa', 'Numan'),
  ('Adamawa', 'Shelleng'),
  ('Adamawa', 'Song'),
  ('Adamawa', 'Toungo'),
  ('Adamawa', 'Yola North'),
  ('Adamawa', 'Yola South'),
  ('Akwa Ibom', 'Abak'),
  ('Akwa Ibom', 'Eastern Obolo'),
  ('Akwa Ibom', 'Eket'),
  ('Akwa Ibom', 'Esit Eket'),
  ('Akwa Ibom', 'Essien Udim'),
  ('Akwa Ibom', 'Etim Ekpo'),
  ('Akwa Ibom', 'Etinan'),
  ('Akwa Ibom', 'Ibeno'),
  ('Akwa Ibom', 'Ibesikpo Asutan'),
  ('Akwa Ibom', 'Ibiono-Ibom'),
  ('Akwa Ibom', 'Ika'),
  ('Akwa Ibom', 'Ikono'),
  ('Akwa Ibom', 'Ikot Abasi'),
  ('Akwa Ibom', 'Ikot Ekpene'),
  ('Akwa Ibom', 'Ini'),
  ('Akwa Ibom', 'Itu'),
  ('Akwa Ibom', 'Mbo'),
  ('Akwa Ibom', 'Mkpat-Enin'),
  ('Akwa Ibom', 'Nsit-Atai'),
  ('Akwa Ibom', 'Nsit-Ibom'),
  ('Akwa Ibom', 'Nsit-Ubium'),
  ('Akwa Ibom', 'Obot Akara'),
  ('Akwa Ibom', 'Okobo'),
  ('Akwa Ibom', 'Onna'),
  ('Akwa Ibom', 'Oron'),
  ('Akwa Ibom', 'Oruk Anam'),
  ('Akwa Ibom', 'Udung-Uko'),
  ('Akwa Ibom', 'Ukanafun'),
  ('Akwa Ibom', 'Uruan'),
  ('Akwa Ibom', 'Urue-Offong/Oruko'),
  ('Akwa Ibom', 'Uyo'),
  ('Anambra', 'Aguata'),
  ('Anambra', 'Anambra East'),
  ('Anambra', 'Anambra West'),
  ('Anambra', 'Anaocha'),
  ('Anambra', 'Awka North'),
  ('Anambra', 'Awka South'),
  ('Anambra', 'Ayamelum'),
  ('Anambra', 'Dunukofia'),
  ('Anambra', 'Ekwusigo'),
  ('Anambra', 'Idemili North'),
  ('Anambra', 'Idemili South'),
  ('Anambra', 'Ihiala'),
  ('Anambra', 'Njikoka'),
  ('Anambra', 'Nnewi North'),
  ('Anambra', 'Nnewi South'),
  ('Anambra', 'Ogbaru'),
  ('Anambra', 'Onitsha North'),
  ('Anambra', 'Onitsha South'),
  ('Anambra', 'Orumba North'),
  ('Anambra', 'Orumba South'),
  ('Anambra', 'Oyi'),
  ('Bauchi', 'Alkaleri'),
  ('Bauchi', 'Bauchi'),
  ('Bauchi', 'Bogoro'),
  ('Bauchi', 'Damban'),
  ('Bauchi', 'Darazo'),
  ('Bauchi', 'Dass'),
  ('Bauchi', 'Gamawa'),
  ('Bauchi', 'Ganjuwa'),
  ('Bauchi', 'Giade'),
  ('Bauchi', 'Itas/Gadau'),
  ('Bauchi', 'Jama''are'),
  ('Bauchi', 'Katagum'),
  ('Bauchi', 'Kirfi'),
  ('Bauchi', 'Misau'),
  ('Bauchi', 'Ningi'),
  ('Bauchi', 'Shira'),
  ('Bauchi', 'Tafawa Balewa'),
  ('Bauchi', 'Toro'),
  ('Bauchi', 'Warji'),
  ('Bauchi', 'Zaki'),
  ('Bayelsa', 'Brass'),
  ('Bayelsa', 'Ekeremor'),
  ('Bayelsa', 'Kolokuma/Opokuma'),
  ('Bayelsa', 'Nembe'),
  ('Bayelsa', 'Ogbia'),
  ('Bayelsa', 'Sagbama'),
  ('Bayelsa', 'Southern Ijaw'),
  ('Bayelsa', 'Yenagoa'),
  ('Benue', 'Ado'),
  ('Benue', 'Agatu'),
  ('Benue', 'Apa'),
  ('Benue', 'Buruku'),
  ('Benue', 'Gboko'),
  ('Benue', 'Guma'),
  ('Benue', 'Gwer East'),
  ('Benue', 'Gwer West'),
  ('Benue', 'Katsina-Ala'),
  ('Benue', 'Konshisha'),
  ('Benue', 'Kwande'),
  ('Benue', 'Logo'),
  ('Benue', 'Makurdi'),
  ('Benue', 'Obi'),
  ('Benue', 'Ogbadibo'),
  ('Benue', 'Ohimini'),
  ('Benue', 'Oju'),
  ('Benue', 'Okpokwu'),
  ('Benue', 'Oturkpo'),
  ('Benue', 'Tarka'),
  ('Benue', 'Ukum'),
  ('Benue', 'Ushongo'),
  ('Benue', 'Vandeikya'),
  ('Borno', 'Abadam'),
  ('Borno', 'Askira/Uba'),
  ('Borno', 'Bama'),
  ('Borno', 'Bayo'),
  ('Borno', 'Biu'),
  ('Borno', 'Chibok'),
  ('Borno', 'Damboa'),
  ('Borno', 'Dikwa'),
  ('Borno', 'Gubio'),
  ('Borno', 'Guzamala'),
  ('Borno', 'Gwoza'),
  ('Borno', 'Hawul'),
  ('Borno', 'Jere'),
  ('Borno', 'Kaga'),
  ('Borno', 'Kala/Balge'),
  ('Borno', 'Konduga'),
  ('Borno', 'Kukawa'),
  ('Borno', 'Kwaya Kusar'),
  ('Borno', 'Mafa'),
  ('Borno', 'Magumeri'),
  ('Borno', 'Maiduguri'),
  ('Borno', 'Marte'),
  ('Borno', 'Mobbar'),
  ('Borno', 'Monguno'),
  ('Borno', 'Ngala'),
  ('Borno', 'Nganzai'),
  ('Borno', 'Shani'),
  ('Cross River', 'Abi'),
  ('Cross River', 'Akamkpa'),
  ('Cross River', 'Akpabuyo'),
  ('Cross River', 'Bakassi'),
  ('Cross River', 'Bekwarra'),
  ('Cross River', 'Biase'),
  ('Cross River', 'Boki'),
  ('Cross River', 'Calabar Municipal'),
  ('Cross River', 'Calabar South'),
  ('Cross River', 'Etung'),
  ('Cross River', 'Ikom'),
  ('Cross River', 'Obanliku'),
  ('Cross River', 'Obubra'),
  ('Cross River', 'Obudu'),
  ('Cross River', 'Odukpani'),
  ('Cross River', 'Ogoja'),
  ('Cross River', 'Yakuur'),
  ('Cross River', 'Yala'),
  ('Delta', 'Aniocha North'),
  ('Delta', 'Aniocha South'),
  ('Delta', 'Bomadi'),
  ('Delta', 'Burutu'),
  ('Delta', 'Ethiope East'),
  ('Delta', 'Ethiope West'),
  ('Delta', 'Ika North East'),
  ('Delta', 'Ika South'),
  ('Delta', 'Isoko North'),
  ('Delta', 'Isoko South'),
  ('Delta', 'Ndokwa East'),
  ('Delta', 'Ndokwa West'),
  ('Delta', 'Okpe'),
  ('Delta', 'Oshimili North'),
  ('Delta', 'Oshimili South'),
  ('Delta', 'Patani'),
  ('Delta', 'Sapele'),
  ('Delta', 'Udu'),
  ('Delta', 'Ughelli North'),
  ('Delta', 'Ughelli South'),
  ('Delta', 'Ukwuani'),
  ('Delta', 'Uvwie'),
  ('Delta', 'Warri North'),
  ('Delta', 'Warri South'),
  ('Delta', 'Warri South West'),
  ('Ebonyi', 'Abakaliki'),
  ('Ebonyi', 'Afikpo North'),
  ('Ebonyi', 'Afikpo South'),
  ('Ebonyi', 'Ebonyi'),
  ('Ebonyi', 'Ezza North'),
  ('Ebonyi', 'Ezza South'),
  ('Ebonyi', 'Ikwo'),
  ('Ebonyi', 'Ishielu'),
  ('Ebonyi', 'Ivo'),
  ('Ebonyi', 'Izzi'),
  ('Ebonyi', 'Ohaozara'),
  ('Ebonyi', 'Ohaukwu'),
  ('Ebonyi', 'Onicha'),
  ('Edo', 'Akoko-Edo'),
  ('Edo', 'Egor'),
  ('Edo', 'Esan Central'),
  ('Edo', 'Esan North-East'),
  ('Edo', 'Esan South-East'),
  ('Edo', 'Esan West'),
  ('Edo', 'Etsako Central'),
  ('Edo', 'Etsako East'),
  ('Edo', 'Etsako West'),
  ('Edo', 'Igueben'),
  ('Edo', 'Ikpoba Okha'),
  ('Edo', 'Orhionmwon'),
  ('Edo', 'Oredo'),
  ('Edo', 'Ovia North-East'),
  ('Edo', 'Ovia South-West'),
  ('Edo', 'Owan East'),
  ('Edo', 'Owan West'),
  ('Edo', 'Uhunmwonde'),
  ('Ekiti', 'Ado Ekiti'),
  ('Ekiti', 'Efon'),
  ('Ekiti', 'Ekiti East'),
  ('Ekiti', 'Ekiti South-West'),
  ('Ekiti', 'Ekiti West'),
  ('Ekiti', 'Emure'),
  ('Ekiti', 'Gbonyin'),
  ('Ekiti', 'Ido Osi'),
  ('Ekiti', 'Ijero'),
  ('Ekiti', 'Ikere'),
  ('Ekiti', 'Ikole'),
  ('Ekiti', 'Ilejemeje'),
  ('Ekiti', 'Irepodun/Ifelodun'),
  ('Ekiti', 'Ise/Orun'),
  ('Ekiti', 'Moba'),
  ('Ekiti', 'Oye'),
  ('Enugu', 'Aninri'),
  ('Enugu', 'Awgu'),
  ('Enugu', 'Enugu East'),
  ('Enugu', 'Enugu North'),
  ('Enugu', 'Enugu South'),
  ('Enugu', 'Ezeagu'),
  ('Enugu', 'Igbo Etiti'),
  ('Enugu', 'Igbo Eze North'),
  ('Enugu', 'Igbo Eze South'),
  ('Enugu', 'Isi Uzo'),
  ('Enugu', 'Nkanu East'),
  ('Enugu', 'Nkanu West'),
  ('Enugu', 'Nsukka'),
  ('Enugu', 'Oji River'),
  ('Enugu', 'Udenu'),
  ('Enugu', 'Udi'),
  ('Enugu', 'Uzo Uwani'),
  ('FCT', 'Abaji'),
  ('FCT', 'Bwari'),
  ('FCT', 'Gwagwalada'),
  ('FCT', 'Kuje'),
  ('FCT', 'Kwali'),
  ('FCT', 'Municipal Area Council'),
  ('Gombe', 'Akko'),
  ('Gombe', 'Balanga'),
  ('Gombe', 'Billiri'),
  ('Gombe', 'Dukku'),
  ('Gombe', 'Funakaye'),
  ('Gombe', 'Gombe'),
  ('Gombe', 'Kaltungo'),
  ('Gombe', 'Kwami'),
  ('Gombe', 'Nafada'),
  ('Gombe', 'Shongom'),
  ('Gombe', 'Yamaltu/Deba'),
  ('Imo', 'Aboh Mbaise'),
  ('Imo', 'Ahiazu Mbaise'),
  ('Imo', 'Ehime Mbano'),
  ('Imo', 'Ezinihitte'),
  ('Imo', 'Ideato North'),
  ('Imo', 'Ideato South'),
  ('Imo', 'Ihitte/Uboma'),
  ('Imo', 'Ikeduru'),
  ('Imo', 'Isiala Mbano'),
  ('Imo', 'Isu'),
  ('Imo', 'Mbaitoli'),
  ('Imo', 'Ngor Okpala'),
  ('Imo', 'Njaba'),
  ('Imo', 'Nkwerre'),
  ('Imo', 'Nwangele'),
  ('Imo', 'Obowo'),
  ('Imo', 'Oguta'),
  ('Imo', 'Ohaji/Egbema'),
  ('Imo', 'Okigwe'),
  ('Imo', 'Orlu'),
  ('Imo', 'Orsu'),
  ('Imo', 'Oru East'),
  ('Imo', 'Oru West'),
  ('Imo', 'Owerri Municipal'),
  ('Imo', 'Owerri North'),
  ('Imo', 'Owerri West'),
  ('Imo', 'Unuimo'),
  ('Jigawa', 'Auyo'),
  ('Jigawa', 'Babura'),
  ('Jigawa', 'Biriniwa'),
  ('Jigawa', 'Birnin Kudu'),
  ('Jigawa', 'Buji'),
  ('Jigawa', 'Dutse'),
  ('Jigawa', 'Gagarawa'),
  ('Jigawa', 'Garki'),
  ('Jigawa', 'Gumel'),
  ('Jigawa', 'Guri'),
  ('Jigawa', 'Gwaram'),
  ('Jigawa', 'Gwiwa'),
  ('Jigawa', 'Hadejia'),
  ('Jigawa', 'Jahun'),
  ('Jigawa', 'Kafin Hausa'),
  ('Jigawa', 'Kazaure'),
  ('Jigawa', 'Kiri Kasama'),
  ('Jigawa', 'Kiyawa'),
  ('Jigawa', 'Kaugama'),
  ('Jigawa', 'Maigatari'),
  ('Jigawa', 'Malam Madori'),
  ('Jigawa', 'Miga'),
  ('Jigawa', 'Ringim'),
  ('Jigawa', 'Roni'),
  ('Jigawa', 'Sule Tankarkar'),
  ('Jigawa', 'Taura'),
  ('Jigawa', 'Yankwashi'),
  ('Kaduna', 'Birnin Gwari'),
  ('Kaduna', 'Chikun'),
  ('Kaduna', 'Giwa'),
  ('Kaduna', 'Igabi'),
  ('Kaduna', 'Ikara'),
  ('Kaduna', 'Jaba'),
  ('Kaduna', 'Jema''a'),
  ('Kaduna', 'Kachia'),
  ('Kaduna', 'Kaduna North'),
  ('Kaduna', 'Kaduna South'),
  ('Kaduna', 'Kagarko'),
  ('Kaduna', 'Kajuru'),
  ('Kaduna', 'Kaura'),
  ('Kaduna', 'Kauru'),
  ('Kaduna', 'Kubau'),
  ('Kaduna', 'Kudan'),
  ('Kaduna', 'Lere'),
  ('Kaduna', 'Makarfi'),
  ('Kaduna', 'Sabon Gari'),
  ('Kaduna', 'Sanga'),
  ('Kaduna', 'Soba'),
  ('Kaduna', 'Zangon Kataf'),
  ('Kaduna', 'Zaria'),
  ('Kano', 'Ajingi'),
  ('Kano', 'Albasu'),
  ('Kano', 'Bagwai'),
  ('Kano', 'Bebeji'),
  ('Kano', 'Bichi'),
  ('Kano', 'Bunkure'),
  ('Kano', 'Dala'),
  ('Kano', 'Dambatta'),
  ('Kano', 'Dawakin Kudu'),
  ('Kano', 'Dawakin Tofa'),
  ('Kano', 'Doguwa'),
  ('Kano', 'Fagge'),
  ('Kano', 'Gabasawa'),
  ('Kano', 'Garko'),
  ('Kano', 'Garun Mallam'),
  ('Kano', 'Gaya'),
  ('Kano', 'Gezawa'),
  ('Kano', 'Gwale'),
  ('Kano', 'Gwarzo'),
  ('Kano', 'Kabo'),
  ('Kano', 'Kano Municipal'),
  ('Kano', 'Karaye'),
  ('Kano', 'Kibiya'),
  ('Kano', 'Kiru'),
  ('Kano', 'Kumbotso'),
  ('Kano', 'Kunchi'),
  ('Kano', 'Kura'),
  ('Kano', 'Madobi'),
  ('Kano', 'Makoda'),
  ('Kano', 'Minjibir'),
  ('Kano', 'Nasarawa'),
  ('Kano', 'Rano'),
  ('Kano', 'Rimin Gado'),
  ('Kano', 'Rogo'),
  ('Kano', 'Shanono'),
  ('Kano', 'Sumaila'),
  ('Kano', 'Takai'),
  ('Kano', 'Tarauni'),
  ('Kano', 'Tofa'),
  ('Kano', 'Tsanyawa'),
  ('Kano', 'Tudun Wada'),
  ('Kano', 'Ungogo'),
  ('Kano', 'Warawa'),
  ('Kano', 'Wudil'),
  ('Katsina', 'Bakori'),
  ('Katsina', 'Batagarawa'),
  ('Katsina', 'Batsari'),
  ('Katsina', 'Baure'),
  ('Katsina', 'Bindawa'),
  ('Katsina', 'Charanchi'),
  ('Katsina', 'Dandume'),
  ('Katsina', 'Danja'),
  ('Katsina', 'Dan Musa'),
  ('Katsina', 'Daura'),
  ('Katsina', 'Dutsi'),
  ('Katsina', 'Dutsin Ma'),
  ('Katsina', 'Faskari'),
  ('Katsina', 'Funtua'),
  ('Katsina', 'Ingawa'),
  ('Katsina', 'Jibia'),
  ('Katsina', 'Kafur'),
  ('Katsina', 'Kaita'),
  ('Katsina', 'Kankara'),
  ('Katsina', 'Kankia'),
  ('Katsina', 'Katsina'),
  ('Katsina', 'Kurfi'),
  ('Katsina', 'Kusada'),
  ('Katsina', 'Mai''Adua'),
  ('Katsina', 'Malumfashi'),
  ('Katsina', 'Mani'),
  ('Katsina', 'Mashi'),
  ('Katsina', 'Matazu'),
  ('Katsina', 'Musawa'),
  ('Katsina', 'Rimi'),
  ('Katsina', 'Sabuwa'),
  ('Katsina', 'Safana'),
  ('Katsina', 'Sandamu'),
  ('Katsina', 'Zango'),
  ('Kebbi', 'Aleiro'),
  ('Kebbi', 'Arewa Dandi'),
  ('Kebbi', 'Argungu'),
  ('Kebbi', 'Augie'),
  ('Kebbi', 'Bagudo'),
  ('Kebbi', 'Birnin Kebbi'),
  ('Kebbi', 'Bunza'),
  ('Kebbi', 'Dandi'),
  ('Kebbi', 'Fakai'),
  ('Kebbi', 'Gwandu'),
  ('Kebbi', 'Jega'),
  ('Kebbi', 'Kalgo'),
  ('Kebbi', 'Koko/Besse'),
  ('Kebbi', 'Maiyama'),
  ('Kebbi', 'Ngaski'),
  ('Kebbi', 'Sakaba'),
  ('Kebbi', 'Shanga'),
  ('Kebbi', 'Suru'),
  ('Kebbi', 'Wasagu/Danko'),
  ('Kebbi', 'Yauri'),
  ('Kebbi', 'Zuru'),
  ('Kogi', 'Adavi'),
  ('Kogi', 'Ajaokuta'),
  ('Kogi', 'Ankpa'),
  ('Kogi', 'Bassa'),
  ('Kogi', 'Dekina'),
  ('Kogi', 'Ibaji'),
  ('Kogi', 'Idah'),
  ('Kogi', 'Igalamela Odolu'),
  ('Kogi', 'Ijumu'),
  ('Kogi', 'Kabba/Bunu'),
  ('Kogi', 'Kogi'),
  ('Kogi', 'Lokoja'),
  ('Kogi', 'Mopa Muro'),
  ('Kogi', 'Ofu'),
  ('Kogi', 'Ogori/Magongo'),
  ('Kogi', 'Okehi'),
  ('Kogi', 'Okene'),
  ('Kogi', 'Olamaboro'),
  ('Kogi', 'Omala'),
  ('Kogi', 'Yagba East'),
  ('Kogi', 'Yagba West'),
  ('Kwara', 'Asa'),
  ('Kwara', 'Baruten'),
  ('Kwara', 'Edu'),
  ('Kwara', 'Ekiti'),
  ('Kwara', 'Ifelodun'),
  ('Kwara', 'Ilorin East'),
  ('Kwara', 'Ilorin South'),
  ('Kwara', 'Ilorin West'),
  ('Kwara', 'Irepodun'),
  ('Kwara', 'Isin'),
  ('Kwara', 'Kaiama'),
  ('Kwara', 'Moro'),
  ('Kwara', 'Offa'),
  ('Kwara', 'Oke Ero'),
  ('Kwara', 'Oyun'),
  ('Kwara', 'Pategi'),
  ('Lagos', 'Agege'),
  ('Lagos', 'Ajeromi-Ifelodun'),
  ('Lagos', 'Alimosho'),
  ('Lagos', 'Amuwo-Odofin'),
  ('Lagos', 'Apapa'),
  ('Lagos', 'Badagry'),
  ('Lagos', 'Epe'),
  ('Lagos', 'Eti Osa'),
  ('Lagos', 'Ibeju-Lekki'),
  ('Lagos', 'Ifako-Ijaiye'),
  ('Lagos', 'Ikeja'),
  ('Lagos', 'Ikorodu'),
  ('Lagos', 'Kosofe'),
  ('Lagos', 'Lagos Island'),
  ('Lagos', 'Lagos Mainland'),
  ('Lagos', 'Mushin'),
  ('Lagos', 'Ojo'),
  ('Lagos', 'Oshodi-Isolo'),
  ('Lagos', 'Shomolu'),
  ('Lagos', 'Surulere'),
  ('Nasarawa', 'Akwanga'),
  ('Nasarawa', 'Awe'),
  ('Nasarawa', 'Doma'),
  ('Nasarawa', 'Karu'),
  ('Nasarawa', 'Keana'),
  ('Nasarawa', 'Keffi'),
  ('Nasarawa', 'Kokona'),
  ('Nasarawa', 'Lafia'),
  ('Nasarawa', 'Nasarawa'),
  ('Nasarawa', 'Nasarawa Egon'),
  ('Nasarawa', 'Obi'),
  ('Nasarawa', 'Toto'),
  ('Nasarawa', 'Wamba'),
  ('Niger', 'Agaie'),
  ('Niger', 'Agwara'),
  ('Niger', 'Bida'),
  ('Niger', 'Borgu'),
  ('Niger', 'Bosso'),
  ('Niger', 'Chanchaga'),
  ('Niger', 'Edati'),
  ('Niger', 'Gbako'),
  ('Niger', 'Gurara'),
  ('Niger', 'Katcha'),
  ('Niger', 'Kontagora'),
  ('Niger', 'Lapai'),
  ('Niger', 'Lavun'),
  ('Niger', 'Magama'),
  ('Niger', 'Mariga'),
  ('Niger', 'Mashegu'),
  ('Niger', 'Mokwa'),
  ('Niger', 'Moya'),
  ('Niger', 'Paikoro'),
  ('Niger', 'Rafi'),
  ('Niger', 'Rijau'),
  ('Niger', 'Shiroro'),
  ('Niger', 'Suleja'),
  ('Niger', 'Tafa'),
  ('Niger', 'Wushishi'),
  ('Ogun', 'Abeokuta North'),
  ('Ogun', 'Abeokuta South'),
  ('Ogun', 'Ado-Odo/Ota'),
  ('Ogun', 'Egbado North'),
  ('Ogun', 'Egbado South'),
  ('Ogun', 'Ewekoro'),
  ('Ogun', 'Ifo'),
  ('Ogun', 'Ijebu East'),
  ('Ogun', 'Ijebu North'),
  ('Ogun', 'Ijebu North East'),
  ('Ogun', 'Ijebu Ode'),
  ('Ogun', 'Ikenne'),
  ('Ogun', 'Imeko Afon'),
  ('Ogun', 'Ipokia'),
  ('Ogun', 'Obafemi Owode'),
  ('Ogun', 'Odeda'),
  ('Ogun', 'Odogbolu'),
  ('Ogun', 'Ogun Waterside'),
  ('Ogun', 'Remo North'),
  ('Ogun', 'Shagamu'),
  ('Ondo', 'Akoko North-East'),
  ('Ondo', 'Akoko North-West'),
  ('Ondo', 'Akoko South-West'),
  ('Ondo', 'Akoko South-East'),
  ('Ondo', 'Akure North'),
  ('Ondo', 'Akure South'),
  ('Ondo', 'Ese Odo'),
  ('Ondo', 'Idanre'),
  ('Ondo', 'Ifedore'),
  ('Ondo', 'Ilaje'),
  ('Ondo', 'Ile Oluji/Okeigbo'),
  ('Ondo', 'Irele'),
  ('Ondo', 'Odigbo'),
  ('Ondo', 'Okitipupa'),
  ('Ondo', 'Ondo East'),
  ('Ondo', 'Ondo West'),
  ('Ondo', 'Ose'),
  ('Ondo', 'Owo'),
  ('Osun', 'Atakunmosa East'),
  ('Osun', 'Atakunmosa West'),
  ('Osun', 'Aiyedaade'),
  ('Osun', 'Aiyedire'),
  ('Osun', 'Boluwaduro'),
  ('Osun', 'Boripe'),
  ('Osun', 'Ede North'),
  ('Osun', 'Ede South'),
  ('Osun', 'Efe'),
  ('Osun', 'Ejigbo'),
  ('Osun', 'Ifedayo'),
  ('Osun', 'Ifelodun'),
  ('Osun', 'Ila'),
  ('Osun', 'Ilesa East'),
  ('Osun', 'Ilesa West'),
  ('Osun', 'Irepodun'),
  ('Osun', 'Irewole'),
  ('Osun', 'Isokan'),
  ('Osun', 'Iwo'),
  ('Osun', 'Obokun'),
  ('Osun', 'Odo Otin'),
  ('Osun', 'Ola Oluwa'),
  ('Osun', 'Olorunda'),
  ('Osun', 'Oriade'),
  ('Osun', 'Orolu'),
  ('Osun', 'Osogbo'),
  ('Oyo', 'Afijio'),
  ('Oyo', 'Akinyele'),
  ('Oyo', 'Atiba'),
  ('Oyo', 'Atisbo'),
  ('Oyo', 'Egbeda'),
  ('Oyo', 'Ibadan North'),
  ('Oyo', 'Ibadan North-East'),
  ('Oyo', 'Ibadan North-West'),
  ('Oyo', 'Ibadan South-East'),
  ('Oyo', 'Ibadan South-West'),
  ('Oyo', 'Ibarapa Central'),
  ('Oyo', 'Ibarapa East'),
  ('Oyo', 'Ibarapa North'),
  ('Oyo', 'Ido'),
  ('Oyo', 'Irepo'),
  ('Oyo', 'Iseyin'),
  ('Oyo', 'Itesiwaju'),
  ('Oyo', 'Iwajowa'),
  ('Oyo', 'Kajola'),
  ('Oyo', 'Lagelu'),
  ('Oyo', 'Ogbomosho North'),
  ('Oyo', 'Ogbomosho South'),
  ('Oyo', 'Ogo Oluwa'),
  ('Oyo', 'Olorunsogo'),
  ('Oyo', 'Oluyole'),
  ('Oyo', 'Ona Ara'),
  ('Oyo', 'Orelope'),
  ('Oyo', 'Ori Ire'),
  ('Oyo', 'Oyo East'),
  ('Oyo', 'Oyo West'),
  ('Oyo', 'Saki East'),
  ('Oyo', 'Saki West'),
  ('Oyo', 'Surulere'),
  ('Plateau', 'Bokkos'),
  ('Plateau', 'Barkin Ladi'),
  ('Plateau', 'Bassa'),
  ('Plateau', 'Jos East'),
  ('Plateau', 'Jos North'),
  ('Plateau', 'Jos South'),
  ('Plateau', 'Kanam'),
  ('Plateau', 'Kanke'),
  ('Plateau', 'Langtang North'),
  ('Plateau', 'Langtang South'),
  ('Plateau', 'Mangu'),
  ('Plateau', 'Mikang'),
  ('Plateau', 'Pankshin'),
  ('Plateau', 'Qua''an Pan'),
  ('Plateau', 'Riyom'),
  ('Plateau', 'Shendam'),
  ('Plateau', 'Wase'),
  ('Rivers', 'Abua/Odual'),
  ('Rivers', 'Ahoada East'),
  ('Rivers', 'Ahoada West'),
  ('Rivers', 'Akuku-Toru'),
  ('Rivers', 'Andoni'),
  ('Rivers', 'Asari-Toru'),
  ('Rivers', 'Bonny'),
  ('Rivers', 'Degema'),
  ('Rivers', 'Eleme'),
  ('Rivers', 'Emohua'),
  ('Rivers', 'Etche'),
  ('Rivers', 'Gokana'),
  ('Rivers', 'Ikwerre'),
  ('Rivers', 'Khana'),
  ('Rivers', 'Obio/Akpor'),
  ('Rivers', 'Ogba/Egbema/Ndoni'),
  ('Rivers', 'Ogu/Bolo'),
  ('Rivers', 'Okrika'),
  ('Rivers', 'Omuma'),
  ('Rivers', 'Opobo/Nkoro'),
  ('Rivers', 'Oyigbo'),
  ('Rivers', 'Port Harcourt'),
  ('Rivers', 'Tai'),
  ('Sokoto', 'Binji'),
  ('Sokoto', 'Bodinga'),
  ('Sokoto', 'Dange Shuni'),
  ('Sokoto', 'Gada'),
  ('Sokoto', 'Goronyo'),
  ('Sokoto', 'Gudu'),
  ('Sokoto', 'Gwadabawa'),
  ('Sokoto', 'Illela'),
  ('Sokoto', 'Isa'),
  ('Sokoto', 'Kebbe'),
  ('Sokoto', 'Kware'),
  ('Sokoto', 'Rabah'),
  ('Sokoto', 'Sabon Birni'),
  ('Sokoto', 'Shagari'),
  ('Sokoto', 'Silame'),
  ('Sokoto', 'Sokoto North'),
  ('Sokoto', 'Sokoto South'),
  ('Sokoto', 'Tambuwal'),
  ('Sokoto', 'Tangaza'),
  ('Sokoto', 'Tureta'),
  ('Sokoto', 'Wamako'),
  ('Sokoto', 'Wurno'),
  ('Sokoto', 'Yabo'),
  ('Taraba', 'Ardo Kola'),
  ('Taraba', 'Bali'),
  ('Taraba', 'Donga'),
  ('Taraba', 'Gashaka'),
  ('Taraba', 'Gassol'),
  ('Taraba', 'Ibi'),
  ('Taraba', 'Jalingo'),
  ('Taraba', 'Karim Lamido'),
  ('Taraba', 'Kumi'),
  ('Taraba', 'Lau'),
  ('Taraba', 'Sardauna'),
  ('Taraba', 'Takum'),
  ('Taraba', 'Ussa'),
  ('Taraba', 'Wukari'),
  ('Taraba', 'Yorro'),
  ('Taraba', 'Zing'),
  ('Yobe', 'Bade'),
  ('Yobe', 'Bursari'),
  ('Yobe', 'Damaturu'),
  ('Yobe', 'Fika'),
  ('Yobe', 'Fune'),
  ('Yobe', 'Geidam'),
  ('Yobe', 'Gujba'),
  ('Yobe', 'Gulani'),
  ('Yobe', 'Jakusko'),
  ('Yobe', 'Karasuwa'),
  ('Yobe', 'Machina'),
  ('Yobe', 'Nangere'),
  ('Yobe', 'Nguru'),
  ('Yobe', 'Potiskum'),
  ('Yobe', 'Tarmuwa'),
  ('Yobe', 'Yunusari'),
  ('Yobe', 'Yusufari'),
  ('Zamfara', 'Anka'),
  ('Zamfara', 'Bakura'),
  ('Zamfara', 'Birnin Magaji/Kiyaw'),
  ('Zamfara', 'Bukkuyum'),
  ('Zamfara', 'Bungudu'),
  ('Zamfara', 'Gummi'),
  ('Zamfara', 'Gusau'),
  ('Zamfara', 'Kaura Namoda'),
  ('Zamfara', 'Maradun'),
  ('Zamfara', 'Maru'),
  ('Zamfara', 'Shinkafi'),
  ('Zamfara', 'Talata Mafara'),
  ('Zamfara', 'Chafe'),
  ('Zamfara', 'Zurmi');

-- Reference data: readable by every signed-in client (and anon, like the rest
-- of the location data the app ships), writable only by the service role.
alter table public.nigeria_states enable row level security;
alter table public.nigeria_lgas enable row level security;
revoke insert, update, delete on public.nigeria_states, public.nigeria_lgas from anon, authenticated;
create policy nigeria_states_select on public.nigeria_states for select to anon, authenticated using (true);
create policy nigeria_lgas_select on public.nigeria_lgas for select to anon, authenticated using (true);

comment on table public.nigeria_states is
  'The 36 states + FCT, canonical spellings. Seeded from lib/core/data/nigeria_locations_data.dart; read-only to clients.';
comment on table public.nigeria_lgas is
  'The 770 LGAs by state, canonical spellings. Seeded from lib/core/data/nigeria_locations_data.dart; read-only to clients. alerts.target_state / target_lga are foreign keys into it.';

-- ── Pre-existing alerts ─────────────────────────────────────────────────────
--
-- The rule, in order. Nothing here ever widens an alert's audience: a target
-- is only ever canonicalised, narrowed to the one state it can mean, or the
-- alert is set aside.
--
--   1. 'all' / ' All ' in target_lga is normalised to 'All', and a state that
--      is a known state under a different casing/padding is canonicalised.
--   2. A (state, LGA) pair that matches a real pair case-insensitively is
--      rewritten to the canonical spelling of both.
--   3. An alert with an LGA and no state whose LGA name belongs to exactly one
--      state adopts that state (this is 20260927070000's backfill again, now
--      driven from the table above, so it also catches casing variants).
--   4. Anything still unresolvable — an ambiguous LGA name with no state, an
--      LGA that is in no state at all, an unknown state — is COPIED to
--      public.alerts_unresolved_target with the reason and DELETED from
--      public.alerts, and the migration raises a WARNING naming each one.
--      Deleting is the only non-widening option left: the row cannot be kept
--      (it cannot satisfy the constraint), and the alternatives — blanking the
--      LGA, or setting target_lga = 'All' — would turn an alert meant for one
--      LGA into one for a whole state or the whole country. The alert is kept
--      verbatim in the quarantine table so an admin can read it and re-issue
--      it with the right state.
--
-- The live database has no alerts at all at the time of writing, so on it
-- every step below is a no-op; the steps exist for any other deployment.
--
-- Safety: alerts only queue a notification_outbox row from the AFTER INSERT
-- trigger alerts_after_insert, so these UPDATEs and DELETEs send no push. The
-- BEFORE UPDATE triggers are alerts_touch (bumps updated_at) and
-- alerts_guard_author (rejects a change of created_by, untouched here).

create table public.alerts_unresolved_target (
  id            uuid primary key,
  title         text not null,
  message       text not null default '',
  severity      text not null default 'info',
  target_lga    text,
  target_state  text,
  report_id     uuid,
  created_by    uuid,
  is_active     boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  reason        text not null,
  quarantined_at timestamptz not null default now()
);

-- Not a client table: it holds alerts that were removed, and is read from the
-- SQL editor (service role) when the WARNING below fires.
alter table public.alerts_unresolved_target enable row level security;
revoke all on public.alerts_unresolved_target from anon, authenticated;

comment on table public.alerts_unresolved_target is
  'Alerts removed by 20260927080000 because their target could not be resolved to one (state, LGA). Kept verbatim so an admin can re-issue them with a state. Service role only.';

-- 1. Normalise the 'All' sentinel and the state spelling.
update public.alerts
   set target_lga = 'All'
 where lower(btrim(target_lga)) = 'all'
   and target_lga <> 'All';

update public.alerts a
   set target_state = s.name
  from public.nigeria_states s
 where a.target_state is not null
   and lower(btrim(a.target_state)) = lower(s.name)
   and a.target_state <> s.name;

-- 2. Canonicalise a (state, LGA) pair that is real apart from case/padding.
update public.alerts a
   set target_state = l.state,
       target_lga   = l.lga
  from public.nigeria_lgas l
 where a.target_state is not null
   and lower(btrim(a.target_lga)) <> 'all'
   and lower(btrim(a.target_state)) = lower(l.state)
   and lower(btrim(a.target_lga)) = lower(l.lga)
   and (a.target_state, a.target_lga) is distinct from (l.state, l.lga);

-- 3. An LGA name that belongs to exactly one state fixes its own state.
update public.alerts a
   set target_state = u.state,
       target_lga   = u.lga
  from (
    select lower(lga) as key, min(state) as state, min(lga) as lga
      from public.nigeria_lgas
     group by lower(lga)
    having count(*) = 1
  ) u
 where a.target_state is null
   and lower(btrim(a.target_lga)) = u.key;

-- 4. Set aside whatever is left, loudly.
with unresolved as (
  select a.*,
         case
           when a.target_state is not null
             and not exists (select 1 from public.nigeria_states s where s.name = a.target_state)
             then format('target_state %L is not a Nigerian state', a.target_state)
           when a.target_state is null and exists (
                  select 1 from public.nigeria_lgas l where lower(l.lga) = lower(btrim(a.target_lga)))
             then format('target_lga %L is an LGA of more than one state and the alert names none', a.target_lga)
           when a.target_state is null
             then format('target_lga %L is not an LGA of any state and the alert names no state', a.target_lga)
           else format('%L is not an LGA of %L', a.target_lga, a.target_state)
         end as reason
    from public.alerts a
   where (a.target_state is null and lower(btrim(a.target_lga)) <> 'all')
      or (a.target_state is not null
          and not exists (select 1 from public.nigeria_states s where s.name = a.target_state))
      or (a.target_state is not null
          and lower(btrim(a.target_lga)) <> 'all'
          and not exists (select 1 from public.nigeria_lgas l
                           where l.state = a.target_state and l.lga = btrim(a.target_lga)))
)
insert into public.alerts_unresolved_target
  (id, title, message, severity, target_lga, target_state, report_id, created_by,
   is_active, created_at, updated_at, reason)
select id, title, message, severity, target_lga, target_state, report_id, created_by,
       is_active, created_at, updated_at, reason
  from unresolved;

delete from public.alerts a
 using public.alerts_unresolved_target q
 where q.id = a.id;

do $$
declare
  n bigint;
  r record;
begin
  select count(*) into n from public.alerts_unresolved_target;
  if n > 0 then
    raise warning 'alert_state_required: % alert(s) had a target that cannot be resolved to one (state, LGA). They were moved to public.alerts_unresolved_target and removed from public.alerts. Re-issue each one with a state:', n;
    for r in select id, title, target_lga, target_state, reason
               from public.alerts_unresolved_target order by created_at loop
      raise warning '  alert % (%): % [target_lga=%, target_state=%]',
        r.id, r.title, r.reason, r.target_lga, coalesce(r.target_state, 'NULL');
    end loop;
  end if;
end $$;

-- ── The constraint ──────────────────────────────────────────────────────────
--
-- target_lga_canonical is target_lga with 'All' (in any casing) collapsed to
-- NULL, so the composite foreign key below is simply not checked for an
-- "every LGA" alert (MATCH SIMPLE: a partly-NULL key passes). It exists only
-- to carry that foreign key; nothing reads it, and nothing writes it.

alter table public.alerts add column target_lga_canonical text
  generated always as (
    case when lower(btrim(target_lga)) = 'all' then null else btrim(target_lga) end
  ) stored;

-- The structural rule, independent of the reference tables: naming an LGA
-- means naming its state. Only 'All' may stand alone.
alter table public.alerts add constraint alerts_target_lga_needs_state
  check (target_state is not null or lower(btrim(target_lga)) = 'all');

-- The state must be a real state...
alter table public.alerts add constraint alerts_target_state_fkey
  foreign key (target_state) references public.nigeria_states (name);

-- ...and a named LGA must be one of that state's. (No ON UPDATE action: a
-- generated column may not take one, and renaming canonical reference data
-- should be a deliberate migration that updates the alerts too, not a silent
-- cascade.)
alter table public.alerts add constraint alerts_target_lga_fkey
  foreign key (target_state, target_lga_canonical)
  references public.nigeria_lgas (state, lga);

comment on column public.alerts.target_state is
  'State the alert targets: every LGA of it when target_lga = ''All'', otherwise the state target_lga belongs to. NULL only with target_lga = ''All'' (everyone, everywhere) — an LGA without a state is rejected by alerts_target_lga_needs_state.';
comment on column public.alerts.target_lga is
  'LGA the alert targets, spelled as in public.nigeria_lgas, or ''All'' for every LGA of target_state (or everyone when target_state is NULL).';
comment on column public.alerts.target_lga_canonical is
  'Generated: btrim(target_lga), or NULL when target_lga is ''All''. Exists only to carry alerts_target_lga_fkey; do not read or write it.';
