# Print as Booklet

Print PDFs and Substack articles as folded booklets, with page numbers and staple guides.
Available as a macOS Quick Action and an iPhone app.

<p>
  <img src="docs/images/iphone-home.png" width="280" alt="iPhone app with article-link entry and Quick Print setup">
  <img src="docs/images/iphone-share.png" width="280" alt="Share panel with article details and a Prepare and print button">
</p>

## iPhone

1. Open the app and tap **Find my printer**. Allow Local Network access.
2. Share a Substack article → **Print as Booklet** → **Prepare & print**.
3. Choose your printer on the first print. Quick Print remembers it for next time.

You can also paste an article link in the app. Subscriber-only articles require
Substack sign-in; the app and share panel use separate sessions.

Requires iOS 17+ and an AirPrint printer on the same Wi-Fi.
Build and install with Xcode: [iPhone setup](ios/README.md).

## macOS

```sh
brew install python pdfbook2
gh repo clone DanishjeetSingh/macos-print-booklet
cd macos-print-booklet
./install.sh
```

Right-click a PDF in Finder → **Quick Actions → Print as Booklet**.
This submits the job immediately, using the default printer and Letter paper.
The source PDF stays unchanged.

For online PDFs, use the copied-URL service or the included Chrome extension.
See [Mac setup](docs/macos.md) for browser printing, A4 paper, and troubleshooting.

## Status

The Mac workflow was tested with a Brother HL-L2420DW. The updated iPhone Quick
Print path passes protocol and raster tests; its physical duplex output still
needs verification. **Standard Print / Change Printer** is available as a fallback.

[Development and printing details](docs/printing.md) · [MIT license](LICENSE)
