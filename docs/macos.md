# Mac setup

Install with the commands in the [README](../README.md). The installer adds two
Services, a Chrome extension, and an isolated Python environment.

## Print a PDF

- **Local file:** right-click in Finder → **Quick Actions → Print as Booklet**.
- **Public PDF URL:** copy the direct link → **Services → Print Copied PDF URL as Booklet**.
- **PDF requiring login:** use the Chrome extension below.

All three submit jobs immediately without a print dialog. Temporary files are
removed after submission; source PDFs are unchanged.

## Chrome extension

After running `./install.sh`:

1. Open `chrome://extensions` and enable **Developer mode**.
2. Choose **Load unpacked** and select
   `~/Library/Application Support/Print Booklet/Chrome Extension`.
3. Open a PDF and click **Print Current PDF as Booklet**.

The extension requests access to the PDF's website and passes its matching
cookies to the local download helper. Substack also needs access to `substack.com`
for its login cookie. The temporary PDF and cookie file are removed afterward.

## Printer and paper

Edit `~/Library/Application Support/Print Booklet/config.zsh`:

```zsh
printer_name=""          # Empty means the macOS default printer.
paper_size="Letter"
pdfbook_paper="letterpaper"
```

For A4, use `paper_size="A4"` and `pdfbook_paper="a4paper"`.
Find printer queue names with `lpstat -p`.

## Check without printing

```sh
"$HOME/Library/Application Support/Print Booklet/print-booklet.zsh" --dry-run "/path/to/document.pdf"
```

## Troubleshooting

| Problem | Check |
| --- | --- |
| Quick Action missing | Rerun the installer or enable it under Finder's **Quick Actions → Customize**. |
| `pdfjam` missing | Run `command -v pdfjam`; confirm Homebrew/MacTeX is installed. |
| Backs upside down | The workflow requests short-edge duplex. Check printer options with `lpoptions -p PRINTER_NAME -l`. |
| Copied link downloads only a preview | Use the Chrome extension while signed in. |
