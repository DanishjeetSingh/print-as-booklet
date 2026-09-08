# BookletCore

`BookletCore` is the platform-neutral application logic for the iPhone booklet
printer. Add this directory to the Xcode workspace as a local Swift package and
link the `BookletCore` product from both the app and its Share Extension.

## Pipeline

```swift
let client = SubstackClient(cookieStorage: authenticatedCookieStorage)
try await client.verifyAuthentication()
let post = try await client.resolvePost(from: sharedURL)
let downloaded = try await client.downloadPDF(for: post)
let bookletData = try BookletPDFRenderer().render(sourcePDF: downloaded.data)
```

The app owns authentication. After login in a persistent `WKWebView`, enumerate
the cookies in `WKWebsiteDataStore.default().httpCookieStore` and copy them into
the `HTTPCookieStorage` passed above. `SubstackClient` never receives or stores a
password.

The renderer reproduces the desktop defaults:

- centered 12–14 pt Times page numbers;
- a 1 cm light-gray band on the left edge of source page 1;
- three 3 pt staple marks at 15%, 50%, and 85% of page height;
- blank-page padding to a multiple of four;
- two-up imposition on landscape US Letter sheets.

Submit the returned data through the regular AirPrint UI with short-edge duplex.
