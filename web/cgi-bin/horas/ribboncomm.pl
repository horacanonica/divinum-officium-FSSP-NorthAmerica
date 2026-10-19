# Commemorations explainer: Office and Mass in one section.
# An FAQ page can require this file and call ribbon_commemorations_html.
# It uses only ribbon_* subs from ribbonlib.pl. Strings live in
# web/www/horas/Ribbon/strings.txt under ui.comm.* and plain.comm.*.
# Latin of Missal articles (n. 269 on) is not in aas52-la.txt.

our $datafolder;

sub ribbon_comm_spec {
  return (
    { kind => 'h', level => 2, key => 'ui.comm.title' },
    { kind => 'p', key => 'plain.comm.bridge' },

    { kind => 'h', level => 3, id => 'comm-office', key => 'ui.comm.office' },
    { kind => 'h', level => 4, key => 'ui.comm.when' },
    { kind => 'p', key => 'plain.comm.when' },
    { kind => 'q', ids => [qw(GR-107 GR-111 GR-114 GR-113 GR-112 GR-106 GR-103 GR-104 GR-105)] },
    { kind => 'p', key => 'plain.comm.gap.three' },

    { kind => 'h', level => 4, key => 'ui.comm.where' },
    { kind => 'p', key => 'plain.comm.where' },
    { kind => 'p', key => 'plain.comm.place' },
    { kind => 'place' },
    { kind => 'q', ids => [qw(BR-214 BR-248)] },
    { kind => 'p', key => 'plain.comm.gap.minor' },

    { kind => 'h', level => 4, key => 'ui.comm.how' },
    { kind => 'p', key => 'plain.comm.how' },
    { kind => 'q', ids => [qw(BR-251 BR-249 BR-250)] },

    { kind => 'h', level => 4, key => 'ui.comm.concl' },
    { kind => 'p', key => 'plain.comm.concl' },
    { kind => 'q', ids => [qw(GR-115)] },
    { kind => 'p', key => 'plain.comm.gap.last' },

    { kind => 'h', level => 4, key => 'ui.comm.joint' },
    { kind => 'p', key => 'plain.comm.joint' },
    { kind => 'q', ids => [qw(GR-110)] },

    { kind => 'h', level => 4, id => 'comm-examples', key => 'ui.comm.examples' },
    { kind => 'p', key => 'plain.comm.ex1' },
    { kind => 'p', key => 'plain.comm.ex2' },

    { kind => 'h', level => 3, id => 'comm-mass', key => 'ui.comm.mass' },
    { kind => 'p', key => 'plain.comm.mass.lead' },
    { kind => 'h', level => 4, key => 'ui.comm.mass.which' },
    { kind => 'p', key => 'plain.comm.mass.which' },
    { kind => 'q', ids => [qw(GR-111)] },
    { kind => 'place' },
    { kind => 'm', ns => [433, 434, 435] },

    { kind => 'h', level => 4, key => 'ui.comm.mass.form' },
    { kind => 'p', key => 'plain.comm.mass.form' },
    { kind => 'm', ns => [436, 437, 444, 480, 505] },
    { kind => 'p', key => 'plain.comm.gap.oremus' },
    { kind => 'q', ids => [qw(GR-115)] },

    { kind => 'h', level => 4, key => 'ui.comm.mass.other' },
    { kind => 'p', key => 'plain.comm.mass.other' },
    { kind => 'm', ns => [454, 457, 458, 461, 463, 391], damaged => { 398 => 1 } },
    { kind => 'm', ns => [398], damaged => { 398 => 1 } },

    { kind => 'h', level => 4, key => 'ui.comm.mass.peter' },
    { kind => 'p', key => 'plain.comm.mass.peter' },
    { kind => 'letter', n => 110, let => 'b' },
    { kind => 'q', ids => [qw(GR-110)] },

    { kind => 'h', level => 4, id => 'comm-mass-examples', key => 'ui.comm.examples' },
    { kind => 'p', key => 'plain.comm.mex1' },
    { kind => 'p', key => 'plain.comm.mex2' },

    { kind => 'h', level => 4, id => 'comm-today', key => 'ui.comm.today' },
    { kind => 'today' },
  );
}

