#!/usr/bin/perl
use utf8;

# Ribbon helper. The office is resolved by the same engine as officium.pl.
package main;

use POSIX;
use FindBin qw($Bin);
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
use Time::Local;
use locale;
use lib "$Bin/..";
use DivinumOfficium::LanguageTextTools
  qw(prayer rubric translate load_languages_data omit_regexp suppress_alleluia process_inline_alleluias alleluia_ant ensure_single_alleluia ensure_double_alleluia);
use DivinumOfficium::RunTimeOptions qw(check_version);
use DivinumOfficium::Date qw(prevnext);

our $Ck       = 0;
our $missa    = 0;
our $version  = '';
our @dayname;
our $winner;
our $commemoratio;
our $scriptura;
our $commune;
our $communetype;
our $rank;
our $laudes;
our $vespera;
our $cvespera;
our $commemorated;
our $comrank = 0;
our $litaniaflag = 0;
our $octavam = '';
our %winner;
our %commemoratio;
our %scriptura;
our %commune;
our (%winner2, %commemoratio2, %commune2);
our $rule;
our $communerule;
our $duplex;
our $buildscript = '';
our $column = 1;
our $error  = '';
our $debug  = '';
our $expand = 'tota';
our $votive = 'Hodie';
our $lang1  = 'Latin';
our $lang2  = 'Latin';
our $langfb = 'English';
our $hora   = '';
our $date1  = '';
our $priest = 0;
our $psalmvar = 0;
our $only   = 1;
our $caller = 0;
our $expandind = 0;
our $searchvalue = 0;
our $dioecesis = 'Generale';
our @commemoentries;
our $dayofweek;
our ($month, $day, $year);
our @RIBBON_EVENTS;

binmode(STDOUT, ':encoding(utf-8)');

require "$Bin/../DivinumOfficium/SetupString.pl";
require "$Bin/horascommon.pl";
require "$Bin/../DivinumOfficium/dialogcommon.pl";
require "$Bin/webdia.pl";
require "$Bin/../DivinumOfficium/setup.pl";
require "$Bin/horas.pl";
require "$Bin/horasscripts.pl";
require "$Bin/specials.pl";
require "$Bin/specmatins.pl";
require "$Bin/monastic.pl";
require "$Bin/altovadum.pl";
require "$Bin/horasjs.pl";
require "$Bin/ribbonlib.pl";

ribbon_boot();

our $q = CGI->new;
if (@ARGV && $ARGV[0] eq '--check') {
  exit ribbon_selftest();
}
if (@ARGV && $ARGV[0] eq '--gaps') {
  my $path = "$Bin/../../../docs/rubric-quotes-to-source.md";
  open my $fh, '>:encoding(UTF-8)', $path or die $!;
  print $fh ribbon_gaps_markdown();
  close $fh;
  exit 0;
}

my $version_in = $q->param('version') // '';
$version = check_version($version_in) || 'Rubrics 1960 - 1960';
my $date = $q->param('date') || $q->param('date1') || '';
$date =~ s/\//-/g;
if ($date !~ /^\d{2}-\d{2}-\d{4}$/) {
  $hora = 'Matutinum';
  $date = gettoday();
}
my $lang = $q->param('lang') || 'English';
$lang = 'English' unless $lang =~ /^(?:English|Espanol|Francais|Deutsch|Latin)\z/;
my $edition = $q->param('edition') || 'general';
$edition = 'general' unless $RIBBON_EDITIONS{$edition};
my $pray = $q->param('pray') || '';
$pray = ($pray eq 'booklet') ? 'booklet' : 'book';

$date1 = $date;
($month, $day, $year) = split /-/, $date;
$day += 0;
$browsertime = '1';
$officium = 'ribbon.pl';

htmlHead('Signacula', '');
# htmlHead opens the office's POST form. This page is a GET of three selects,
# so that form is closed and a shareable one is opened in its place.
print '</FORM>';
print ribbon_style();
print '<H1><FONT COLOR="MAROON" SIZE="+1"><B><I>Divinum Officium</I></B></FONT> '
  . '<FONT COLOR="RED" SIZE="+1">' . ribbon_h(ribbon_s(ribbon_code($lang), 'ui.title')) . '</FONT></H1>';
print '<p style="text-align:center">' . ribbon_sh(ribbon_code($lang), 'ui.intro') . '</p>';
print '<FORM ACTION="ribbon.pl" METHOD="get">';
print ribbon_controls($version, $date, $edition, $lang);
my $code = ribbon_code($lang);
print '<p style="text-align:center"><A HREF="officium.pl?date1=' . ribbon_h($date)
  . '&version=' . ribbon_h($version) . '&lang2=' . ribbon_h($lang eq 'Latin' ? 'Latin' : $lang) . '">'
  . ribbon_sh($code, 'ui.office') . '</A></p>';

my $facts = eval { ribbon_resolve($date, $version) };
if ($@) {
  print '<p style="color:red">' . ribbon_h($@) . '</p>';
} else {
  print ribbon_html($facts, $lang, $edition, $pray);
}
print "<SCRIPT TYPE='text/JavaScript' SRC='../../www/js/jquery.min.js'></SCRIPT>\n";
htmlEnd();
