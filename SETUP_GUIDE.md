# CharBar Setup Guide

This document covers:

1. **Auto-updates with Sparkle** (replacing the old custom update system)
2. **Changing the app icon**
3. **Hosting your website on Vercel**

---

## 1. Auto-Updates with Sparkle

CharBar uses [Sparkle](https://sparkle-project.org/), the industry-standard open-source update framework used by thousands of macOS apps (iTerm, Cyberduck, Things, HandBrake, etc.). It handles everything: checking for updates, showing a native update dialog, downloading, and installing, all seamlessly.

### What persists across updates?

Sparkle replaces only the `.app` bundle. Everything else stays:

| Data | Persists? | Where it's stored |
|------|-----------|-------------------|
| License keys (@AppStorage) | Yes | ~/Library/Preferences/ |
| UserDefaults settings | Yes | ~/Library/Preferences/ |
| Keychain items | Yes | macOS Keychain |
| App Support files | Yes | ~/Library/Application Support/ |

### Step 1: Add Sparkle to the Xcode project

1. Open `CharBar.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Paste this URL: `https://github.com/sparkle-project/Sparkle`
4. Set "Dependency Rule" to **Up to Next Major Version**, starting at `2.0.0`
5. Click **Add Package**
6. When prompted to choose products, select **Sparkle** (not SparkleTestTools)
7. Make sure it's added to the **CharBar** target
8. Click **Add Package**

### Step 2: Generate signing keys

Sparkle uses EdDSA (Ed25519) signatures to verify updates are authentic.

```bash
# After adding Sparkle via SPM, find the generate_keys tool:
# It's inside the Sparkle package in DerivedData. Easiest approach:

# Build the project once in Xcode (⌘B), then run:
find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -type f 2>/dev/null | head -1

# Or download Sparkle directly and use the bundled tool:
# https://github.com/sparkle-project/Sparkle/releases
# Unzip → look in bin/generate_keys

# Run generate_keys (first time creates a new keypair):
./generate_keys
```

This outputs:
```
A]  Public key to embed in your app's Info.plist:
    <YOUR_EDDSA_PUBLIC_KEY>

B]  Private key saved to Keychain. Use `generate_keys -x` to export if needed.
```

**Copy the public key** and paste it into `CharBar/Info.plist` replacing `REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY`:

```xml
<key>SUPublicEDKey</key>
<string>paste-your-actual-public-key-here</string>
```

**Important:** The private key is stored in your macOS Keychain. Back it up:
```bash
./generate_keys -x > sparkle_private_key.txt
# Store this file somewhere VERY safe (not in git!)
```

### Step 3: Set up the appcast URL

The appcast is an XML feed that tells Sparkle about available updates. Update `Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://charbar.app/appcast.xml</string>
```

You can host the appcast on:
- **Your website** (charbar.app/appcast.xml), recommended
- **GitHub Pages** (yourusername.github.io/charbar/appcast.xml)
- **Raw GitHub** (raw.githubusercontent.com/...), works but less professional

### Step 4: Build and archive your app

1. **Bump the version** in Xcode:
   - Target → General → Version: `1.0.1`
   - Target → General → Build: `2`

2. **Archive**:
   - Product → Archive
   - In Organizer: "Distribute App" → "Copy App"
   - This gives you `CharBar.app`

3. **Zip the app** (Sparkle expects a `.zip`, not `.dmg`):
   ```bash
   # Create a zip archive
   cd /path/to/exported/
   zip -r -y CharBar-1.0.1.zip CharBar.app
   ```

### Step 5: Sign the zip with Sparkle

```bash
# Find the sign_update tool (same location as generate_keys):
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1

# Sign the zip:
./sign_update CharBar-1.0.1.zip

# Output:
# sparkle:edSignature="ABCD1234...long-base64-string..." length="12345678"
```

**Save both the `edSignature` and `length`**: you need them for the appcast.

### Step 6: Upload the zip

Upload the signed `.zip` to wherever you host releases:

```bash
# Option A: GitHub Releases
gh release create v1.0.1 \
  --title "CharBar v1.0.1" \
  --notes "Bug fixes and improvements" \
  CharBar-1.0.1.zip

# Option B: Your website's /downloads/ folder
# Upload to charbar.app/downloads/CharBar-1.0.1.zip
```

### Step 7: Create the appcast.xml

You can either write it manually or use Sparkle's `generate_appcast` tool.

#### Option A: Use generate_appcast (recommended)

```bash
# Put all your signed .zip release files in one folder:
mkdir releases
cp CharBar-1.0.1.zip releases/

# Generate the appcast:
./generate_appcast releases/

# This creates releases/appcast.xml automatically
```

#### Option B: Write manually

Create `appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>CharBar Updates</title>
    <link>https://charbar.app/appcast.xml</link>
    <description>CharBar release feed</description>
    <language>en</language>
    <item>
      <title>Version 1.0.1</title>
      <description><![CDATA[
        <ul>
          <li>Fixed a bug with the floating bar</li>
          <li>Improved Bluetooth reconnection speed</li>
          <li>New background images added</li>
        </ul>
      ]]></description>
      <pubDate>Sun, 08 Mar 2026 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/YOUR_USERNAME/charbar-releases/releases/download/v1.0.1/CharBar-1.0.1.zip"
        sparkle:version="2"
        sparkle:shortVersionString="1.0.1"
        length="PASTE_LENGTH_HERE"
        type="application/octet-stream"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"/>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
```

### Step 8: Host the appcast

Upload `appcast.xml` to your website so it's accessible at the `SUFeedURL` you set in Info.plist.

If using Vercel for your website (see Section 3), just put `appcast.xml` in your `public/` folder.

### Release checklist (every new version)

```
1. Bump version + build number in Xcode
2. Archive → Export → Zip the .app
3. Sign the zip:        ./sign_update CharBar-x.x.x.zip
4. Upload zip to GitHub Releases (or your server)
5. Regenerate appcast:  ./generate_appcast releases/
   (or manually update appcast.xml with new item)
6. Upload appcast.xml to charbar.app/appcast.xml
7. Done. Existing users get notified automatically
```

### How Sparkle works at runtime

```
App launches
    ↓
Sparkle checks SUFeedURL automatically (configurable interval)
    ↓
Parses appcast.xml, compares version/build to current app
    ↓
If newer version found → shows native update dialog
(with YOUR app icon, release notes, Download/Skip/Later buttons)
    ↓
User clicks "Install Update"
    ↓
Sparkle downloads the zip, verifies EdDSA signature
    ↓
Replaces the .app bundle, relaunches
    ↓
All settings, license keys, preferences are preserved
```

### Settings in CharBar

The Updates section in General settings provides:
- **Check for Updates** button (triggers `SPUUpdater.checkForUpdates()`)
- **Automatically check for updates** toggle
- **Auto-download updates when available** toggle
- Last checked date

---

## 2. Changing the App Icon

The app icon lives in `CharBar/Assets.xcassets/AppIcon.appiconset/`.

### Required sizes

| File | Size | Purpose |
|------|------|---------|
| 16.png | 16×16 | Menu bar, Finder sidebar (1x) |
| 32.png | 32×32 | Finder (1x) |
| 32 1.png | 32×32 | Menu bar (2x) |
| 64.png | 64×64 | Finder (2x) |
| 128.png | 128×128 | Spotlight (1x) |
| 256.png | 256×256 | Finder, Spotlight (1x) |
| 256 1.png | 256×256 | Spotlight (2x) |
| 512.png | 512×512 | About window (1x) |
| 512 1.png | 512×512 | About window (2x) |
| 1024.png | 1024×1024 | App Store (2x) |

### Steps to change the icon

#### Option A: Using Xcode (easiest)

1. Open `CharBar.xcodeproj`
2. Navigate to `Assets.xcassets` → `AppIcon`
3. Drag your 1024×1024 PNG into the 1024pt @2x slot
4. Xcode 15+ auto-generates all smaller sizes

#### Option B: Manual with sips

```bash
cd CharBar/Assets.xcassets/AppIcon.appiconset

sips -z 16 16 ~/Desktop/icon-1024.png --out 16.png
sips -z 32 32 ~/Desktop/icon-1024.png --out 32.png
sips -z 32 32 ~/Desktop/icon-1024.png --out "32 1.png"
sips -z 64 64 ~/Desktop/icon-1024.png --out 64.png
sips -z 128 128 ~/Desktop/icon-1024.png --out 128.png
sips -z 256 256 ~/Desktop/icon-1024.png --out 256.png
sips -z 256 256 ~/Desktop/icon-1024.png --out "256 1.png"
sips -z 512 512 ~/Desktop/icon-1024.png --out 512.png
sips -z 512 512 ~/Desktop/icon-1024.png --out "512 1.png"
cp ~/Desktop/icon-1024.png 1024.png
```

Then clean build: Product → Clean Build Folder (⌘⇧K)

#### Option C: Online tools

- https://www.appicon.co
- https://icon.kitchen

Upload 1024×1024 → download macOS set → replace files in the appiconset folder.

### Tips

- macOS icons should be square; the OS applies the rounded-rect mask
- Keep important details within the center 80%
- Test at 16px to ensure readability

---

## 3. Hosting Your Website on Vercel

### Prerequisites

- GitHub account
- Website code (HTML, Next.js, or any framework)
- Domain name (optional; Vercel gives a free `.vercel.app` subdomain)

### Step 1: Create your website

Fastest start with Next.js:

```bash
npx create-next-app@latest charbar-website
cd charbar-website
```

Or use plain HTML, just have an `index.html`.

Push to a GitHub repository.

### Step 2: Sign up for Vercel

1. Go to https://vercel.com
2. **Sign Up** → **Continue with GitHub**
3. Authorize Vercel

### Step 3: Import and deploy

1. Dashboard → **Add New...** → **Project**
2. Select your GitHub repo
3. Click **Deploy**
4. Live in ~30 seconds at `https://charbar-website.vercel.app`

### Step 4: Connect your custom domain

1. Project → **Settings** → **Domains**
2. Type `charbar.app` → **Add**
3. Add DNS records at your registrar:

   **Option A: Vercel nameservers (recommended)**
   ```
   ns1.vercel-dns.com
   ns2.vercel-dns.com
   ```

   **Option B: A/CNAME records**
   - A record: `@` → `76.76.21.21`
   - CNAME: `www` → `cname.vercel-dns.com`

4. Vercel auto-provisions HTTPS

### Step 5: Automatic deployments

Every push to `main` triggers an auto-deploy:

```bash
git add .
git commit -m "Update landing page"
git push origin main
# → Vercel deploys in ~30s
```

### Hosting the appcast on your Vercel site

Put `appcast.xml` in your website's `public/` folder:

```
charbar-website/
├── public/
│   ├── appcast.xml          ← Sparkle checks this
│   ├── favicon.ico
│   └── og-image.png
├── app/
│   ├── page.tsx             (landing page)
│   └── privacy/page.tsx     (privacy policy)
└── package.json
```

After deploying, it's live at `https://charbar.app/appcast.xml`.

### Useful Vercel config

Add `vercel.json` for a download redirect:

```json
{
  "redirects": [
    {
      "source": "/download",
      "destination": "https://github.com/YOUR_USERNAME/charbar-releases/releases/latest",
      "permanent": false
    }
  ],
  "headers": [
    {
      "source": "/appcast.xml",
      "headers": [
        { "key": "Content-Type", "value": "application/xml" },
        { "key": "Cache-Control", "value": "public, max-age=300" }
      ]
    }
  ]
}
```

---

## Code Signing & Notarization (required for distribution)

For users to open CharBar without Gatekeeper warnings:

1. **Apple Developer account** ($99/year): https://developer.apple.com

2. **Code-sign**: Xcode handles this automatically when you Archive with your Team selected in Signing & Capabilities

3. **Notarize the zip**:
   ```bash
   xcrun notarytool submit CharBar-1.0.1.zip \
     --apple-id "your@email.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "app-specific-password" \
     --wait

   xcrun stapler staple CharBar.app
   # Then re-zip after stapling
   zip -r -y CharBar-1.0.1.zip CharBar.app
   # Then sign with Sparkle's sign_update
   ```

4. Create an app-specific password at https://appleid.apple.com → Sign-In & Security → App-Specific Passwords

---

## Quick Reference

| Task | Location / Command |
|------|--------------------|
| Sparkle package | SPM: `https://github.com/sparkle-project/Sparkle` |
| Appcast URL | `CharBar/Info.plist` → `SUFeedURL` |
| EdDSA public key | `CharBar/Info.plist` → `SUPublicEDKey` |
| Generate keys | `./generate_keys` (from Sparkle tools) |
| Sign a release | `./sign_update CharBar-x.x.x.zip` |
| Generate appcast | `./generate_appcast releases/` |
| App icon assets | `CharBar/Assets.xcassets/AppIcon.appiconset/` |
| Vercel deploy | Push to `main` → auto-deploys |
| Report an issue | https://github.com/MonishSoundarRaj/CharBar/issues |
