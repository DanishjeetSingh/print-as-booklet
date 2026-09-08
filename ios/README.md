# Print as Booklet for iPhone

This folder contains the initial iOS app and Share Extension shell.

## Current flow

1. Share an article URL from Substack and choose **Print as Booklet**.
2. The Share Extension downloads the complete PDF using its own persistent
   Substack session.
3. If authentication is required, the extension opens Substack sign-in inside
   the same share panel. Tap **Done** after signing in; the original article is
   retried automatically without copying its URL or opening the main app.
4. The extension renders the PDF as a booklet, overlays the full-height binding
   guide on the imposed half-sheet containing page 1, and submits it through
   Quick Print.
5. On the first Quick Print, choose the printer once. The extension remembers
   that printer and sends later booklets directly with Letter paper and the
   duplex mode verified for the Brother printer. Tap **Quick Printer** in the
   share panel whenever you need to change it.

Quick Print uses the printer's IPP service because UIKit's built-in direct-print
method disables duplex. If direct submission fails, the error alert offers the
standard AirPrint window as a fallback.

Before downloading, the extension verifies the session against Substack's signed-in
profile endpoint. This prevents a valid but shortened public preview PDF from being
accepted as the complete paid article.

The local `BookletCore` Swift package contains URL resolution, authenticated PDF
download, booklet rendering, and imposition. `LiveBookletProcessor` adapts that
package to both targets and writes prepared files into each target's temporary
container.

The app and Share Extension intentionally have independent Substack sessions.
Free Apple Personal Team provisioning does not support App Groups. Signing into
the main app therefore does not sign in the Share Extension; the extension asks
for its own login the first time a paid article requires it. Neither target reads
or stores the user's password.

## Signing setup

In Xcode, select the project, choose the **PrintAsBooklet** target, open
**Signing & Capabilities**, and select your Personal Team. Repeat for
**PrintAsBookletShare**. No paid capabilities or App Groups are required.

If either bundle identifier is already registered to someone else, change both
identifiers to unique values while keeping the extension identifier prefixed by
the app identifier, for example:

- `com.yourname.PrintAsBooklet`
- `com.yourname.PrintAsBooklet.Share`

Build without signing for the simulator:

```sh
xcodebuild -project PrintAsBooklet.xcodeproj \
  -scheme PrintAsBooklet \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```
