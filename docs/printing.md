# Printing and development

## Page layout

Each sheet holds four document pages: two on each side. Pages are numbered in
reading order, and blank pages pad the final sheet. Page 1 gets a 1 cm binding
band with staple marks at 15%, 50%, and 85% of its height.

For eight pages:

```text
Sheet 1: front 8 | 1    back 2 | 7
Sheet 2: front 6 | 3    back 4 | 5
```

Stack, fold through the middle, and staple along the guide.

## iPhone Quick Print

AirPrint can save a Bonjour service name instead of a URL. The resolver decodes
that name and looks up the current host, port, and resource path. Existing saved
printers work without resetting preferences. IPP/IPPS URLs default to port 631.

The client queries printer capabilities before sending a job. It sends PDF when
supported, or PWG Raster for raster-only printers such as the Brother HL-L2420DW.
Raster output requires advertised 8-bit grayscale and a square resolution of
150–600 dpi, preferring 300 dpi. Other printers can use Standard Print.

Raster pages are rendered in 128-row strips and uploaded from a temporary file.
The landscape booklet rotates onto portrait Letter media with short-edge duplex
and the printer's advertised backside transform. The normal AirPrint sheet
retains the previously tested long-edge setting.

The client checks response IDs and status codes, rejects redirects, and never
automatically repeats an uncertain submission. Self-signed certificates are
accepted only for the selected private-network or `.local` host.

## Tests

Run from the repository root on macOS:

```sh
swift test --package-path ios/BookletCore
/usr/bin/python3 tests/ipp-smoke.py
xcodebuild -project ios/PrintAsBooklet.xcodeproj -scheme PrintAsBooklet \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The core tests cover downloads, booklet layout, saved printer names, IPP
responses, raster encoding, and backside transforms. The smoke test uploads to
a local mock printer and checks the raster with macOS CUPS. It does not print.

The current build passes 24 core tests, the smoke test, and simulator/device
builds. Physical duplex output remains unverified: the development Mac could
discover the Brother printer but could not connect to it during testing.

## References

- [IPP encoding and transport](https://www.rfc-editor.org/rfc/rfc8010.html)
- [PWG Raster specification](https://ftp.pwg.org/pub/pwg/candidates/cs-ippraster10-20120420-5102.4.pdf)
- [Apple local-network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
