#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 8;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;

my @trace = $ebug->stack_trace;
is(scalar(@trace), 0);
$ebug->break_point(12);

$ebug->run;
@trace = $ebug->stack_trace;
is(scalar(@trace), 1);

# use YAML; warn Dump \@trace;

my $trace = $trace[0];
is($trace->package   , "main");
is($trace->filename  , "t/calc.pl");
is($trace->subroutine, "main::add");
is($trace->wantarray , 0);
is($trace->line      , 5);
is_deeply([$trace->args], [1, 2]);
