#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 4;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;
$ebug->break_point(6);
$ebug->run;
is($ebug->line, 6);
is($ebug->eval('$e'), 3);
$ebug->step;
is($ebug->eval('$e'), 4);
$ebug->step;
is($ebug->eval('$e'), 5);
