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
        $L[$j]{kind} = ($L[$j]{nocturn} == 2) ? 'legend' : 'scripture';
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
      $remember->($id, $e->{file}, $name);
      # At Matins the proper or common antiphons carry the psalm numbers and
      # replace the weekday scheme that was loaded first.
      if ($name =~ /Ant Matutinum/i && $cmt =~ /subst/i) {
        $remember->('psalms', $e->{file}, $name);
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
  my ($facts, $lang, $edition_id) = @_;
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

  $out .= '<h2>' . ribbon_sh($code, 'ui.ribbons') . '</h2>';
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

  my $sancti = ($facts->{winner} =~ /Sancti/i) ? $facts->{winner} : '';
  my $sancti_note = '';
  if (!$sancti) {
    for my $c (@{ $facts->{hours}{Laudes}{comms} || [] }, $facts->{hours}{Laudes}{commemoratio}) {
      if ($c && $c =~ /Sancti/i) { $sancti = $c; $sancti_note = 'commem'; last; }
    }
  }
  $out .= ribbon_section_row($code, $edition_id, $facts, 'sancti', $sancti, $sancti_note);

  $out .= ribbon_section_row($code, $edition_id, $facts, 'commune', $facts->{commune}, '');
  $out .= ribbon_section_row($code, $edition_id, $facts, 'ordinarium', 'Ordinarium', '');
  $out .= "</ul>\n";

  $out .= '<h2>' . ribbon_sh($code, 'ui.shape') . '</h2>';
  my @shape =
      $facts->{kind} eq 'festive'        ? qw(BR-167)
    : $facts->{kind} eq 'semifestive'    ? qw(BR-168)
    : $facts->{kind} eq 'ordinary'       ? qw(BR-169 BR-177)
    : $facts->{kind} eq 'sunday'         ? qw(BR-165 BR-166)
    : $facts->{kind} eq 'sunday_special' ? qw(BR-163)
    :                                      qw(BR-170 BR-171);
  $out .= ribbon_quote_html($code, $_) for @shape;

  $out .= '<h2>' . ribbon_sh($code, 'ui.hours') . '</h2>';
  for my $h (@RIBBON_HOURS) {
    $out .= ribbon_hour_html($code, $edition_id, $facts, $h);
  }
  $out .= '</div>';
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

sub ribbon_hour_html {
  my ($code, $edition, $facts, $h) = @_;
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
    $out .= ribbon_lesson_table($code, $facts);
  } elsif ($h eq 'Laudes') {
    my $scheme = ribbon_s($code, 'ui.scheme', { n => $facts->{laudes_scheme} || 1 });
    my $fest = $facts->{kind} =~ /festive/ || $sum->{sunday};
    $out .= '<p>' . ribbon_sh($code, $fest ? 'plain.lauds.festive' : 'plain.lauds.weekday', { scheme => $scheme }) . '</p>';
    @q = qw(BR-197);
    $out .= ribbon_collect_block($code, $sum);
    push @q, qw(BR-246 BR-248) if $sum->{parts}{collect};
  } elsif ($h eq 'Prima') {
    $out .= '<p>' . ribbon_sh($code, 'plain.prime') . '</p>';
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

  $out .= '<ul class="hour-parts">';
  my $parts = $sum->{parts};
  for my $pid (qw(invitatory hymn antiphons psalms verse lessons capitulum collect lectio_brevis)) {
    next unless $parts->{$pid};
    my $extra = '';
    if ($pid eq 'psalms') {
      $extra = $parts->{$pid}{sunday} || $sum->{sunday}
        ? ribbon_s($code, 'ui.sunday_psalms')
        : ribbon_s($code, 'ui.weekday_psalms');
    }
    $out .= ribbon_part_line($code, $edition, $facts->{season}, $h, $pid, $parts->{$pid}{file}, $extra);
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
  my ($code, $facts) = @_;
  my $rows = $facts->{lessons} || [];
  return '' unless @$rows;
  my $html = '<h3>' . ribbon_sh($code, 'ui.lessons') . '</h3>';
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
table.lessons { border-collapse: collapse; width: 100%; }
table.lessons td, table.lessons th { vertical-align: top; text-align: left; }
p.volume { color: maroon; }
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

  my $gen = ribbon_resolve('03-17-2026', 'Rubrics 1960 - 1960');
  ($gen->{winner} =~ /Quad4-2/ && $gen->{kind} eq 'ferial' && $gen->{nocturns} == 1)
    ? $ok->('universal feria')
    : $bad->("universal winner=$gen->{winner} kind=$gen->{kind} nocturns=$gen->{nocturns}");

  my $html = ribbon_controls($el->{version}, $el->{date}, 'general', 'English') . ribbon_html($el, 'English', 'general');
  $html =~ /name="version"/ && $html =~ /name="date"/ && $html =~ /name="edition"/
    ? $ok->('three dropdowns')
    : $bad->('three dropdowns');
  $html =~ /General structure only/ ? $ok->('edition option') : $bad->('edition option');
  $html =~ /temporal cycle/ ? $ok->('volume note') : $bad->('volume note');
  $html =~ /class="page-num"/ ? $bad->('page number shown for general edition') : $ok->('no page numbers yet');
  $html =~ /praeferuntur|preferred to feasts/ ? $ok->('quote on the page') : $bad->('quote missing on the page');
  $html =~ /AAS 52/ ? $ok->('AAS attribution') : $bad->('AAS attribution');

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
