# Release Keystore Setup Guide

## Step 1: Create the Keystore

Open a terminal/command prompt in the `android` folder and run:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

You will be prompted for:
- **Keystore password**: Choose a strong password (remember this!)
- **Key password**: Press Enter to use the same password, or enter a different one
- **Your name**: Your name or company name
- **Organizational Unit**: Your department (optional)
- **Organization**: Your company name
- **City**: Your city
- **State**: Your state/province
- **Country code**: Two-letter country code (e.g., US, GB, SA)

**IMPORTANT**: Save these passwords securely! You'll need them for future updates.

## Step 2: Update key.properties

Edit `android/key.properties` and replace:
- `YOUR_KEYSTORE_PASSWORD` with your keystore password
- `YOUR_KEY_PASSWORD` with your key password (or same as keystore password)

## Step 3: Build Release Bundle

After setting up the keystore, build your release bundle:

```bash
flutter build appbundle --release
```

The bundle will be at: `build/app/outputs/bundle/release/app-release.aab`

## Security Note

- **NEVER commit** `key.properties` or `upload-keystore.jks` to version control
- Keep backups of your keystore file in a secure location
- If you lose the keystore, you cannot update your app on Google Play

