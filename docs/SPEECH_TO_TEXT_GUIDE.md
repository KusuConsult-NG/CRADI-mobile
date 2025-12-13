# Speech-to-Text Feature - User Guide

## 🎤 Voice Input for Description Fields

The CRADI Mobile app now supports **FREE speech-to-text** functionality, allowing you to dictate your hazard reports instead of typing!

## ✨ Features

- **Real-time transcription**: See your words appear as you speak
- **Animated microphone button**: Visual feedback when recording
- **Character counter**: Track your description length (max 500 characters)
- **Automatic punctuation**: In English and supported languages
- **Partial results**: Text updates as you speak

## 🚀 How to Use

### Step 1: Navigate to Report Details
1. Start creating a new hazard report
2. Select hazard type and severity
3. Choose location
4. Proceed to the **Report Details** screen

### Step 2: Activate Voice Input
1. Look for the **microphone icon** (🎙️) in the bottom-right of the description field
2. Tap the microphone button
3. **First time**: You'll be asked to grant microphone permission - tap "Allow"

### Step 3: Start Speaking
1. When the microphone turns **RED** and glows, it's listening
2. You'll see "**Listening... Speak now**" below the description field
3. Speak clearly and naturally in English
4. Watch your words appear in real-time!

### Step 4: Stop Recording
1. Tap the microphone button again to stop
2. Review and edit your text if needed
3. Continue with your report

## 📱 Platform Support

### ✅ **Supported Platforms**
- **Android**: Full support with microphone permission
- **iOS**: Full support with microphone permission
- **Web (Chrome/Edge)**: Supported with browser permission

### ⚠️ **Browser Compatibility (Web)**
- **Chrome/Edge**: ✅ Full support
- **Firefox**: ⚠️ Limited support
- **Safari**: ⚠️ May require HTTPS

## 🗣️ Language Support

Currently optimized for:
- **English** (US, UK, AU, etc.)

Additional languages can be added based on your device's speech recognition capabilities.

## 💡 Tips for Best Results

### ✅ **DO:**
- Speak clearly and at a normal pace
- Use in a quiet environment
- Hold device at comfortable distance
- Pause briefly between sentences
- Say punctuation if needed ("period", "comma", "question mark")

### ❌ **DON'T:**
- Speak too fast or too slow
- Use in very noisy environments
- Cover the microphone
- Speak from too far away

## 🔒 Privacy & Permissions

### Microphone Permission
- **Android**: Granted through app permissions
- **iOS**: Granted through app permissions
- **Web**: Granted through browser permissions

### Data Privacy
- ✅ Speech processing happens **on-device**
- ✅ Your voice is **NOT recorded or stored**
- ✅ Only the transcribed text is saved
- ✅ No audio data sent to servers

## 🎯 Visual Indicators

| State | Icon | Color | Message |
|-------|------|-------|---------|
| **Ready** | 🎙️ mic_none | Light Red | "Be specific about location..." |
| **Listening** | 🎙️ mic (filled) | Bright Red (glowing) | "Listening... Speak now" |
| **Not Available** | 🎙️ mic_off | Gray | "Speech recognition not available" |

## 🐛 Troubleshooting

### "Speech recognition not available"
**Solutions**:
1. Check microphone permissions in device settings
2. Ensure device has microphone hardware
3. Try restarting the app
4. On web: Use Chrome or Edge browser

### Microphone button not working
**Solutions**:
1. Check if permission was granted
2. Tap the button again
3. Wait a moment after opening the screen
4. Check browser console for errors (web only)

### Text not appearing
**Solutions**:
1. Speak louder and clearer
2. Move to a quieter location
3. Check internet connection (some devices need it)
4. Try speaking in shorter phrases

### Permission denied
**Solutions**:
1. **Android**: Settings → Apps → CRADI Mobile → Permissions → Microphone → Allow
2. **iOS**: Settings → Privacy → Microphone → CRADI Mobile → Enable
3. **Web**: Click the 🎙️ icon in browser address bar → Allow microphone

## 🔧 Technical Details

### Package Used
- `speech_to_text: ^7.0.0`

### Permissions Added
- **Android**: `RECORD_AUDIO`, `MICROPHONE`
- **iOS**: Microphone usage description in Info.plist

### Features Implemented
- Real-time transcription
- Partial results display
- Error handling with user feedback
- Character count updating
- Animated UI states
- Automatic locale detection

## 📊 Character Limit

- **Maximum**: 500 characters
- **Counter**: Updates in real-time
- **Warning**: Turns red when exceeding limit
- **Recommendation**: Keep descriptions concise and specific

## 🎓 Example Usage

### Good Description (via Voice):
> "Flooding on main road near central market. Water level approximately 2 feet. Three vehicles stranded. Road completely blocked. Situation worsening due to heavy rain."

### Poor Description (via Voice):
> "Um... there's like... you know... some water and stuff... it's bad... yeah..."

## 🆘 Need Help?

If speech-to-text isn't working:
1. Check the troubleshooting section above
2. Try typing instead (always available)
3. Contact your coordinator if issues persist
4. Report bugs through the app's Help & Support

## 🔄 Updates & Improvements

**Coming Soon:**
- Multi-language support
- Voice commands ("new paragraph", "delete last sentence")
- Background noise filtering
- Offline speech recognition

---

**Remember**: Voice input is designed to make reporting faster and easier, especially in field conditions. If it's not working well, you can always type your description manually!
