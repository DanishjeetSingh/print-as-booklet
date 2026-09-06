# macOS Print as Booklet

A Finder Quick Action that converts ordinary PDFs into folded booklet order and prints them automatically.

The workflow:

- accepts one or more PDFs from Finder;
- adds centered Times Roman page numbers to the original pages;
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

## Install

```sh
git clone git@github.com:DanishjeetSingh/macos-print-booklet.git
cd macos-print-booklet
./install.sh
```

Then right-click a PDF in Finder and choose:

```text
Quick Actions > Print as Booklet
```

The action submits the print job immediately. It does not show the normal print dialog.

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
