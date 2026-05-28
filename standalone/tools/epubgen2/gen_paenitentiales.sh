#!/bin/bash
# Generate EPUB of Septem Psalmi Paenitentiales cum Litaniis Sanctorum
# Output: output_sac3/septem_psalmi_paenitentiales.epub

EPUBGEN_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$EPUBGEN_DIR/output_sac3"
TMPDIR=$(mktemp -d)
EPUB_FILE="$OUTPUT_DIR/septem_psalmi_paenitentiales.epub"
VERSION="Rubrics+1960+-+Sacramento"

cd "$EPUBGEN_DIR"
mkdir -p "$TMPDIR/META-INF"

echo "Generating Septem Psalmi Paenitentiales..."
perl EofficiumXhtml.pl \
  "command=Appendix+Septem+psalmi+paenitentiales&version=${VERSION}&lang1=Latin&lang2=Latin" \
  2>/dev/null > "$TMPDIR/septem_psalmi.xhtml"

echo "Generating Litaniae Sanctorum cum Precibus..."
perl EofficiumXhtml.pl \
  "command=Appendix+Litaniae&version=${VERSION}&lang1=Latin&lang2=Latin" \
  2>/dev/null > "$TMPDIR/litaniae.xhtml"

# Fix the cross-reference link in septem_psalmi.xhtml so it points to litaniae.xhtml
# (The activate_links override already does this, but double-check just in case)
sed -i '' 's|href="litaniae.xhtml"|href="litaniae.xhtml"|g' "$TMPDIR/septem_psalmi.xhtml"

cp data/s.css "$TMPDIR/"

# META-INF/container.xml
cat > "$TMPDIR/META-INF/container.xml" << 'EOF'
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

# content.opf
cat > "$TMPDIR/content.opf" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid_id" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Septem Psalmi Paenitentiales cum Litaniis Sanctorum</dc:title>
    <dc:creator opf:role="aut">Divinum Officium</dc:creator>
    <dc:language>la</dc:language>
    <dc:subject>Liturgia</dc:subject>
    <dc:identifier id="uuid_id" opf:scheme="uuid">septem-psalmi-paenitentiales-2026</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx"         href="toc.ncx"           media-type="application/x-dtbncx+xml"/>
    <item id="css"         href="s.css"              media-type="text/css"/>
    <item id="septem"      href="septem_psalmi.xhtml" media-type="application/xhtml+xml"/>
    <item id="litaniae"    href="litaniae.xhtml"     media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="septem"/>
    <itemref idref="litaniae"/>
  </spine>
</package>
EOF

# toc.ncx
cat > "$TMPDIR/toc.ncx" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="la">
  <head>
    <meta name="dtb:uid"            content="septem-psalmi-paenitentiales-2026"/>
    <meta name="dtb:depth"          content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber"  content="0"/>
  </head>
  <docTitle>
    <text>Septem Psalmi Paenitentiales cum Litaniis Sanctorum</text>
  </docTitle>
  <navMap>
    <navPoint id="navPoint-1" playOrder="1">
      <navLabel><text>Septem Psalmi Paenitentiales</text></navLabel>
      <content src="septem_psalmi.xhtml"/>
    </navPoint>
    <navPoint id="navPoint-2" playOrder="2">
      <navLabel><text>Litani&#230; Sanctorum cum Precibus</text></navLabel>
      <content src="litaniae.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
EOF

# mimetype file must be first and uncompressed
cd "$TMPDIR"
echo -n "application/epub+zip" > mimetype
zip -X "$EPUB_FILE" mimetype
zip -rg "$EPUB_FILE" META-INF content.opf toc.ncx s.css septem_psalmi.xhtml litaniae.xhtml

rm -rf "$TMPDIR"

echo "Done: $EPUB_FILE"
ls -lh "$EPUB_FILE"
