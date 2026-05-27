# PleaseDontStopTheMusic

An iOS tweak that allows multiple audio sources to play simultaneously by preventing audio session interruptions.

---

## Overview

**PleaseDontStopTheMusic** is a tweak that hooks into iOS's `AVAudioSession` to enable audio mixing. This allows your currently playing audio (music, podcasts, etc.) to continue uninterrupted when other apps request audio playback, instead of the usual behavior where the system pauses your audio and plays only the new source.

## Features

- **Continuous Playback** - Your audio keeps playing even when other apps want to play sound.
- **Audio Mixing** - Multiple audio sources blend together using the `MixWithOthers` option.
- **Universal Support** - Works with rootful, rootless, and jailed installations.
- **Lightweight** - Minimal overhead, purely hook-based implementation.

## How It Works

The tweak intercepts `AVAudioSession` method calls and automatically applies the `AVAudioSessionCategoryOptionMixWithOthers` option to all audio category configurations. This tells iOS to mix incoming audio with existing playback rather than interrupting it.

### Hooked Methods

- `setCategory:error:`
- `setCategory:mode:options:error:`
- `setCategory:withOptions:error:`
- `setActive:error:`
- `setActive:withOptions:error:`

---

## Installation Guide

Choose the method below that applies to your device configuration.

### Method 1: Non-Jailbroken (Sideloading)
Use this method if your device is not jailbroken. You will need to inject the tweak `.dylib` from releases into your target application's IPA file.

1. **Prepare:** Ensure you have the `PleaseDontStopTheMusic.dylib` file.
2. **Select Tool:** Use a sideloading tool such as **Esign**, **Feather**, or **Sideloadly**.
3. **Inject:** Import your target application's IPA into the tool, select the `.dylib` for injection, and sign the app.
4. **Install:** Install the resulting modified IPA to your device.

### Method 2: Jailbroken
Use this method if your device is jailbroken.

| iOS Version | Architecture |
| :--- | :--- |
| **iOS 15+** | `arm64e` |
| **Below iOS 15** | `arm64` |

1. **Download:** Obtain the correct package (`.deb`) for your device's architecture.
2. **Install:** Transfer the file to your device and install it using your preferred package manager (e.g., **Sileo**, **Zebra**, or **Filza**).
3. **Finalize:** Perform a **respring** of your device to apply the hooks.

---

## Building

To build all variants of the tweak, run the following command in your terminal:

```bash
make all
