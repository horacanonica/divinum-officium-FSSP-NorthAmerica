# Ribbon helper: read the office the engine already resolved, and say
# where the ribbons go and how each hour is ordered.
# English of the 1960 Code is taken from the two project HTML files.
# Latin is taken from web/www/horas/Ribbon/aas52-la.txt and attributed to AAS 52 (1960).

use utf8;
use File::Basename qw(basename);

our $RIBBON_ROOT;
our $RIBBON_READY;
our %RIBBON_STRINGS;
our %RIBBON_CATALOG;
our %RIBBON_LA;
our %RIBBON_EN;
our %RIBBON_EDITIONS;
our @RIBBON_EDITION_ORDER;
# Future combined-propers booklet (FSSP + USA + diocese + parish).
# booklets.txt maps a particular file to a URL or path. Nothing is filled in yet,
# so the page shows the print-separately note and does not invent a link.
our %RIBBON_BOOKLET;
our @RIBBON_EVENTS;
our $RIBBON_HOOKS;

my @RIBBON_HOURS = qw(Matutinum Laudes Prima Tertia Sexta Nona Vespera Completorium);
my %RIBBON_LANG = (
  English => 'en', Espanol => 'es', Francais => 'fr', Deutsch => 'de', Latin => 'la',
);
my @RIBBON_LANGS = qw(English Espanol Francais Deutsch Latin);
my %RIBBON_CORPUS = (
  general  => 'General Rubrics.html',
  breviary => 'Breviary 1960.html',
);

sub ribbon_root {
  return $RIBBON_ROOT if $RIBBON_ROOT;
  $RIBBON_ROOT = "$Bin/../../www/horas/Ribbon";
  return $RIBBON_ROOT;
}

sub ribbon_boot {
  return if $RIBBON_READY;
  ribbon_install_hooks();
  getini('horas');
  loadsetup(0);
  $RIBBON_READY = 1;
  ribbon_load_strings();
  ribbon_load_catalog();
  ribbon_load_latin();
  ribbon_load_english();
  ribbon_load_editions();
  ribbon_load_booklets();
}

