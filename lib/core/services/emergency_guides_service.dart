/// Service for fetching disaster preparedness content
/// Uses curated content based on FEMA/CDC/Red Cross and local guidelines
class EmergencyGuidesService {
  /// Fetch hazard-specific emergency guides
  Future<List<Map<String, dynamic>>> fetchGuides({
    String? hazardType,
    int limit = 20,
  }) async {
    // Return curated emergency response guides
    final guides = _getCuratedGuides();

    if (hazardType != null && hazardType != 'All') {
      return guides
          .where((guide) => guide['category'] == hazardType)
          .take(limit)
          .toList();
    }

    return guides.take(limit).toList();
  }

  /// Get professionally curated emergency guides
  List<Map<String, dynamic>> _getCuratedGuides() {
    final now = DateTime.now().toIso8601String();

    return [
      // FLOOD GUIDES
      {
        'title': 'River Benue Flooding Protocols',
        'content': '''**Early Warning Indicators:**
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
• Benue SEMA Headquarters: 0803 000 0000 (Replace with live local SEMA line)
• NEMA North Central Office: Jos, Plateau State''',
        'category': 'Flood',
        'tags': ['safety', 'river benue', 'lagdo dam', 'evacuation'],
        'source': 'Benue SEMA / NEMA',
        'sourceUrl': 'https://nema.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1504701954957-2010ec3bcec1?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // EROSION & GULLY GUIDES
      {
        'title': 'Gully Erosion Mitigation (Nasarawa/Plateau Context)',
        'content': '''**Recognizing Erosion Threats:**
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
• Report expanding gullies immediately via CRADI to alert NEWMAP (Nigeria Erosion and Watershed Management Project) and local works ministries.''',
        'category': 'Erosion',
        'tags': ['gully', 'landslide', 'newmap', 'conservation'],
        'source': 'NEMA / NEWMAP',
        'sourceUrl': 'https://nema.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1509316785289-025f5b846b35?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // EXTREME HEAT GUIDES
      {
        'title': 'Extreme Heat Survival (Makurdi/Lafia Corridors)',
        'content': '''**Understanding the Threat:**
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
• Ensure constant access to clean, cool drinking water for all animals to prevent mass dehydration.''',
        'category': 'Extreme Heat',
        'tags': ['heatwave', 'hydration', 'farming', 'health'],
        'source': 'Federal Ministry of Health / NiMet',
        'sourceUrl': 'https://health.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1504192010706-dd7f569ee2be?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // FIRE / WILDFIRE GUIDES
      {
        'title': 'Bush Fire & Urban Fire Response',
        'content': '''**Prevention & Preparedness:**
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
• Protect respiratory health from lingering smoke by wearing masks (N95 or heavy cloth).''',
        'category': 'Fire',
        'tags': ['harmattan', 'bush burning', 'smoke', 'fire'],
        'source': 'Federal Fire Service',
        'sourceUrl': 'https://fire.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1516912481808-3406841bd33c?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // CONFLICT GUIDES
      {
        'title':
            'Communal Conflict & Security Preparedness (Middle Belt Context)',
        'content': '''**Early Warning Indicators:**
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
• Cooperate fully with security agencies and human rights monitors gathering evidence.''',
        'category': 'Conflict',
        'tags': ['security', 'peace', 'clashes', 'safety'],
        'source': 'Institute for Peace and Conflict Resolution (IPCR)',
        'sourceUrl': 'https://ipcr.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1599059813005-11265ba4b4ce?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // ACCIDENT GUIDES
      {
        'title': 'Road Traffic & Industrial Accident Response',
        'content': '''**Road Traffic Accidents (RTA):**
• **Secure the Scene:** Park your vehicle at a safe distance with hazard lights on. Put out reflective warning triangles at least 50 meters behind the accident to warn oncoming traffic.
• **Assessment:** Check if victims are responsive. Do NOT move a severely injured person (especially neck/back injuries) unless there is immediate danger of fire or explosion.
• **Alerting:** Use the CRADI app to call the Federal Road Safety Corps (FRSC) (Toll-free: 122) and nearby medical emergency services.
• **First Aid:** Administer CPR only if trained. Use clean cloth to apply firm, direct pressure to severely bleeding wounds.

**Industrial & Farming Accidents:**
• **Machine Entanglement:** Immediately shut off the power source. Do not attempt to reverse the machinery unless trained to do so safely.
• **Chemical Spills (Agrochemicals/Pesticides):** Evacuate the immediate area. If chemicals contact the skin or eyes, flush continuously with clean water for at least 15 minutes. Remove contaminated clothing. Seek medical help immediately.
• **Falls from Height:** Do not move the victim. Keep them warm and wait for emergency medical transport.

**General Safety Rule:**
Always carry a well-stocked First Aid kit in your vehicle and on large farming sites. Document the incident details safely for police and insurance reports.''',
        'category': 'Accident',
        'tags': ['rta', 'frsc', 'first aid', 'spills'],
        'source': 'Federal Road Safety Corps (FRSC)',
        'sourceUrl': 'https://frsc.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // STORM GUIDES
      {
        'title': 'Storm & Severe Weather Safety',
        'content': '''**Before a Storm:**
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
• Check on neighbors, especially elderly''',
        'category': 'Storm',
        'tags': ['storm', 'severe weather', 'lightning'],
        'source': 'NOAA/FEMA',
        'sourceUrl': 'https://www.ready.gov/severe-weather',
        'imageUrl':
            'https://images.unsplash.com/photo-1535350356005-fd52b3b524fb?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // EARTHQUAKE GUIDES
      {
        'title': 'Earthquake Preparedness & Response',
        'content': '''**Before an Earthquake:**
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
• Move inland and to higher ground immediately if near coast''',
        'category': 'Earthquake',
        'tags': ['earthquake', 'seismic', 'tremor'],
        'source': 'FEMA/USGS',
        'sourceUrl': 'https://www.ready.gov/earthquakes',
        'imageUrl':
            'https://images.unsplash.com/photo-1548337138-e87d889cc369?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // DISEASE / EPIDEMIC GUIDES
      {
        'title': 'Epidemic & Disease Outbreak Response',
        'content': '''**Prevention & Preparedness:**
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
• Report clusters of unusual sickness in the community via the CRADI app.''',
        'category': 'Disease',
        'tags': ['disease', 'pandemic', 'health', 'outbreak', 'ncdc'],
        'source': 'NCDC / WHO',
        'sourceUrl': 'https://ncdc.gov.ng',
        'imageUrl':
            'https://images.unsplash.com/photo-1588681664899-f142ff2dc9b1?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },

      // SAFETY / GENERAL EMERGENCY PREPAREDNESS
      {
        'title': 'General Safety & Emergency Kit Essentials',
        'content': '''**Basic Emergency Supply Kit:**

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
Always have an evacuation plan and discuss it with your household members regularly.''',
        'category': 'Safety',
        'tags': ['emergency kit', 'preparedness', 'supplies', 'safety'],
        'source': 'FEMA / Red Cross / SEMA',
        'sourceUrl': 'https://www.ready.gov/kit',
        'imageUrl':
            'https://images.unsplash.com/photo-1496247749665-49cf5b1022e9?auto=format&fit=crop&q=80&w=800',
        'createdAt': now,
        'updatedAt': now,
      },
    ];
  }

  /// Get available disaster types
  List<String> getDisasterTypes() {
    return [
      'All',
      'Flood',
      'Fire',
      'Accident',
      'Erosion',
      'Disease',
      'Conflict',
      'Safety',
      'Extreme Heat',
      'Storm',
      'Earthquake',
    ];
  }
}
