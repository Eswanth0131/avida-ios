# Setting up Avida on your own Mac and iPhone

This guide gets Avida running on your iPhone with a **free Apple ID**. No paid developer account is needed.

You'll need:
- A Mac with **Xcode 26 or later** (the project uses Swift 6.2 features).
- An iPhone on **iOS 18 or later**, and a USB cable.
- Access to the GitHub repository (it's private: ask the owner to add you).
- The **proxy URL and app token**, which you'll receive privately from the project owner. They are never stored in this repository.

## 1. Install Xcode

1. Install **Xcode** from the Mac App Store and open it once. Let it install any extra components it asks for.
2. In Xcode, open **Xcode → Settings → Platforms** and make sure an **iOS** platform is installed.
3. Point the command-line tools at Xcode (Terminal; it asks for your Mac password):
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

## 2. Clone the repository

```bash
git clone https://github.com/aishwarya4114/avida-ios.git
```

If Git asks you to sign in, use your GitHub account (the one the owner added).

## 3. Open the project

```bash
open avida-ios/Avida.xcodeproj
```

## 4. Signing: use your own Apple ID and a unique bundle identifier

1. In Xcode, choose **Xcode → Settings → Accounts**, click **+**, choose **Apple ID**, and sign in.
2. In the left sidebar, click the blue **Avida** project, then select the **Avida** target and open the **Signing & Capabilities** tab.
3. Keep **Automatically manage signing** checked.
4. Set **Team** to your name (it shows as "Your Name (Personal Team)").
5. Change **Bundle Identifier** to something unique to you, for example `com.yourname.Avida`.
   The current identifier belongs to the original developer's team, and Xcode can't sign it for you.
6. Optional, only if you want to run the unit tests on your iPhone: select the **AvidaTests** target and do the same
   (your Team, and a unique identifier such as `com.yourname.AvidaTests`). Tests also run in the iOS Simulator without this.

## 5. Add the Claude config (proxy URL and app token)

Avida writes experience titles and answers questions with Claude, through a small proxy. The app needs the proxy's URL
and an app token, which you receive privately.

1. From the cloned folder, copy the example file:
   ```bash
   cp config/LLMConfig.example.json Avida/LLMConfig.json
   ```
2. Open `Avida/LLMConfig.json` and replace both placeholders with the values you received:
   ```json
   {
     "proxyURL": "https://<the proxy URL you received>/v1/messages",
     "appToken": "<the app token you received>"
   }
   ```
3. Don't commit this file. `Avida/LLMConfig.json` is already in `.gitignore`. Don't paste the token into issues, chats or docs.

Xcode includes the file in the app automatically when you build. Without it the app still works, but titles stay as
simple templates and the Ask questions show a "missing config" error.

## 6. Connect your iPhone

1. Connect the iPhone to the Mac with the cable and unlock it.
2. If the iPhone asks **Trust This Computer?**, tap **Trust** and enter your passcode.
3. In Xcode's toolbar, open the device menu next to the scheme name and choose your iPhone.

## 7. Turn on Developer Mode

1. Press **Run** (▶) once in Xcode. iOS needs to see an app from Xcode before it shows the Developer Mode option.
2. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, and restart when asked.
3. After the restart, unlock the iPhone and tap **Turn On** to confirm.

## 8. Trust your developer certificate

The first time you install with a free Apple ID, iOS won't open the app until you trust your certificate:

1. On the iPhone, open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your Apple ID, then **Trust "Apple Development: …"** and confirm.

## 9. Run

1. In Xcode, press **Run** (▶). Xcode builds, installs and opens Avida on the iPhone.
2. If Xcode shows a signing error, go back to step 4. The bundle identifier must be unique and the Team must be your Apple ID.

## 10. Allow Full Access to photos

1. In Avida, tap **Allow Photo Access**, then choose **Allow Full Access**.
   With "Limited Access", Avida only sees the photos you select and says so.
2. Avida reads your camera photos on the iPhone (not screenshots or screen recordings). Your photos never leave the
   phone. Only short text (places, months, categories, landmark names) is sent to Claude to write titles.
3. The first scan can take a while on a large library. Watch the progress ring on the "Analyzing your photos" screen.

Photos need a location to be grouped into experiences, so make sure **Settings → Privacy & Security →
Location Services → Camera** is set to "While Using the App" for future photos.

## Things to know with a free Apple ID

- Apps installed this way **stop opening after 7 days**. Connect the iPhone and press Run again to reinstall
  (your data stays).
- A free Apple ID can have only a few apps installed this way at once.

## Optional: deploy your own proxy with your own Anthropic key

If you'd rather not use the shared proxy, you can deploy your own on Cloudflare with your own Anthropic API key.
Follow **[tools/proxy/README.md](tools/proxy/README.md)**. In short:

1. Create an Anthropic API key at console.anthropic.com and set a monthly spend limit.
2. Deploy the Worker with `npx wrangler deploy`, then add the key and a new random app token as Worker secrets
   (`npx wrangler secret put ANTHROPIC_API_KEY`, `npx wrangler secret put APP_TOKEN`).
3. Put your Worker's URL (ending in `/v1/messages`) and your app token in `Avida/LLMConfig.json` (step 5).

The Anthropic key only ever lives in the Worker's secrets: never in the app, the repository, or `LLMConfig.json`.
