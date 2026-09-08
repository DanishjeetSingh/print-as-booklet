# Print as Booklet for iPhone

This folder contains the initial iOS app and Share Extension shell.

## Current flow

1. Open the app and sign in to Substack in its web view.
2. Share an article URL from Substack and choose **Print as Booklet**.
3. The Share Extension uses the shared authenticated cookie store to download the
   complete PDF, render it as a booklet, and open AirPrint directly.
4. If extension processing or print presentation fails, it stores the URL in the
   shared App Group and asks the containing app to continue the same job.
5. The app performs the identical `LiveBookletProcessor` pipeline and opens
   AirPrint with short-edge duplex requested.

The local `BookletCore` Swift package contains URL resolution, authenticated PDF
download, booklet rendering, and imposition. `LiveBookletProcessor` adapts that
package to the app shell and writes prepared files into the App Group container.

The Substack sign-in view copies cookies from WebKit into an App Group cookie
store. Both targets use that store, so paid posts can be downloaded without
collecting or storing the user's password.

## Signing setup

In Xcode, select both targets and choose a development team. The App Group
`group.com.danishjeetsingh.PrintAsBooklet` must be enabled for both identifiers.

Build without signing for the simulator:

```sh
xcodebuild -project PrintAsBooklet.xcodeproj \
  -scheme PrintAsBooklet \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```
