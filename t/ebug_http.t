#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 13;
use Test::WWW::Mechanize::Catalyst 'Devel::ebug::HTTP';
use Devel::ebug;

my $ebug = Devel::ebug->new();
$ebug->program("t/calc.pl");
$ebug->load;
$Devel::ebug::HTTP::ebug = $ebug;

my $root = "http://localhost";

my $m = Test::WWW::Mechanize::Catalyst->new;
$m->get_ok("$root/");
is($m->ct, "text/html");
$m->title_is('t/calc.pl main(t/calc.pl#3) my $q = 1;');
$m->content_contains("Step");
$m->content_contains("Next");
$m->content_contains("t/calc.pl main(t/calc.pl#3)");
$m->content_contains("#!perl");
$m->content_contains("Variables in main");
$m->content_contains("Stack trace");
$m->content_contains("STDOUT");
$m->content_contains("STDERR");
$m->content_contains("Devel::ebug");
$m->content_contains($Devel::ebug::VERSION);