sub ribbon_install_hooks {
  return if $RIBBON_HOOKS++;
  no warnings 'redefine';
  my $b  = \&setbuild;
  my $b1 = \&setbuild1;
  my $b2 = \&setbuild2;
  my $c  = \&setcomment;
  *setbuild = sub {
    push @RIBBON_EVENTS, {
      kind => 'src', file => $_[0] // '', name => $_[1] // '', comment => $_[2] // '', hora => $hora
    };
    $b->(@_);
  };
  *setbuild1 = sub {
    push @RIBBON_EVENTS, { kind => 'lab', label => $_[0] // '', comment => $_[1] // '', hora => $hora };
    $b1->(@_);
  };
  *setbuild2 = sub {
    push @RIBBON_EVENTS, { kind => 'note', comment => $_[0] // '', hora => $hora };
    $b2->(@_);
  };
  *setcomment = sub {
    push @RIBBON_EVENTS, {
      kind => 'cmt', label => $_[0] // '', comment => $_[1] // '',
      ind => $_[2], prefix => $_[4] // '', hora => $hora
    };
    $c->(@_);
  };
}

sub ribbon_slurp {
  my ($path) = @_;
  open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
  local $/;
  return scalar <$fh>;
}

sub ribbon_load_strings {
  my $text = ribbon_slurp(ribbon_root() . '/strings.txt');
  my $id;
  for my $line (split /\n/, $text) {
    if ($line =~ /^\[(.+)\]\s*$/) { $id = $1; next; }
    next if !defined $id || $line =~ /^\s*#/ || $line =~ /^\s*$/;
    if ($line =~ /^(en|es|fr|de|la):\s*(.*)$/) {
      $RIBBON_STRINGS{$id}{$1} = $2;
    }
  }
}

sub ribbon_load_catalog {
  my $text = ribbon_slurp(ribbon_root() . '/catalog.txt');
  my $id;
  my $cur;
  for my $line (split /\n/, $text) {
    if ($line =~ /^@@\s+(\S+)\s*$/) {
      $id = $1;
      $cur = { id => $id };
      $RIBBON_CATALOG{$id} = $cur;
      next;
    }
    next if !defined $id || $line =~ /^\s*#/ || $line =~ /^\s*$/;
    if ($line =~ /^([A-Za-z0-9_]+):\s*(.*)$/) {
      $cur->{$1} = $2;
    }
  }
}

sub ribbon_load_latin {
  my $text = ribbon_slurp(ribbon_root() . '/aas52-la.txt');
  my ($n, $page, $buf, $on);
  my $store = sub {
    return unless defined $n;
    my $body = $buf // '';
    $body =~ s/\s+\z//;
    $RIBBON_LA{$n} = { page => $page, la => $body };
  };
  for my $line (split /\n/, $text, -1) {
    if (!defined $n && $line =~ /^\s*#/) { next; }
    if ($line =~ /^@@\s+(\d+)\s*$/) {
      $store->();
      $n = $1; $page = ''; $buf = ''; $on = 0;
      next;
    }
    next unless defined $n;
    if ($line =~ /^page:\s*(\d*)\s*$/) { $page = $1; next; }
    if ($line =~ /^(?:pages|flags_stripped):/) { next; }
    if ($line =~ /^la:\s*$/) { $on = 1; next; }
    $buf .= "$line\n" if $on;
  }
  $store->();
}

sub ribbon_norm {
  my ($s) = @_;
  $s //= '';
  $s =~ s/\s+/ /g;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}

sub ribbon_html_to_text {
  my ($html) = @_;
  $html =~ s/<BR\s*\/?>/\n/gi;
  $html =~ s/<[^>]+>//g;
  $html =~ s/&nbsp;/ /g;
  $html =~ s/&amp;/&/g;
  $html =~ s/&lt;/</g;
  $html =~ s/&gt;/>/g;
  $html =~ s/&#(\d+);/chr($1)/ge;
  $html =~ s/\r//g;
  return $html;
}

sub ribbon_slice_article {
  my ($text, $n) = @_;
  return '' unless $text =~ /(?:^|\n|[ \t])($n)\.\s/;
  my $rest = substr($text, $-[1]);
  my $cut;
  while ($rest =~ /(?:^|\n)\s*(\d+)\.\s/g) {
    next if $1 <= $n;
    next if $-[1] == 0;
    $cut = $-[1];
    last;
  }
  $rest = substr($rest, 0, $cut) if defined $cut;
  $rest =~ s/[ \t]+/ /g;
  $rest =~ s/ *\n+/\n/g;
  $rest =~ s/\s+Top\b.*//s;
  $rest =~ s/\s+\z//;
  return $rest;
}

sub ribbon_load_english {
  my $dir = "$Bin/../../www/horas/Help/Rubrics";
  for my $corpus (keys %RIBBON_CORPUS) {
    my $path = "$dir/$RIBBON_CORPUS{$corpus}";
    $RIBBON_EN{$corpus} = ribbon_html_to_text(ribbon_slurp($path));
  }
}

sub ribbon_parse_edition {
  my ($text) = @_;
  my %ed = (id => '', names => {}, volumes => [], coming_soon => 0);
  my $vol;
  for my $line (split /\n/, $text) {
    $line =~ s/\r\z//;
    next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
    if ($line =~ /^volume:\s*(.+?)\s*$/) {
      $vol = { id => $1, labels => {}, seasons => {}, pages => {} };
      push @{ $ed{volumes} }, $vol;
      next;
    }
    if ($line !~ /\t/ && $line =~ /^([^\t:]+):\s*(.*?)\s*$/) {
      my ($k, $v) = ($1, $2);
      if ($k eq 'id') { $ed{id} = $v; }
      elsif ($k eq 'coming_soon') { $ed{coming_soon} = ($v && $v ne '0') ? 1 : 0; }
      elsif ($k =~ /^name\.([a-z]+)\z/) { $ed{names}{$1} = $v; }
      elsif ($vol && $k =~ /^label\.([a-z]+)\z/) { $vol->{labels}{$1} = $v; }
      elsif ($vol && $k eq 'seasons') { $vol->{seasons}{$_} = 1 for split /\s+/, $v; }
      next;
    }
    if ($vol && $line =~ /^([^\t]+)\t([^\t]*)(?:\t(.*))?\s*$/) {
      $vol->{pages}{$1} = { page => $2, note => defined $3 ? $3 : '' };
    }
  }
  return \%ed;
}

sub ribbon_load_editions {
  %RIBBON_EDITIONS = ();
  @RIBBON_EDITION_ORDER = ();
  my $dir = ribbon_root() . '/editions';
  for my $path (sort glob "$dir/*.edition") {
    next if basename($path) =~ /^_/;
    my $ed = ribbon_parse_edition(ribbon_slurp($path));
    next unless $ed->{id};
    $ed->{path} = $path;
    $RIBBON_EDITIONS{ $ed->{id} } = $ed;
  }
  @RIBBON_EDITION_ORDER = sort {
    return -1 if $a eq 'general';
    return 1  if $b eq 'general';
    ($RIBBON_EDITIONS{$a}{names}{en} // $a) cmp ($RIBBON_EDITIONS{$b}{names}{en} // $b);
  } keys %RIBBON_EDITIONS;
}

sub ribbon_edition_label {
  my ($id, $code) = @_;
  my $ed = $RIBBON_EDITIONS{$id} or return $id;
  return $ed->{names}{$code} || $ed->{names}{en} || $id;
}

sub ribbon_volume_label {
  my ($vol, $code) = @_;
  return '' unless $vol;
  return $vol->{labels}{$code} || $vol->{labels}{en} || $vol->{id};
}

sub ribbon_s {
  my ($code, $id, $slots) = @_;
  my $pack = $RIBBON_STRINGS{$id};
  my $text;
  my $sourced = 1;
  if ($pack && defined $pack->{$code} && $pack->{$code} ne '') {
    $text = $pack->{$code};
  } elsif ($code eq 'la' && $pack && defined $pack->{en}) {
    $text = $pack->{en} . ' [to be sourced]';
    $sourced = 0;
  } else {
    $text = $id;
    $sourced = 0;
  }
  if ($slots) {
    $text =~ s/\{(\w+)\}/defined $slots->{$1} ? $slots->{$1} : "{$1}"/ge;
  }
  return wantarray ? ($text, $sourced) : $text;
}

sub ribbon_h {
  my ($s) = @_;
  $s //= '';
  $s =~ s/&/&amp;/g;
  $s =~ s/</&lt;/g;
  $s =~ s/>/&gt;/g;
  $s =~ s/"/&quot;/g;
  return $s;
}

sub ribbon_sh {
  my ($code, $id, $slots) = @_;
  return ribbon_h(ribbon_s($code, $id, $slots));
}

sub ribbon_code {
  my ($lang) = @_;
  return $RIBBON_LANG{$lang} || 'en';
}

sub ribbon_dow {
  my ($y, $m, $d) = @_;
  my @t = (0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4);
  $y -= 1 if $m < 3;
  return ($y + int($y / 4) - int($y / 100) + int($y / 400) + $t[$m - 1] + $d) % 7;
}

sub ribbon_month_length {
  my ($y, $m) = @_;
  my @ml = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
  my $leap = ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0));
  return $m == 2 && $leap ? 29 : $ml[$m - 1];
}

sub ribbon_season_code {
  my ($week, $month) = @_;
  $week  //= '';
  $month ||= 0;
  return 'Quadp' if $week =~ /^Quadp/i;
  return 'Quad'  if $week =~ /^Quad/i;
  return 'Adv'   if $week =~ /^Adv/i;
  return 'Nat'   if $week =~ /^Nat/i;
  return 'Pasc'  if $week =~ /^Pasc/i;
  return 'Pent'  if $week =~ /^Pent/i;
  if ($week =~ /^Epi/i) {
    # The engine reuses Epi for the unused Epiphany Sundays just before Advent.
    # A printed breviary still has those days in the volume after Pentecost.
    return 'Pent' if $month >= 9;
    return 'Epi';
  }
  return '';
}

sub ribbon_feast_key {
  my ($file) = @_;
  return '' unless $file && $file =~ /(\d\d-\d\d)/;
  return $1;
}

sub ribbon_stem {
  my ($file) = @_;
  $file //= '';
  $file =~ s/\.txt\z//;
  return $file;
}

sub ribbon_section {
  my ($file) = @_;
  return 'psalterium'  if $file =~ /^Psalterium/i;
  return 'tempora'     if $file =~ /Tempora/i;
  return 'sancti'      if $file =~ /Sancti/i;
  return 'commune'     if $file =~ /Commune/i;
  return 'ordinarium'  if $file =~ /Ordinarium/i;
  return '';
}

sub ribbon_office_name {
  my ($lang, $file) = @_;
  return '' unless $file;
  my $h = eval { officestring($lang, $file) };
  return '' unless ref $h eq 'HASH';
  my $n = $h->{Officium} // '';
  $n =~ s/\s+\z//;
  if ($n eq '') {
    my $rank = $h->{Rank} // '';
    ($n) = split /;;/, $rank;
    $n =~ s/\s+\z//;
  }
  return $n;
}

sub ribbon_versions_table {
  my %t;
  my $path = "$Bin/../../www/Tabulae/data.txt";
  open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
  my $header = <$fh>;
  while (my $line = <$fh>) {
    chomp $line;
    next if $line eq '';
    my ($ver, $kal, $tr, $str, $base) = split /,/, $line, 6;
    $t{$ver} = { kalendar => $kal // '', base => $base // '' };
  }
  return \%t;
}

sub ribbon_stock_version {
  my ($version) = @_;
  my $table = ribbon_versions_table();
  my %stock = map { $_ => 1 } qw(1570 1888 1906 1939 1954 1955 1960);
  my $cur = $version;
  my $guard = 0;
  while ($cur && $guard++ < 12) {
    my $row = $table->{$cur} or last;
    return $cur if $stock{ $row->{kalendar} // '' };
    last if !$row->{base} || $row->{base} eq $cur;
    $cur = $row->{base};
  }
  return 'Rubrics 1960 - 1960';
}

sub ribbon_prepare {
  my ($ver) = @_;
  $version = $ver;
  $lang1 = 'Latin';
  $lang2 = 'Latin';
  $langfb = 'English';
  $only = 1;
  $votive = 'Hodie';
  $column = 1;
  $priest = 0;
  $expand = 'tota';
  $dioecesis = 'Generale';
  $error = '';
  load_languages_data($lang1, $lang2, $langfb, $version, 0);
}

sub ribbon_incipit {
  my ($num, $source) = @_;
  my $text = '';
  if ($source =~ /Commune/i && $commune{"Lectio$num"}) {
    $text = $commune{"Lectio$num"};
  } elsif ($source =~ /Tempora/i && $scriptura{"Lectio$num"}) {
    $text = $scriptura{"Lectio$num"};
  } elsif ($winner{"Lectio$num"}) {
    $text = $winner{"Lectio$num"};
  } elsif ($commune{"Lectio$num"}) {
    $text = $commune{"Lectio$num"};
  } elsif ($scriptura{"Lectio$num"}) {
    $text = $scriptura{"Lectio$num"};
  }
  return '' unless $text;
  for my $line (split /\n/, $text) {
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*[\#\$\@\&]/;
    $line =~ s/^!+\s*//;
    $line =~ s/^v\.\s*//i;
    $line =~ s/~//g;
    $line =~ s/\s+/ /g;
    $line =~ s/^\s+|\s+$//g;
    next if $line eq '';
    return substr($line, 0, 160);
  }
  return '';
}

sub ribbon_lessons_from {
  my ($events, $nocturns) = @_;
  my $nless = ($nocturns || 1) * 3;
  my @L;
  for my $i (1 .. $nless) {
    $L[$i] = {
      n => $i, nocturn => int(($i - 1) / 3) + 1,
      kind => '', source => '', note => ''
    };
  }
  for my $e (@$events) {
    next unless ($e->{kind} // '') eq 'note';
    my $c = $e->{comment} // '';
    if ($c =~ /Lectio(\d+)-(\d+) from (\S+)/) {
      for my $i ($1 .. $2) {
        next if $i < 1 || $i > $nless || $L[$i]{source};
        $L[$i]{source} = $3;
        $L[$i]{kind}   = 'scripture';
        $L[$i]{note}   = $c;
      }
    } elsif ($c =~ /Lectio(\d+) ex Sancti/) {
      my $i = $1;
      my $end = ($i % 3 == 1) ? $i + 2 : $i;
      $end = $nless if $end > $nless;
      for my $j ($i .. $end) {
        next if $L[$j]{source};
        $L[$j]{source} = $winner;
        $L[$j]{kind} =
            ($L[$j]{nocturn} == 3) ? 'homily'
          : ($L[$j]{nocturn} == 2) ? 'legend'
          :                          'scripture';
      }
      $L[$i]{note} = $c;
    } elsif ($c =~ /Lectio(\d+) ex (.+)/) {
      my ($i, $rest) = ($1, $2);
      my $end = ($i % 3 == 1) ? $i + 2 : $i;
      $end = $nless if $end > $nless;
      my $src = ($rest =~ /\.txt/) ? $rest : ($commune || $winner);
      for my $j ($i .. $end) {
        next if $L[$j]{source};
        $L[$j]{source} = $src;
        $L[$j]{kind} =
            ($L[$j]{nocturn} == 3) ? 'homily'
          : ($L[$j]{nocturn} == 2) ? 'legend'
          :                          'scripture';
      }
      $L[$i]{note} = $c;
    } elsif ($c =~ /de scriptura|ex scriptura/i) {
      my $i = ($c =~ /Lectio(\d+)/) ? $1 : 1;
      if ($i >= 1 && $i <= $nless && !$L[$i]{source}) {
        $L[$i]{source} = $scriptura || $winner;
        $L[$i]{kind}   = 'scripture';
        $L[$i]{note}   = $c;
      }
    } elsif ($c =~ /Diverged to Homily/i && $L[3]) {
      $L[3]{kind} = 'homily';
      $L[3]{note} = $c;
    } elsif ($c =~ /Diverged to Legend/i && $L[3]) {
      $L[3]{kind} = 'contracted';
      $L[3]{note} = $c;
    } elsif ($c =~ /Homily from Evang/i) {
      for my $i (1 .. $nless) {
        $L[$i]{kind}   = 'homily' unless $L[$i]{kind};
        $L[$i]{source} = $winner unless $L[$i]{source};
      }
    } elsif ($c =~ /fit una|Contract scripture/i) {
      $L[2]{kind} = 'contracted' if $L[2];
    }
  }
  my @out;
  for my $i (1 .. $nless) {
    $L[$i]{incipit} = ribbon_incipit($i, $L[$i]{source} // '');
    push @out, $L[$i];
  }
  return @out;
}

sub ribbon_hour_facts {
  my ($events) = @_;
  my %part;
  my @order;
  my $remember = sub {
    my ($id, $file, $name) = @_;
    return unless $id;
    push @order, $id unless exists $part{$id};
    $part{$id} = { id => $id, file => $file // '', name => $name // '' };
  };
  my @comms;
  my $preces;
  my $sunday = 0;
  my $creed  = 0;
  for my $e (@$events) {
    my $kind = $e->{kind} // '';
    if ($kind eq 'src') {
      my $name = $e->{name} // '';
      my $cmt  = $e->{comment} // '';
      # The psalm scheme is often filed under the day key (Day2, Prima Day2)
      # with the comment "Psalmi ord", and the short lesson under a season key.
      my $id =
          $name =~ /^Invit/i              ? 'invitatory'
        : $name =~ /Hymnus/i              ? 'hymn'
        : $name =~ /^Ant\b|Antiphona/i    ? 'antiphons'
        : $name =~ /Psalmi|Psalm/i        ? 'psalms'
        : $cmt  =~ /Psalmi/i              ? 'psalms'
        : $name =~ /Versum|Versus/i       ? 'verse'
        : $name =~ /Capitulum/i           ? 'capitulum'
        : $name =~ /Oratio/i              ? 'collect'
        : $name =~ /Lectio brevis/i       ? 'lectio_brevis'
        : $cmt  =~ /Lectio brevis/i       ? 'lectio_brevis'
        :                                   '';
      my $path = ribbon_resolve_label($e->{file});
      $remember->($id, $path, $name);
      # At Matins the proper or common antiphons carry the psalm numbers and
      # replace the weekday scheme that was loaded first.
      if ($name =~ /Ant Matutinum/i && $cmt =~ /subst/i) {
        $remember->('psalms', $path, $name);
      }
    } elsif ($kind eq 'note') {
      my $c = $e->{comment} // '';
      $sunday = 1 if $c =~ /Psalmi dominica/i;
      $creed  = 1 if $c =~ /Quicumque/i;
      if ($c =~ /^(\S+\.txt):\s*\d+/) { push @comms, $1; }
    } elsif ($kind eq 'lab') {
      if (($e->{label} // '') =~ /Preces/i) {
        $preces = (($e->{comment} // '') =~ /omit/i) ? 0 : 1;
      }
    } elsif ($kind eq 'cmt') {
      if (($e->{comment} // '') =~ /Source/i && defined $e->{ind} && $e->{ind} == 6) {
        $sunday = 1;
      }
    }
  }
  $part{psalms}{sunday} = $sunday if $part{psalms};
  return {
    parts  => \%part,
    order  => \@order,
    comms  => \@comms,
    preces => $preces,
    sunday => $sunday,
    creed  => $creed,
  };
}

sub ribbon_run_hour {
  my ($date, $h) = @_;
  $hora = $h;
  $date1 = $date;
  $column = 1;
  @RIBBON_EVENTS = ();
  precedence($date);
  my @script = getordinarium('Latin', $hora);
  @script = specials(\@script, 'Latin');
  if ($h eq 'Matutinum') {
    for my $block (@script) {
      eval { resolve_refs($block, 'Latin'); };
    }
  }
  my @events = @RIBBON_EVENTS;
  my $sum = ribbon_hour_facts(\@events);
  $sum->{vespera} = $vespera;
  $sum->{laudes}  = $laudes;
  $sum->{rank}    = $rank;
  $sum->{winner}  = $winner;
  $sum->{commune} = $commune;
  $sum->{commemoratio} = $commemoratio;
  $sum->{events}  = \@events;
  return $sum;
}

sub ribbon_kind_of {
  my ($file, $rankline, $rank, $dow) = @_;
  $rankline //= '';
  $file     //= '';
  if ($file =~ /Pasc0-0|Pasc7-0/) { return 'sunday_special'; }
  if ($rankline =~ /Dominica/i) { return 'sunday'; }
  if ($file =~ /Sancti|Commune/i || $rankline =~ /S\.|Ss\.|Sanct/i) {
    return 'festive'     if $rank >= 6;
    return 'semifestive' if $rank >= 5 && $rank < 6;
    return 'ordinary'    if $file =~ /Sancti|Commune/i;
  }
  return 'ferial';
}

sub ribbon_capture_names {
  my ($file) = @_;
  my %n;
  for my $lang (@RIBBON_LANGS) {
    $n{$lang} = ribbon_office_name($lang, $file);
    $n{$lang} = $n{Latin} if $n{$lang} eq '' && $lang ne 'Latin';
  }
  return \%n;
}

sub ribbon_resolve {
  my ($date, $version) = @_;
  ribbon_prepare($version);
  my $stock = ribbon_stock_version($version);

  my $mat = ribbon_run_hour($date, 'Matutinum');
  my $nocturns = ($rule =~ /9 lectiones/i) ? 3 : 1;
  for my $e (@{ $mat->{events} }) {
    $nocturns = 3 if ($e->{comment} // '') =~ /9 lectiones/;
    $nocturns = 1 if ($e->{comment} // '') =~ /3 lectiones|One nocturn/;
  }
  $nocturns = 1 if $winner =~ /Pasc0-0|Pasc7-0/;
  my $tedeum = tedeum_required($nocturns == 3 ? 9 : 3) ? 1 : 0;
  my @lessons = ribbon_lessons_from($mat->{events}, $nocturns);

  my %names_rank;
  for my $lang (@RIBBON_LANGS) {
    $names_rank{$lang} = rankname($lang);
  }
  my $kind = ribbon_kind_of($winner, $winner{Rank}, $rank, $dayofweek);
  my $week = $dayname[0] // '';
  my $season = ribbon_season_code($week, $month);

  my %hours = (Matutinum => $mat);
  for my $h (@RIBBON_HOURS) {
    next if $h eq 'Matutinum';
    $hours{$h} = ribbon_run_hour($date, $h);
  }

  my $local_winner = $mat->{winner};
  my $local_key    = ribbon_feast_key($local_winner);
  my $prev = prevnext($date, -1);
  my $first = ribbon_run_hour($prev, 'Vespera');
  my $first_vespers = ($first->{vespera} && $first->{vespera} == 1
      && ribbon_feast_key($first->{winner}) ne ''
      && ribbon_feast_key($first->{winner}) eq $local_key) ? 1 : 0;

  my %general;
  if ($stock ne $version) {
    ribbon_prepare($stock);
    my $gmat = ribbon_run_hour($date, 'Matutinum');
    my $glau = ribbon_run_hour($date, 'Laudes');
    %general = (
      version => $stock,
      winner  => $gmat->{winner},
      rank    => $gmat->{rank},
      names   => ribbon_capture_names($gmat->{winner}),
      rank_name => { Latin => rankname('Latin'), English => rankname('English') },
      laudes_comm => $glau->{commemoratio} || '',
      matins_comm => $gmat->{commemoratio} || '',
    );
    $general{comm_names} = ribbon_capture_names($general{laudes_comm} || $general{matins_comm});
    ribbon_prepare($version);
    ribbon_run_hour($date, 'Matutinum');
  } else {
    %general = (
      version => $version,
      winner  => $local_winner,
      rank    => $mat->{rank},
      names   => {},
      same    => 1,
    );
  }

  my $why = 'other';
  my $gkey = ribbon_feast_key($general{winner});
  my $gcomm = ribbon_feast_key($general{laudes_comm} || $general{matins_comm} || '');
  if ($general{same}) {
    $why = 'same';
  } elsif ($local_winner =~ /Sancti/i && $general{winner} =~ /Tempora/i && $gcomm eq $local_key && $local_key ne '') {
    $why = 'elevated';
  } elsif ($local_key ne '' && $local_key eq $gkey && ($mat->{rank} || 0) != ($general{rank} || 0)) {
    $why = 'rankup';
  } elsif ($local_winner eq $general{winner}) {
    $why = 'same';
  }

  my $vnum = $hours{Vespera}{vespera} || 0;
  return {
    date => $date, version => $version, stock => $stock,
    is_1960 => ($version =~ /1960/ ? 1 : 0),
    month => $month, day => $day, year => $year, dow => $dayofweek,
    week => $week, season => $season,
    winner => $local_winner, rank => $mat->{rank},
    rank_name => \%names_rank,
    names => ribbon_capture_names($local_winner),
    commune => $mat->{commune} || '',
    commune_names => ribbon_capture_names($mat->{commune}),
    scriptura => $scriptura || '',
    kind => $kind, why => $why,
    nocturns => $nocturns, tedeum => $tedeum,
    lessons => \@lessons,
    hours => \%hours,
    first_vespers => $first_vespers,
    vespera => $vnum,
    laudes_scheme => $hours{Laudes}{laudes} || $mat->{laudes} || 1,
    general => \%general,
    dayname => [ @dayname ],
  };
}

sub v_page {
  my ($vol, $k) = @_;
  return unless $vol->{pages}{$k} && ($vol->{pages}{$k}{page} // '') ne '';
  return $vol->{pages}{$k};
}

sub ribbon_find_page {
  my ($edition_id, $season, @keys) = @_;
  my $ed = $RIBBON_EDITIONS{$edition_id} or return;
  return unless @{ $ed->{volumes} || [] };
  my $vol;
  for my $v (@{ $ed->{volumes} }) {
    if ($season && $v->{seasons}{$season}) { $vol = $v; last; }
  }
  my $page;
  if ($vol) {
    for my $k (@keys) {
      my $row = v_page($vol, $k);
      if ($row) { $page = $row; last; }
    }
  }
  return { volume => $vol, page => $page ? $page->{page} : undef, note => $page ? $page->{note} : '' };
}

sub ribbon_keys_for {
  my ($hour, $part, $file) = @_;
  my $stem = ribbon_stem($file);
  my @k;
  push @k, "hour:$hour:$part:$stem" if $hour && $part && $stem;
  push @k, "hour:$hour:$part" if $hour && $part;
  my $sec = ribbon_section($file);
  push @k, "section:$sec:$stem" if $sec && $stem;
  push @k, "section:$sec" if $sec;
  return @k;
}

sub ribbon_page_span {
  my ($code, $found) = @_;
  return '' unless $found && defined $found->{page} && $found->{page} ne '';
  return ' <span class="page-num">' . ribbon_sh($code, 'ui.page') . ' ' . ribbon_h($found->{page}) . '</span>';
}

sub ribbon_quote {
  my ($id) = @_;
  my $c = $RIBBON_CATALOG{$id} or return;
  my $corpus = $c->{corpus} || '';
  my $num = $c->{number};
  my $en_full = ribbon_slice_article($RIBBON_EN{$corpus} || '', $num);
  my $la_row = $RIBBON_LA{$num} || {};
  my $la_full = $la_row->{la} || '';
  my $en = $en_full;
  my $la = $la_full;
  my $en_ok = ($en_full ne '');
  my $la_ok = ($la_full ne '');
  if (defined $c->{en} && $c->{en} ne '') {
    if (index(ribbon_norm($en_full), ribbon_norm($c->{en})) >= 0) {
      $en = $c->{en};
      $en_ok = 1;
    } else {
      $en = '';
      $en_ok = 0;
    }
  }
  if (defined $c->{la} && $c->{la} ne '') {
    if (index(ribbon_norm($la_full), ribbon_norm($c->{la})) >= 0) {
      $la = $c->{la};
      $la_ok = 1;
    } else {
      $la = '';
      $la_ok = 0;
    }
  }
  my $page = $c->{page} || $la_row->{page} || '';
  return {
    id => $id, topic => $c->{topic} || '', number => $num, corpus => $corpus,
    file => $c->{file} || '', page => $page, en => $en, la => $la,
    en_ok => $en_ok, la_ok => $la_ok, en_damaged => ($c->{en_damaged} ? 1 : 0),
  };
}

sub ribbon_quote_html {
  my ($code, $id) = @_;
  my $q = ribbon_quote($id);
  if (!$q) {
    return '<blockquote class="rubric">[to be sourced]</blockquote>';
  }
  my $cite_id = $q->{corpus} eq 'breviary' ? 'ui.rubrics_breviary' : 'ui.rubrics_general';
  my $html = '<blockquote class="rubric">';
  $html .= '<p class="cite"><b>' . ribbon_sh($code, $cite_id, { n => $q->{number} }) . '</b>';
  $html .= '<br>' . ribbon_h($q->{file}) if $q->{file};
  $html .= '</p>';
  if ($q->{en_ok}) {
    my $body = ribbon_h($q->{en});
    $body =~ s/\n/<br>\n/g;
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>' . $body . '</p>';
    if ($q->{en_damaged}) {
      $html .= '<p class="ribbon-note">' . ribbon_sh($code, 'ui.en_damaged') . '</p>';
    }
  } else {
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>[to be sourced]</p>';
  }
  if ($q->{la_ok}) {
    my $body = ribbon_h($q->{la});
    $body =~ s/\n/<br>\n/g;
    my $where = ribbon_s($code, 'ui.quote_la');
    $where .= ', p. ' . $q->{page} if $q->{page};
    $html .= '<p><i>' . ribbon_h($where) . '</i><br>' . $body . '</p>';
  } else {
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_la') . '</i><br>[to be sourced]</p>';
  }
  $html .= '</blockquote>';
  return $html;
}

sub ribbon_part_line {
  my ($code, $edition, $season, $hour, $part, $file, $extra) = @_;
  my $label = ribbon_sh($code, "part.$part");
  my $src = $file ? ribbon_h($file) : '';
  my $found = ribbon_find_page($edition, $season, ribbon_keys_for($hour, $part, $file));
  my $page = ribbon_page_span($code, $found);
  my $more = $extra ? ' — ' . ribbon_h($extra) : '';
  return "<li><b>$label</b>" . ($src ? ": $src" : '') . $more . $page . "</li>\n";
}

sub ribbon_html {
  my ($facts, $lang, $edition_id, $pray) = @_;
  my $code = ribbon_code($lang);
  $edition_id = 'general' unless $RIBBON_EDITIONS{$edition_id};
  my $ed = $RIBBON_EDITIONS{$edition_id};
  my $out = '';
  $out .= '<div class="ribbon-wrap">';

  if (!$facts->{is_1960}) {
    $out .= '<p class="ribbon-note">' . ribbon_sh($code, 'ui.not1960') . '</p>';
  }

  my $title = $facts->{names}{$lang} || $facts->{names}{Latin} || '';
  my $rankn = $facts->{rank_name}{$lang} || $facts->{rank_name}{Latin} || '';
  my $kind  = ribbon_s($code, 'kind.' . $facts->{kind});
  $out .= '<h2>' . ribbon_h($title) . '</h2>';
  $out .= '<p class="ribbon-note">' . ribbon_h($rankn) . ' — ' . ribbon_h($kind)
    . '<br>' . ribbon_sh($code, 'ui.engine') . '</p>';

  $out .= '<h2>' . ribbon_sh($code, 'ui.why') . '</h2>';
  my $g = $facts->{general};
  my $slots = {
    gversion => $g->{version} || $facts->{stock},
    goffice  => ($g->{names}{$lang} || $g->{names}{Latin} || $g->{winner} || ''),
    grank    => ($g->{rank_name}{$lang} || $g->{rank_name}{English} || $g->{rank_name}{Latin} || ''),
    gfeast   => ($g->{comm_names}{$lang} || $g->{comm_names}{Latin} || ''),
    calendar => $facts->{version},
    lrank    => $rankn,
    loffice  => $title,
    office   => $title,
    rank     => $rankn,
    kind     => $kind,
  };
  my $why_id = 'plain.why.' . ($facts->{why} || 'other');
  $out .= '<p>' . ribbon_sh($code, $why_id, $slots) . '</p>';
  if ($facts->{kind} eq 'festive') {
    $out .= '<p>' . ribbon_sh($code, $facts->{first_vespers} ? 'plain.first.yes' : 'plain.first.no') . '</p>';
  }
  my @why_q;
  if ($facts->{why} eq 'elevated') {
    @why_q = qw(GR-25 GR-91-22 GR-91-24 GR-91-12 GR-37);
  } elsif ($facts->{kind} eq 'festive') {
    @why_q = qw(GR-37 GR-91-intro);
  } elsif ($facts->{why} eq 'rankup') {
    @why_q = qw(GR-91-intro);
  }
  $out .= ribbon_quote_html($code, $_) for @why_q;

  # Volume banner
  my $probe = ribbon_find_page($edition_id, $facts->{season}, 'section:psalterium');
  if ($ed && @{ $ed->{volumes} || [] }) {
    if ($probe && $probe->{volume}) {
      my $label = ribbon_volume_label($probe->{volume}, $code);
      $out .= '<p class="volume"><b>' . ribbon_sh($code, 'ui.hold', { label => $label }) . '</b></p>';
    } else {
      my $sname = ribbon_s($code, 'season.' . ($facts->{season} || 'Pent'));
      $out .= '<p class="ribbon-note">' . ribbon_sh($code, 'ui.no_volume', { season => $sname }) . '</p>';
    }
  }

  my $shape = ribbon_shape_html($code, $facts);
  my $feast = ribbon_booklet_feast($facts);
  if ($feast) {
    my $which = ($pray && $pray eq 'booklet') ? 'booklet' : 'book';
    $out .= '<h2>' . ribbon_sh($code, 'ui.how') . '</h2>';
    $out .= '<div class="pray-modes">';
    $out .= '<input type="radio" class="pray-radio" name="pray" id="pray-book" value="book"'
      . ($which eq 'book' ? ' checked' : '') . '>';
    $out .= '<input type="radio" class="pray-radio" name="pray" id="pray-booklet" value="booklet"'
      . ($which eq 'booklet' ? ' checked' : '') . '>';
    $out .= '<div class="pray-switch" role="group">';
    $out .= '<label for="pray-book">' . ribbon_sh($code, 'ui.mode.book') . '</label>';
    $out .= '<label for="pray-booklet">' . ribbon_sh($code, 'ui.mode.booklet') . '</label>';
    $out .= '</div>';
    $out .= '<p class="pray-lead book-lead">' . ribbon_sh($code, 'ui.mode.book_lead') . '</p>';
    $out .= '<p class="pray-lead booklet-lead">' . ribbon_sh($code, 'ui.mode.booklet_lead') . ' '
      . ribbon_booklet_status_html($code, $feast) . '</p>';
    $out .= '<div class="pray-panel book-panel">'
      . ribbon_ribbons_html($code, $edition_id, $facts, 'book') . '</div>';
    $out .= '<div class="pray-panel booklet-panel">'
      . ribbon_ribbons_html($code, $edition_id, $facts, 'booklet') . '</div>';
    $out .= $shape;
    $out .= '<div class="pray-panel book-panel">'
      . ribbon_hours_html($code, $edition_id, $facts, 'book') . '</div>';
    $out .= '<div class="pray-panel booklet-panel">'
      . ribbon_hours_html($code, $edition_id, $facts, 'booklet') . '</div>';
    $out .= '</div>';
  } else {
    $out .= ribbon_ribbons_html($code, $edition_id, $facts, '');
    $out .= $shape;
    $out .= ribbon_hours_html($code, $edition_id, $facts, '');
  }
  $out .= '</div>';
  return $out;
}

sub ribbon_shape_html {
  my ($code, $facts) = @_;
  my $out = '<h2>' . ribbon_sh($code, 'ui.shape') . '</h2>';
  my @shape =
      $facts->{kind} eq 'festive'        ? qw(BR-167)
    : $facts->{kind} eq 'semifestive'    ? qw(BR-168)
    : $facts->{kind} eq 'ordinary'       ? qw(BR-169 BR-177)
    : $facts->{kind} eq 'sunday'         ? qw(BR-165 BR-166)
    : $facts->{kind} eq 'sunday_special' ? qw(BR-163)
    :                                      qw(BR-170 BR-171);
  $out .= ribbon_quote_html($code, $_) for @shape;
  return $out;
}

sub ribbon_hours_html {
  my ($code, $edition_id, $facts, $mode) = @_;
  my $out = '<h2>' . ribbon_sh($code, 'ui.hours') . '</h2>';
  for my $h (@RIBBON_HOURS) {
    $out .= ribbon_hour_html($code, $edition_id, $facts, $h, $mode);
  }
  return $out;
}

sub ribbon_ribbons_html {
  my ($code, $edition_id, $facts, $mode) = @_;
  $mode //= '';
  my $out = '<h2>' . ribbon_sh($code, 'ui.ribbons') . '</h2>';
  $out .= '<ul class="ribbons">';
  my $psalm_file = $facts->{hours}{Matutinum}{parts}{psalms}{file} || 'Psalterium';
  my $which_ps = $facts->{hours}{Laudes}{sunday} ? ribbon_s($code, 'ui.sunday_psalms') : ribbon_s($code, 'ui.weekday_psalms');
  my $scheme = ribbon_s($code, 'ui.scheme', { n => $facts->{laudes_scheme} || 1 });
  $out .= ribbon_section_row($code, $edition_id, $facts, 'psalterium', $psalm_file,
    ribbon_s($code, 'ui.psalter_detail', { which => $which_ps, scheme => $scheme }));

  my $tempora = '';
  for my $cand ($facts->{winner}, $facts->{scriptura}, $facts->{hours}{Laudes}{commemoratio}) {
    if ($cand && $cand =~ /Tempora/i) { $tempora = $cand; last; }
  }
  $out .= ribbon_section_row($code, $edition_id, $facts, 'tempora', $tempora, '');

  if ($mode eq '') {
    my $sancti = ($facts->{winner} =~ /Sancti/i) ? $facts->{winner} : '';
    my $sancti_note = '';
    if (!$sancti) {
      for my $c (@{ $facts->{hours}{Laudes}{comms} || [] }, $facts->{hours}{Laudes}{commemoratio}) {
        if ($c && $c =~ /Sancti/i) { $sancti = $c; $sancti_note = 'commem'; last; }
      }
    }
    $out .= ribbon_section_row($code, $edition_id, $facts, 'sancti', $sancti, $sancti_note);
  } else {
    my @sancti = ribbon_sancti_files($facts, $mode);
    if (!@sancti) {
      $out .= ribbon_section_row($code, $edition_id, $facts, 'sancti', '', '');
    } else {
      my $label = ribbon_sh($code, 'sec.sancti');
      my $detail = join '<br>', map { ribbon_sh($code, 'ui.open', { file => $_ }) } @sancti;
      my $found = ribbon_find_page($edition_id, $facts->{season},
        'section:sancti:' . $sancti[0], 'section:sancti');
      my $page = ribbon_page_span($code, $found);
      $out .= "<li><b>$label</b><br>$detail$page</li>\n";
    }
    if ($mode eq 'booklet') {
      my $file = ribbon_booklet_feast($facts);
      my $label = ribbon_sh($code, 'sec.booklet');
      my $detail = ribbon_sh($code, 'sk.booklet.insert', { file => $file });
      $out .= '<li><b>' . $label . '</b><br>' . $detail . ' '
        . ribbon_booklet_status_html($code, $file) . "</li>\n";
    }
  }

  $out .= ribbon_section_row($code, $edition_id, $facts, 'commune', $facts->{commune}, '');
  $out .= ribbon_section_row($code, $edition_id, $facts, 'ordinarium', 'Ordinarium', '');
  $out .= "</ul>\n";
  return $out;
}

sub ribbon_section_row {
  my ($code, $edition, $facts, $sec, $file, $note) = @_;
  my $label = ribbon_sh($code, "sec.$sec");
  my $found = ribbon_find_page($edition, $facts->{season},
    $file ? ("section:$sec:" . ribbon_stem($file)) : (),
    "section:$sec");
  my $page = ribbon_page_span($code, $found);
  my $detail;
  if (!$file) {
    $detail = ribbon_sh($code, 'ui.unused');
  } elsif ($note eq 'commem') {
    $detail = ribbon_sh($code, 'ui.commem_file', { file => $file });
  } elsif ($note) {
    $detail = ribbon_h($note) . ($file && $file ne 'Ordinarium' ? ' — ' . ribbon_h($file) : '');
  } else {
    $detail = ribbon_sh($code, 'ui.open', { file => $file });
  }
  return "<li><b>$label</b><br>$detail$page</li>\n";
}

# A display name from setbuild ("Commune unius…") is not a file path.
# The commune or the winner that carries that Officium is the path.
sub ribbon_resolve_label {
  my ($label) = @_;
  $label //= '';
  return $label if $label =~ m{/};
  return $label if $label eq '';
  my $wo = $winner{Officium} // '';
  my $co = $commune{Officium} // '';
  for ($wo, $co) { s/\s+\z//; s/\n.*//s; }
  return $winner  if $wo ne '' && index($label, $wo) == 0;
  return $commune if $co ne '' && index($label, $co) == 0;
  return $commune if $label =~ /^Commune\b/i && $commune;
  return $winner  if $winner =~ m{/};
  return $label;
}

sub ribbon_load_booklets {
  %RIBBON_BOOKLET = ();
  my $path = ribbon_root() . '/booklets.txt';
  open my $fh, '<:encoding(UTF-8)', $path or return;
  while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ /^\s*$/ || $line =~ /^\s*#/;
    my ($file, $href) = split /\t/, $line, 2;
    next unless $file;
    $file =~ s/\.txt\z//;
    $file =~ s/^\s+|\s+\z//g;
    $href = '' if !defined $href;
    $href =~ s/^\s+|\s+\z//g;
    # A file with no URL is still in the booklet. The note is shown; the link stays empty.
    $RIBBON_BOOKLET{$file} = $href;
  }
  close $fh;
}

# Href for a future per-parish booklet. Empty until booklets.txt has a URL on the line.
sub ribbon_booklet_href {
  my ($file) = @_;
  return '' unless $file;
  my $stem = ribbon_stem($file);
  return $RIBBON_BOOKLET{$stem} || $RIBBON_BOOKLET{ribbon_base($stem)} || '';
}

# The day's feast, when booklets.txt lists it. Empty href still counts.
sub ribbon_booklet_feast {
  my ($facts) = @_;
  return '' unless $facts;
  my $stem = ribbon_stem($facts->{winner} // '');
  return '' if $stem eq '' || !exists $RIBBON_BOOKLET{$stem};
  return $stem;
}

sub ribbon_commune_stem {
  my ($facts) = @_;
  my $com = ribbon_stem($facts->{commune} || '');
  $com = "Commune/$com" if $com ne '' && $com !~ m{/};
  return $com;
}

# A part the printed book does not have is read from the Common instead.
sub ribbon_book_fallback {
  my ($class, $facts) = @_;
  return $class if !$class || $class->{book};
  my $com = ribbon_commune_stem($facts);
  return $class if $com eq '';
  return {
    place => 'commune', file => $com, book => 1, booklet => '', substituted => 1,
  };
}

# book: stay inside the printed breviary. booklet: the insert supplies book=0 parts.
sub ribbon_view_class {
  my ($class, $facts, $mode) = @_;
  $mode //= '';
  return ribbon_book_fallback($class, $facts) if $mode eq 'book';
  if ($mode eq 'booklet' && $class && !$class->{book}) {
    return { %$class, place => 'booklet' };
  }
  return $class;
}

sub ribbon_booklet_status_html {
  my ($code, $file) = @_;
  my $href = (defined $file && exists $RIBBON_BOOKLET{$file}) ? ($RIBBON_BOOKLET{$file} // '') : '';
  my $attr = ' data-file="' . ribbon_h($file) . '" data-booklet="' . ribbon_h($href) . '"';
  if ($href) {
    return '<a class="print-proper"' . $attr . ' href="' . ribbon_h($href) . '">'
      . ribbon_sh($code, 'sk.booklet.link') . '</a>';
  }
  return '<span class="booklet-soon"' . $attr . '>' . ribbon_sh($code, 'sk.booklet.soon') . '</span>';
}

# Printed Proper of Saints files this mode actually opens.
sub ribbon_sancti_files {
  my ($facts, $mode) = @_;
  my %seen;
  my @out;
  my $add = sub {
    my ($f) = @_;
    $f = ribbon_stem($f // '');
    return if $f eq '' || $seen{$f}++;
    push @out, $f;
  };
  if (($mode || '') ne 'booklet') {
    my $abr = ribbon_abridged_life($facts);
    $add->($abr->{roman}) if $abr && $abr->{roman};
  }
  for my $h (@RIBBON_HOURS) {
    my $sum = $facts->{hours}{$h} or next;
    my $parts = $sum->{parts} || {};
    for my $pid (keys %$parts) {
      my $c = ribbon_view_class(
        ribbon_part_class($h, $pid, $parts->{$pid}{file}), $facts, $mode);
      $add->($c->{file}) if ($c->{place} || '') eq 'sancti' && $c->{book};
    }
  }
  return @out;
}

sub ribbon_base {
  my ($file) = @_;
  $file = ribbon_stem($file // '');
  $file =~ s{.*/}{};
  return $file;
}

sub ribbon_universal_ensure {
  return if $RIBBON_UNIV_READY;
  $RIBBON_UNIV_READY = 1;
  my $table = ribbon_versions_table();
  my @up;
  my $cur = 'Rubrics 1960 - 1960';
  my %seen;
  while ($cur && !$seen{$cur}++) {
    push @up, $cur;
    $cur = $table->{$cur}{base} || '';
    $cur =~ s/^\s+|\s+\z//g;
  }
  my %day;
  for my $ver (reverse @up) {
    my $kal = $table->{$ver}{kalendar} or next;
    my $path = "$Bin/../../www/Tabulae/Kalendaria/$kal.txt";
    open my $fh, '<:encoding(UTF-8)', $path or next;
    while (my $line = <$fh>) {
      chomp $line;
      next if $line =~ /^\s*$/ || $line =~ /^\s*[#*]/;
      next unless $line =~ /=/;
      my ($day, $files) = split /=/, $line, 3;
      next unless $day && $day =~ /^\d\d-\d\d\z/;
      if (!$files || $files eq 'XXXXX') {
        delete $day{$day};
        next;
      }
      my @f = grep { $_ ne '' && $_ ne 'XXXXX' } split /~/, $files;
      $day{$day} = \@f if @f;
    }
    close $fh;
  }
  %RIBBON_UNIV_DAY = %day;
  %RIBBON_UNIV_STEM = ();
  for my $files (values %day) {
    $RIBBON_UNIV_STEM{$_} = 1 for @$files;
  }
}

sub ribbon_office_doc {
  my ($file) = @_;
  my $stem = ribbon_stem($file);
  return $RIBBON_OFFICE_DOC{$stem} if exists $RIBBON_OFFICE_DOC{$stem};
  my $path = "$datafolder/Latin/$stem.txt";
  my %doc = (include => '', sec => {});
  if (open my $fh, '<:encoding(UTF-8)', $path) {
    my $key = '';
    my @body;
    my $flush = sub {
      return unless $key ne '';
      $doc{sec}{$key} = join "\n", @body;
    };
    while (my $line = <$fh>) {
      chomp $line;
      if ($line =~ /^\s*\[([^\]]+)\]\s*$/) {
        $flush->();
        $key = $1;
        $key =~ s/\s+\z//;
        @body = ();
        next;
      }
      if ($key eq '' && $line =~ /^\s*@([^\s:]+)\s*$/) {
        $doc{include} ||= $1;
        next;
      }
      push @body, $line if $key ne '';
    }
    $flush->();
    close $fh;
  }
  $RIBBON_OFFICE_DOC{$stem} = \%doc;
  return \%doc;
}

sub ribbon_first_include {
  my ($body) = @_;
  my $inc;
  for my $line (split /\n/, $body // '') {
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*\(/;
    next if $line =~ /^\s*&/;
    if ($line =~ /^\s*@([^\s:]*)(?::([^\s:]+))?/) {
      $inc ||= { file => $1 // '', key => $2 // '' };
      next;
    }
    return;
  }
  return $inc;
}

sub ribbon_section_owner {
  my ($file, $key, $seen) = @_;
  $seen ||= {};
  my $stem = ribbon_stem($file);
  return $stem if !$stem || $seen->{$stem . '|' . ($key // '')}++;
  my $doc = ribbon_office_doc($stem);
  if ($key && exists $doc->{sec}{$key}) {
    my $inc = ribbon_first_include($doc->{sec}{$key});
    if ($inc) {
      my $next = $inc->{file} || $stem;
      my $nkey = $inc->{key} || $key;
      return $stem if $next eq $stem && $nkey eq $key;
      return ribbon_section_owner($next, $nkey, $seen);
    }
    return $stem;
  }
  return ribbon_section_owner($doc->{include}, $key, $seen) if $doc->{include};
  return $stem;
}

sub ribbon_section_prose {
  my ($file, $key, $seen) = @_;
  $seen ||= {};
  my $stem = ribbon_stem($file);
  return '' if !$stem || $seen->{$stem . '|' . ($key // '')}++;
  my $doc = ribbon_office_doc($stem);
  return '' unless $key && exists $doc->{sec}{$key};
  my $body = $doc->{sec}{$key};
  my $inc = ribbon_first_include($body);
  if ($inc) {
    my $next = $inc->{file} || $stem;
    my $nkey = $inc->{key} || $key;
    return '' if $next eq $stem && $nkey eq $key;
    return ribbon_section_prose($next, $nkey, $seen);
  }
  my @lines;
  for my $line (split /\n/, $body) {
    next if $line =~ /^\s*$/ || $line =~ /^\s*\(/ || $line =~ /^\s*[@\$&]/;
    push @lines, $line;
  }
  return join ' ', @lines;
}

sub ribbon_norm {
  my ($t) = @_;
  $t = lc($t // '');
  $t =~ s/æ/ae/g;
  $t =~ s/œ/oe/g;
  $t =~ s/[áàäâ]/a/g;
  $t =~ s/[éèëê]/e/g;
  $t =~ s/[íìïî]/i/g;
  $t =~ s/[óòöô]/o/g;
  $t =~ s/[úùüû]/u/g;
  $t =~ s/[ýÿ]/y/g;
  $t =~ s/ñ/n/g;
  $t =~ s/[^a-z0-9]//g;
  return $t;
}

sub ribbon_same_text {
  my ($a, $b) = @_;
  $a = ribbon_norm($a);
  $b = ribbon_norm($b);
  return 0 if length($a) < 80 || length($b) < 80;
  return 1 if $a eq $b;
  my $m = length($a) < length($b) ? length($a) : length($b);
  my $n = 0;
  for my $i (0 .. $m - 1) {
    last if substr($a, $i, 1) ne substr($b, $i, 1);
    $n++;
  }
  return $n >= 240;
}

sub ribbon_in_roman_sancti {
  my ($file) = @_;
  ribbon_universal_ensure();
  my $base = ribbon_base($file);
  return 1 if $RIBBON_UNIV_STEM{$base};
  my ($md) = $base =~ /^(\d\d-\d\d)/;
  return 0 unless $md && $RIBBON_UNIV_DAY{$md};
  return 1 if $base eq $md;
  return 1 if $base =~ /^\d\d-\d\d(?:r|o|t|da|p|q|cc|v)\z/;
  return 0;
}

# Where a part is found, and whether a generic 1960 Breviarium Romanum has it.
# place: ordinary | psalter | tempora | sancti | commune | local
# book: 1 if the printed book has it. booklet: future href, or ''.
sub ribbon_classify {
  my ($file, $key) = @_;
  $file = ribbon_stem($file // '');
  my $blank = { place => 'unresolved', file => '', book => 1, booklet => '' };
  return $blank if $file eq '';
  if ($file =~ m{^Psalterium/Psalmi}i) {
    return { place => 'psalter', file => $file, book => 1, booklet => '' };
  }
  if ($file =~ m{^Psalterium/}i || $file =~ /Ordinarium/i) {
    return { place => 'ordinary', file => $file, book => 1, booklet => '' };
  }
  if ($file =~ m{^Tempora/}i) {
    return { place => 'tempora', file => $file, book => 1, booklet => '' };
  }
  if ($file =~ m{^Commune/}i && $file !~ /CommuneM/i) {
    return { place => 'commune', file => $file, book => 1, booklet => '' };
  }
  my $owner = $key ? ribbon_section_owner($file, $key) : $file;
  $owner = ribbon_stem($owner);
  if ($owner =~ m{^Commune/}i && $owner !~ /CommuneM/i) {
    return { place => 'commune', file => $owner, book => 1, booklet => '' };
  }
  if ($owner =~ m{^Tempora/}i) {
    return { place => 'tempora', file => $owner, book => 1, booklet => '' };
  }
  if ($owner =~ m{^Psalterium/Psalmi}i) {
    return { place => 'psalter', file => $owner, book => 1, booklet => '' };
  }
  if (ribbon_in_roman_sancti($owner)) {
    return { place => 'sancti', file => $owner, book => 1, booklet => '' };
  }
  ribbon_universal_ensure();
  my ($md) = ribbon_base($owner) =~ /^(\d\d-\d\d)/;
  if ($md && $RIBBON_UNIV_DAY{$md} && $key) {
    my $prose = ribbon_section_prose($owner, $key);
    for my $uni (@{ $RIBBON_UNIV_DAY{$md} }) {
      my $u = $uni =~ m{/} ? $uni : "Sancti/$uni";
      next if ribbon_stem($u) eq $owner;
      if (ribbon_same_text($prose, ribbon_section_prose($u, $key))) {
        return { place => 'sancti', file => ribbon_stem($u), book => 1, booklet => '' };
      }
    }
  }
  return {
    place => 'local', file => $owner, book => 0,
    booklet => ribbon_booklet_href($owner),
  };
}

sub ribbon_where_html {
  my ($code, $class) = @_;
  my $place = ribbon_s($code, 'sk.place.' . ($class->{place} || 'unresolved'));
  my $file = ($class->{file} && $class->{place} ne 'unresolved') ? ' (' . $class->{file} . ')' : '';
  my $from = ribbon_sh($code, 'sk.from', { place => $place, file => $file });
  my $book;
  if ($class->{book}) {
    $book = '<span class="in-book">' . ribbon_sh($code, 'sk.book.in') . '</span>';
    if ($class->{substituted}) {
      $book .= ' <span class="from-common">' . ribbon_sh($code, 'sk.from_common') . '</span>';
    }
  } else {
    my $stem = ribbon_stem($class->{file} // '');
    my $listed = $stem ne '' && exists $RIBBON_BOOKLET{$stem};
    my $href = $class->{booklet} || ($listed ? ($RIBBON_BOOKLET{$stem} // '') : '');
    my $note = ribbon_sh($code, 'sk.book.out');
    my $attr = ' class="print-proper" data-file="' . ribbon_h($class->{file})
      . '" data-booklet="' . ribbon_h($href) . '"';
    $book = '<span' . $attr . '>' . $note . '</span>';
    if ($href) {
      $book .= ' <a' . $attr . ' href="' . ribbon_h($href) . '">'
        . ribbon_sh($code, 'sk.booklet.link') . '</a>';
    } elsif ($listed) {
      $book .= ' <span class="booklet-soon">' . ribbon_sh($code, 'sk.booklet.soon') . '</span>';
    }
  }
  return '<span class="from">' . $from . '</span> ' . $book;
}

my %RIBBON_PART_KEY = (
  Matutinum => {
    invitatory => 'Invit', hymn => 'Hymnus Matutinum', antiphons => 'Ant Matutinum',
    capitulum => 'Capitulum Laudes', collect => 'Oratio',
  },
  Laudes => {
    hymn => 'Hymnus Laudes', antiphons => 'Ant Laudes', capitulum => 'Capitulum Laudes',
    verse => 'Versum 2', collect => 'Oratio',
  },
  Prima => { collect => 'Oratio', lectio_brevis => '' },
  Tertia => { capitulum => 'Capitulum Tertia', verse => 'Versum Tertia', collect => 'Oratio' },
  Sexta  => { capitulum => 'Capitulum Sexta', verse => 'Versum Sexta', collect => 'Oratio' },
  Nona   => { capitulum => 'Capitulum Nona', verse => 'Versum Nona', collect => 'Oratio' },
  Vespera => {
    hymn => 'Hymnus Vespera', antiphons => 'Ant Vespera', capitulum => 'Capitulum Laudes',
    verse => 'Versum 3', collect => 'Oratio',
  },
  Completorium => { capitulum => 'Capitulum Completorium' },
);

sub ribbon_part_class {
  my ($hour, $pid, $file) = @_;
  my $key = $RIBBON_PART_KEY{$hour}{$pid} || '';
  return ribbon_classify($file, $key);
}

sub ribbon_office_hash {
  my ($stem) = @_;
  $stem = ribbon_stem($stem // '');
  return {} if $stem eq '';
  my $h = eval { setupstring('Latin', "$stem.txt") };
  return ($h && ref $h eq 'HASH') ? $h : {};
}

sub ribbon_rank_num_of {
  my ($stem) = @_;
  my @p = split /;;/, (ribbon_office_hash($stem)->{Rank} // '');
  return undef unless defined $p[2] && $p[2] =~ /([\d.]+)/;
  return $1 + 0;
}

sub ribbon_feast_title {
  my ($stem) = @_;
  my $h = ribbon_office_hash($stem);
  my $o = $h->{Officium} // '';
  $o =~ s/\s+/ /g;
  $o =~ s/^\s+|\s+\z//g;
  return $o if $o =~ /\S/;
  my ($t) = split /;;/, $h->{Rank} // '';
  $t //= '';
  $t =~ s/^\s+|\s+\z//g;
  return $t;
}

sub ribbon_title_words {
  my ($s) = @_;
  $s = lc($s // '');
  $s =~ s/æ/ae/g;
  $s =~ s/œ/oe/g;
  $s =~ tr/áàäâéèëêíìïîóòöôúùüûýÿçñ/aaaaeeeeiiiioooouuuuyycn/;
  $s =~ s/[^a-z0-9 ]//g;
  return grep { $_ ne '' } split / /, $s;
}

sub ribbon_same_title {
  my ($a, $b) = @_;
  my @a = ribbon_title_words($a);
  my @b = ribbon_title_words($b);
  return 0 unless @a >= 3 && @b >= 3;
  return $a[0] eq $b[0] && $a[1] eq $b[1] && $a[2] eq $b[2];
}

sub ribbon_one_lesson_key {
  my ($stem) = @_;
  my $h = ribbon_office_hash($stem);
  return 'Lectio94' if ($h->{Lectio94} // '') =~ /\S/;
  return 'Lectio93' if ($h->{Lectio93} // '') =~ /\S/;
  return 'Lectio4+5+6' if ($h->{Lectio4} // '') =~ /\S/;
  return '';
}

sub ribbon_roman_on {
  my ($md) = @_;
  ribbon_universal_ensure();
  if ($RIBBON_UNIV_DAY{$md} && $RIBBON_UNIV_DAY{$md}[0]) {
    my $f = $RIBBON_UNIV_DAY{$md}[0];
    $f = "Sancti/$f" unless $f =~ m{/};
    return $f if -e "$datafolder/Latin/$f.txt";
  }
  return "Sancti/$md" if $md && -e "$datafolder/Latin/Sancti/$md.txt";
  return '';
}

# A first- or second-class feast whose 1960 book prints only one abridged
# lesson. Lesson 4 is that lesson; lessons 5 and 6 come from the Common.
# Returns a hashref, or undef.
sub ribbon_abridged_life {
  my ($facts) = @_;
  return $facts->{_abridged} if $facts && exists $facts->{_abridged};
  my $finish = sub {
    $facts->{_abridged} = $_[0] if $facts;
    return $_[0];
  };
  return $finish->(undef) unless $facts && ($facts->{rank} || 0) >= 5 && ($facts->{nocturns} || 0) == 3;
  my ($mo, $da) = split /-/, $facts->{date} // '';
  return $finish->(undef) unless defined $mo && $mo ne '';
  my $md = sprintf('%02d-%02d', $mo, $da);
  my $winner = ribbon_stem($facts->{winner});
  my $title = ribbon_feast_title($winner);
  my $roman = ribbon_roman_on($md);
  my $use;
  if ($roman && ribbon_same_title($title, ribbon_feast_title($roman))) {
    my $rr = ribbon_rank_num_of($roman);
    $use = $roman if defined $rr && $rr < 5 && ribbon_one_lesson_key($roman);
  }
  if (!$use) {
    my ($L4) = grep { ($_->{n} || 0) == 4 } @{ $facts->{lessons} || [] };
    my $src = ribbon_stem($L4->{source} // '');
    if ($src && ribbon_in_roman_sancti($src) && ribbon_same_title($title, ribbon_feast_title($src))) {
      my $sr = ribbon_rank_num_of($src);
      $use = $src if defined $sr && $sr < 5 && ribbon_one_lesson_key($src);
    }
  }
  return $finish->(undef) unless $use;
  my @life = grep { ($_->{n} || 0) >= 4 && ($_->{n} || 0) <= 6 } @{ $facts->{lessons} || [] };
  return $finish->(undef) unless @life;
  my $engine = ribbon_stem($life[0]{source} // '');
  return $finish->(undef) if $engine =~ m{^Commune/}i;
  my $owned = ribbon_section_owner($engine, 'Lectio4');
  $engine = $owned if $owned;
  my $com = ribbon_stem($facts->{commune} || '');
  $com = "Commune/$com" if $com ne '' && $com !~ m{/};
  return $finish->({
    roman   => ribbon_stem($use),
    key     => ribbon_one_lesson_key($use),
    engine  => $engine || $winner,
    commune => $com,
    winner  => $winner,
  });
}

sub ribbon_lesson_groups {
  my ($lessons, $noct) = @_;
  my @g;
  for my $L (@{ $lessons || [] }) {
    next unless ($L->{nocturn} || 0) == $noct;
    my $c = ribbon_classify($L->{source}, 'Lectio' . $L->{n});
    # A third-class proprium does not print a third nocturn. Those homily
    # lessons are not in the 1960 book when the feast is said with nine lessons.
    if (($L->{n} || 0) >= 7 && $c->{book} && ($c->{place} || '') eq 'sancti') {
      my $r = ribbon_rank_num_of($c->{file});
      if (defined $r && $r < 5) {
        $c = {
          %$c, book => 0, place => 'local',
          booklet => ribbon_booklet_href($c->{file}),
        };
      }
    }
    my $sig = join "\x1e", ($L->{kind} || ''), $c->{place}, $c->{file}, $c->{book};
    if (@g && $g[-1]{sig} eq $sig && $g[-1]{b} == $L->{n} - 1) {
      $g[-1]{b} = $L->{n};
    } else {
      push @g, { a => $L->{n}, b => $L->{n}, kind => $L->{kind} || '', sig => $sig, class => $c };
    }
  }
  return @g;
}

sub ribbon_skeleton_html {
  my ($code, $facts, $h, $sum, $comms, $mode) = @_;
  $mode = '' unless defined $mode && ($mode eq 'book' || $mode eq 'booklet');
  my $view = sub { ribbon_view_class($_[0], $facts, $mode) };
  my @li;
  my $push = sub { push @li, '<li>' . $_[0] . '</li>'; };
  my $part = $sum->{parts} || {};

  if ($h eq 'Matutinum') {
    for my $pid (qw(invitatory hymn)) {
      next unless $part->{$pid};
      my $c = $view->(ribbon_part_class($h, $pid, $part->{$pid}{file}));
      $push->(ribbon_sh($code, "part.$pid") . ' — ' . ribbon_where_html($code, $c));
    }
    my @rom = qw(I II III);
    my $nn = $facts->{nocturns} || 1;
    for my $noct (1 .. $nn) {
      my $head = ribbon_sh($code, 'sk.nocturn', { n => $rom[$noct - 1] || $noct });
      my @inner;
      if ($part->{antiphons} || $part->{psalms}) {
        my $src = $part->{antiphons} || $part->{psalms};
        my $c = $view->(ribbon_part_class($h, $part->{antiphons} ? 'antiphons' : 'psalms', $src->{file}));
        push @inner, '<li>' . ribbon_sh($code, 'sk.ants_psalms') . ' — ' . ribbon_where_html($code, $c) . '</li>';
      }
      my $abr = ($noct == 2) ? ribbon_abridged_life($facts) : undef;
      if ($abr && $mode eq 'booklet') {
        my $flag = {
          place => 'booklet', file => $abr->{winner}, book => 0,
          booklet => ribbon_booklet_href($abr->{winner}),
        };
        push @inner, '<li>' . ribbon_sh($code, 'sk.engine_life', { file => $abr->{engine} })
          . ' — ' . ribbon_where_html($code, $flag) . '</li>';
      } elsif ($abr) {
        my $proper = { place => 'sancti', file => $abr->{roman}, book => 1, booklet => '' };
        my $common = { place => 'commune', file => $abr->{commune}, book => 1, booklet => '' };
        my $kind = ribbon_s($code, 'lk.abridged');
        push @inner, '<li>' . ribbon_h(ribbon_s($code, 'sk.lesson', { n => 4, kind => $kind }))
          . ' — ' . ribbon_where_html($code, $proper) . '</li>';
        push @inner, '<li>' . ribbon_h(ribbon_s($code, 'sk.lessons_plain', { a => 5, b => 6 }))
          . ' — ' . ribbon_where_html($code, $common) . '</li>';
        push @inner, '<li class="slot-note">' . ribbon_sh($code, 'sk.slot_order') . '</li>';
      } else {
        for my $g (ribbon_lesson_groups($facts->{lessons}, $noct)) {
          my $c = $view->($g->{class});
          my $kind = $g->{kind} ? ribbon_s($code, 'lk.' . $g->{kind}) : '';
          my $lab = $g->{a} == $g->{b}
            ? ribbon_s($code, 'sk.lesson', { n => $g->{a}, kind => $kind })
            : ribbon_s($code, 'sk.lessons', { a => $g->{a}, b => $g->{b}, kind => $kind });
          push @inner, '<li>' . ribbon_h($lab) . ' — ' . ribbon_where_html($code, $c) . '</li>';
        }
      }
      $push->($head . (@inner ? '<ul>' . join('', @inner) . '</ul>' : ''));
    }
    $push->(ribbon_sh($code, $facts->{tedeum} ? 'plain.tedeum.yes' : 'plain.tedeum.no'));
  } else {
    if ($h eq 'Prima' && $facts->{kind} eq 'festive' && !$part->{antiphons}) {
      my $la = $facts->{hours}{Laudes}{parts}{antiphons};
      my $c = $la ? $view->(ribbon_part_class('Laudes', 'antiphons', $la->{file})) : ribbon_classify('', '');
      $push->(ribbon_sh($code, 'part.antiphons') . ' — ' . ribbon_sh($code, 'sk.from_lauds')
        . ' ' . ribbon_where_html($code, $c));
    }
    if ($h =~ /^(?:Tertia|Sexta|Nona)\z/ && ($facts->{kind} eq 'festive' || $sum->{sunday}) && !$part->{antiphons}) {
      my $la = $facts->{hours}{Laudes}{parts}{antiphons};
      my $c = $la ? $view->(ribbon_part_class('Laudes', 'antiphons', $la->{file})) : ribbon_classify('', '');
      $push->(ribbon_sh($code, 'part.antiphons') . ' — ' . ribbon_sh($code, 'sk.from_lauds')
        . ' ' . ribbon_where_html($code, $c));
    }
    for my $pid (qw(antiphons psalms hymn capitulum verse lectio_brevis collect)) {
      next unless $part->{$pid};
      my $c = $view->(ribbon_part_class($h, $pid, $part->{$pid}{file}));
      my $extra = '';
      if ($pid eq 'psalms') {
        $extra = ' — ' . ribbon_h($part->{$pid}{sunday} || $sum->{sunday}
          ? ribbon_s($code, 'ui.sunday_psalms')
          : ribbon_s($code, 'ui.weekday_psalms'));
      }
      $push->(ribbon_sh($code, "part.$pid") . ' — ' . ribbon_where_html($code, $c) . $extra);
    }
    if (defined $sum->{preces}) {
      $push->(ribbon_sh($code, 'part.preces') . ' — '
        . ribbon_sh($code, $sum->{preces} ? 'sk.said' : 'sk.omitted'));
    }
    if ($h eq 'Prima') {
      $push->(ribbon_sh($code, 'part.athanasian') . ' — '
        . ribbon_sh($code, $sum->{creed} ? 'sk.said' : 'sk.omitted'));
      $push->(ribbon_sh($code, 'sk.martyrology'));
    }
    for my $f (@{ $comms || [] }) {
      my $c = ribbon_classify($f, 'Oratio');
      my $name = ribbon_office_name(ribbon_lang_from_code($code), $f) || $f;
      $push->(ribbon_sh($code, 'part.commemoration') . ' — ' . ribbon_h($name) . ' — '
        . ribbon_where_html($code, $c));
    }
  }

  return '' unless @li;
  return '<div class="skeleton"><p class="skeleton-title"><b>' . ribbon_sh($code, 'ui.skeleton')
    . '</b></p><ol class="skeleton">' . join('', @li) . "</ol></div>\n";
}

sub ribbon_martyrology_latin {
  my $path = "$datafolder/Latin/Psalterium/Common/Rubricae.txt";
  open my $fh, '<:encoding(UTF-8)', $path or return '';
  local $/;
  my $text = <$fh>;
  close $fh;
  return '' unless defined $text;
  return $1 if $text =~ m{/:(\s*Deinde in Choro legitur Martyrologium, quod laudabiliter fit etiam extra Chorum\.)\s*:/};
  return '';
}

sub ribbon_martyrology_quote_html {
  my ($code) = @_;
  my $la = ribbon_martyrology_latin();
  return '' if $la eq '';
  return '<blockquote class="rubric ordinary"><p class="cite"><b>'
    . ribbon_sh($code, 'ui.quote_ordinary') . '</b></p><p>'
    . ribbon_h($la) . "</p></blockquote>\n";
}

sub ribbon_hour_html {
  my ($code, $edition, $facts, $h, $mode) = @_;
  $mode = '' unless defined $mode && ($mode eq 'book' || $mode eq 'booklet');
  my $sum = $facts->{hours}{$h} or return '';
  my $out = '<h3>' . ribbon_sh($code, "hora.$h") . '</h3>';
  my @q;
  if ($h eq 'Matutinum') {
    if ($facts->{kind} eq 'sunday_special') {
      $out .= '<p>' . ribbon_sh($code, 'plain.matins.easter') . '</p>';
      @q = qw(BR-163);
    } elsif ($facts->{nocturns} == 3) {
      $out .= '<p>' . ribbon_sh($code, 'plain.matins.nine') . '</p>';
      @q = qw(BR-161 BR-211);
    } else {
      $out .= '<p>' . ribbon_sh($code, 'plain.matins.three') . '</p>';
      @q = qw(BR-162 BR-211);
    }
    my $lesson_plain =
        $facts->{kind} =~ /festive/     ? 'plain.lessons.festive'
      : $facts->{kind} eq 'sunday'      ? 'plain.lessons.sunday'
      : $facts->{kind} eq 'ordinary'    ? 'plain.lessons.ordinary'
      :                                   'plain.lessons.ferial';
    $out .= '<p>' . ribbon_sh($code, $lesson_plain) . '</p>';
    push @q, $facts->{kind} =~ /festive/  ? qw(BR-217 BR-218 BR-219)
            : $facts->{kind} eq 'sunday'   ? qw(BR-220)
            : $facts->{kind} eq 'ordinary' ? qw(BR-221)
            :                                qw(BR-222);
    $out .= '<p>' . ribbon_sh($code, $facts->{tedeum} ? 'plain.tedeum.yes' : 'plain.tedeum.no') . '</p>';
    push @q, $facts->{tedeum} ? 'BR-237' : 'BR-238';
    $out .= '<p>' . ribbon_sh($code, 'plain.antiphons') . '</p>';
    push @q, 'BR-191';
  } elsif ($h eq 'Laudes') {
    my $scheme = ribbon_s($code, 'ui.scheme', { n => $facts->{laudes_scheme} || 1 });
    my $fest = $facts->{kind} =~ /festive/ || $sum->{sunday};
    $out .= '<p>' . ribbon_sh($code, $fest ? 'plain.lauds.festive' : 'plain.lauds.weekday', { scheme => $scheme }) . '</p>';
    @q = qw(BR-197);
    $out .= ribbon_collect_block($code, $sum);
    push @q, qw(BR-246 BR-248) if $sum->{parts}{collect};
  } elsif ($h eq 'Prima') {
    $out .= '<p>' . ribbon_sh($code, 'plain.prime') . '</p>';
    $out .= '<p>' . ribbon_sh($code, 'plain.martyrology') . '</p>';
    $out .= ribbon_martyrology_quote_html($code);
    $out .= '<p>' . ribbon_sh($code, $sum->{creed} ? 'plain.creed.yes' : 'plain.creed.no') . '</p>';
    @q = qw(BR-242 BR-203);
  } elsif ($h =~ /^(?:Tertia|Sexta|Nona)\z/) {
    my $fest = $facts->{kind} eq 'festive' || $sum->{sunday};
    $out .= '<p>' . ribbon_sh($code, $fest ? 'plain.minor.festive' : 'plain.minor.weekday') . '</p>';
  } elsif ($h eq 'Vespera') {
    my $which_id = $facts->{vespera} == 1 ? 'ui.vespers_1' : $facts->{vespera} == 3 ? 'ui.vespers_2' : 'ui.vespers_day';
    $out .= '<p>' . ribbon_sh($code, 'plain.vespers', { which => ribbon_s($code, $which_id) }) . '</p>';
  } elsif ($h eq 'Completorium') {
    $out .= '<p>' . ribbon_sh($code, $sum->{sunday} ? 'plain.compline.sunday' : 'plain.compline.weekday') . '</p>';
  }

  if (defined $sum->{preces}) {
    $out .= '<p>' . ribbon_sh($code, $sum->{preces} ? 'plain.preces.yes' : 'plain.preces.no') . '</p>';
    push @q, 'BR-260' if $h =~ /^(?:Laudes|Vespera)\z/;
  }

  # Only the hours that actually insert a commemoration (the engine's
  # "file.txt: rank" note, at Lauds and Vespers) list one. The day's
  # commemorated office is remembered on every hour and is not said at the
  # little hours or at Compline.
  my @comms = @{ $sum->{comms} || [] };
  my %seen;
  @comms = grep { $_ && !$seen{$_}++ } @comms;
  if (@comms) {
    my @names;
    for my $f (@comms) {
      my $n = ribbon_office_name($code eq 'la' ? 'Latin' : ($code eq 'es' ? 'Espanol' : $code eq 'fr' ? 'Francais' : $code eq 'de' ? 'Deutsch' : 'English'), $f);
      # The language argument above is clumsy; use the facts names when the file matches.
      $n = ribbon_office_name(ribbon_lang_from_code($code), $f) if !$n;
      push @names, $n || $f;
    }
    $out .= '<p>' . ribbon_sh($code, 'plain.commemoration', { name => join('; ', @names) }) . '</p>';
    push @q, 'BR-251' if $h =~ /^(?:Laudes|Vespera)\z/;
  }

  $out .= ribbon_skeleton_html($code, $facts, $h, $sum, \@comms, $mode);
  $out .= ribbon_lesson_table($code, $facts, $mode) if $h eq 'Matutinum';
  $out .= '<ul class="hour-parts">';
  my $parts = $sum->{parts};
  for my $pid (qw(invitatory hymn antiphons psalms verse lessons capitulum collect lectio_brevis)) {
    next unless $parts->{$pid};
    my $file = $parts->{$pid}{file};
    my $extra = '';
    if ($mode eq 'book' || $mode eq 'booklet') {
      my $c = ribbon_view_class(ribbon_part_class($h, $pid, $file), $facts, $mode);
      $file = $c->{file} if $c->{file};
      if ($c->{substituted}) {
        $extra = ribbon_s($code, 'sk.from_common');
      } elsif ($mode eq 'booklet' && !$c->{book}) {
        my $stem = ribbon_stem($c->{file});
        if ($stem && exists $RIBBON_BOOKLET{$stem} && ($RIBBON_BOOKLET{$stem} // '') eq '') {
          $extra = ribbon_s($code, 'sk.booklet.soon');
        }
      }
    }
    if ($pid eq 'psalms') {
      my $ps = $parts->{$pid}{sunday} || $sum->{sunday}
        ? ribbon_s($code, 'ui.sunday_psalms')
        : ribbon_s($code, 'ui.weekday_psalms');
      $extra = $extra ? "$extra — $ps" : $ps;
    }
    $out .= ribbon_part_line($code, $edition, $facts->{season}, $h, $pid, $file, $extra);
  }
  if ($h eq 'Matutinum') {
    $out .= ribbon_part_line($code, $edition, $facts->{season}, $h, 'te_deum', '', $facts->{tedeum} ? 'Te Deum' : '');
  }
  if (@comms) {
    $out .= ribbon_part_line($code, $edition, $facts->{season}, $h, 'commemoration', $comms[0], '');
  }
  $out .= "</ul>\n";
  $out .= ribbon_quote_html($code, $_) for @q;
  return $out;
}

sub ribbon_lang_from_code {
  my ($code) = @_;
  return 'Latin'   if $code eq 'la';
  return 'Espanol' if $code eq 'es';
  return 'Francais' if $code eq 'fr';
  return 'Deutsch' if $code eq 'de';
  return 'English';
}

sub ribbon_collect_block {
  my ($code, $sum) = @_;
  return '<p>' . ribbon_sh($code, 'plain.collect') . '</p>';
}

sub ribbon_lesson_table {
  my ($code, $facts, $mode) = @_;
  $mode = '' unless defined $mode && ($mode eq 'book' || $mode eq 'booklet');
  my $rows = $facts->{lessons} || [];
  return '' unless @$rows;
  my $html = '<h3>' . ribbon_sh($code, 'ui.lessons') . '</h3>';
  my $note =
      ($mode eq 'book' && ribbon_abridged_life($facts))    ? 'sk.table_book'
    : ($mode eq 'booklet' && ribbon_abridged_life($facts)) ? 'sk.table_booklet_life'
    : ($mode eq 'book' && ribbon_booklet_feast($facts))    ? 'sk.table_book_common'
    : ($mode eq 'booklet' && ribbon_booklet_feast($facts)) ? 'sk.table_booklet_proper'
    : ribbon_abridged_life($facts)                         ? 'sk.table_note'
    :                                                        '';
  $html .= '<p>' . ribbon_sh($code, $note) . '</p>' if $note;
  $html .= '<table class="lessons" border="1" cellpadding="4" cellspacing="0">';
  $html .= '<tr><th>' . ribbon_sh($code, 'ui.col_n') . '</th><th>' . ribbon_sh($code, 'ui.col_nocturn')
    . '</th><th>' . ribbon_sh($code, 'ui.col_kind') . '</th><th>' . ribbon_sh($code, 'ui.col_source')
    . '</th><th>' . ribbon_sh($code, 'ui.col_incipit') . '</th></tr>';
  for my $L (@$rows) {
    my $kind = $L->{kind} ? ribbon_sh($code, 'lk.' . $L->{kind}) : '';
    $html .= '<tr><td>' . ribbon_h($L->{n}) . '</td><td>' . ribbon_h($L->{nocturn})
      . '</td><td>' . $kind . '</td><td>' . ribbon_h($L->{source})
      . '</td><td>' . ribbon_h($L->{incipit}) . '</td></tr>';
  }
  $html .= '</table>';
  return $html;
}

sub ribbon_controls {
  my ($version, $date, $edition, $lang) = @_;
  my ($m, $d, $y) = split /-/, $date;
  my $code = ribbon_code($lang);
  my $html = '<div class="ribbon-controls">';
  $html .= '<p><label>' . ribbon_sh($code, 'ui.calendar') . ' ';
  $html .= '<select name="version" onchange="this.form.submit()">';
  for my $v (getdialog('versions')) {
    my $sel = ($v eq $version) ? ' selected' : '';
    $html .= '<option value="' . ribbon_h($v) . "\"$sel>" . ribbon_h($v) . '</option>';
  }
  $html .= '</select></label></p>';

  $html .= '<p><label>' . ribbon_sh($code, 'ui.date') . ' ';
  $html .= '<select name="date" onchange="this.form.submit()">';
  for my $yy (($y - 1) .. ($y + 1)) {
    for my $mm (1 .. 12) {
      my $mlen = ribbon_month_length($yy, $mm);
      my $mname = ribbon_s($code, 'month.' . $mm);
      $html .= '<optgroup label="' . ribbon_h("$mname $yy") . '">';
      for my $dd (1 .. $mlen) {
        my $val = sprintf('%02d-%02d-%04d', $mm, $dd, $yy);
        my $dow = ribbon_dow($yy, $mm, $dd);
        my $dname = ribbon_s($code, 'dow.' . $dow);
        my $sel = ($val eq $date) ? ' selected' : '';
        $html .= '<option value="' . $val . "\"$sel>" . ribbon_h("$dd $mname $yy, $dname") . '</option>';
      }
      $html .= '</optgroup>';
    }
  }
  $html .= '</select></label></p>';

  $html .= '<p><label>' . ribbon_sh($code, 'ui.edition') . ' ';
  $html .= '<select name="edition" onchange="this.form.submit()">';
  for my $id (@RIBBON_EDITION_ORDER) {
    my $sel = ($id eq $edition) ? ' selected' : '';
    $html .= '<option value="' . ribbon_h($id) . "\"$sel>" . ribbon_h(ribbon_edition_label($id, $code)) . '</option>';
  }
  $html .= '</select></label></p>';
  my $ed = $RIBBON_EDITIONS{$edition};
  if (!$ed || $ed->{coming_soon} || !@{ $ed->{volumes} || [] }) {
    $html .= '<p class="ribbon-note">' . ribbon_sh($code, 'ui.edition_soon') . '</p>' if $ed && $ed->{coming_soon};
    $html .= '<p class="ribbon-note">' . ribbon_sh($code, 'ui.volume_note') . '</p>';
  }

  $html .= '<p><label>' . ribbon_sh($code, 'ui.language') . ' ';
  $html .= '<select name="lang" onchange="this.form.submit()">';
  for my $L (@RIBBON_LANGS) {
    my $sel = ($L eq $lang) ? ' selected' : '';
    my $lab = $L eq 'Espanol' ? 'Español' : $L eq 'Francais' ? 'Français' : $L eq 'Latin' ? 'Latine' : $L;
    $html .= '<option value="' . $L . "\"$sel>" . ribbon_h($lab) . '</option>';
  }
  $html .= '</select></label></p>';
  $html .= '<noscript><p><input type="submit" value="Show"></p></noscript>';
  $html .= '</div>';
  return $html;
}

sub ribbon_style {
  return <<'CSS';
<style type="text/css">
.ribbon-wrap { max-width: 48em; margin: 0 auto 3em auto; text-align: left; }
.ribbon-controls { text-align: center; }
.ribbon-controls select { max-width: 36em; }
.ribbon-note { font-size: 0.95em; }
.ribbon-wrap h2, .ribbon-wrap h3 { text-align: left; }
blockquote.rubric { border-left: 3px solid maroon; margin: 0.8em 0; padding: 0.2em 0.8em; }
blockquote.rubric .cite { color: maroon; }
ul.ribbons li, ul.hour-parts li { margin: 0.45em 0; }
.page-num { color: maroon; font-weight: bold; }
ol.skeleton { margin: 0.4em 0 1em 1.2em; padding: 0; }
ol.skeleton li { margin: 0.35em 0; }
ol.skeleton ul { margin: 0.2em 0 0.4em 1.2em; padding: 0; }
.skeleton-title { margin-bottom: 0.2em; }
.in-book { color: #333; }
.print-proper { color: maroon; font-weight: bold; }
table.lessons { border-collapse: collapse; width: 100%; }
table.lessons td, table.lessons th { vertical-align: top; text-align: left; }
p.volume { color: maroon; }
.pray-modes { position: relative; }
.pray-radio { position: absolute; left: -9999px; width: 1px; height: 1px; margin: 0; }
.pray-switch { display: flex; flex-wrap: wrap; gap: 0.4em; }
.pray-switch label {
  flex: 1 1 12em; text-align: center; border: 2px solid maroon; border-radius: 0.4em;
  padding: 0.7em 0.6em; font-weight: bold; cursor: pointer; background: #fff; color: maroon;
}
#pray-book:checked ~ .pray-switch label[for="pray-book"],
#pray-booklet:checked ~ .pray-switch label[for="pray-booklet"] { background: maroon; color: #fff; }
.book-panel, .booklet-panel, .book-lead, .booklet-lead { display: none; }
#pray-book:checked ~ .book-panel, #pray-book:checked ~ .book-lead { display: block; }
#pray-booklet:checked ~ .booklet-panel, #pray-booklet:checked ~ .booklet-lead { display: block; }
.pray-lead { margin: 0.7em 0; }
.booklet-soon { color: maroon; font-weight: bold; }
.from-common { display: block; font-size: 0.92em; }
li.slot-note { list-style: none; margin-left: -1.2em; font-size: 0.92em; }
</style>
CSS
}

sub ribbon_strings_missing_la {
  my @ids;
  for my $id (sort keys %RIBBON_STRINGS) {
    my $la = $RIBBON_STRINGS{$id}{la};
    push @ids, $id if !defined $la || $la eq '';
  }
  return @ids;
}

sub ribbon_gaps_markdown {
  my $n = 0;
  my $en_ok = 0;
  my $en_gap = 0;
  my $la_ok = 0;
  my $la_gap = 0;
  my @rows;
  for my $id (sort keys %RIBBON_CATALOG) {
    my $q = ribbon_quote($id);
    $n++;
    $en_ok += $q->{en_ok} ? 1 : 0;
    $en_gap += $q->{en_ok} ? 0 : 1;
    $la_ok += $q->{la_ok} ? 1 : 0;
    $la_gap += $q->{la_ok} ? 0 : 1;
    my $en = $q->{en_ok} ? ($q->{en_damaged} ? 'sourced, file damaged' : 'sourced') : '[to be sourced]';
    my $la = $q->{la_ok} ? "AAS 52 (1960), p. $q->{page}, n. $q->{number}" : '[to be sourced]';
    my $topic = $q->{topic};
    $topic =~ s/\|/\//g;
    push @rows, "| $id | $topic | $en | $la | $q->{file} |";
  }
  my @no_la = ribbon_strings_missing_la();
  my $md = <<"MD";
# Rubric quotations still to be sourced

The ribbon helper quotes the 1960 *Codex Rubricarum*.

- English is taken from `web/www/horas/Help/Rubrics/General Rubrics.html` (articles 1–137) and `web/www/horas/Help/Rubrics/Breviary 1960.html` (articles 138–268). Those files are the English source. Nothing is invented, and the pre-1960 files `web/www/horas/Help/Rubrics/R01.txt`–`R37.txt` are not used.
- Latin is taken from the plain-text transcription at <https://clemensdsh.xyz/posts/aas-1960-rubricae-et-calendarium-latin/>, which was OCR'd from the AAS page images and collated with them. Every Latin quotation is attributed to **Acta Apostolicae Sedis, vol. 52 (1960)**, with the printed page and the article number. The transcription is only the working copy.
- Stored Latin: `web/www/horas/Ribbon/aas52-la.txt`. The catalogue of what the page cites: `web/www/horas/Ribbon/catalog.txt`.

## Counts

| | |
| --- | --- |
| Quotations in the catalogue | $n |
| English sourced from the project files | $en_ok |
| English still [to be sourced] | $en_gap |
| Latin sourced from AAS 52 (1960) | $la_ok |
| Latin still [to be sourced] | $la_gap |
| Plain-language strings with no Latin wording | ${\(scalar @no_la)} |

## Catalogue

| Id | Topic | English | Latin | File |
| --- | --- | --- | --- | --- |
MD
  $md .= join("\n", @rows) . "\n";
  $md .= <<'MD';

## English articles quoted as the file has them

These project transcriptions are visibly damaged. They are still quoted, because those files are the English source, and the AAS Latin is shown beside them.

| Article | What is wrong in the project file |
| --- | --- |
| 165 | "the arrangement of thew Office" |
| 169 | "Proper of the Common"; "proper of from the common" |
| 171 | "on If rids" where the sentence should name ferias |
| 219 | the second clause is lettered "h)" |
| 221 | "The first and second lessons as are said" |

## Restorations checked against the AAS page images

The transcription marks seventeen places (sixteen in the articles, one in a heading) where the photograph was unclear and the text was restored. They were compared with `AAS-52-1960-ocr.pdf` before the marks were removed from `aas52-la.txt`.

| Place | What the image/OCR showed | Reading kept |
| --- | --- | --- |
| n. 8 | The article number was not a clear 8 (`<S` / `≮`) | The sentence *Dies liturgici sunt primae…* |
| n. 11 | Letters of the Sunday list misread (`d)`, `' /)`) | Sequential letters a–f, which the page image bears |
| n. 14 | Article number read as 11, between 13 and 15 | Body *Dominica celebratur suo die* |
| n. 16 | Letter read as `o)` | `b)`, as the page image has it |
| n. 30 | `milia fit commemoratio` | `nulla fit commemoratio` (the page image reads *nulla*) |
| n. 34 | `Oflicium` / `Oficium` | `Officium` |
| n. 52 | A letter read as `1)` | The restored letter in sequence |
| n. 68 | A doubtful letter glyph | The restored letter in sequence |
| n. 77 | `Septuagesimo`, with the editor's note that it should be *Septuagesima* | `in Septuagesima` |
| n. 90 | A stray stop in `non. intersunt` | `non intersunt, non tenentur` (the page image has the second *non*) |
| n. 91, table item on the vigil | Printed `dominicae occurrente`; the editor suggested *occurrenti* | `occurrente`, as printed. This sentence is not one of the lines the page quotes |
| n. 91, a letter before a patron feast | Read as `S)` | The restored letter. That line is not one of the lines the page quotes |
| n. 95 | Article number read as `05` | Body *Ius translationis* |
| n. 109 | Two doubtful letter glyphs | The restored letters in sequence |
| Heading of chapter 16 | `COMMEMORATIO^J.BUS` | Not part of an article quotation |

The lines the page actually quotes from n. 91 (the introduction, proper 1st class feasts, the 3rd class Lenten ferias, and universal 3rd class feasts) do not contain those two flagged spots.

## Plain language with no Latin wording

The Latin of the Code, above, is a different thing from a Latin paraphrase. Where no `la:` line is stored, the Latin view of the page shows the English sentence and the marker `[to be sourced]`. Hour names, section names, and the short rubrical sentences that are ordinary Latin do have a `la:` line.

MD
  $md .= join("\n", map { "- `$_`" } @no_la) . "\n";
  return $md;
}

sub ribbon_selftest {
  ribbon_boot();
  my $fail = 0;
  my $ok = sub { print "OK  $_[0]\n"; };
  my $bad = sub { print "FAIL $_[0]\n"; $fail++; };

  $ok->('latin articles ' . scalar(keys %RIBBON_LA)) if keys(%RIBBON_LA) == 268;
  $bad->('latin article count ' . scalar(keys %RIBBON_LA)) if keys(%RIBBON_LA) != 268;

  my $q25 = ribbon_quote('GR-25');
  $q25->{en_ok} && $q25->{en} =~ /preferred to feasts of the 3rd class/ ? $ok->('GR-25 en') : $bad->('GR-25 en');
  $q25->{la_ok} && $q25->{la} =~ /praeferuntur festis III classis/ ? $ok->('GR-25 la') : $bad->('GR-25 la');
  my $q161 = ribbon_quote('BR-161');
  $q161->{la_ok} && $q161->{la} =~ /tribus Nocturnis/ ? $ok->('BR-161 la') : $bad->('BR-161 la');
  my $q22 = ribbon_quote('GR-91-22');
  $q22->{en_ok} && $q22->{la_ok} ? $ok->('GR-91-22 both') : $bad->("GR-91-22 en=$q22->{en_ok} la=$q22->{la_ok}");

  my $gaps = 0;
  for my $id (keys %RIBBON_CATALOG) {
    my $q = ribbon_quote($id);
    $gaps++ if !$q->{en_ok} || !$q->{la_ok};
  }
  $gaps == 0 ? $ok->('catalogue fully sourced') : $bad->("$gaps catalogue rows missing a language");

  ribbon_season_code('Quad4', 3) eq 'Quad' ? $ok->('season Quad') : $bad->('season Quad');
  ribbon_season_code('Epi3', 1) eq 'Epi' ? $ok->('season Epi') : $bad->('season Epi');
  ribbon_season_code('Epi6', 11) eq 'Pent' ? $ok->('late Epi is Pent') : $bad->('late Epi');
  ribbon_season_code('Adv1', 12) eq 'Adv' ? $ok->('season Adv') : $bad->('season Adv');

  my $sample = ribbon_parse_edition(<<'ED');
id: sample
coming_soon: 0
name.en: Sample three volumes
volume: II
label.en: Volume II — Septuagesima to Pentecost
seasons: Quadp Quad Pasc
hour:Matutinum:lessons	80
section:psalterium	14
volume: III
label.en: Volume III — after Pentecost
seasons: Pent
hour:Matutinum:lessons	90
section:psalterium	10
ED
  my $hit = do {
    local $RIBBON_EDITIONS{sample} = $sample;
    ribbon_find_page('sample', 'Quad', 'hour:Matutinum:lessons');
  };
  ($hit && $hit->{page} eq '80' && $hit->{volume}{id} eq 'II')
    ? $ok->('volume II for Lent')
    : $bad->('volume II page ' . (($hit && $hit->{page}) // 'none'));
  my $hit3 = do {
    local $RIBBON_EDITIONS{sample} = $sample;
    ribbon_find_page('sample', 'Pent', 'section:psalterium');
  };
  ($hit3 && $hit3->{page} eq '10' && $hit3->{volume}{id} eq 'III')
    ? $ok->('volume III after Pentecost')
    : $bad->('volume III');

  $RIBBON_EDITIONS{general} && $RIBBON_EDITIONS{general}{coming_soon}
    && !@{ $RIBBON_EDITIONS{general}{volumes} }
    ? $ok->('general edition has no volumes')
    : $bad->('general edition');
  (grep { $_ eq 'general' } @RIBBON_EDITION_ORDER)
    ? $ok->('edition dropdown discovers general.edition')
    : $bad->('edition discovery');

  my $el = ribbon_resolve('03-17-2026', 'Rubrics 1960 - Diocese of El Paso');
  ($el->{winner} =~ /03-17/ && $el->{rank} >= 6 && $el->{kind} eq 'festive' && $el->{nocturns} == 3)
    ? $ok->("El Paso festive $el->{winner} rank $el->{rank}")
    : $bad->("El Paso winner=$el->{winner} rank=$el->{rank} kind=$el->{kind} nocturns=$el->{nocturns}");
  ($el->{commune} =~ /C4/ && ($el->{hours}{Laudes}{commemoratio} || '') =~ /Quad4/)
    ? $ok->('El Paso common and feria commemoration')
    : $bad->("commune=$el->{commune} laudes-comm=$el->{hours}{Laudes}{commemoratio}");
  (@{ $el->{hours}{Laudes}{comms} } && $el->{hours}{Laudes}{comms}[0] =~ /Quad4/
      && @{ $el->{hours}{Vespera}{comms} }
      && !@{ $el->{hours}{Prima}{comms} }
      && !@{ $el->{hours}{Completorium}{comms} })
    ? $ok->('commemoration only at Lauds and Vespers')
    : $bad->('commemoration hours L=' . join(',', @{ $el->{hours}{Laudes}{comms} })
      . ' P=' . join(',', @{ $el->{hours}{Prima}{comms} }));
  (($el->{hours}{Prima}{parts}{psalms}{file} || '') =~ /Psalmi minor/
      && ($el->{hours}{Prima}{parts}{lectio_brevis}{file} || '') =~ /Prima/)
    ? $ok->('Prime psalms and short lesson')
    : $bad->('Prime parts ' . join(',', sort keys %{ $el->{hours}{Prima}{parts} }));
  (($el->{hours}{Matutinum}{parts}{psalms}{file} || '') =~ /Confessoris|C4/)
    ? $ok->('Matins psalms from the Common')
    : $bad->('Matins psalms ' . ($el->{hours}{Matutinum}{parts}{psalms}{file} // ''));
  $el->{why} eq 'elevated' ? $ok->('El Paso elevated') : $bad->("why=$el->{why} general=$el->{general}{winner}");
  $el->{tedeum} ? $ok->('El Paso Te Deum') : $bad->('El Paso Te Deum');
  $el->{first_vespers} ? $ok->('El Paso first vespers') : $bad->('El Paso first vespers');
  (grep { $_->{n} == 1 && $_->{source} =~ /C4/ } @{ $el->{lessons} })
    ? $ok->('lessons 1-3 from the Common')
    : $bad->('lesson 1 source ' . ($el->{lessons}[0]{source} // ''));
  (grep { $_->{n} == 4 && ($_->{kind} || '') eq 'legend' } @{ $el->{lessons} })
    ? $ok->('lesson 4 is the life')
    : $bad->('lesson 4 kind ' . join(',', map { $_->{n} . ':' . $_->{kind} . ':' . $_->{source} } @{ $el->{lessons} }));
  my $life = ribbon_classify($el->{lessons}[3]{source}, 'Lectio4');
  ($life->{place} eq 'sancti' && $life->{file} =~ /03-17/ && $life->{file} !~ /nl/)
    ? $ok->('Patrick life text is the universal file')
    : $bad->("life place=$life->{place} file=$life->{file} book=$life->{book}");
  my $abr = ribbon_abridged_life($el);
  ($abr && $abr->{roman} =~ /03-17/ && $abr->{key} eq 'Lectio4+5+6' && $abr->{commune} =~ /C4/)
    ? $ok->('Patrick book prints one abridged lesson')
    : $bad->('abridged ' . ($abr ? "$abr->{roman} $abr->{key} $abr->{commune}" : 'undef'));
  my $sk = ribbon_skeleton_html('en', $el, 'Matutinum', $el->{hours}{Matutinum}, [], 'book');
  ($sk =~ /class="skeleton"/ && $sk =~ /Nocturn I/ && $sk =~ /Lessons 1/
      && $sk =~ /Lesson 4: abridged lesson of the saint/ && $sk =~ /Sancti\/03-17/
      && $sk =~ /Lessons 5/ && $sk =~ /Commune\/C4/ && $sk =~ /in the printed breviary/
      && $sk =~ /order used here/ && $sk !~ /Some arrange/ && $sk !~ /03-17nl1/
      && $sk !~ /print this proper separately/)
    ? $ok->('El Paso breviary-only Nocturn II')
    : $bad->('El Paso book skeleton');
  my $sklet = ribbon_skeleton_html('en', $el, 'Matutinum', $el->{hours}{Matutinum}, [], 'booklet');
  ($sklet =~ /three older life lessons/ && $sklet =~ /Sancti\/03-17/
      && $sklet =~ /data-file="Sancti\/03-17nl1"/ && $sklet =~ /Booklet coming soon/
      && $sklet =~ /propers booklet/ && $sklet !~ /abridged lesson of the saint/)
    ? $ok->('El Paso booklet Nocturn II is the three life lessons')
    : $bad->('El Paso booklet skeleton');
  my $q218 = ribbon_quote('BR-218');
  ($q218->{en_ok} && $q218->{en} =~ /made up by lessons taken from the Common/
      && $q218->{la_ok} && $q218->{la} =~ /numerus ternarius completur lectionibus de Communi/)
    ? $ok->('BR-218 both languages')
    : $bad->('BR-218 quote');
  my $gu = ribbon_resolve('12-12-2026', 'Rubrics 1960 - Diocese of Phoenix');
  exists $RIBBON_BOOKLET{'Sancti/03-17nl1'}
    ? $ok->('booklet seam lists Patrick')
    : $bad->('03-17nl1 missing from booklets.txt');
  ($gu->{winner} =~ /12-12s/)
    ? $ok->('Phoenix Guadalupe')
    : $bad->("Phoenix winner=$gu->{winner}");
  my $gbook = ribbon_skeleton_html('en', $gu, 'Matutinum', $gu->{hours}{Matutinum}, [], 'book');
  ($gbook =~ /Commune\/C11/ && $gbook =~ /This proper is not in the printed breviary/
      && $gbook =~ /Sancti\/12-08/ && $gbook !~ /data-file="Sancti\/12-12s"/
      && $gbook =~ /Lessons 1/ && $gbook =~ /Lessons 7/)
    ? $ok->('Guadalupe breviary-only stays in the book')
    : $bad->('Guadalupe book skeleton');
  my $gsk = ribbon_skeleton_html('en', $gu, 'Matutinum', $gu->{hours}{Matutinum}, [], 'booklet');
  ($gsk =~ /print this proper separately/ && $gsk =~ /data-booklet=""/ && $gsk =~ /data-file="Sancti\/12-12s"/
      && $gsk =~ /Booklet coming soon/ && $gsk =~ /propers booklet/
      && $gsk =~ /Lessons 7.{1,3}9: Homily/ && $gsk =~ /Antiphons and psalms/)
    ? $ok->('particular proper flagged, booklet link empty')
    : $bad->('Guadalupe skeleton');
  my $rb = ribbon_ribbons_html('en', 'general', $el, 'book');
  ($rb =~ /Sancti\/03-17/ && $rb !~ /03-17nl1/ && $rb =~ /Commune\/C4/)
    ? $ok->('Patrick breviary ribbons open the printed proper')
    : $bad->('Patrick book ribbons');
  my $rl = ribbon_ribbons_html('en', 'general', $el, 'booklet');
  ($rl =~ /03-17nl1/ && $rl =~ /Booklet coming soon/ && $rl =~ /Insert the propers booklet/)
    ? $ok->('Patrick booklet ribbon names the insert')
    : $bad->('Patrick booklet ribbons');
  my $gb = ribbon_ribbons_html('en', 'general', $gu, 'book');
  ($gb =~ /Sancti\/12-08/ && $gb !~ /12-12s/ && $gb =~ /Commune\/C11/)
    ? $ok->('Guadalupe breviary ribbons omit the unprinted proper')
    : $bad->('Guadalupe book ribbons');
  my $gl = ribbon_ribbons_html('en', 'general', $gu, 'booklet');
  ($gl =~ /12-12s/ && $gl =~ /Booklet coming soon/ && $gl =~ /Sancti\/12-08/)
    ? $ok->('Guadalupe booklet ribbon names the insert')
    : $bad->('Guadalupe booklet ribbons');
  {
    local $RIBBON_BOOKLET{'Sancti/12-12s'} = '/booklets/phoenix';
    my $linked = ribbon_skeleton_html('en', $gu, 'Matutinum', $gu->{hours}{Matutinum}, [], 'booklet');
    $linked =~ m{href="/booklets/phoenix"} && $linked =~ /data-booklet="\/booklets\/phoenix"/
      ? $ok->('booklet seam accepts a later href')
      : $bad->('booklet seam');
  }

  my $gen = ribbon_resolve('03-17-2026', 'Rubrics 1960 - 1960');
  ($gen->{winner} =~ /Quad4-2/ && $gen->{kind} eq 'ferial' && $gen->{nocturns} == 1)
    ? $ok->('universal feria')
    : $bad->("universal winner=$gen->{winner} kind=$gen->{kind} nocturns=$gen->{nocturns}");
  my $genhtml = ribbon_html($gen, 'English', 'general');
  $genhtml !~ /pray-modes/ ? $ok->('a day without a booklet feast has one instruction')
    : $bad->('universal page showed the mode toggle');
  my $aas = ribbon_slurp(ribbon_root() . '/aas52-la.txt');
  $aas !~ /laudabiliter/i ? $ok->('AAS 52 transcription has no laudabiliter')
    : $bad->('unexpected laudabiliter in aas52-la.txt');
  my $mla = ribbon_martyrology_latin();
  $mla eq 'Deinde in Choro legitur Martyrologium, quod laudabiliter fit etiam extra Chorum.'
    ? $ok->('Ordinary Martyrology sentence')
    : $bad->("martyrology latin [$mla]");

  my $html = ribbon_controls($el->{version}, $el->{date}, 'general', 'English') . ribbon_html($el, 'English', 'general');
  $html =~ /name="version"/ && $html =~ /name="date"/ && $html =~ /name="edition"/
    ? $ok->('three dropdowns')
    : $bad->('three dropdowns');
  $html =~ /General structure only/ ? $ok->('edition option') : $bad->('edition option');
  $html =~ /temporal cycle/ ? $ok->('volume note') : $bad->('volume note');
  $html =~ /class="page-num"/ ? $bad->('page number shown for general edition') : $ok->('no page numbers yet');
  $html =~ /praeferuntur|preferred to feasts/ ? $ok->('quote on the page') : $bad->('quote missing on the page');
  $html =~ /numerus ternarius completur lectionibus de Communi/
    ? $ok->('art. 218 on the El Paso page')
    : $bad->('art. 218 missing on the page');
  $html =~ /abridged lesson of the saint/ && $html =~ /print this proper separately/
    && $html =~ /id="pray-book"[^>]*checked/ && $html =~ /Breviary only/
    && $html =~ /Breviary \+ propers booklet/ && $html =~ /Booklet coming soon/
    && $html !~ /Some arrange/
    ? $ok->('El Paso page states the book and the booklet')
    : $bad->('El Paso page skeleton');
  my $guhtml = ribbon_html($gu, 'English', 'general', 'booklet');
  ($guhtml =~ /id="pray-booklet"[^>]*checked/ && $guhtml =~ /Sancti\/12-12s/
      && $guhtml =~ /Booklet coming soon/ && $guhtml =~ /Commune\/C11/)
    ? $ok->('Guadalupe page has both modes')
    : $bad->('Guadalupe page modes');
  $html =~ /AAS 52/ ? $ok->('AAS attribution') : $bad->('AAS attribution');
  ($html =~ /Deinde in Choro legitur Martyrologium, quod laudabiliter fit etiam extra Chorum/
      && $html =~ /not required in order to satisfy the obligation/
      && $html =~ /V\. Pretiósa in conspéctu Dómini/
      && $html =~ /not an article of the Codex in AAS 52/)
    ? $ok->('Martyrology note quotes the Ordinary and says it is not required')
    : $bad->('Martyrology note');

  my $de = ribbon_html($el, 'Deutsch', 'general');
  $de =~ /Fastenferie/ ? $ok->('German plain') : $bad->('German plain');
  my $es = ribbon_html($el, 'Espanol', 'general');
  $es =~ /Cuaresma/ ? $ok->('Spanish plain') : $bad->('Spanish plain');
  my $fr = ribbon_html($el, 'Francais', 'general');
  $fr =~ /Carême/ ? $ok->('French plain') : $bad->('French plain');
  my $la = ribbon_html($el, 'Latin', 'general');
  $la =~ /praeferuntur festis III classis/ ? $ok->('Latin quote on the page') : $bad->('Latin quote');
  $la =~ /\[to be sourced\]/ ? $ok->('Latin plain still marked where unwritten') : $bad->('expected a Latin plain gap');

  for my $id (sort keys %RIBBON_STRINGS) {
    for my $k (qw(en es fr de)) {
      if (!defined $RIBBON_STRINGS{$id}{$k} || $RIBBON_STRINGS{$id}{$k} eq '') {
        $bad->("string $id missing $k");
      }
    }
  }

  my $doc = ribbon_gaps_markdown();
  open my $fh, '>:encoding(UTF-8)', "$Bin/../../../docs/rubric-quotes-to-source.md" or die $!;
  print $fh $doc;
  close $fh;
  $doc =~ /Latin still \[to be sourced\] \| 0/ ? $ok->('gap doc latin 0') : $bad->('gap doc count');

  print $fail ? "FAILED $fail\n" : "ALL OK\n";
  return $fail ? 1 : 0;
}

1;
