#!/bin/bash
# Generate EPUB: "Officium Parvum Beatae Mariae Virginis" — the complete Little
# Office of the BVM, with every form used through the liturgical year.
#
# The Little Office is a votive office (votive=C12). Its proper texts change with
# the season, and the engine redirects C12 -> C12/C12A/C12N/C12Q by date. Within
# each season, only Matins varies (a 3-group weekday psalm cycle); every other
# hour is the same on every weekday. So this book contains 5 seasonal "forms",
# each with all 8 hours, and Matins is shown with its three weekday psalm-schemes.
# A short appendix gathers the seasonal concluding Marian antiphons.
#
# Output: ~/Downloads/ParvumOfficium/OfficiumParvumBMV.epub

set -euo pipefail

EPUBGEN_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$HOME/Downloads/ParvumOfficium"
EPUB_FILE="$OUTPUT_DIR/OfficiumParvumBMV.epub"
VERSION="Rubrics%201960%20%2D%201960"   # 1960 rubrics, Latin
TMPDIR="$(mktemp -d)"

cd "$EPUBGEN_DIR"
mkdir -p "$OUTPUT_DIR" "$TMPDIR/META-INF"

# ---- the five seasonal forms (representative dates in 2026) -----------------
# Within a season only Matins changes by weekday, in 3 groups:
#   g1 = Sun/Mon/Thu   g2 = Tue/Fri   g3 = Wed/Sat
# OTHER = date used for all non-Matins hours (weekday-invariant in a season).
FORM_ROMAN=(I II III IV V)
FORM_TITLE=(
  "Per Annum"
  "Tempore Adventus"
  "Tempore Nativitatis (a Nativitate ad Purificationem)"
  "Tempore Septuagesimae usque ad Sabbatum Sanctum"
  "Tempore Paschali"
)
FORM_OTHER=(07-13-2026 11-30-2026 12-28-2026 02-16-2026 04-13-2026)  # Monday of each
FORM_MAT1=(07-13-2026 11-30-2026 12-28-2026 02-16-2026 04-13-2026)   # g1 (Mon)
FORM_MAT2=(07-14-2026 12-01-2026 12-29-2026 02-17-2026 04-14-2026)   # g2 (Tue)
FORM_MAT3=(07-15-2026 12-02-2026 12-30-2026 02-18-2026 04-15-2026)   # g3 (Wed)

HCMD=(_ Matutinum Laudes Prima Tertia Sexta Nona Vespera Completorium)
HNAME=(_ "Ad Matutinum" "Ad Laudes" "Ad Primam" "Ad Tertiam" "Ad Sextam" "Ad Nonam" "Ad Vesperas" "Ad Completorium")

# ---- helpers ----------------------------------------------------------------
render() {  # $1=MM-DD-YYYY  $2=HourCommand   -> raw rendered XHTML on stdout
  perl EofficiumXhtml.pl \
    "date1=$1&command=pray$2&version=$VERSION&testmode=regular&lang1=Latin&lang2=Latin&votive=C12&linkmissa=&nofancychars=1" \
    2>/dev/null
}

# Extract just the office body: from the first <TR ...> to the last </TR>.
# This drops the engine's date-bar, hour menu and the page <H2> heading, so we
# supply our own clean headings.
extract_body() { perl -0777 -ne 'print $1 if /(<TR\b.*<\/TR>)/s'; }

# Extract the seasonal "Antiphona finalis B.M.V." unit — the Marian antiphon said
# at the very end of Compline, together with its versicle and oration. The engine
# puts that whole unit in one <TR>...</TR> row, so we grab the single row carrying
# that label.
# WHY match on the label and not on the antiphon's first word: the engine wraps
# each antiphon's opening letter in a decorative drop-cap, e.g. it prints
# "<span class=\"a\">A</span>lma" — so the literal word "Alma" is split by a tag
# and a first-word search ("Alma", "Salve", …) silently finds nothing. Matching
# the always-present label "Antiphona finalis B.M.V." avoids that trap.
extract_final() { perl -0777 -e 'local $/; $_=<STDIN>; for (/(<TR\b.*?<\/TR>)/sg){ print if index($_,"Antiphona finalis B.M.V.")>=0 }'; }

chead() {  # $1 = <title> text
  printf '%s\n' "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\"><html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"la\"><head> <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" /> <link href=\"s.css\" rel=\"stylesheet\" type=\"text/css\"/><title>$1</title></head>"
  printf '<body><div>\n'
}
cfoot() { printf '</div></body></html>\n'; }

# ---- static assets ----------------------------------------------------------
cp data/s.css "$TMPDIR/"
cp data/cover.jpg "$TMPDIR/"

cat > "$TMPDIR/META-INF/container.xml" << 'EOF'
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

