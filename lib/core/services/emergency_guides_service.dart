/// Service for fetching disaster preparedness content
/// Uses curated content based on FEMA/CDC/Red Cross guidelines
class EmergencyGuidesService {
  /// Fetch hazard-specific emergency guides
  Future<List<Map<String, dynamic>>> fetchGuides({
    String? hazardType,
    int limit = 20,
  }) async {
    // Return curated emergency response guides
    // Based on FEMA, Red Cross, and CDC guidelines
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
  /// Based on FEMA, American Red Cross, and CDC guidelines
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
        'createdAt': now,
        'updatedAt': now,
      },

      // WILDFIRE / BUSH FIRE GUIDES
      {
        'title': 'Bush Fire / Wildfire Response',
        'content': '''**Prevention & Preparedness:**
• Avoid indiscriminate bush burning (slash-and-burn agriculture) during the peak dry season or Harmattan.
• Create firebreaks (cleared pathways of at least 10 meters) around farms and vulnerable settlements.
• Do not discard cigarette butts or glass bottles in dry grass.

**During a Bush Fire:**
• Evacuate upwind of the fire immediately. Do not attempt to outrun a fast-moving fire uphill.
• Use the CRADI app to alert the community and deploy the local emergency response volunteer network.
• If trapped, find a cleared area or water body, lie flat, and cover your mouth with a wet cloth to filter smoke.

**Post-Fire Recovery:**
• Do not return until local authorities declare the area totally clear of smoldering hazards.
• Watch for "hot spots" that can flare up with wind.
• Protect respiratory health from lingering smoke by wearing masks (N95 or heavy cloth).''',
        'category': 'Wildfires',
        'tags': ['harmattan', 'bush burning', 'smoke'],
        'source': 'Federal Fire Service',
        'sourceUrl': 'https://fire.gov.ng',
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
• Take COVER under sturdy furniture
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

**Tsunami Warning (if near coast):**
• Move inland and to higher ground immediately
• Stay away from coast until all-clear is given''',
        'category': 'Earthquake',
        'tags': ['earthquake', 'seismic', 'tsunami'],
        'source': 'FEMA/USGS',
        'sourceUrl': 'https://www.ready.gov/earthquakes',
        'createdAt': now,
        'updatedAt': now,
      },

      // EPIDEMIC/PANDEMIC GUIDES
      {
        'title': 'Epidemic & Disease Outbreak Response',
        'content': '''**Prevention & Preparedness:**
• Stay informed through official health sources
• Practice good hygiene: wash hands frequently (20 seconds with soap)
• Maintain clean living environment
• Keep vaccinations up to date
• Stock 30-day supply of medications
• Prepare 2-week supply of food and water

**During an Outbreak:**
• Follow official health guidelines
• Maintain social distancing as advised
• Wear masks if recommended by health authorities
• Avoid touching face with unwashed hands
• Disinfect frequently-touched surfaces
• Monitor your health for symptoms
• Isolate if you feel ill

**If You Get Sick:**
• Stay home except to get medical care
• Separate yourself from others in household
• Wear a mask when around others
• Cover coughs and sneezes
• Clean and disinfect surfaces daily
• Seek medical attention if symptoms worsen
• Notify close contacts

**Community Protection:**
• Support vulnerable populations (elderly, immunocompromised)
• Share reliable information from official sources
• Combat misinformation
• Follow quarantine orders if issued
• Maintain mental health - stay connected virtually''',
        'category': 'Epidemic',
        'tags': ['disease', 'pandemic', 'health', 'outbreak'],
        'source': 'CDC/WHO',
        'sourceUrl': 'https://www.cdc.gov/emergency-preparedness',
        'createdAt': now,
        'updatedAt': now,
      },

      // GENERAL EMERGENCY PREPAREDNESS
      {
        'title': 'Emergency Kit Essentials',
        'content': '''**Basic Emergency Supply Kit:**

**Water & Food:**
• 1 gallon of water per person per day (3-day supply)
• Non-perishable food (3-day supply)
• Manual can opener
• Baby formula and food (if applicable)
• Pet food and water

**First Aid:**
• First aid kit
• Prescription medications (7-day supply)
• Over-the-counter medications (pain relievers, anti-diarrhea, etc.)
• Glasses/contact lenses
• Medical equipment (hearing aids, wheelchair, etc.)

**Tools & Supplies:**
• Battery-powered or hand-crank radio (NOAA Weather Radio)
• Flashlight with extra batteries
• Whistle (to signal for help)
• Dust masks, plastic sheeting, duct tape
• Moist towelettes, garbage bags
• Wrench or pliers (to turn off utilities)
• Local maps

**Documents & Money:**
• Copies of important documents (ID, insurance policies, bank records)
• Store in waterproof container
• Emergency cash

**Communication:**
• Charged cell phone with chargers and backup battery
• Emergency contact list
 
**Additional Items:**
• Sleeping bag or blanket per person
• Change of clothing and sturdy shoes
• Fire extinguisher
• Matches in waterproof container
• Feminine supplies and personal hygiene items
• Books, games, puzzles for children''',
        'category': 'General',
        'tags': ['emergency kit', 'preparedness', 'supplies'],
        'source': 'FEMA/Red Cross',
        'sourceUrl': 'https://www.ready.gov/kit',
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
      'Drought',
      'Storm',
      'Earthquake',
      'Epidemic',
      'General',
    ];
  }
}