sub ribbon_sub_unica {
  my ($winner) = @_;
  my $stem = ribbon_stem($winner);
  return 0 if !defined $stem || $stem eq '';
  my $path = "$datafolder/Latin/$stem.txt";
  return 0 if !-e $path;
  my $text = ribbon_slurp($path);
  return $text =~ /Sub unica conc/i ? 1 : 0;
}

sub ribbon_comm_see_html {
  my ($code, $n) = @_;
  return '<p class="ribbon-note">' . ribbon_sh($code, 'plain.comm.see', { n => $n }) . '</p>';
}

sub ribbon_missal_html {
  my ($code, $n, $damaged) = @_;
  my $en = ribbon_slice_article(ribbon_corpus_text('missal'), $n);
  my $file = 'web/www/horas/Help/Rubrics/' . ribbon_corpus_filename('missal');
  my $html = '<blockquote class="rubric">';
  $html .= '<p class="cite"><b>' . ribbon_sh($code, 'ui.rubrics_missal', { n => $n }) . '</b>';
  $html .= '<br>' . ribbon_h($file) . '</p>';
  if ($en ne '') {
    my $body = ribbon_h($en);
    $body =~ s/\n/<br>\n/g;
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>' . $body . '</p>';
    $html .= '<p class="ribbon-note">' . ribbon_sh($code, 'ui.en_damaged') . '</p>' if $damaged;
  } else {
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>[to be sourced]</p>';
  }
  # aas52-la.txt stops at n. 268. Do not invent the Missal Latin.
  $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_la') . '</i><br>[to be sourced]</p>';
  $html .= '</blockquote>';
  return $html;
}

sub ribbon_letter_html {
  my ($code, $n, $let) = @_;
  my $en_full = ribbon_slice_article(ribbon_corpus_text('general'), $n);
  my $en_flat = $en_full;
  $en_flat =~ s/\s+/ /g;
  my $next = chr(ord($let) + 1);
  my $pat = '(' . $let . '\\)\\s*.*?)(?=\\s*' . $next . '\\)|\\z)';
  my $en = ($en_flat =~ /$pat/) ? $1 : '';
  $en = '' if $en !~ /Mass of St\. Peter/i;
  my $la = ribbon_la_piece($n, $let);
  $la = '' if $la !~ /Missa S\. Petri/;
  my $html = '<blockquote class="rubric">';
  $html .= '<p class="cite"><b>' . ribbon_sh($code, 'ui.rubrics_general', { n => $n }) . '</b>';
  $html .= ' — ' . ribbon_sh($code, 'ui.comm.letter', { let => $let }) . '</p>';
  $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>'
    . ($en ne '' ? ribbon_h($en) : '[to be sourced]') . '</p>';
  my $where = ribbon_s($code, 'ui.quote_la');
  my $row_page = '';
  if ($la ne '') {
    my $q = ribbon_quote('GR-110');
    $row_page = $q && $q->{page} ? $q->{page} : '';
    $where .= ', p. ' . $row_page if $row_page ne '';
  }
  $html .= '<p><i>' . ribbon_h($where) . '</i><br>'
    . ($la ne '' ? ribbon_h($la) : '[to be sourced]') . '</p>';
  $html .= '</blockquote>';
  return $html;
}

sub ribbon_place_html {
  my ($code) = @_;
  my $la = ribbon_la_body(108);
  my $en_list = ribbon_slice_article(ribbon_corpus_text('general'), 108);
  my $la_list = ribbon_la_body(109);
  my $file = 'web/www/horas/Help/Rubrics/' . ribbon_corpus_filename('general');
  my $html = '<blockquote class="rubric" id="comm-place">';
  $html .= '<p class="cite"><b>' . ribbon_sh($code, 'ui.rubrics_general', { n => 108 }) . '</b>';
  $html .= '<br>' . ribbon_h($file) . '</p>';
  $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>[to be sourced]</p>';
  if ($la ne '') {
    my $where = ribbon_s($code, 'ui.quote_la');
    my $pg = ribbon_la_page(108);
    $where .= ', p. ' . $pg if $pg ne '';
    $html .= '<p><i>' . ribbon_h($where) . '</i><br>' . ribbon_h($la) . '</p>';
  } else {
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_la') . '</i><br>[to be sourced]</p>';
  }
  $html .= '</blockquote>';
  $html .= '<p class="ribbon-note">' . ribbon_sh($code, 'plain.comm.listnote') . '</p>';
  $html .= '<blockquote class="rubric">';
  $html .= '<p class="cite"><b>' . ribbon_sh($code, 'ui.rubrics_general', { n => 109 }) . '</b>';
  $html .= '<br>' . ribbon_h($file) . '</p>';
  if ($en_list ne '') {
    my $body = ribbon_h($en_list);
    $body =~ s/\n/<br>\n/g;
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>' . $body . '</p>';
  } else {
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_en') . '</i><br>[to be sourced]</p>';
  }
  if ($la_list ne '') {
    my $where = ribbon_s($code, 'ui.quote_la');
    my $pg = ribbon_la_page(109);
    $where .= ', p. ' . $pg if $pg ne '';
    $html .= '<p><i>' . ribbon_h($where) . '</i><br>' . ribbon_h($la_list) . '</p>';
  } else {
    $html .= '<p><i>' . ribbon_sh($code, 'ui.quote_la') . '</i><br>[to be sourced]</p>';
  }
  $html .= '</blockquote>';
  return $html;
}

