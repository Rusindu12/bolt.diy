# Binance Trader (Flutter)

A complete Flutter application for trading **Binance Spot** from a phone, built
against the official public REST + WebSocket APIs. It ships with a Testnet/Live
switch, hardware-backed key storage, live price streaming, balances, market and
limit orders, order history and a dark trading UI.

> **Want the APK without installing anything?** See
> [section 6.0](#60-fastest-option-let-github-build-it-no-local-setup) - the
> included GitHub Actions workflow builds it for you in about eight minutes.

> **This project contains no API keys.** You paste your own key/secret into the
> app; they are stored in the Android Keystore / iOS Keychain and are never
> hardcoded, logged or uploaded anywhere except to Binance itself.

---

## Table of contents

1. [Features](#1-features)
2. [Screens](#2-screens)
3. [Project structure](#3-project-structure)
4. [Requirements](#4-requirements)
5. [Quick start](#5-quick-start)
6. [Building the APK](#6-building-the-apk)
7. [Getting Binance API keys](#7-getting-binance-api-keys)
8. [Using the app](#8-using-the-app)
9. [How orders are built and validated](#9-how-orders-are-built-and-validated)
10. [Security notes](#10-security-notes)
11. [Testing & static analysis](#11-testing--static-analysis)
12. [Troubleshooting](#12-troubleshooting)
13. [Disclaimer](#13-disclaimer)

---

## 1. Features

| # | Feature | Where |
|---|---------|-------|
| 1 | API key/secret entry with **verification before saving** | `SetupScreen` |
| 2 | **Testnet ⇄ Live** switch (separate credentials per environment) | Settings, Setup |
| 3 | **Live price ticker** from `wss://…/ws/<symbol>@trade` with auto-reconnect | `MarketStreamService`, `LivePriceCard` |
| 4 | **Account balances** from `GET /api/v3/account` (zero balances hidden) | `BalancesScreen` |
| 5 | **Market orders** (base amount *or* quote amount) | `OrderForm` |
| 6 | **Limit orders** with price aligned to the symbol tick size | `OrderForm` |
| 7 | **Order history** (`GET /api/v3/allOrders`) + open orders + cancel | `OrdersScreen` |
| 8 | **Friendly error handling** for HTTP/Binance/network failures | `utils/api_exceptions.dart` |
| 9 | **Dark theme** with bottom navigation: Trade / Balances / Orders / Settings | `HomeShell` |
| 10 | **Settings**: clear keys, switch environment, default symbol, security info | `SettingsScreen` |

Additional production details:

* **HMAC-SHA256 request signing** built by hand (`crypto`), with the exact signed
  query string reused for the request.
* **Clock-offset correction** (`GET /api/v3/time`) and one automatic retry when
  Binance answers `-1021`, which is the most common failure on phones whose clock
  drifts.
* **Local order validation** against `exchangeInfo` filters (`LOT_SIZE`,
  `MARKET_LOT_SIZE`, `PRICE_FILTER`, `MIN_NOTIONAL`) so orders are rounded and
  checked before they are sent – no more `-1013` rejections.
* **Confirmation dialog** before every order and an optional
  **dry run** (`POST /api/v3/order/test`) that validates without trading.
* **Auto-refresh** of 24h statistics (30 s), balances (pull-to-refresh) and open
  orders (20 s while the tab is visible).
* WebSocket **exponential-backoff reconnect** (1 s → 30 s) plus an inactivity
  watchdog, and the socket is closed while the app is in the background.

---

## 2. Screens

| Tab | Contents |
|-----|----------|
| **Trade** | Pair selector, live price + 24h stats, trade tape, order entry (Buy/Sell, Market/Limit, 25/50/75/100 %, summary, confirm dialog, receipt) |
| **Balances** | Spot wallet summary, permissions (trade/withdraw), fee tier, non-zero assets, tap an asset to jump to its pair |
| **Orders** | Open orders (cancellable, optional all-symbols mode) and order history with fill %, average price and fees |
| **Settings** | Environment switch, stored key (masked), clock offset, default pair, security checklist, disclaimer, sign out |

---

## 3. Project structure

```
binance_trader_app/
├── android/                      # Android host project (Kotlin DSL, AGP 9.1, Gradle 9.3.1)
│   ├── app/
│   │   ├── build.gradle.kts      # minSdk 24, release signing from key.properties
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       ├── kotlin/…/MainActivity.kt
│   │       └── res/              # launch theme, colours, launcher icon (all densities)
│   ├── build.gradle.kts, settings.gradle.kts, gradle.properties
│   ├── gradlew, gradlew.bat, gradle/wrapper/gradle-wrapper.jar (Gradle 9.3.1)
│   └── key.properties.example    # template for release signing
├── lib/
│   ├── main.dart                 # entry point + dependency injection (provider)
│   ├── models/                   # plain data models (no Flutter imports)
│   │   ├── account_balance.dart  #   balances, permissions, AccountSnapshot
│   │   ├── api_credentials.dart
│   │   ├── binance_environment.dart  # Testnet / Live hosts, WS URLs
│   │   ├── binance_order.dart    #   orders, sides, types, statuses, fills
│   │   ├── market_tick.dart      #   WebSocket trade + 24h ticker
│   │   └── symbol_info.dart      #   exchange filters + rounding/validation
│   ├── providers/
│   │   ├── app_state.dart        # session: setup, environment, symbol, stream, account
│   │   ├── trade_state.dart      # order entry + submission
│   │   └── orders_state.dart     # open orders, history, cancel
│   ├── screens/
│   │   ├── home_shell.dart       # splash → setup → 4 tabs, lifecycle handling
│   │   ├── setup_screen.dart     # API key entry + security checklist
│   │   ├── trade_screen.dart
│   │   ├── balances_screen.dart
│   │   ├── orders_screen.dart
│   │   └── settings_screen.dart
│   ├── services/
│   │   ├── binance_service.dart      # REST client, signing, error mapping
│   │   ├── market_stream_service.dart# WebSocket trade stream + reconnect
│   │   └── settings_service.dart     # secure storage + preferences
│   ├── theme/app_theme.dart      # dark palette and text styles
│   ├── utils/
│   │   ├── api_exceptions.dart   # typed errors + Binance code → message map
│   │   ├── formatters.dart       # price/amount/time formatting + input parsing
│   │   ├── json_utils.dart       # tolerant JSON parsing helpers
│   │   └── signing.dart          # HMAC-SHA256 + query-string building
│   └── widgets/                  # reusable UI (cards, pills, banners, order form…)
├── test/                         # unit + widget tests (signing, filters, models, UI)
├── tool/generate_icons.py        # regenerates the launcher/web icons (stdlib only)
├── web/                          # optional web target (prices only – see note in index.html)
├── pubspec.yaml
└── analysis_options.yaml
```

---

## 4. Requirements

| Tool | Version |
|------|---------|
| Flutter | 3.47.6 or newer (stable channel) |
| Dart | 3.8 or newer (3.13 ships with Flutter 3.47.6) |
| JDK | 17 (bundled with current Android Studio, or `openjdk-17-jdk`) |
| Gradle | 9.3.1 (via the committed wrapper) |
| Android Gradle Plugin | 9.1.0 / Kotlin 2.4.0 |
| Android SDK | Platform 36 + Build-Tools 36 + Platform-Tools |
| Android device | API 24 (Android 7.0) or newer |

The Android build files are Kotlin-DSL (`.kts`) and use exactly the Gradle,
AGP and Kotlin versions that the Flutter 3.47 template ships, so the Flutter
Gradle plugin, the Android plugin and the Kotlin compiler stay in step.

Check your setup:

```bash
flutter --version      # 3.47.6 or newer
flutter doctor -v      # the Android toolchain section must be green
java -version          # must report 17.x
cd android && ./gradlew --version   # optional: checks the Gradle wrapper
```

---

## 5. Quick start

```bash
cd binance_trader_app

# 1. Resolve dependencies (creates .dart_tool/ and pubspec.lock)
flutter pub get

# 2. Static analysis + tests
flutter analyze
flutter test

# 3. Run on a connected phone (USB debugging enabled)
flutter devices
flutter run
```

The app starts in **Testnet** mode with **BTCUSDT**. Use
*Continue without API keys* to browse prices immediately, or paste Testnet keys
to unlock balances and trading.

---

## 6. Building the APK

### 6.0 Fastest option: let GitHub build it (no local setup)

This repository ships a workflow (`.github/workflows/build-apk.yml`) that builds
the APK on GitHub's machines. Nothing to install locally:

1. Open the **Actions** tab of the repository. If you see the banner
   *"Workflows aren't being run on this forked repository"*, click
   **I understand my workflows, go ahead and enable them** (forks start with
   Actions switched off).
2. Choose **Build Android APK** → **Run workflow** → **Run workflow**.
3. After ~8 minutes the run finishes and the APK is available in two places:
   * the run summary → **Artifacts** → `binance-trader-apk`, and
   * the repository **Releases** page (a release is created automatically), e.g.
     `https://github.com/<you>/<repo>/releases` → download `app-release.apk`.

Copy the APK to your phone (or download it directly on the phone), tap it and
allow installation from unknown sources. If a previous version is installed,
uninstall it first - the CI build is signed with a fresh debug key.

### 6.1 Release APK (single, universal)

```bash
cd binance_trader_app
flutter clean
flutter pub get
flutter build apk --release
```

Result:

```
build/app/outputs/flutter-apk/app-release.apk
```

Install it on a connected device or copy it to the phone:

```bash
# over USB
flutter install --release

# or with adb directly
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 6.2 Smaller APKs (one per CPU architecture)

```bash
flutter build apk --release --split-per-abi
```

Output: `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`,
`app-x86_64-release.apk`. Most modern phones need **arm64-v8a**.

### 6.3 App Bundle for Google Play

```bash
flutter build appbundle --release
# build/app/outputs/bundle/release/app-release.aab
```

### 6.4 Release signing (recommended before publishing)

Without extra configuration the release build is signed with the debug key
(installable, but not publishable). To sign with your own key:

```bash
keytool -genkey -v -keystore ~/binance-trader-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias binance_trader

cp android/key.properties.example android/key.properties
# then edit android/key.properties with your passwords and keystore path
```

`android/app/build.gradle` picks the file up automatically on the next build.
`android/key.properties` and `*.jks` are in `.gitignore` – never commit them.

### 6.5 First build takes a while

The first Gradle run downloads the Android Gradle Plugin, Kotlin and the AndroidX
dependencies (a few hundred MB). Subsequent builds take ~1 minute.

---

## 7. Getting Binance API keys

### 7.1 Testnet (start here – virtual money)

1. Open <https://testnet.binance.vision/> and log in with GitHub.
2. Click **Generate HMAC_SHA256 Key**.
3. Copy the **API Key** and **Secret Key** immediately – the secret is shown once.
4. In the app: keep the environment on **Testnet** and paste both values.
5. Optional: fund the testnet wallet with the faucet on the same page so you have
   assets to trade.

Testnet endpoints used by the app:
`https://testnet.binance.vision` and `wss://stream.testnet.binance.vision`.

### 7.2 Live (real money)

1. Log in to Binance → **Profile → API Management → Create API**.
2. Choose **System generated** (HMAC) and confirm with 2FA.
3. **Before you copy the key**, configure the restrictions:
   * **Enable Reading** ✅
   * **Enable Spot & Margin Trading** ✅ (required – without it orders fail with `-2015`)
   * **Enable Withdrawals** ❌ **leave this off** (the app never needs it)
   * **Restrict access to trusted IPs only** ✅ – add your current public IP
     (find it with `curl ifconfig.me`). Note that mobile IPs change; update the
     list or trade from a fixed connection.
4. Copy the **API Key** and the **Secret Key** (shown once) into the app after
   switching the environment to **Live**.
5. Start with a **tiny order** (e.g. 10 USDT of a liquid pair such as BTCUSDT or
   ETHUSDT) to confirm the whole flow works.

> **IP restriction and mobile data.** Binance only accepts requests from the
> whitelisted IPs. On 4G/5G your carrier IP changes constantly, so either
> whitelist a range you control, use a fixed/VPN exit IP, or trade without IP
> restriction – which is riskier because the key alone is enough to trade.

### 7.3 Recommended key hygiene

* One dedicated key for this phone; delete it if the phone is lost or sold.
* Never enable withdrawals, never share the secret, never paste it into a chat.
* Rotate the key periodically (create the new one, update the app, delete the old one).
* Keep only what you can afford to lose in the trading account.

---

## 8. Using the app

### Setup screen
* Paste key + secret, tap **Verify & save keys**. The app calls
  `GET /api/v3/account` **before** writing anything to storage, so a typo is
  rejected with a readable message and nothing is persisted.
* *Continue without API keys (read-only)* unlocks live prices only.

### Trade tab
* **Pair selector** – searchable list built from `exchangeInfo` (only symbols that
  are actually tradable in the current environment).
* **Live price** – streamed trade-by-trade; the pill shows `LIVE / CONNECTING /
  RETRYING / OFFLINE` with a manual retry.
* **Order entry**
  * Buy/Sell tab and Market/Limit tab.
  * Market orders: choose the denomination (`BTC` = base amount, `USDT` = spend
    this much quote currency and Binance converts it).
  * Limit orders: type a price or tap **Market** to pre-fill the current price;
    the price is floored to the tick size automatically.
  * 25/50/75/100 % buttons fill the maximum affordable amount (100 % leaves
    rounding headroom so Binance does not reject the order).
  * A summary shows available balance, reference price and estimated value.
  * Tap the action button → confirmation dialog → order is signed and sent →
    receipt with fill details.
  * **Dry run** validates the exact order via `POST /api/v3/order/test` without
    placing it.

### Balances tab
* Pull to refresh; shows only non-zero assets with free/locked/total amounts.
* Permission card warns loudly if the key is allowed to withdraw.
* Tap an asset to jump to `<asset>USDT` (or the best available quote) on the Trade tab.

### Orders tab
* **Open** – working orders, cancellable, optional *all symbols* mode.
* **History** – last 25/50/100 orders for the selected symbol with quantity,
  average price, fill %, fees and timestamp.

### Settings tab
* Environment switch (Live asks for confirmation first).
* Masked key, permissions, maker/taker fee, measured clock offset.
* Default trading pair, security checklist, disclaimer, sign out (wipes keys).

---

## 9. How orders are built and validated

1. **Filters** – `exchangeInfo` is downloaded once (cached 15 min) and each
   symbol's `LOT_SIZE`, `MARKET_LOT_SIZE`, `PRICE_FILTER` and `MIN_NOTIONAL`
   filters are parsed.
2. **Rounding** – quantities are floored to the step size, prices to the tick size.
3. **Local validation** – minimum/maximum quantity, step alignment, minimum
   notional (value ≥ e.g. 5 USDT) and available balance (free base for sells,
   free quote for buys).
4. **Signing** – parameters are ordered, percent-encoded, and signed with
   HMAC-SHA256 using the secret; the identical string is sent in the URL, with
   `X-MBX-APIKEY` in the headers.
5. **Error mapping** – Binance codes (`-1013`, `-1021`, `-2010`, `-2015`, …) and
   HTTP statuses are translated into actionable sentences, with the raw response
   available under *Details*.

---

## 10. Security notes

* Keys live in `flutter_secure_storage` 11 (AES-GCM data encryption with the
  key wrapped by RSA-OAEP inside the Android Keystore / iOS Keychain) in a
  dedicated storage namespace. Nothing sensitive is written to
  `shared_preferences` — only the symbol, the environment and flags.
* Android backup/transfer of app data is disabled
  (`allowBackup="false"` + `data_extraction_rules.xml`), so keys cannot be
  exfiltrated through cloud backups.
* If an encrypted entry can no longer be decrypted (keystore reset, restored
  backup, reinstalled app) it is erased and the app falls back to the setup
  screen instead of crashing (`resetOnError`).
* Withdrawals are never implemented – the app only calls spot trading endpoints.
* The release build allows **no cleartext traffic**; every call goes to Binance
  over TLS. (Debug/profile builds enable cleartext only for the Flutter tool.)
* The clock offset returned by Binance is displayed in Settings so you can see
  whether your device clock is drifting.

---

## 11. Testing & static analysis

```bash
flutter analyze     # static analysis (no errors expected)
flutter test        # unit + widget tests
```

What the tests cover:

* `test/signing_test.dart` – HMAC-SHA256 against a published test vector, query
  building and encoding.
* `test/symbol_info_test.dart` – filter parsing, step/tick rounding, minimum
  notional validation, max affordable quantity.
* `test/models_test.dart` – order/trade/balance/ticker JSON parsing, tolerant of
  strings vs numbers, zero-balance filtering, fill fees.
* `test/formatters_test.dart` – price/amount/time formatting and user input
  parsing (`1,234.5` → `1234.5`).
* `test/widget_test.dart` – segmented control, status pills, banner details
  toggle, cards and empty states.

Regenerate the launcher/web icons (no extra tooling required):

```bash
python3 tool/generate_icons.py
```

---

## 12. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `-2015` *Invalid API-key, IP, or permissions for action* | Wrong environment (Testnet key used on Live or vice versa), IP not whitelisted, *Spot & Margin Trading* disabled, or the key was deleted. |
| `-1021` / `-1125` *Timestamp outside recvWindow* | Device clock drifted. Enable *Automatic date & time*, then press Retry (the app also re-syncs automatically and retries once). |
| `-1013` *Filter failure* | Amount/price not aligned to the step/tick size or below the minimum notional. The app pre-validates this, so also check you are on the latest symbol info (pull to refresh). |
| `-2010` *NEW_ORDER_REJECTED* | Usually insufficient balance. Check the Balances tab and the “Available” line in the order form. |
| `-1003` / HTTP 429 / 418 | Rate limited; wait a minute. The Orders tab auto-refresh may be pulling too often if you have many open orders. |
| Price stream stays `OFFLINE` | WebSocket blocked (some carriers/VPNs/proxies). Switch network, disable VPN, tap the retry icon. REST prices keep working. |
| `Flutter not found` / Gradle errors | Run `flutter doctor -v`; ensure JDK 17 and Android SDK 34+ are installed; `flutter clean` then rebuild. |
| Build fails on `minSdkVersion` | The project uses `minSdk 24`. Older devices are not supported (they lack the required Keystore APIs). |

---

## 13. Disclaimer

Cryptocurrency trading is highly volatile and you can lose your entire deposit.
This application is an **unofficial** client of the public Binance API, is not
affiliated with or endorsed by Binance, and is provided **as-is without any
warranty**. You are solely responsible for the API keys you create, the
permissions you grant them and every order you place. Always start on the
Testnet, verify the on-screen confirmation before sending an order, and never
trade funds you cannot afford to lose.
