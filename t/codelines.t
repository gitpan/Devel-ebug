#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 1;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;

# Let's get some lines of code

my $codelines = $ebug->codelines(1..15);
is_deeply($codelines, {
          '1' => '#!perl',
          '2' => '',
          '3' => 'my $q = 1;',
          '4' => 'my $w = 2;',
          '5' => 'my $e = add($q, $w);',
          '6' => '$e++;',
          '7' => '$e++;',
          '8' => '',
          '9' => 'print "$e\\n";',
          '10' => '',
          '11' => 'sub add {',
          '12' => '  my($z, $x) = @_;',
          '13' => '  my $c = $z + $x;',
          '14' => '  return $c;',
          '15' => '}',
});

