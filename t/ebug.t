#!perl
use strict;
use warnings;
use lib 'lib';
use Devel::ebug;
use Expect::Simple;
use Test::Expect;
use Test::More tests => 15;

expect_run(
  command => "PERL_RL=\"o=0\" $^X ebug t/calc.pl",
  prompt  => 'ebug: ',
  quit    => 'q',
);

my $version = $Devel::ebug::VERSION;

expect_like(qr/Welcome to Devel::ebug $version/);
expect_like(qr{main\(t/calc.pl#3\): my \$q = 1;});
expect("h", 'Commands:

    b Set breakpoint at a line number (eg: b 6, b code.t 6, b code.t 6 $x > 7,
      b Calc::fib)
    e Eval Perl code and print the result (eg: e $x+$y)
    f Show all the filenames loaded
    l Show codelines
    n Next (steps over subroutine calls)
    p Show pad
    r Run until next break point or watch point
  ret Return from subroutine
    s Step (steps into subroutine calls)
    w Set a watchpoint (eg: w $t > 10)
    y Dump a variable using YAML (eg: d $x)
    q Quit
main(t/calc.pl#3): my $q = 1;');

expect("b 9", 'main(t/calc.pl#3): my $q = 1;');
expect("s", 'main(t/calc.pl#4): my $w = 2;');
expect("", 'main(t/calc.pl#5): my $e = add($q, $w);');
expect("n", 'main(t/calc.pl#6): $e++;');
expect("r", 'main(t/calc.pl#9): print "$e\n";');

