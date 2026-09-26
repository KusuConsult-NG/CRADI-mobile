-- Built-in content moves out of the app and into the database, where admins
-- manage it (web admin: Knowledge Base, News Links, Settings):
-- 1. The 10 safety guides the app used to bundle are seeded into
--    knowledge_base (the placeholder SEMA phone number is replaced with a
--    pointer to the app's Emergency Contacts screen).
-- 2. news_links: curated links the app shows when the live ReliefWeb feed is
--    unavailable (previously hard-coded, one with a dead '#' link).
-- 3. support_email setting (previously hard-coded in the Help screen).
-- Seed rows use fixed ids (on conflict do nothing), so admin edits to them are
-- never overwritten by a re-seed.

insert into public.knowledge_base (id, title, content, source, category, hazard_type, image_url) values
  ('a5fd2620-6d5a-5d98-a0fd-5877944ab528', 'River Benue Flooding Protocols', $seed$**Early Warning Indicators:**
• Heavy rainfall reports from upstream regions (Cameroon/Lagdo Dam releases).
• Unusual rise in River Benue and local tributaries.
• Flash-flood alerts via CRADI app or local authorities.

**Before a Flood:**
• Move valuables, livestock, and essential documents to higher ground or designated secure community centers.
• Prepare an emergency Go-Bag with 3 days of water, non-perishable food, and a battery/solar radio.
• Identify the nearest high-ground community evacuation route (avoiding known washout zones).
• Secure your crops if possible and clear local drainage channels.

**During a Flood:**
• Evacuate IMMEDIATELY to higher ground when ordered by SEMA or the State Emergency Response Team.
• NEVER walk, swim, or drive through floodwaters (6 inches of moving water can sweep a person away).
• Listen exclusively to official local broadcasts (Radio Benue, Joy FM) or CRADI alerts.
• Stay entirely clear of downed power lines and transformers.

**Emergency Contacts:**
• National Emergency Toll-Free: 112
• Your State Emergency Management Agency (SEMA): see Emergency Contacts in the app
• NEMA North Central Office: Jos, Plateau State$seed$, 'Benue SEMA / NEMA', 'Flood', 'flood', 'https://images.unsplash.com/photo-1504701954957-2010ec3bcec1?auto=format&fit=crop&q=80&w=800'),
  ('fa566a96-2090-5ac6-af78-034f16d23451', 'Gully Erosion Mitigation (Nasarawa/Plateau Context)', $seed$**Recognizing Erosion Threats:**
• Sudden cracks appearing in community roads or near building foundations.
• Rapid widening of existing gullies after heavy seasonal rains.
• Exposed tree roots or leaning utility poles along embankments.

**Preventative Measures (Dry Season):**
• Plant deep-rooted native grasses (like Vetiver grass) and bamboo along vulnerable slopes to bind the soil.
• Construct community sandbag barriers or stone-pitching at the head of advancing gullies.
• Do NOT dump refuse in erosion channels or natural waterways; this blocks flow and destroys banks.
• Practice terraced farming on hillsides (especially in Plateau State) to reduce water runoff speed.

**Emergency Response (Heavy Rains):**
• Keep children and livestock completely away from gully edges (banks can collapse without warning).
• If a building is threatened, evacuate immediately and notify local authorities via the CRADI app.
• Do not attempt to cross flooded gullies during rainstorms.

**Where to Report:**
• Report expanding gullies immediately via CRADI to alert NEWMAP (Nigeria Erosion and Watershed Management Project) and local works ministries.$seed$, 'NEMA / NEWMAP', 'Erosion', 'erosion', 'https://images.unsplash.com/photo-1509316785289-025f5b846b35?auto=format&fit=crop&q=80&w=800'),
  ('51ea6c2c-ce4a-5be3-91ec-1c327add7ab9', 'Extreme Heat Survival (Makurdi/Lafia Corridors)', $seed$**Understanding the Threat:**
• Extended dry seasons with temperatures routinely exceeding 38°C (100°F).
• High risk of heatstroke for outdoor workers, farmers, and the elderly.

**Safety Protocols:**
• **Hydration:** Drink plenty of clean water constantly, even if you do not feel thirsty. Avoid excessive sugary or alcoholic drinks.
• **Shelter:** Seek shade during peak sun hours (11:00 AM to 4:00 PM). Ensure good cross-ventilation in homes.
• **Clothing:** Wear loose-fitting, light-colored cotton clothing to reflect heat.
• **Farming Adjustments:** Shift heavy labor to early morning (before 10 AM) or late afternoon.

**Recognizing Heatstroke:**
• Symptoms: High body temperature, hot/dry/red skin, rapid pulse, dizziness, nausea, or confusion.
• **Action:** This is a medical emergency. Move the person to shade immediately, actively cool them with wet cloths, and transport to the nearest Primary Healthcare Center (PHC).

**Livestock Care:**
• Provide natural shade structures or planting trees for livestock.
• Ensure constant access to clean, cool drinking water for all animals to prevent mass dehydration.$seed$, 'Federal Ministry of Health / NiMet', 'Extreme Heat', 'extreme_heat', 'https://images.unsplash.com/photo-1504192010706-dd7f569ee2be?auto=format&fit=crop&q=80&w=800'),
  ('074a4313-796f-5902-8a45-fc30b9487bff', 'Bush Fire & Urban Fire Response', $seed$**Prevention & Preparedness:**
• Avoid indiscriminate bush burning (slash-and-burn agriculture) during the peak dry season or Harmattan.
• Create firebreaks (cleared pathways of at least 10 meters) around farms and vulnerable settlements.
• Keep fire extinguishers accessible in urban homes, and never leave cooking gas or firewood unattended.
• Do not discard cigarette butts or glass bottles in dry grass.

**During a Fire:**
• Evacuate upwind of the fire immediately. Do not attempt to outrun a fast-moving fire uphill.
• In an urban building fire, crawl low under the smoke where the air is cleaner.
• Use the CRADI app to alert the community and deploy the local emergency response volunteer network.
• If trapped in bush, find a cleared area or water body, lie flat, and cover your mouth with a wet cloth to filter smoke.

**Post-Fire Recovery:**
• Do not return until local authorities declare the area totally clear of smoldering hazards.
• Watch for "hot spots" that can flare up with wind.
• Protect respiratory health from lingering smoke by wearing masks (N95 or heavy cloth).$seed$, 'Federal Fire Service', 'Fire', 'fire', 'https://images.unsplash.com/photo-1516912481808-3406841bd33c?auto=format&fit=crop&q=80&w=800'),
  ('1f5190b6-576b-5f2b-8be9-4779fc4d400f', 'Communal Conflict & Security Preparedness (Middle Belt Context)', $seed$**Early Warning Indicators:**
• Reports of stolen livestock, destroyed crops, or violent skirmishes in neighboring communities.
• Unusual mass movement of nomadic groups or sudden influx of displaced persons.
• Circulation of inflammatory messages, hate speech, or unverified rumors on social media or local gatherings.
• Sudden withdrawal of ethnic or religious groups from shared markets.

**Preparedness & Prevention:**
• Engage continuously with local Peace and Reconciliation Committees (PRCs) and inter-faith dialogue groups.
• Avoid sharing unverified provocative images or voice notes (fake news). Verify information through community leaders or the CRADI app.
• Identify safe havens (e.g., heavily guarded central zones, designated religious grounds, or police compounds).
• Keep emergency contacts of local vigilante commanders, police DPOs, and military task force units handy.

**During an Outbreak of Violence:**
• Secure your family indoors if the threat is external, or evacuate immediately to pre-identified safe havens if your area is directly targeted.
• Avoid nighttime travel entirely. Stick to major, well-patrolled roads if movement is absolutely necessary.
• Report ongoing attacks immediately via the CRADI app so that EWER networks can alert joint military and police task forces.

**Post-Conflict Protocol:**
• Do not engage in retaliatory attacks; this perpetuates the cycle of violence.
• Assist IDPs (Internally Displaced Persons) with basic needs and report their numbers to SEMA for relief coordination.
• Cooperate fully with security agencies and human rights monitors gathering evidence.$seed$, 'Institute for Peace and Conflict Resolution (IPCR)', 'Conflict', 'conflict', 'https://images.unsplash.com/photo-1599059813005-11265ba4b4ce?auto=format&fit=crop&q=80&w=800'),
  ('c83d5158-6dbc-5773-be9c-64cca9069dc2', 'Road Traffic & Industrial Accident Response', $seed$**Road Traffic Accidents (RTA):**
• **Secure the Scene:** Park your vehicle at a safe distance with hazard lights on. Put out reflective warning triangles at least 50 meters behind the accident to warn oncoming traffic.
• **Assessment:** Check if victims are responsive. Do NOT move a severely injured person (especially neck/back injuries) unless there is immediate danger of fire or explosion.
• **Alerting:** Use the CRADI app to call the Federal Road Safety Corps (FRSC) (Toll-free: 122) and nearby medical emergency services.
• **First Aid:** Administer CPR only if trained. Use clean cloth to apply firm, direct pressure to severely bleeding wounds.

**Industrial & Farming Accidents:**
• **Machine Entanglement:** Immediately shut off the power source. Do not attempt to reverse the machinery unless trained to do so safely.
• **Chemical Spills (Agrochemicals/Pesticides):** Evacuate the immediate area. If chemicals contact the skin or eyes, flush continuously with clean water for at least 15 minutes. Remove contaminated clothing. Seek medical help immediately.
• **Falls from Height:** Do not move the victim. Keep them warm and wait for emergency medical transport.

**General Safety Rule:**
Always carry a well-stocked First Aid kit in your vehicle and on large farming sites. Document the incident details safely for police and insurance reports.$seed$, 'Federal Road Safety Corps (FRSC)', 'Accident', 'accident', 'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?auto=format&fit=crop&q=80&w=800'),
  ('d8539b52-b279-5fd6-94b3-16d5d4ba68b9', 'Storm & Severe Weather Safety', $seed$**Before a Storm:**
• Monitor weather forecasts and warnings
• Prepare emergency kit: water, non-perishable food, flashlight, battery radio
• Charge phones and backup power banks
• Secure outdoor objects that could blow away
• Know your evacuation routes
• Trim trees and branches near buildings

**During Thunderstorms:**
• Go indoors to a sturdy building
• Avoid windows and doors
• Unplug electronics
• Do not use corded phones
• Stay away from plumbing and running water
• If outdoors: avoid tall objects, seek low ground

**During High Winds:**
• Stay indoors away from windows
• Close all interior doors
• Go to an interior room on the lowest floor
• If in vehicle: park safely and stay inside

**After the Storm:**
• Wait for official all-clear
• Watch for fallen power lines
• Avoid flooded areas
• Document damage for insurance
• Use flashlights, not candles
• Check on neighbors, especially elderly$seed$, 'NOAA/FEMA', 'Storm', 'storm', 'https://images.unsplash.com/photo-1535350356005-fd52b3b524fb?auto=format&fit=crop&q=80&w=800'),
  ('6dc6401f-e70a-5650-92c7-34d8a5a9a54f', 'Earthquake Preparedness & Response', $seed$**Before an Earthquake:**
• Secure heavy furniture and appliances to walls
• Store heavy items on lower shelves
• Identify safe spots in each room (under sturdy furniture, against interior walls)
• Prepare emergency kit with supplies for 72 hours
• Practice "Drop, Cover, and Hold On" drills
• Know how to turn off utilities (gas, water, electricity)

**During an Earthquake:**
• DROP to hands and knees
• take COVER under sturdy furniture
• HOLD ON until shaking stops
• If indoors: stay inside, away from windows
• If outdoors: move to open area away from buildings
• If in vehicle: pull over and stay inside
• DO NOT run outside or stand in doorways

**After an Earthquake:**
• Check yourself and others for injuries
• Inspect home for damage
• Expect aftershocks
• Turn off gas if you smell or hear leaking
• Use SMS instead of phone calls
• Stay away from damaged buildings
• Listen to emergency broadcasts
• Help neighbors who may need assistance
• Move inland and to higher ground immediately if near coast$seed$, 'FEMA/USGS', 'Earthquake', 'earthquake', 'https://images.unsplash.com/photo-1548337138-e87d889cc369?auto=format&fit=crop&q=80&w=800'),
  ('f4bb8a6f-db2f-5107-ae3c-e5f5bb1a53fc', 'Epidemic & Disease Outbreak Response', $seed$**Prevention & Preparedness:**
• Stay informed through official health sources (NCDC, WHO).
• Practice good hygiene: wash hands frequently (20 seconds with soap) and use sanitizer.
• Maintain clean living environment. Dispose of refuse properly to prevent cholera and malaria vectors.
• Keep vaccinations up to date (yellow fever, meningitis, measles, etc.).
• Stock 30-day supply of personal medications.

**During an Outbreak:**
• Follow official Nigeria Centre for Disease Control (NCDC) guidelines.
• Maintain social distancing as advised.
• Wear masks if recommended by health authorities (especially for respiratory diseases like COVID-19 or Lassa fever prevention).
• Store food securely in rat-proof containers to prevent Lassa Fever transmission.
• Avoid touching face with unwashed hands and disinfect frequently-touched surfaces.

**If You Get Sick:**
• Isolate yourself from others in household.
• Stay home except to get medical care.
• Wear a mask when around others and cover coughs/sneezes.
• Seek prompt medical attention, especially for high fever or severe symptoms. Do not rely entirely on self-medication.
• Notify close contacts.

**Community Protection:**
• Support vulnerable populations (elderly, immunocompromised).
• Combat misinformation and share only official NCDC updates.
• Report clusters of unusual sickness in the community via the CRADI app.$seed$, 'NCDC / WHO', 'Disease', 'disease', 'https://images.unsplash.com/photo-1588681664899-f142ff2dc9b1?auto=format&fit=crop&q=80&w=800'),
  ('a538ef91-3b9b-565e-b903-49e9150b1f7a', 'General Safety & Emergency Kit Essentials', $seed$**Basic Emergency Supply Kit:**

**Water & Food:**
• 1 gallon of water per person per day (3-day supply)
• Non-perishable food (3-day supply, e.g., garri, canned beans, groundnuts)
• Manual can opener
• Baby formula and food (if applicable)

**First Aid:**
• First aid kit (bandages, antiseptic wipes, iodine)
• Prescription medications (7-day supply)
• Over-the-counter medications (pain relievers, anti-diarrhea, anti-malaria)
• Medical equipment (hearing aids, glasses)

**Tools & Supplies:**
• Battery-powered or hand-crank radio (NOAA or local stations)
• Flashlight with extra batteries (or fully charged solar torch)
• Whistle (to signal for help)
• Moist towelettes, garbage bags for sanitation
• Basic tools to turn off utilities.

**Documents & Money:**
• Copies of important documents (ID cards, insurance policies, land titles). Store in a waterproof container or ziplock bag.
• Emergency cash (small denominations as ATMs may not work during crises).

**Communication:**
• Charged cell phone with chargers and backup power bank.
• Emergency contact list written on paper.
 
**Stay vigilant:**
Always have an evacuation plan and discuss it with your household members regularly.$seed$, 'FEMA / Red Cross / SEMA', 'Safety', 'safety', 'https://images.unsplash.com/photo-1496247749665-49cf5b1022e9?auto=format&fit=crop&q=80&w=800')
on conflict (id) do nothing;

create table public.news_links (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(btrim(title)) between 1 and 300),
  url         text not null check (url ~* '^https?://[^[:space:]]+$' and length(url) <= 2000),
  source      text not null default '' check (length(source) <= 120),
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index news_links_order_idx on public.news_links (sort_order, created_at);

create trigger news_links_touch before update on public.news_links
  for each row execute function public.touch_updated_at();

alter table public.news_links enable row level security;

create policy news_links_select on public.news_links for select to authenticated
  using (is_active or public.app_role() in ('admin', 'techSupport'));

create policy news_links_write on public.news_links for all to authenticated
  using (public.app_role() in ('admin', 'techSupport'))
  with check (public.app_role() in ('admin', 'techSupport'));

insert into public.news_links (id, title, url, source, sort_order) values
  ('bbf2766b-49fb-5d84-b7dd-b6ff6ac3f4ca', 'Flood Safety: What to do before, during, and after', 'https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/flood.html', 'Safety Guide', 10),
  ('bd5faf7e-9426-599b-abee-95444292d858', 'NiMet Seasonal Climate Prediction', 'https://nimet.gov.ng/', 'NiMet', 20),
  ('f925b3cf-9525-54c5-a784-a0afeeb79942', 'Emergency Contact Directory: Nigeria', 'https://www.redcrossnigeria.org/', 'Red Cross', 30),
  ('4c7598b5-dc7f-561b-9afe-6f12cc62fb6c', 'Understanding Early Warning Systems', 'https://www.undrr.org/terminology/early-warning-system', 'UNDRR', 40)
on conflict (id) do nothing;

insert into public.app_settings (key, value) values
  ('support_email', '"support@cradi.org"')
on conflict (key) do nothing;
