#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 8;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/signal.pl");
$ebug->load;

$ebug->run;
is($ebug->finished, 0);
is($ebug->line, 8);
my $pad = $ebug->pad;
is($pad->{'$i'}, 11);
is($pad->{'$square'}, 121);

$ebug->run;
is($ebug->finished, 0);
is($ebug->line, 8);
$pad = $ebug->pad;
is($pad->{'$i'}, 12);
is($pad->{'$square'}, 144);

