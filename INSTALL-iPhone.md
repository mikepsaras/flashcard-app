# Put Flashcards on your iPhone (free, via Xcode)

No paid account needed — a free Apple ID installs the app on **your own** iPhone.
Trade-off: the app stops opening after **7 days** and you re-run it from Xcode to
renew (a paid account removes this).

### You need
- Your iPhone + a USB-C / Lightning cable
- This Mac with Xcode (already installed)
- Your Apple ID (free is fine)

### Steps
1. **Open the project** (I've opened it for you; or run):
   ```bash
   open /Users/mike/Developer/flashcard-app/Flashcards.xcodeproj
   ```
2. In Xcode's left sidebar, click the blue **Flashcards** project → select the
   **Flashcards** target → **Signing & Capabilities** tab.
3. Tick **Automatically manage signing**. For **Team**, choose your Apple ID.
   - Not listed? Xcode ▸ **Settings… ▸ Accounts ▸ +** ▸ sign in with your Apple ID,
     then come back and pick it.
4. If you see **“Failed to register bundle identifier / not available”**, change the
   **Bundle Identifier** to something unique, e.g. `com.mkps.Flashcards`.
5. **Plug in your iPhone**, unlock it, tap **Trust** if prompted.
6. At the top of the Xcode window, click the device menu and choose **your iPhone**
   (not a simulator).
7. Press **▶ Run** (⌘R). Xcode builds, installs, and launches it on your phone.
8. First launch shows **“Untrusted Developer.”** On the iPhone:
   **Settings ▸ General ▸ VPN & Device Management ▸ [your Apple ID] ▸ Trust**,
   then tap the Flashcards icon on your Home Screen.

### Good to know (free-account limits)
- **7-day expiry** — when it stops opening, repeat steps 5–7 to reinstall a fresh
  7 days. Your decks/cards stay on the phone.
- **Decks are stored as `.deck` files** in the app's Documents folder (visible under
  Files → On My iPhone → Flashcards). To move a deck between devices, Share its `.deck`
  file and Open it on the other device.
- The first iOS device build may prompt Xcode to download iOS device-support
  components — let it.

### Make it permanent across project regenerations (optional)
The Xcode signing choice lives in the generated `.xcodeproj`, which is recreated by
`xcodegen generate`. To bake it into the source so it survives, add to the
`Flashcards` target in `project.yml`:
```yaml
        DEVELOPMENT_TEAM: YOURTEAMID      # 10-char ID from Xcode ▸ Settings ▸ Accounts
        CODE_SIGN_STYLE: Automatic
```
then run `xcodegen generate`. (Send me your Team ID and I'll wire it in for you.)