cat > "$TMPDIR/titlepage.xhtml" << 'EOF'
<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="la">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
    <meta name="calibre:cover" content="true"/>
    <title>Officium Parvum B.M.V.</title>
    <style type="text/css">@page {padding:0; margin:0} body {text-align:center; padding:0; margin:0}</style>
  </head>
  <body><div>
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="100%" height="100%" viewBox="0 0 590 750" preserveAspectRatio="xMidYMid meet">
      <image width="590" height="750" xlink:href="cover.jpg"/>
    </svg>
  </div></body>
</html>
EOF

cat > "$TMPDIR/about.xhtml" << 'EOF'
<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="la">
  <head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/><title>De editione</title></head>
  <body><div>
    <p>Officium Parvum Beatae Mariae Virginis, secundum Breviarium Romanum (Rubricae 1960).</p>
    <p>Textus de <a href="http://divinumofficium.com">DivinumOfficium.com</a>.</p>
  </div></body>
</html>
EOF

# ---- front matter: preface + contents --------------------------------------
{
  chead "Officium Parvum B.M.V."
  cat <<'EOF'
<p class="cen"><br/><span class="c" style="font-size:150%">Officium Parvum<br/>Beatae Mariae Virginis</span></p>
<p class="cen"><span class="rb">secundum Breviarium Romanum &#8212; Rubricae 1960</span></p>
<p class="cen"><br/><span class="m">Omnes formae per anni circulum</span></p>
<hr/>
<p><b>Praefatio.</b> Hoc libello continentur omnes formae Officii Parvi B.M.V. quae per
annum adhibentur. Pro tempore liturgico eligenda est forma conveniens:</p>
<ol>
<li><b>Per Annum</b> &#8212; a Festo SS. Trinitatis usque ad Adventum (et tempore post Epiphaniam).</li>
<li><b>Tempore Adventus</b> &#8212; et in festo Annuntiationis.</li>
<li><b>Tempore Nativitatis</b> &#8212; a Vesperis vigiliae Nativitatis usque ad Purificationem (2 Feb.).</li>
<li><b>Tempore Septuagesimae</b> &#8212; a Dominica Septuagesimae usque ad Sabbatum Sanctum.</li>
<li><b>Tempore Paschali</b> &#8212; a Dominica Resurrectionis usque ad Pentecosten.</li>
</ol>
<p>In unaquaque forma <b>Matutinum</b> habet tres psalmorum ordines, qui per hebdomadam
sic distribuuntur: in <i>Dominica, Feria II et V</i>; in <i>Feria III et VI</i>; in
<i>Feria IV et Sabbato</i>. Ceterae horae eaedem sunt omnibus diebus.</p>
<p>In fine, <b>Antiphonae finales B.M.V.</b> pro diversis anni temporibus.</p>
<hr/>
<p class="cen"><span class="c">Index</span></p>
EOF
  for i in 0 1 2 3 4; do
    echo "<p><a href=\"f$((i+1))-00.xhtml\">${FORM_ROMAN[$i]}. &#160; ${FORM_TITLE[$i]}</a></p>"
  done
  echo "<p><a href=\"antiphonae.xhtml\">Antiphonae finales B.M.V.</a></p>"
  cfoot
} > "$TMPDIR/index.xhtml"

