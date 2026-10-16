#!/usr/bin/perl
use utf8;
package main;
use FindBin qw($Bin);
use lib "/var/www/web/cgi-bin";
our ($version,$missa,$hora,$dayname,$dayofweek,$month,$votive,$commune,$dioecesis,$lang1,$lang2,$datafolder,$missanumber);
our @dayname;
binmode(STDOUT,":encoding(UTF-8)");
our $datafolder = "/var/www/web/www/horas"; our $langfb="English";
require "/var/www/web/cgi-bin/DivinumOfficium/SetupString.pl";
require "/var/www/web/cgi-bin/DivinumOfficium/dialogcommon.pl";
require "/var/www/web/cgi-bin/horas/horascommon.pl";
$version = shift; 
for my $f (@ARGV){
  my %s = %{setupstring('Latin', $f)};
  print "== $f\n";
  for my $k (qw(Officium Rank Rule Name)) { my $v=$s{$k}; $v=~s/\n/\\n/g; print "$k: $v\n"; }
  print "SECTIONS: ", join(",", sort keys %s), "\n";
}
