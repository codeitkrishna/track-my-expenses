# TME

A personal expense tracker for iPhone, built for people who won't type in every expense.

- **Bank SMS log themselves.** A Shortcuts automation hands each debit or credit alert to TME. TME reads the amount and merchant, ignores OTPs and offers, and skips duplicates.
- **A banner asks for the category.** Press and hold it, tap "Food", done. Once a merchant is filed, its later payments are filed automatically.
- **Scan and pay.** Tap the scan button next to **+** and point at a shop's UPI QR code (or pick a screenshot of one). TME shows who it pays and the UPI apps on your phone: PhonePe, Google Pay, Paytm, CRED or BHIM. Type a note once and it goes to both the payment app and your log. Tap an app and it opens on its amount screen for that UPI ID. When you come back, the payment is ready to log, filed under the shop's category from last time, and its bank SMS doesn't log it twice.
- **Quick add from anywhere.** "Add Expense", "Add Income" and "Add Category" are Shortcuts actions, so they work from iPhone's floating AssistiveTouch button, Back Tap, or Siri without opening the app. In the app, tap **+** for an expense, or hold it for income or a new category. Type two letters of who you paid and TME suggests people and shops you've paid before, with their usual category.
- **Your balance.** Enter your current balance once; TME keeps it up to date as income and spending come in.
- **Your month on one screen.** Touch and hold the strip of daily spending to scrub through the days, tap a category to see just that one, and file uncategorised payments in place or one card at a time. Tap a payment to edit it; swipe it left to delete it.
- **Trends.** Spending over the last 7 days to a year, or any dates you pick: how it compares with the same stretch before, a chart to scrub, each category's trend, and who you paid most.
- **Split with friends.** Split any payment equally, by amount or by percentage, with or without yourself. The **Friends** panel shows who owes you and for which payments. Mark a payment paid back or settle everything at once, add money you lent, and share a picture of what someone owes.
- **Goals.** Set money aside for things you're saving for, and the main screen shows what's left free to spend. Each goal's photo starts blurred and sharpens as it fills. A departure board says when you'll get there at your pace, and flips to "Delayed" after a splurge. Goals can fill themselves (round-ups, a share of a category, part of each payday from the Dynamic Island), measure new payments in days of saving, and be spent from on a trip. Finished ones go on a shelf.
- **Limits.** Give any category a daily, weekly or monthly limit. Go over and TME tells you how much later that makes your goal. The Categories page shows each one as a ring, with its payments.
- **Private.** Everything stays on your iPhone. No accounts, no servers, no bank logins.

Reads alerts from HDFC, SBI, ICICI, Axis and Kotak (UPI, cards, NEFT, refunds). Use **Settings → Test a bank SMS** to check yours.

## Install it on your iPhone (free)

You need an iPhone on iOS 26 or later and an Apple ID. No paid developer account.

New to this? [GUIDE.md](GUIDE.md) walks through both ways step by step, then setting TME up and using it.

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
2. Copy `Config/Signing.example.xcconfig` to `Config/Signing.xcconfig` and fill in your team ID (sign in under Xcode → Settings → Apple Accounts; [GUIDE.md](GUIDE.md#step-3-add-your-team-id) shows how to find the ID) and a bundle ID prefix of your own.
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
- Optional runs, switched on with environment variables for `xcodebuild test`: `TEST_RUNNER_TME_SCREENSHOTS=1` walks every screen and attaches screenshots, `TEST_RUNNER_TME_PERF=1` measures scrolling a busy month, and `TEST_RUNNER_TME_UPGRADE=1` checks splitting on a database made by an older version (install that version first).
- Publishing a version for SideStore: push your commits, then run `scripts/release.sh 0.2 "What's new"`. It builds `TME.ipa` from the latest commit and creates GitHub release v0.2, and SideStore offers it to everyone who added the source. `BUILD_ONLY=1` builds without publishing.

## License

MIT. See [LICENSE](LICENSE).