# ---- the five forms ---------------------------------------------------------
for i in 0 1 2 3 4; do
  n=$((i+1))
  title="${FORM_TITLE[$i]}"
  roman="${FORM_ROMAN[$i]}"

  # divider page
  {
    chead "$roman. $title"
    echo "<p class=\"cen\"><br/><br/><span class=\"c\" style=\"font-size:150%\">$roman</span></p>"
    echo "<p class=\"cen\"><span class=\"c\" style=\"font-size:125%\">$title</span></p>"
    echo "<p class=\"cen\"><br/><span class=\"rb\">Officium parvum Beatae Mariae Virginis</span></p>"
    cfoot
  } > "$TMPDIR/f${n}-00.xhtml"

  # Matutinum: three weekday psalm-schemes in one chapter.
  # Matins is the ONLY hour whose psalms change with the weekday, so at the top of
  # the chapter we print a little "jump menu": three hyperlinks that scroll the
  # reader straight to the scheme for their day. Each scheme heading below carries
  # a matching id="mat-gN" anchor, and a same-page link uses href="#mat-gN" to
  # reach it. After each day's psalms we add a forward link to Lauds (the next
  # hour, file f<n>-2.xhtml) so the reader jumps straight on without scrolling past
  # the other schemes, plus a small "back to top" link (to id="mat-top").
  {
    chead "$title &#8212; Ad Matutinum"
    echo "<p class=\"cen\"><span class=\"rb\">$title</span></p>"
    echo "<p class=\"cen\" id=\"mat-top\"><span class=\"c\">Ad Matutinum</span></p>"
    # the jump menu — the "options" to pick your weekday's psalm scheme
    echo "<p class=\"cen\"><a href=\"#mat-g1\">Dominica, Feria II et V</a> &#160;|&#160; <a href=\"#mat-g2\">Feria III et VI</a> &#160;|&#160; <a href=\"#mat-g3\">Feria IV et Sabbato</a></p>"
    echo "<p class=\"cen\" id=\"mat-g1\"><span class=\"m\">In Dominica, Feria II et Feria V</span></p>"
    render "${FORM_MAT1[$i]}" Matutinum | extract_body
    echo "<p class=\"cen\"><a href=\"#mat-top\">&#8593; Ad initium</a> &#160;&#160; <a href=\"f${n}-2.xhtml\">Ad Laudes &#8594;</a></p>"
    echo "<p class=\"cen\" id=\"mat-g2\"><br/><span class=\"m\">In Feria III et Feria VI</span></p>"
    render "${FORM_MAT2[$i]}" Matutinum | extract_body
    echo "<p class=\"cen\"><a href=\"#mat-top\">&#8593; Ad initium</a> &#160;&#160; <a href=\"f${n}-2.xhtml\">Ad Laudes &#8594;</a></p>"
    echo "<p class=\"cen\" id=\"mat-g3\"><br/><span class=\"m\">In Feria IV et Sabbato</span></p>"
    render "${FORM_MAT3[$i]}" Matutinum | extract_body
    echo "<p class=\"cen\"><a href=\"#mat-top\">&#8593; Ad initium</a> &#160;&#160; <a href=\"f${n}-2.xhtml\">Ad Laudes &#8594;</a></p>"
    cfoot
  } > "$TMPDIR/f${n}-1.xhtml"

  # other hours (Laudes .. Completorium)
  for h in 2 3 4 5 6 7 8; do
    {
      chead "$title &#8212; ${HNAME[$h]}"
      echo "<p class=\"cen\"><span class=\"rb\">$title</span></p>"
      echo "<p class=\"cen\"><span class=\"c\">${HNAME[$h]}</span></p>"
      render "${FORM_OTHER[$i]}" "${HCMD[$h]}" | extract_body
      cfoot
    } > "$TMPDIR/f${n}-${h}.xhtml"
  done
  echo "  form $roman ($title) done" >&2
done

# ---- appendix: the four seasonal concluding Marian antiphons ----------------
# The Roman Breviary (1960) assigns exactly FOUR seasonal final antiphons of the
# B.M.V. We render one representative date inside each season and pull out its
# "Antiphona finalis" row (antiphon + versicle + oration).
# NOTE: there is deliberately no "Sub tuum præsidium" / "Triduum" entry here.
# "Sub tuum præsidium" is the daily antiphon of the Nunc dimittis canticle at
# Compline — NOT a seasonal final antiphon — and it already appears in each
# form's Ad Completorium chapter. Through the Sacred Triduum the engine keeps the
# Ave Regina cælorum final antiphon (it changes to Regina cæli only at Easter),
# so no separate Triduum antiphon exists to list.
{
  chead "Antiphonae finales B.M.V."
  echo "<p class=\"cen\"><span class=\"c\">Antiphonae finales B.M.V.</span></p>"
  echo "<p>Pro tempore anni dicitur conveniens antiphona finalis in fine Completorii.</p>"

  echo "<p class=\"cen\"><span class=\"m\">Ab Adventu usque ad Purificationem</span></p>"
  render 11-30-2026 Completorium | extract_final          # Alma Redemptoris Mater

  echo "<p class=\"cen\"><br/><span class=\"m\">A Purificatione usque ad Feriam IV Hebdomadae Sanctae</span></p>"
  render 02-16-2026 Completorium | extract_final          # Ave Regina caelorum

  echo "<p class=\"cen\"><br/><span class=\"m\">Tempore Paschali</span></p>"
  render 04-13-2026 Completorium | extract_final          # Regina caeli

  echo "<p class=\"cen\"><br/><span class=\"m\">A Pentecoste usque ad Adventum</span></p>"
  render 07-13-2026 Completorium | extract_final          # Salve Regina
  cfoot
} > "$TMPDIR/antiphonae.xhtml"

