#!/usr/bin/perl
use utf8;
use strict;
use warnings;
use CGI;
use JSON::PP;
use POSIX qw(strftime);
use Time::Local qw(timelocal);
use FindBin qw($Bin);

my $cgi = CGI->new;
my $json = JSON::PP->new->utf8->canonical(0);

# --- Valid calendars (from data.txt) ---
my %valid_calendars;
{
    my $data_file = "$Bin/../../www/Tabulae/data.txt";
    if (open my $fh, '<:encoding(UTF-8)', $data_file) {
        while (<$fh>) {
            chomp;
            next if /^#/ || /^version,/;
            my ($ver) = split /,/, $_, 2;
            $valid_calendars{$ver} = 1 if defined $ver && $ver ne '';
        }
        close $fh;
    }
}

sub json_error {
    my ($code, $msg) = @_;
    print "Status: $code\nContent-Type: application/json; charset=utf-8\n\n";
    print $json->encode({ error => $msg });
    exit 0;
}

# --- Parse and validate params ---
my $calendar = $cgi->param('calendar') // '';
json_error(400, "Missing calendar parameter") unless $calendar ne '';
json_error(400, "Unknown calendar: $calendar") unless $valid_calendars{$calendar};

my $days_raw = $cgi->param('days') // '7';
my $days = int($days_raw);
$days = 7  if $days < 1;
$days = 90 if $days > 90;

my $lang_raw = $cgi->param('lang') // 'lat';
json_error(400, "Invalid lang — use lat, en, or both") unless $lang_raw =~ /^(lat|en|both)$/;
my $lang1 = ($lang_raw eq 'en')   ? 'English' : 'Latin';
my $lang2 = ($lang_raw eq 'both') ? 'English' : '';

my $start_raw = $cgi->param('start') // '';
my ($sy, $sm, $sd);
if ($start_raw =~ /^(\d{4})-(\d{2})-(\d{2})$/) {
    ($sy, $sm, $sd) = ($1, $2+0, $3+0);
} else {
    my @t = localtime;
    ($sy, $sm, $sd) = ($t[5]+1900, $t[4]+1, $t[3]);
}

# --- Hours ---
my @HORAS = (
    { key => 'matins',   hora => 'Matutinum'   },
    { key => 'lauds',    hora => 'Laudes'       },
    { key => 'prime',    hora => 'Prima'        },
    { key => 'terce',    hora => 'Tertia'       },
    { key => 'sext',     hora => 'Sexta'        },
    { key => 'none',     hora => 'Nona'         },
    { key => 'vespers',  hora => 'Vespera'      },
    { key => 'compline', hora => 'Completorium' },
);

# --- Build response ---
my @days_out;
my ($cy, $cm, $cd) = ($sy, $sm, $sd);

for my $i (0 .. $days - 1) {
    if ($i > 0) {
        my $epoch = timelocal(0, 0, 12, $cd, $cm - 1, $cy - 1900);
        $epoch += 86400;
        my @t = localtime($epoch);
        ($cy, $cm, $cd) = ($t[5]+1900, $t[4]+1, $t[3]);
    }

    my $iso_date = sprintf('%04d-%02d-%02d', $cy, $cm, $cd);
    my $do_date  = sprintf('%02d/%02d/%04d', $cm, $cd, $cy);

    my %hours_out;
    for my $h (@HORAS) {
        my $html = call_hora($do_date, $h->{hora}, $calendar, $lang1, $lang2);
        $hours_out{$h->{key}} = {
            title => $h->{hora},
            html  => $html,
        };
    }

    push @days_out, {
        date  => $iso_date,
        hours => \%hours_out,
    };
}

print "Content-Type: application/json; charset=utf-8\n\n";
print $json->encode({
    calendar     => $calendar,
    generated_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    days         => \@days_out,
});

# --- Subroutines ---

sub uri_encode {
    my $s = shift;
    $s =~ s/([^A-Za-z0-9._~-])/sprintf('%%%02X', ord($1))/ge;
    return $s;
}

sub call_hora {
    my ($date, $hora, $version, $lang, $lang2) = @_;
    $lang2 //= '';

    my $qs = join('&',
        'date='    . uri_encode($date),
        'hora='    . uri_encode($hora),
        'version=' . uri_encode($version),
        'lang='    . uri_encode($lang),
        'lang2='   . uri_encode($lang2),
    );

    pipe(my $reader, my $writer) or return '';

    my $pid = fork();
    unless (defined $pid) {
        close $reader; close $writer;
        return '';
    }

    if ($pid == 0) {
        close $reader;

        # Redirect STDOUT to pipe so parent can capture it
        open(STDOUT, '>&', $writer) or exit 1;
        close $writer;
        # Suppress STDERR from the DO engine
        open(STDERR, '>', '/dev/null');

        # CGI environment for the DO engine
        $ENV{REQUEST_METHOD}    = 'GET';
        $ENV{QUERY_STRING}      = $qs;
        $ENV{HTTP_HOST}         = 'localhost';
        $ENV{SCRIPT_NAME}       = '/cgi-bin/horas/Pofficium.pl';
        $ENV{SERVER_NAME}       = 'localhost';
        $ENV{SERVER_PORT}       = '8080';
        $ENV{SERVER_PROTOCOL}   = 'HTTP/1.1';
        $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
        $ENV{HTTP_COOKIE}       = '';
        delete $ENV{HTTP_ACCEPT_ENCODING};

        chdir "$Bin";
        exec 'perl', "$Bin/Pofficium.pl";
        exit 1;
    }

    close $writer;
    my $output = '';
    while (<$reader>) { $output .= $_; }
    close $reader;
    waitpid($pid, 0);

    return strip_html($output);
}

sub strip_html {
    my $html = shift;

    # Strip HTTP/CGI headers (everything up to the blank line)
    $html =~ s/\A[^\r\n]*[\r\n]+(?:[^\r\n]*[\r\n]+)*?[\r\n]//;

    # Extract content between <BODY> and </BODY>
    if ($html =~ /<BODY[^>]*>(.*?)<\/BODY>/si) {
        $html = $1;
    }

    # Remove the opening FORM tag
    $html =~ s/<FORM\b[^>]*>//gi;
    # Remove the closing FORM tag
    $html =~ s/<\/FORM>//gi;

    # Remove pwa-nav bar
    $html =~ s/<div class='pwa-nav'>.*?<\/div>//si;

    # Remove all SCRIPT blocks
    $html =~ s/<SCRIPT\b[^>]*>.*?<\/SCRIPT>//gsi;
    $html =~ s/<script\b[^>]*>.*?<\/script>//gsi;

    # Remove inline style attributes (replace with nothing)
    $html =~ s/\s+style="[^"]*"//gi;
    $html =~ s/\s+STYLE="[^"]*"//gi;

    # Trim leading/trailing whitespace
    $html =~ s/\A\s+//;
    $html =~ s/\s+\z//;

    return $html;
}
