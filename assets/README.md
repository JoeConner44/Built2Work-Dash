# Logo asset

The Built to Work logo shown at the top of every page and on the login screens is
loaded from a single shared file:

```
assets/logo.png
```

## To install / replace the logo

1. Drop your logo image into this folder and name it exactly **`logo.png`**
   (overwrite the existing file — keep the same name and path).
2. Use a transparent-background PNG for best results. It is displayed on a white
   header/login, sized by height (~26–52px depending on the spot), so any width is
   fine — width scales automatically to preserve aspect ratio.
3. Commit the file. No HTML/CSS changes are needed — every page (`index.html`,
   `operations.html`, `customer.html`) and both login screens already point at
   `assets/logo.png`.

The file currently checked in is the previous logo, kept as a placeholder so the
pages never show a broken image. Replacing it swaps the logo everywhere at once.

## Note: PDF export logo

The PDF export in `index.html` embeds its own copy of the logo as a base64 string
(the `const LOGO = '...'` near the export code) because the PDF generator needs the
raw image data at build time. That copy is intentionally separate and is **not**
updated by replacing `assets/logo.png`. If you want the exported PDF header to use
the new logo too, update that `LOGO` constant with the base64 of the new image.
