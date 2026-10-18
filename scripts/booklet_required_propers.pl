#!/usr/bin/env perl
# List every first- or second-class feast on an FSSP North America calendar
# whose Matins uses material a physical 1960 Breviarium Romanum does not print.
#
# Writes docs/booklet-required-propers.md and the file list in
# web/www/horas/Ribbon/booklets.txt (hrefs already stored there are kept).
#   perl scripts/booklet_required_propers.pl
#   perl scripts/booklet_required_propers.pl --stdout

use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use lib "$Bin/../web/cgi-bin";

our $version    = 'Rubrics 1960 - 1960';
our $datafolder = "$Bin/../web/www/horas";
require "$Bin/../web/cgi-bin/DivinumOfficium/SetupString.pl";

my $ROOT   = "$Bin/..";
my $TAB    = "$ROOT/web/www/Tabulae";
my $STDOUT = grep { $_ eq '--stdout' } @ARGV;

binmode STDOUT, ':encoding(UTF-8)';

# --- calendars ---------------------------------------------------------------

my (%KAL, %BASE);
open my $df, '<:encoding(UTF-8)', "$TAB/data.txt" or die $!;
my $header = <$df>;
while (my $line = <$df>) {
  chomp $line;
  my ($ver, $kal, $tra, $str, $base) = split /,/, $line;
  next unless $ver;
  $KAL{$ver}  = $kal  // '';
  $BASE{$ver} = $base // '';
}
close $df;

sub chain_has {
  my ($ver, $want, $seen) = @_;
  return 0 if !$ver || $seen->{$ver}++;
  return 1 if $ver eq $want;
  return chain_has($BASE{$ver}, $want, $seen);
}

# North American province: FSSP itself, USA, Canada, and everything under
# those two. Guadalajara also sits on FSSP and is outside this province.
my @VERSIONS = sort grep {
  chain_has($_, 'Rubrics 1960 - FSSP', {})
    && !chain_has($_, 'Rubrics 1960 - Guadalajara', {})
} keys %KAL;

