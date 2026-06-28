# divinum-officium — FSSP North America Fork

Data files and source code for the
[Divinum Officium](http://www.divinumofficium.com/) project, extended with
parish Kalendaria for **FSSP North America** communities.

This document is intended for people wishing to contribute to the project. To
pray the office, please [visit the website](http://www.divinumofficium.com/).

To generate standalone files (e.g. for electronic eBook readers) see
[How to generate Divine Office files](standalone/tools/epubgen2/README.md).

---

## FSSP North America — Parish Propers

This fork adds custom Kalendaria for FSSP parishes and an automated workflow that
generates a **supplement bundle** containing the Office texts for all feasts
unique to each parish calendar.

### Parish Kalendaria

Custom calendar files live in `web/www/Tabulae/`:

| File | Calendar |
|---|---|
| `Nashua.txt` | St. Augustine, Nashua NH |
| `Arlington.txt` | FSSP Arlington |
| `Chesapeake.txt` | FSSP Chesapeake |
| `Sacramento.txt` | FSSP Sacramento |
| `Guadalajara.txt` | FSSP Guadalajara |

Each line follows the Divinum Officium Kalendaria format:
```
MM-DD=FileRef~TransferRef=Feast Name=ClassNumber=
```
where `ClassNumber` is `1` (I Class), `2` (II Class), or `3` (Double / III Class).

### Annual Bundle Generation

A GitHub Actions workflow (`.github/workflows/generate-propers.yml`) runs automatically on **November 1** each year. It:

1. Reads each parish Kalendarium to find feasts that differ from the parent calendar
2. Calls `standalone/tools/epubgen2/EofficiumXhtml.pl` for each feast × 8 canonical hours in Latin and English
3. Assembles `supplement-YYYY.json` (~8 MB) with all Office text
4. Publishes it as a public GitHub Release tagged `propers-YYYY`

The workflow can also be triggered manually from the **Actions** tab (useful after calendar edits or for testing a specific year).

### Desktop App

The companion app [divinum-officium-client](https://github.com/horacanonica/divinum-officium-client) downloads the bundle and generates printable PDFs or EPUBs on the user's machine — no server connection required after the initial download.

---

## Contributing to the project

Contributions are very welcome. To propose a change, please create a GitHub
account if necessary, and then open a **pull request**.

For small changes -- for example, for typographical corrections -- the simplest
way to do so is to navigate to the relevant file in GitHub's repository browser
and use its built-in editor. Any changes made in this way will automatically be
converted to a pull request.

For more substantial changes, please **fork** this repository using the link on
the repository's page on GitHub. This will create a copy of the repository
under your own account to which you may commit freely. When you are ready to
submit your change, GitHub's web interface can be used to create a
corresponding pull request. There are various ways to do this, and the
process is [described in the GitHub
documentation](https://help.github.com/articles/using-pull-requests/).

### Data files

The data files for the office and Mass are contained in the `web/www/horas/`
and `web/www/missa/` directories. Within these directories there is a directory
for each language. The files are UTF-8-encoded text files (Windows-1252
encoding is also supported, but is deprecated). The files are arranged into
sections, with each section beginning with its name enclosed in square
brackets. Please browse the files in the aforementioned directories for
examples.

## Architecture: Plack / Starman

To improve performance and reduce server overhead, this project uses **Plack/Starman**. Unlike traditional CGI, which spawns a new process for every request, Starman keeps a persistent pool of workers to handle traffic more efficiently.

For a detailed walkthrough of how the liturgical calendar is generated and served — including the full-year (Totus) ordo cache — see [How the Calendar Works](docs/how-the-calendar-works.md).

## Docker

### Production

To pull a pre-built container, pull see docker image `ghcr.io/divinumofficium/divinum-officium:master`.

To get the yml file:
`$ wget https://raw.githubusercontent.com/DivinumOfficium/divinum-officium/master/docker-compose-prod.yml`

You can also use Docker Compose to load a copy of the container in one command:

```bash
docker-compose -f docker-compose-prod.yml up -d
```

This will download Divinum Officium, and run a local copy on your system. It maps your local port 80 to the container's port 8080.

When you are done, stop the container by running:

```bash
docker-compose -f docker-compose-prod.yml down
```

### Development

[Docker](https://docker.com/) contains complete development environment
necessary for running Divinum Officium website. To run this project you need to
have docker and [Docker Compose](https://docs.docker.com/compose/) installed on
your system. Run the following command in root directory of project:

```bash
docker-compose up
```

This starts the web server on http://localhost:8080 (mapping to internal port 8080). It will mount the current web directory into the container
so that you can change files and do live-changes without restarting the container.

#### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

This permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
