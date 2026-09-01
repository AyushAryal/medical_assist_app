# Release runbook — TestFlight & App Store

How to cut a test (or store) build of this app. Repo-side readiness is already
done (see the "Prep for App Store" commit); this is the repeatable checklist for
the parts that live in Xcode / App Store Connect.

Bundle ID: `com.ayusharyal.medicalApp` · Min iOS: 15.5 · Version: `pubspec.yaml`
`version:` (e.g. `1.0.0+1` → CFBundleShortVersionString `1.0.0`, build `1`).

---

## 0. One-time prerequisites

- **Paid Apple Developer Program** membership (org or individual). A free
  personal team cannot upload to TestFlight/App Store.
- The **app record exists in App Store Connect** for `com.ayusharyal.medicalApp`.
  Creating it needs an **Admin / App Manager** role — a Developer role usually
  cannot. (App Store Connect → Apps → + → New App.)
- Your Apple ID (with the org team) is signed into **Xcode → Settings →
  Accounts**.

## 1. Bump the version

Edit `pubspec.yaml` `version:` — increment the build number every upload (App
Store Connect rejects a duplicate build for the same version):

```
version: 1.0.0+2   # marketing 1.0.0, build 2
```

## 2. Signing (once per machine/team)

Open the **workspace** (not the project):

```
open ios/Runner.xcworkspace
```

Runner target → **Signing & Capabilities** → ✅ Automatically manage signing →
**Team = your org team**. This writes `DEVELOPMENT_TEAM`; Xcode provisions the
distribution certificate/profile (cloud-managed, so a Developer role does not
need to hold the cert).

Also confirm **`ios/Runner/PrivacyInfo.xcprivacy`** is a member of the Runner
target (File Inspector → Target Membership → Runner). Add it if missing
(right-click Runner → Add Files → tick Runner).

## 3. Build the archive

**Option A — Xcode (simplest for a first upload):**
1. Destination → **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. Organizer → **Distribute App → App Store Connect → Upload** → defaults →
   Upload.

**Option B — CLI:** set the team in `ios/ExportOptions.plist` (`teamID`) then:

```
flutter build ipa --export-options-plist=ios/ExportOptions.plist
# → build/ios/ipa/*.ipa  — upload with Transporter (Mac App Store app) or:
xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

Do **not** pass `--dart-define=ALLOW_DEMO_DATA=true` for a release build — a
store/TestFlight build must ship with demo data and debug auto-provisioning
compiled out (they are gated on `demoDataAllowed`, which is false without the
flag and in release).

## 4. TestFlight (internal — fastest)

App Store Connect → your app → **TestFlight**:
- The build shows as "Processing" for a few minutes, then "Ready to Test".
- **Internal Testing** group → add testers (up to 100 team members). No Beta App
  Review for internal — installs via the TestFlight app immediately.
- **External** testing (public link, up to 10 000) requires a Beta App Review on
  the first build (a day or two) and TestFlight test info (what to test, contact).

## 5. Export compliance & privacy (already declared, confirm once)

- `ITSAppUsesNonExemptEncryption = false` in Info.plist — the app's only
  encryption is local data-at-rest (SQLCipher/AES) + standard OS crypto, covered
  by the exemption. If your compliance stance differs, remove the key and answer
  the App Store Connect prompt, filing a self-classification report if needed.
- **App Privacy** nutrition label: **Data Not Collected** — the app sends nothing
  off the device (records, transcription, OCR and any model run on-device).

## 6. Medical-app note

This handles health data, so App Store review (for a public release, not
internal TestFlight) applies Apple's Health & medical guidelines. Be ready to
describe data handling (all on-device, no sharing) and, for a public listing,
that it is a records tool, not a diagnostic device.

---

## Quick reference

| Step | Where | Who |
|---|---|---|
| Create app record + bundle ID | App Store Connect | Admin/App Manager |
| Select org team, manage signing | Xcode → Signing | Developer |
| Add PrivacyInfo.xcprivacy to target | Xcode | Developer |
| Archive + upload | Xcode Organizer / `flutter build ipa` | Developer |
| Add internal testers | App Store Connect → TestFlight | Developer/Admin |
