#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 4;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/calc_oo.pl");
$ebug->load;

$ebug->break_point_subroutine("Calc::add");
$ebug->run;
is($ebug->line, 9);
is($ebug->subroutine, 'Calc::add');
$ebug->return();
is($ebug->line, 9);
is($ebug->subroutine, 'main');

