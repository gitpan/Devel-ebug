#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 9;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;

# Let's step through the program, and check that we get the
# lexical variables for each line

my $want_vars = {
  3 => '',
  4 => '$q=1',
  5 => '$q=1,$w=2',
 12 => '$e=undef,$q=1,$w=2',
 13 => '$e=undef,$q=1,$w=2,$x=2,$z=1',
 14 => '$c=3,$e=undef,$q=1,$w=2,$x=2,$z=1',
  6 => '$e=3,$q=1,$w=2',
  7 => '$e=4,$q=1,$w=2',
  9 => '$e=5,$q=1,$w=2',
};

foreach (1..9) {
  my $line = $ebug->line;
  my $pad  = $ebug->pad;
  my @vars;
  foreach my $k (sort keys %$pad) {
    my $v = $pad->{$k};
    push @vars, "$k=$v";
  }
  my $vars = join ',', @vars;
  $vars ||= '';
  is($want_vars->{$line}, $vars, "$line has $vars");
  $ebug->step;
}