# ---- content.opf ------------------------------------------------------------
{
  cat <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid_id" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <meta name="cover" content="cover"/>
    <dc:title>Officium Parvum Beatae Mariae Virginis</dc:title>
    <dc:creator opf:role="aut">Divinum Officium</dc:creator>
    <dc:language>la</dc:language>
    <dc:subject>Liturgia</dc:subject>
    <dc:description>Officium Parvum B.M.V. — omnes formae per anni circulum (Rubricae 1960).</dc:description>
    <dc:identifier id="uuid_id" opf:scheme="uuid">officium-parvum-bmv-2026</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx"   href="toc.ncx"        media-type="application/x-dtbncx+xml"/>
    <item id="css"   href="s.css"          media-type="text/css"/>
    <item id="cover" href="cover.jpg"      media-type="image/jpeg"/>
    <item id="title" href="titlepage.xhtml" media-type="application/xhtml+xml"/>
    <item id="index" href="index.xhtml"     media-type="application/xhtml+xml"/>
EOF
  for i in 0 1 2 3 4; do n=$((i+1))
    echo "    <item id=\"f${n}00\" href=\"f${n}-00.xhtml\" media-type=\"application/xhtml+xml\"/>"
    for h in 1 2 3 4 5 6 7 8; do
      echo "    <item id=\"f${n}h${h}\" href=\"f${n}-${h}.xhtml\" media-type=\"application/xhtml+xml\"/>"
    done
  done
  cat <<'EOF'
    <item id="antiph" href="antiphonae.xhtml" media-type="application/xhtml+xml"/>
    <item id="about"  href="about.xhtml"      media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="title"/>
    <itemref idref="index"/>
EOF
  for i in 0 1 2 3 4; do n=$((i+1))
    echo "    <itemref idref=\"f${n}00\"/>"
    for h in 1 2 3 4 5 6 7 8; do echo "    <itemref idref=\"f${n}h${h}\"/>"; done
  done
  cat <<'EOF'
    <itemref idref="antiph"/>
    <itemref idref="about"/>
  </spine>
  <guide>
    <reference type="cover" title="Cover" href="titlepage.xhtml"/>
  </guide>
</package>
EOF
} > "$TMPDIR/content.opf"

# ---- toc.ncx (nested: form -> hours) ----------------------------------------
{
  cat <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="la">
  <head>
    <meta name="dtb:uid" content="officium-parvum-bmv-2026"/>
    <meta name="dtb:depth" content="2"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>Officium Parvum Beatae Mariae Virginis</text></docTitle>
  <navMap>
EOF
  po=0
  po=$((po+1)); printf '    <navPoint id="np-%s" playOrder="%s"><navLabel><text>Titulus</text></navLabel><content src="titlepage.xhtml"/></navPoint>\n' "$po" "$po"
  po=$((po+1)); printf '    <navPoint id="np-%s" playOrder="%s"><navLabel><text>Praefatio et Index</text></navLabel><content src="index.xhtml"/></navPoint>\n' "$po" "$po"
  for i in 0 1 2 3 4; do n=$((i+1))
    po=$((po+1))
    printf '    <navPoint id="np-%s" playOrder="%s"><navLabel><text>%s. %s</text></navLabel><content src="f%s-00.xhtml"/>\n' \
      "$po" "$po" "${FORM_ROMAN[$i]}" "${FORM_TITLE[$i]}" "$n"
    for h in 1 2 3 4 5 6 7 8; do
      po=$((po+1))
      printf '      <navPoint id="np-%s" playOrder="%s"><navLabel><text>%s</text></navLabel><content src="f%s-%s.xhtml"/></navPoint>\n' \
        "$po" "$po" "${HNAME[$h]}" "$n" "$h"
    done
    printf '    </navPoint>\n'
  done
  po=$((po+1)); printf '    <navPoint id="np-%s" playOrder="%s"><navLabel><text>Antiphonae finales B.M.V.</text></navLabel><content src="antiphonae.xhtml"/></navPoint>\n' "$po" "$po"
  po=$((po+1)); printf '    <navPoint id="np-%s" playOrder="%s"><navLabel><text>De editione</text></navLabel><content src="about.xhtml"/></navPoint>\n' "$po" "$po"
  printf '  </navMap>\n</ncx>\n'
} > "$TMPDIR/toc.ncx"

# ---- zip up the EPUB --------------------------------------------------------
rm -f "$EPUB_FILE"
cd "$TMPDIR"
echo -n "application/epub+zip" > mimetype
zip -X -q "$EPUB_FILE" mimetype
zip -rg -q "$EPUB_FILE" META-INF content.opf toc.ncx s.css cover.jpg \
  titlepage.xhtml index.xhtml about.xhtml antiphonae.xhtml \
  f1-*.xhtml f2-*.xhtml f3-*.xhtml f4-*.xhtml f5-*.xhtml

cd "$EPUBGEN_DIR"
rm -rf "$TMPDIR"
echo "Done: $EPUB_FILE"
ls -lh "$EPUB_FILE"
