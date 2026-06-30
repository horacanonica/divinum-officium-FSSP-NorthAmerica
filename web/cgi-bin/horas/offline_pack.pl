#!/usr/bin/perl
use utf8;
use strict;
use warnings;
use CGI;
use JSON::PP;
use POSIX qw(strftime);
use Time::Local qw(timelocal);
use FindBin qw($Bin);

my $cgi  = CGI->new;
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

my $days = int($cgi->param('days') // 7);
$days = 7  if $days < 1;
$days = 90 if $days > 90;

my $lang_raw = $cgi->param('lang') // 'lat';
json_error(400, "Invalid lang — use lat, en, or both") unless $lang_raw =~ /^(lat|en|both)$/;
my $lang1 = ($lang_raw eq 'en') ? 'English' : 'Latin';
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

    # Use a temp file so subprocess stdout capture works regardless of
    # how PSGI/CGI::Emulate may have tied STDOUT in the parent process.
    require File::Temp;
    my ($tmpfh, $tmpfile) = File::Temp::tempfile(UNLINK => 1, SUFFIX => '.html');
    close $tmpfh;

    my $pid = fork();
    unless (defined $pid) { return ''; }

    if ($pid == 0) {
        # Child: wire FD 1 to the temp file at the OS level (bypasses any Perl STDOUT ties)
        open(my $out, '>', $tmpfile) or POSIX::_exit(1);
        require POSIX;
        POSIX::dup2(fileno($out), 1);
        close $out;
        open(STDERR, '>', '/dev/null');

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

        chdir $Bin;
        exec 'perl', "$Bin/Pofficium.pl";
        POSIX::_exit(1);
    }

    waitpid($pid, 0);

    open my $fh, '<:encoding(UTF-8)', $tmpfile or return '';
    my $output = do { local $/; <$fh> };
    close $fh;

    return strip_html($output);
}

sub strip_html {
    my $html = shift;
    return '' unless $html;

    # 1. Strip all CGI/HTTP headers up to the first blank line
    #    (Output always starts with one or more header lines, then \n\n, then HTML)
    $html =~ s/\A.+?\n\n//s;

    # 2. Strip everything up to and including </HEAD>
    $html =~ s/.*?<\/HEAD>//si;

    # 3. Strip the opening BODY tag
    $html =~ s/\s*<BODY[^>]*>//i;

    # 4. Strip the opening FORM tag
    $html =~ s/\s*<FORM[^>]*>//i;

    # 5. Strip from pwa-nav bar to end (nav bar + scroll script + /FORM/BODY/HTML)
    $html =~ s/<div class='pwa-nav'>.*//si;

    # 6. Catch-all: strip any remaining structural close tags
    $html =~ s/<\/FORM>//gi;
    $html =~ s/<\/BODY>//gi;
    $html =~ s/<\/HTML>//gi;

    # 7. Strip script blocks
    $html =~ s/<script\b[^>]*>.*?<\/script>//gsi;

    # 8. Strip DO site-title H1 ("Divinum Officium ... FSSP")
    $html =~ s/<H1\b[^>]*>.*?<\/H1>\s*//gsi;

    # 9. Strip navigation paragraphs that link to Pofficium.pl
    #    (date prev/next bar and hora selection bar)
    1 while $html =~ s/<P\b[^>]*>(?:(?!<\/P>).)*?Pofficium\.pl\?(?:(?!<\/P>).)*?<\/P>\s*//gsi;

    # 10. Strip remaining A tags but keep their visible text (links are dead offline)
    $html =~ s/<A\b[^>]*>(.*?)<\/A>/$1/gsi;

    # 11. Strip inline STYLE attributes so the PWA's own CSS controls typography
    $html =~ s/\s+STYLE="[^"]*"//gi;

    # 12. Trim
    $html =~ s/\A\s+//;
    $html =~ s/\s+\z//;

    return $html;
}
