# Piano

## Development

Run the app with `bin/dev` or `docker compose up`. Rails UI uses the Hound theme
and provides sample pages at `/railsui` and `/rui/dashboard`.

Rails UI configuration is in `config/railsui.yml`. The generated sample pages
and theme assets can be customized in `app/views/rui` and
`app/assets/stylesheets/railsui`.

The Tools page converts score PDFs locally with Audiveris 5.11.0 (AGPL-3.0).
It also previews MusicXML (`.xml`, `.musicxml`, or `.mxl`) files and can download
the score as MusicXML or export the rendered score directly to PDF in the
browser.
PDF document metadata and extractable text from every page are retained in the
MusicXML output. Title and composer are also shown in the preview when available;
image-only scans do not provide text to recover.
The Docker images install Audiveris for PDF score recognition. MusicXML rendering uses
OpenSheetMusicDisplay (BSD-3-Clause); PDF export uses jsPDF and svg2pdf.js (MIT).
