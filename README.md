# macOS Print as Booklet

A Finder Quick Action that converts ordinary PDFs into folded booklet order and prints them automatically.

The repository also contains an initial [iPhone app](ios/README.md) with a Share Extension. After signing into Substack once in the app, it can accept an article URL from the Substack share sheet, fetch the authenticated PDF, apply the same booklet formatting, and open AirPrint with short-edge duplex requested.

It also includes a system Service that downloads a copied direct PDF URL into temporary storage, prints it through the same booklet workflow, and removes the temporary file afterward.

The workflow:

- accepts one or more PDFs from Finder;
- adds centered Times Roman page numbers to the original pages;
- adds a 1 cm light-gray binding band and three heavy staple marks to the first page;
- pads the document to a complete four-page booklet signature;
- imposes two pages on each landscape sheet side;
- prints duplex with short-edge flipping;
- removes temporary files when the job has been submitted;
- leaves the source PDFs unchanged.

It was built and tested on macOS 26 with a Brother HL-L2420DW using US Letter paper.

## Requirements

- macOS with a duplex printer configured
- [Homebrew](https://brew.sh/)
- Python 3
- `pdfbook2`

Install the command-line requirements:

```sh
brew install python pdfbook2
```

The installer creates an isolated Python virtual environment and installs `pypdf` and `reportlab` there.
It prefers Python 3.13 or 3.12 when either is installed, then falls back to the system `python3` command.

## Install

```sh
gh repo clone DanishjeetSingh/macos-print-booklet
cd macos-print-booklet
./install.sh
```

Then right-click a PDF in Finder and choose:

```text
Quick Actions > Print as Booklet
```

For a PDF displayed online, copy its direct URL and choose this from the current application's menu:

```text
Services > Print Copied PDF URL as Booklet
```

The URL must begin with `http://` or `https://` and return an actual PDF. Public direct PDF links work; links that require browser cookies or an authenticated session may not.

Both actions submit the print job immediately. They do not show the normal print dialog.

## Authenticated PDFs in Chrome

Copied URLs may return a shortened public preview when the full PDF depends on a logged-in browser session. The included Chrome extension solves this by passing cookies for only the active tab to the local native helper. The helper downloads the PDF into a uniquely named macOS temporary directory, validates it, runs the normal booklet workflow, and removes the PDF and cookie file afterward.

Run `./install.sh`, then:

1. Open `chrome://extensions` in Chrome.
2. Enable **Developer mode**.
3. Choose **Load unpacked**.
4. Select `~/Library/Application Support/Print Booklet/Chrome Extension`.
5. Optionally pin **Print Current PDF as Booklet** to Chrome's toolbar.

While viewing a PDF, click the extension. It requests access to that PDF's website and sends only the cookies applicable to its URL to the registered local helper. For Substack, it also requests the parent `substack.com` domain because that is where Substack stores its login cookie. Chrome retains approved site permissions until you revoke them from the extension's settings. The extension does not create a file in Downloads.

## Configuration

The first installation creates:

```text
~/Library/Application Support/Print Booklet/config.zsh
```

By default, the action uses the macOS default printer and US Letter paper:

```zsh
printer_name=""
paper_size="Letter"
pdfbook_paper="letterpaper"
```

Set `printer_name` to a CUPS queue from `lpstat -p` when you do not want the default printer.

For A4 paper, use:

```zsh
paper_size="A4"
pdfbook_paper="a4paper"
```

## Test without printing

```sh
"$HOME/Library/Application Support/Print Booklet/print-booklet.zsh" --dry-run "/path/to/document.pdf"
```

This prepares and validates the temporary booklet without submitting a print job.

## Page numbering

Page numbers are added before booklet imposition, so they follow reading order rather than sheet order. Padding pages remain blank. The default style is a centered 12-14 pt Times Roman number with a subtle white backing for readability.

## First-page binding guide

After booklet imposition, the first finished booklet page receives a 1 cm light-gray band along its left edge. Applying the guide after two-up scaling makes the band span the full height of the booklet page and preserves its physical 1 cm width. Three heavier, vertical marks indicate suggested staple positions at 15%, 50%, and 85% of the finished page height. The middle mark is exactly centered. Other pages are unchanged apart from page numbering.

## How booklet imposition works

For an eight-page document, the imposed sheet order is:

```text
Front: 8 | 1
Back:  2 | 7

Front: 6 | 3
Back:  4 | 5
```

Stack the sheets, fold them through the center, and staple or bind through the fold.

## Troubleshooting

### Back sides are upside down

The supplied workflow requests short-edge duplex using both the IPP and legacy CUPS options. If a printer interprets duplex settings differently, inspect its options with:

```sh
lpoptions -p PRINTER_NAME -l
```

### The Quick Action is missing

Run the installer again, relaunch Finder, or enable it from Finder's **Quick Actions > Customize** menu.

### Automator cannot find `pdfjam`

The script adds the common Homebrew and MacTeX locations to its command path. Confirm `pdfjam` is available with:

```sh
command -v pdfjam
```

## License

MIT
