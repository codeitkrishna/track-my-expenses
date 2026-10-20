# TME

A personal expense tracker for iPhone, built for people who won't type in every expense.

- **Bank SMS log themselves.** A Shortcuts automation hands each debit or credit alert to TME. TME reads the amount and merchant, ignores OTPs and offers, and skips duplicates.
- **A banner asks for the category.** Press and hold it, tap "Food", done. Once a merchant is filed, its later payments are filed automatically.
- **Quick add from anywhere.** "Add Expense", "Add Income" and "Add Category" are Shortcuts actions, so they work from iPhone's floating AssistiveTouch button, Back Tap, or Siri without opening the app.
- **Your balance.** Enter your current balance once; TME keeps it up to date as income and spending come in.
- **Your month on one screen.** Drag across the strip of daily spending to scrub through the days, tap a category to see just that one, and file uncategorised payments in place or one card at a time.
- **Private.** Everything stays on your iPhone. No accounts, no servers, no bank logins.

Reads alerts from HDFC, SBI, ICICI, Axis and Kotak (UPI, cards, NEFT, refunds). Use **Settings → Test a bank SMS** to check yours.

## Install it on your iPhone (free)

You need an iPhone on iOS 26 or later and an Apple ID. No paid developer account.

### Without a Mac

Install TME with [SideStore](https://docs.sidestore.io/docs/installation/prerequisites). It needs a computer (Windows is fine) only once, to set up SideStore. After that, you install, renew and update TME on the iPhone.

1. Set up SideStore with [its guide](https://docs.sidestore.io/docs/installation/prerequisites). On Windows that's iTunes and iloader on the computer, and LocalDevVPN on the iPhone.
2. In SideStore, open **Sources**, tap **+**, and add this source:

   ```
   https://github.com/codeitkrishna/track-my-expenses/releases/latest/download/source.json
   ```

3. With LocalDevVPN connected, find TME in **Browse** and install it. When SideStore asks about app extensions, keep them: choose **Keep App Extensions (Register App ID for Each Extension)**. Removing them stops the banner that asks for a category.

With a free Apple ID, apps stop opening after 7 days. At least once a week, connect LocalDevVPN, open SideStore and tap **Refresh All** in **My Apps**. If SideStore itself expires, you'll need the computer to set it up again. New versions of TME show up in **My Apps**, and updating keeps your data.

### With a Mac

Build it yourself with Xcode 27.

1. Clone this repo.
2. Copy `Config/Signing.example.xcconfig` to `Config/Signing.xcconfig` and fill in your team ID (Xcode → Settings → Accounts) and a bundle ID prefix of your own.
3. Open `TME.xcodeproj`, choose your iPhone as the run destination, and press Run.
   - iPhone on iOS 27: pair it over Wi-Fi with no cable, from Xcode's **Device Hub → + → Pair Nearby Device**.
4. The first time, trust the app on the phone: **Settings → General → VPN & Device Management**.

With a free Apple ID the app stops opening after 7 days. To have your Mac renew it automatically before then, run once:

```sh
scripts/install-renew-agent.sh
```

Every 6 hours it checks how long the app on your phone has left; with 3 days or less, it fetches fresh signing profiles, rebuilds and reinstalls over Wi-Fi. Your data is kept. It needs Xcode signed in and the phone on the Mac's Wi-Fi, and shows a Mac notification if it can't renew. Log: `~/Library/Logs/tme-renew.log`. Turn it off with `scripts/install-renew-agent.sh --remove`.

## Set it up

In the app, **Settings** walks you through:

- **Auto-log bank SMS**: one Shortcuts automation per keyword (`debited`, `credited`, ...), running **Log Bank SMS**.
- **Floating quick-add button**: AssistiveTouch with Add Expense, Add Income and Add Category in its menu.

## Development

- The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing files, run `xcodegen`.
- The SMS parser lives in `Packages/TMECore` and has its own tests: `swift test` in that folder.
- App and UI tests: `xcodebuild test -scheme TME -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Publishing a version for SideStore: push your commits, then run `scripts/release.sh 0.2 "What's new"`. It builds `TME.ipa` from the latest commit and creates GitHub release v0.2, and SideStore offers it to everyone who added the source. `BUILD_ONLY=1` builds without publishing.

## License

MIT. See [LICENSE](LICENSE).