sub read_kal {
  my ($ver) = @_;
  my $name = $KAL{$ver} or return {};
  my $path = "$TAB/Kalendaria/$name.txt";
  my %day;
  open my $fh, '<:encoding(UTF-8)', $path or return {};
  while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ /^\s*$/ || $line =~ /^\s*[#*]/;
    next unless $line =~ /=/;
    my @p = split /=/, $line;
    my $day = $p[0] // '';
    next unless $day =~ /^\d\d-\d\d\z/;
    my $files = $p[1] // '';
    if ($files eq '' || $files eq 'XXXXX') {
      $day{$day} = { deleted => 1 };
      next;
    }
    my ($file) = split /~/, $files;
    next unless $file;
    $day{$day} = { file => $file, name => $p[2] // '', layer => $ver };
  }
  close $fh;
  return \%day;
}

my %KAL_CACHE;
sub kal_of {
  my ($ver) = @_;
  return $KAL_CACHE{$ver} if $KAL_CACHE{$ver};
  return $KAL_CACHE{$ver} = read_kal($ver);
}

# Merge from the FSSP layer down to this calendar. A child line replaces
# the parent's line for that date. The universal 1960 kalendar is not merged:
# those feasts are the book itself.
sub merged {
  my ($ver) = @_;
  my @up;
  my $v = $ver;
  my %seen;
  while ($v && !$seen{$v}++ && $v ne 'Rubrics 1960 - 1960') {
    push @up, $v;
    $v = $BASE{$v} || '';
  }
  my %day;
  for my $layer (reverse @up) {
    my $k = kal_of($layer);
    for my $d (keys %$k) {
      if ($k->{$d}{deleted}) { delete $day{$d}; }
      else                   { $day{$d} = $k->{$d}; }
    }
  }
  return \%day;
}

# Files the 1960 typical edition actually uses (the universal chain only).
my (%ROMAN_STEM, %ROMAN_DAY);
{
  my @up;
  my $v = 'Rubrics 1960 - 1960';
  my %seen;
  while ($v && !$seen{$v}++) {
    push @up, $v;
    $v = $BASE{$v} || '';
  }
  for my $ver (reverse @up) {
    my $k = kal_of($ver);
    for my $d (keys %$k) {
      if ($k->{$d}{deleted}) { delete $ROMAN_DAY{$d}; }
      elsif ($k->{$d}{file}) {
        $ROMAN_DAY{$d} = $k->{$d}{file};
        $ROMAN_STEM{ $k->{$d}{file} } = 1;
      }
    }
  }
}

sub is_roman_stem {
  my ($stem) = @_;
  $stem =~ s{.*/}{};
  return 1 if $ROMAN_STEM{$stem};
  return 1 if $stem =~ /^\d\d-\d\d(?:r|o|t|da|p|q|cc|v)?\z/;
  return 0;
}

# --- offices -----------------------------------------------------------------

my %RAW;
sub raw {
  my ($stem) = @_;
  $stem =~ s/\.txt\z//;
  return $RAW{$stem} if exists $RAW{$stem};
  my $path = "$datafolder/Latin/$stem.txt";
  if (!-e $path) {
    return $RAW{$stem} = {};
  }
  my $h = setupstring_parse_file($path, $stem, 'Latin') || {};
  return $RAW{$stem} = $h;
}

sub stem_of {
  my ($file) = @_;
  my $stem = $file;
  $stem =~ s/\.txt\z//;
  return $stem if $stem =~ m{/};
  return "Sancti/$stem" if -e "$datafolder/Latin/Sancti/$stem.txt";
  return "Tempora/$stem" if -e "$datafolder/Latin/Tempora/$stem.txt";
  return "Commune/$stem" if -e "$datafolder/Latin/Commune/$stem.txt";
  return "Sancti/$stem";
}

sub rank_num {
  my ($stem) = @_;
  my $rank = raw($stem)->{Rank} // '';
  my @p = split /;;/, $rank;
  return undef unless defined $p[2] && $p[2] =~ /([\d.]+)/;
  return $1 + 0;
}

sub officium {
  my ($stem, $seen) = @_;
  $seen ||= {};
  return '' if !$stem || $seen->{$stem}++;
  my $o = raw($stem)->{Officium} // '';
  if ($o !~ /\S/) {
    my ($title) = split /;;/, raw($stem)->{Rank} // '';
    $o = $title // '';
  }
  $o =~ s/^\s+|\s+\z//g;
  $o =~ s/\s+/ /g;
  return $o if $o =~ /\S/;
  my $pre = raw($stem)->{__preamble} // '';
  if ($pre =~ /@(\S+)/) {
    my $n = $1;
    $n =~ s/\.txt\z//;
    return officium($n, $seen);
  }
  return '';
}

sub commune_id {
  my ($stem) = @_;
  my $rule = raw($stem)->{Rule} // '';
  return $1 if $rule =~ /\b(?:ex|vide)\s+(C\d+[a-z]?)\b/i;
  my $rank = raw($stem)->{Rank} // '';
  return $1 if $rank =~ /\b(?:ex|vide)\s+(C\d+[a-z]?)\b/i;
  return '';
}

# File that actually holds the section, following @includes.
sub origin {
  my ($stem, $key, $seen) = @_;
  $seen ||= {};
  return '' if !$stem || $seen->{"$stem|$key"}++;
  my $doc = raw($stem);
  return '' if !%$doc;
  if (exists $doc->{$key} && $doc->{$key} =~ /\S/) {
    my $body = $doc->{$key};
    if ($body =~ /^\s*@([^\s:]+)(?::(\S+))?/m) {
      my ($nf, $nk) = ($1, $2 || $key);
      $nf =~ s/\.txt\z//;
      return origin($nf, $nk, $seen);
    }
    return $stem;
  }
  if (($doc->{__preamble} // '') =~ /@(\S+)/) {
    my $nf = $1;
    $nf =~ s/\.txt\z//;
    return origin($nf, $key, $seen);
  }
  return '';
}

sub one_lesson_key {
  my ($stem, $seen) = @_;
  $seen ||= {};
  return '' if !$stem || $seen->{$stem}++;
  my $doc = raw($stem);
  return '' if !%$doc;
  return 'Lectio94' if ($doc->{Lectio94} // '') =~ /\S/;
  return 'Lectio93' if ($doc->{Lectio93} // '') =~ /\S/;
  return 'Lectio4+5+6' if ($doc->{Lectio4} // '') =~ /\S/;
  my $pre = $doc->{__preamble} // '';
  if ($pre =~ /@(\S+)/) {
    my $n = $1;
    $n =~ s/\.txt\z//;
    return one_lesson_key($n, $seen);
  }
  return '';
}

# Rank of this file, or of the file it includes when this one only retouches responsories.
sub rank_of {
  my ($stem, $seen) = @_;
  $seen ||= {};
  return undef if !$stem || $seen->{$stem}++;
  my $r = rank_num($stem);
  return $r if defined $r;
  my $pre = raw($stem)->{__preamble} // '';
  if ($pre =~ /@(\S+)/) {
    my $n = $1;
    $n =~ s/\.txt\z//;
    return rank_of($n, $seen);
  }
  return undef;
}

sub roman_for {
  my ($md) = @_;
  # The universal kalendar names the file the 1960 book uses when it differs
  # from Sancti/MM-DD (for example 01-18r).
  if (my $named = $ROMAN_DAY{$md}) {
    my $full = stem_of($named);
    return $full if -e "$datafolder/Latin/$full.txt";
  }
  my $stem = "Sancti/$md";
  return $stem if -e "$datafolder/Latin/$stem.txt";
  return '';
}

sub name_words {
  my ($s) = @_;
  $s = lc($s // '');
  $s =~ s/æ/ae/g;
  $s =~ s/œ/oe/g;
  $s =~ tr/áàäâéèëêíìïîóòöôúùüûýÿçñ/aaaaeeeeiiiioooouuuuyycn/;
  $s =~ s/[^a-z0-9 ]//g;
  $s =~ s/\s+/ /g;
  return grep { $_ ne '' } split / /, $s;
}

# The first three words of the title. "S. Thomae de Aquino, Conf." and the
# longer universal title name the same saint. A dedication does not.
sub same_title {
  my ($a, $b) = @_;
  my @a = name_words($a);
  my @b = name_words($b);
  return 0 unless @a >= 3 && @b >= 3;
  return $a[0] eq $b[0] && $a[1] eq $b[1] && $a[2] eq $b[2];
}

sub same_saint {
  my ($winner, $roman) = @_;
  return 0 if !$roman;
  return 1 if $winner eq $roman;
  return 1 if same_title(officium($winner), officium($roman));
  my $cur = $winner;
  my %seen;
  while ($cur && !$seen{$cur}++) {
    my $pre = raw($cur)->{__preamble} // '';
    last unless $pre =~ /@(\S+)/;
    my $n = $1;
    $n =~ s/\.txt\z//;
    return 1 if $n eq $roman && same_title(officium($winner), officium($n) || officium($roman));
    $cur = $n;
  }
  return 0;
}

# Where a section is read from. An @include of a different celebration
# (a dedication file that also names the saint of the date) does not
# supply the lessons: the rule sends those to the Common.
sub lesson_origin {
  my ($stem, $key) = @_;
  my $doc = raw($stem);
  if (exists $doc->{$key} && $doc->{$key} =~ /\S/) {
    return origin($stem, $key);
  }
  my $pre = $doc->{__preamble} // '';
  if ($pre =~ /@(\S+)/) {
    my $inc = $1;
    $inc =~ s/\.txt\z//;
    return '' unless same_title(officium($stem), officium($inc));
  }
  return origin($stem, $key);
}

sub in_printed_book {
  my ($origin, $key) = @_;
  return 1 if !$origin;                          # supplied from the Common or the Ordinary
  return 1 if $origin =~ m{^(?:Commune|Psalterium|Ordinarium)/}i;
  if ($origin =~ m{^Tempora/}i) {
    return 0 if $origin =~ /nhf\z/i;
    return 1;
  }
  return 0 unless $origin =~ m{^Sancti/}i && is_roman_stem($origin);
  my $rank = rank_of($origin);
  return 1 if !defined $rank;                     # unreadable: do not invent a gap
  return 1 if $rank >= 5;                         # nine lessons are printed
  # Third class and below. The one abridged lesson is printed, and so are
  # the short proper parts. The old nine-lesson division is not.
  return 1 if $key =~ /^Lectio9[34]\z/;
  return 1 if $key =~ /^Lectio[123]\z/;
  return 1 if $key =~ /^(?:Invit|Hymnus Matutinum|Ant Matutinum)\z/;
  return 0;
}

# --- one feast ---------------------------------------------------------------

sub analyse {
  my ($stem) = @_;
  my $rank = rank_num($stem);
  return undef unless defined $rank && $rank >= 5;
  my ($md) = $stem =~ /(\d\d-\d\d)/;
  $md = '' if $stem =~ m{^Tempora/};
  my $dated = $md ? roman_for($md) : '';
  # The proprium that prints the one abridged lesson. Usually the saint of
  # this date. When the 1960 kalendar puts a vigil there instead, it is the
  # roman file this elevation actually reads (Vianney's file is Sancti/08-09
  # even though 8 August is where the book places him).
  my $roman = '';
  if ($dated && same_saint($stem, $dated) && defined rank_of($dated) && rank_of($dated) < 5 && one_lesson_key($dated)) {
    $roman = $dated;
  } else {
    my $base = lesson_origin($stem, 'Lectio4') || '';
    if ($base && is_roman_stem($base) && same_saint($stem, $base)
      && defined rank_of($base) && rank_of($base) < 5 && one_lesson_key($base))
    {
      $roman = $base;
    }
  }
  my $one = $roman ? one_lesson_key($roman) : '';
  my $same = $roman ne '';

  my @missing;
  my $abridged = 0;

  if ($same) {
    my $o4 = lesson_origin($stem, 'Lectio4') || lesson_origin($stem, 'Lectio5') || lesson_origin($stem, 'Lectio6') || $stem;
    # Life lessons come from the Common only when this file has none and
    # does not inherit the saint's. That office can be said from the book.
    my $from_common = !lesson_origin($stem, 'Lectio4') && !lesson_origin($stem, 'Lectio5') && !lesson_origin($stem, 'Lectio6');
    if (!$from_common) {
      $abridged = 1;
      my $how =
          $one eq 'Lectio94'     ? "the contracted lesson ($roman, Lectio94)"
        : $one eq 'Lectio93'     ? "the single historical lesson ($roman, Lectio93)"
        :                          "lessons 4–6 of $roman joined into one (the file has no contracted lesson)";
      push @missing, "Nocturn II life lessons 4–6, read from $o4. "
        . "A 1960 breviary prints only one abridged lesson: $how. "
        . "With the book alone, lesson 4 is that abridged lesson and lessons 5–6 are from the Common.";
    }
  }

  my @hom;
  for my $n (7, 8, 9) {
    my $o = lesson_origin($stem, "Lectio$n");
    next if in_printed_book($o, "Lectio$n");
    push @hom, $n;
  }
  if (@hom) {
    my $o = lesson_origin($stem, 'Lectio' . $hom[0]) || $stem;
    my $roman_hom = is_roman_stem($o) && defined rank_of($o) && rank_of($o) < 5;
    if ($roman_hom) {
      push @missing, "Nocturn III homily, lessons " . join(', ', @hom) . ", in $o. "
        . "A 1960 breviary does not print a third nocturn for this feast; the Common has the homily.";
    } else {
      push @missing, "Nocturn III homily, lessons " . join(', ', @hom) . ", in $o, not in a 1960 breviary.";
    }
  }

  for my $n (1, 2, 3) {
    my $o = lesson_origin($stem, "Lectio$n");
    next if in_printed_book($o, "Lectio$n");
    push @missing, "Lesson $n in $o, not printed in a 1960 breviary.";
  }

  # Life lessons that are not the abridged-elevation case: a proper the book lacks entirely.
  if (!$abridged) {
    my @life;
    for my $n (4, 5, 6) {
    my $o = lesson_origin($stem, "Lectio$n");
    next if in_printed_book($o, "Lectio$n");
    push @life, $n;
  }
  if (@life) {
    my $o = lesson_origin($stem, 'Lectio' . $life[0]) || $stem;
      push @missing, "Nocturn II lessons " . join(', ', @life) . " in $o, not in a 1960 breviary.";
    }
  }

  for my $pair (
    ['Invit',            'Invitatory'],
    ['Hymnus Matutinum', 'Matins hymn'],
    ['Ant Matutinum',    'Matins antiphons'],
  ) {
    my ($key, $label) = @$pair;
    my $o = lesson_origin($stem, $key);
    next if in_printed_book($o, $key);
    push @missing, "$label in $o.";
  }

  return undef unless @missing;
  return {
    stem     => $stem,
    rank     => $rank,
    name     => officium($stem),
    missing  => \@missing,
    abridged => $abridged,
    roman    => $roman,
    one      => $one,
  };
}

# --- walk --------------------------------------------------------------------

my @rows;
my %by_file;
my $calendars = 0;
for my $ver (@VERSIONS) {
  $calendars++;
  my $day = merged($ver);
  for my $d (sort keys %$day) {
    my $stem = stem_of($day->{$d}{file});
    next unless -e "$datafolder/Latin/$stem.txt";
    my $info = analyse($stem) or next;
    my $row = {
      calendar => $ver,
      date     => $d,
      name     => $info->{name} || $day->{$d}{name},
      file     => $info->{stem},
      missing  => $info->{missing},
      abridged => $info->{abridged},
      rank     => $info->{rank},
    };
    push @rows, $row;
    push @{ $by_file{$info->{stem}} }, $row;
  }
}

# Movable elevation: Holy Family and any other local Tempora file of I/II class.
my @movable_notes;
opendir my $td, "$datafolder/Latin/Tempora" or die $!;
for my $fn (sort readdir $td) {
  next unless $fn =~ /\.txt\z/;
  my $stem = "Tempora/$fn";
  $stem =~ s/\.txt\z//;
  my $rank = rank_num($stem);
  next unless defined $rank && $rank >= 5;
  next if is_standard_tempora($stem);
  my $info = analyse($stem);
  if (!$info) {
    push @movable_notes, "$stem is first or second class and its Matins is already in a 1960 breviary.";
  } else {
    push @rows, {
      calendar => '(movable Tempora file, every calendar that uses it)',
      date     => 'movable',
      name     => $info->{name},
      file     => $stem,
      missing  => $info->{missing},
      abridged => $info->{abridged},
      rank     => $info->{rank},
    };
    push @{ $by_file{$stem} }, $rows[-1];
  }
}
closedir $td;

sub is_standard_tempora {
  my ($stem) = @_;
  return 0 if $stem =~ /nhf\z/i;
  return 1;
}

# --- write -------------------------------------------------------------------

my @files = sort keys %by_file;
my $n_rows = scalar @rows;
my $n_files = scalar @files;
my $n_abr = scalar grep { $_->{abridged} } @rows;

sub md_cell {
  my ($s) = @_;
  $s //= '';
  $s =~ s/\|/\\|/g;
  $s =~ s/\n/ /g;
  return $s;
}

my $md = <<"MD";
# Propers a 1960 breviary does not print

Generated by `scripts/booklet_required_propers.pl`. The script reads the FSSP North America calendars in `web/www/Tabulae/` (the FSSP layer, FSSP USA, FSSP Canada, and the dioceses and churches under them) and the Latin office files. Guadalajara is on the FSSP trunk and is outside this province, so it is not included.

An elevated feast here is first or second class: the file's 1960 rank is 5 or higher, so Matins has nine lessons. A physical 1960 *Breviarium Romanum* prints nine lessons for a universal first- or second-class feast. For a third-class feast it prints one abridged lesson (the *lectio contracta*, or the old second nocturn joined into one). It does not print three separate life lessons, and it does not print a third nocturn.

Article 218a of the 1960 rubrics: if only one or two lessons are proper, the group of three is completed from the Common. With the book alone, lesson 4 is the abridged lesson from the Proper of Saints and lessons 5 and 6 are from the Common. No article fixes that slot order; some put the Common first and the life last. The three older life lessons this site reads are not in the book. They are printed separately, and every such feast goes in the combined propers booklet.

The booklet is not built yet. `web/www/horas/Ribbon/booklets.txt` lists the files. A later URL can be added after a tab on the same line.

## Count

| | |
| --- | --- |
| Calendars examined | $calendars |
| Feast entries (one calendar, one date) | $n_rows |
| Of which the book has only the abridged lesson | $n_abr |
| Distinct files in the booklet | $n_files |

## Distinct files

MD

$md .= "| File | Class | Feast | Calendars | What a 1960 book does not print |\n| --- | --- | --- | --- | --- |\n";
for my $f (@files) {
  my $sample = $by_file{$f}[0];
  my $class = $sample->{rank} >= 6 ? 'I' : 'II';
  my %cals;
  $cals{$_->{calendar}} = 1 for @{ $by_file{$f} };
  my $nc = scalar keys %cals;
  my $miss = join(' ', @{ $sample->{missing} });
  $md .= '| `' . md_cell($f) . '` | ' . $class . ' | ' . md_cell($sample->{name})
    . " | $nc | " . md_cell($miss) . " |\n";
}

$md .= "\n## Every calendar entry\n\n";
$md .= "| Calendar | Date | Feast | File | Missing from a 1960 book |\n| --- | --- | --- | --- | --- |\n";
for my $r (@rows) {
  my $cal = $r->{calendar};
  $cal =~ s/^Rubrics 1960 - //;
  $md .= '| ' . md_cell($cal) . ' | ' . $r->{date} . ' | ' . md_cell($r->{name})
    . ' | `' . md_cell($r->{file}) . '` | ' . md_cell(join(' ', @{ $r->{missing} })) . " |\n";
}

if (@movable_notes) {
  $md .= "\n## Movable feasts checked\n\n";
  $md .= "- $_\n" for @movable_notes;
}

$md .= "\n";

# Preserve hrefs already written beside a file.
my %href;
my $book_path = "$ROOT/web/www/horas/Ribbon/booklets.txt";
if (open my $bh, '<:encoding(UTF-8)', $book_path) {
  while (my $line = <$bh>) {
    chomp $line;
    next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
    my ($file, $href) = split /\t/, $line, 2;
    next unless $file && defined $href && $href =~ /\S/;
    $file =~ s/\.txt\z//;
    $file =~ s/^\s+|\s+\z//g;
    $href =~ s/^\s+|\s+\z//g;
    $href{$file} = $href;
  }
  close $bh;
}

my $book = <<'TXT';
# Combined-propers booklet — not built yet.
#
# Every file listed here is a first- or second-class feast, on an FSSP
# North America calendar, whose Matins uses material a physical 1960
# Breviarium Romanum does not print. The ribbon page says to print that
# proper separately. The list is written by scripts/booklet_required_propers.pl
# together with docs/booklet-required-propers.md.
#
# A line is a file the engine reads, without ".txt". When a booklet exists,
# a tab and a URL or site path follow:
#   Sancti/12-12s	https://example.invalid/booklet#12-12s
# Until then the line has no URL. The note is shown, and data-booklet stays empty.
TXT
for my $f (@files) {
  $book .= $href{$f} ? "$f\t$href{$f}\n" : "$f\n";
}

print "calendars $calendars\nrows $n_rows\nabridged-rows $n_abr\nfiles $n_files\n";
print "movable: $_\n" for @movable_notes;
print "--- sample files ---\n";
for my $f (@files[0 .. ($#files < 12 ? $#files : 12)]) {
  my $s = $by_file{$f}[0];
  print "$f  $s->{name}\n  $_\n" for @{ $s->{missing} };
}

if ($STDOUT) {
  print "\n$md";
  exit 0;
}

open my $out, '>:encoding(UTF-8)', "$ROOT/docs/booklet-required-propers.md" or die $!;
print $out $md;
close $out;
open my $bout, '>:encoding(UTF-8)', $book_path or die $!;
print $bout $book;
close $bout;
print "wrote docs/booklet-required-propers.md and booklets.txt\n";