sub ribbon_comm_today_html {
  my ($code, $facts) = @_;
  my $out = '';
  my @lines;
  for my $h (qw(Matutinum Laudes Prima Tertia Sexta Nona Vespera Completorium)) {
    my @comms = @{ $facts->{hours}{$h}{comms} || [] };
    my %seen;
    @comms = grep { $_ && !$seen{$_}++ } @comms;
    next unless @comms;
    my @names;
    for my $f (@comms) {
      my $n = ribbon_office_name(ribbon_lang_from_code($code), $f);
      push @names, ($n && $n ne '') ? "$n ($f)" : $f;
    }
    push @lines, ribbon_sh($code, 'plain.comm.hour', {
      hour  => ribbon_s($code, "hora.$h"),
      names => join('; ', @names),
    });
  }
  my $unica = ribbon_sub_unica($facts->{winner});
  if (!@lines) {
    $out .= '<p>' . ribbon_sh($code, 'plain.comm.none') . '</p>';
  } else {
    $out .= '<ul class="comm-today">';
    $out .= join '', map { "<li>$_</li>" } @lines;
    $out .= '</ul>';
    $out .= '<p>' . ribbon_sh($code, 'plain.comm.today.mass') . '</p>';
  }
  if ($unica) {
    $out .= '<p>' . ribbon_sh($code, 'plain.comm.unica') . '</p>';
    $out .= '<p>' . ribbon_sh($code, 'plain.comm.today.unica') . '</p>';
  }
  return $out;
}

sub ribbon_commemorations_html {
  my ($code, $facts) = @_;
  my %seen_q;
  my $seen_place = 0;
  my $out = '<section class="comm-box" id="commemorations">';
  for my $b (ribbon_comm_spec()) {
    my $kind = $b->{kind};
    if ($kind eq 'h') {
      my $id = $b->{id} ? ' id="' . $b->{id} . '"' : '';
      $out .= '<h' . $b->{level} . $id . '>' . ribbon_sh($code, $b->{key}) . '</h' . $b->{level} . '>';
    } elsif ($kind eq 'p') {
      $out .= '<p>' . ribbon_sh($code, $b->{key}) . '</p>';
    } elsif ($kind eq 'q') {
      for my $id (@{ $b->{ids} }) {
        if ($seen_q{$id}++) {
          my $q = ribbon_quote($id);
          $out .= ribbon_comm_see_html($code, $q ? $q->{number} : $id);
        } else {
          $out .= ribbon_quote_html($code, $id);
        }
      }
    } elsif ($kind eq 'm') {
      my $dmg = $b->{damaged} || {};
      for my $n (@{ $b->{ns} }) {
        $out .= ribbon_missal_html($code, $n, $dmg->{$n});
      }
    } elsif ($kind eq 'place') {
      if ($seen_place++) {
        $out .= ribbon_comm_see_html($code, 108);
      } else {
        $out .= ribbon_place_html($code);
      }
    } elsif ($kind eq 'letter') {
      $out .= ribbon_letter_html($code, $b->{n}, $b->{let});
    } elsif ($kind eq 'today') {
      $out .= ribbon_comm_today_html($code, $facts);
    }
  }
  $out .= '</section>';
  return $out;
}

1;
