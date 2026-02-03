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
        'title': 'Flood Response Checklist',
        'content': '''**Before a Flood:**
• Know your flood risk - Check FEMA flood maps for your area
• Sign up for community warning systems and local alerts
• Prepare an emergency kit with water, food, flashlight, battery radio, and first-aid supplies
• Move valuable items and important documents to higher levels
• Consider flood insurance (standard policies don't cover flood damage)
• Clear drains and gutters
• Install a sump pump with battery backup
• Create a family evacuation plan

**During a Flood:**
• Evacuate immediately if instructed by authorities
• NEVER walk, swim or drive through floodwaters (6 inches can knock you down, 12 inches can sweep away a vehicle)
• If trapped in a building, go to the highest floor (avoid closed attics)
• Listen for emergency broadcasts
• Stay away from downed power lines

**After a Flood:**
• Return home only when authorities say it's safe
• Avoid floodwaters - they may be contaminated or electrically charged
• Document damage with photos for insurance
• Clean and disinfect everything that got wet
• Check for structural damage before re-entering buildings''',
        'category': 'Flood',
        'tags': ['safety', 'emergency', 'preparedness'],
        'source': 'FEMA/Ready.gov',
        'sourceUrl': 'https://www.ready.gov/floods',
        'createdAt': now,
        'updatedAt': now,
      },

      // WILDFIRE GUIDES
      {
        'title': 'Wildfire Reporting & Response Protocol',
        'content': '''**How to Report a Wildfire:**
• Call emergency services immediately (local emergency number)
• Provide exact location (coordinates if possible)
• Describe smoke color, flame height, and direction of spread
• Note any threatened structures or populated areas
• Stay on the line for questions

**Before Wildfire Season:**
• Create defensible space around your home (30 feet minimum)
• Clear leaves, debris, and flammable materials
• Use fire-resistant building materials
• Assemble emergency supply kit
• Plan evacuation routes with family
• Back up important documents digitally

**During a Wildfire:**
• Evacuate immediately if ordered
• Monitor local news and emergency alerts
• Wear N95 mask to protect from smoke
• Close all windows and doors
• Turn on lights to increase visibility in heavy smoke
• Remember the "Five Ps": People & Pets, Prescriptions, Papers, Personal needs, Priceless items

**After a Wildfire:**
• Wait for official all-clear before returning
• Watch for hot ash, charred trees, and smoldering debris
• Wet down debris to minimize dust
• Wear protective gear during cleanup (gloves, long sleeves, N95 respirator)''',
        'category': 'Fire',
        'tags': ['wildfire', 'fire safety', 'emergency'],
        'source': 'FEMA/CAL FIRE',
        'sourceUrl': 'https://www.ready.gov/wildfires',
        'createdAt': now,
        'updatedAt': now,
      },

      // DROUGHT GUIDES
      {
        'title': 'Drought Preparedness & Response',
        'content': '''**Before a Drought:**
• Conserve water - fix leaks, install low-flow fixtures
• Store water in safe containers
• Mulch gardens to retain moisture
• Plant drought-resistant crops and native plants
• Create a water conservation plan

**During a Drought:**
• Limit water use for essential needs only
• Reuse water when possible (greywater for plants)
• Avoid outdoor watering during peak heat
• Monitor local water restrictions
• Protect livestock with adequate water supply
• Watch for signs of water stress in crops

**Health & Safety:**
• Stay hydrated - drink plenty of water
• Protect skin from sun exposure
• Watch for heat-related illnesses
• Ensure sanitation with limited water
• Monitor air quality (drought increases dust)

**Long-term Planning:**
• Diversify water sources (wells, rainwater harvesting  )
• Improve soil health to retain moisture
• Plan crop rotation for drought resilience
• Participate in community water conservation programs''',
        'category': 'Drought',
        'tags': ['drought', 'water conservation', 'farming'],
        'source': 'FEMA/CDC',
        'sourceUrl': 'https://www.ready.gov/drought',
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
