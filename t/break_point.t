#!perl
use strict;
use warnings;
use lib 'lib';
use Test::More tests => 17;
use Devel::ebug;

my $ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;

# set break points at line numbers
$ebug->break_point(6);
$ebug->break_point(12);
$ebug->break_point(9);
is_deeply([$ebug->break_points], [6, 9, 12]);
$ebug->run;
is($ebug->line, 12);
$ebug->run;
is($ebug->line, 6);
$ebug->run;
is($ebug->line, 9);
is($ebug->pad->{'$e'}, 5);
$ebug->step;

# set break point at add()
$ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;
$ebug->break_point_subroutine("main::add");
$ebug->run;
is($ebug->line, 12);

# set break point at fib2()
$ebug = Devel::ebug->new;
$ebug->program("t/calc_oo.pl");
$ebug->load;
$ebug->break_point("t/Calc.pm", 29);
$ebug->run;
is($ebug->line, 29);
is($ebug->eval('$i'), 1);

# set break point at add()
$ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;
$ebug->break_point(6, '$e == 4');
$ebug->break_point(7, '$e == 4');
$ebug->run;
is($ebug->line, 7);
is($ebug->eval('$e'), 4);

# set break point at fib2()
$ebug = Devel::ebug->new;
$ebug->program("t/calc_oo.pl");
$ebug->load;
$ebug->break_point("t/Calc.pm", 29, '$i == 2');
$ebug->run;
is($ebug->line, 29);
is($ebug->eval('$i'), 2);
is($ebug->eval('$x1'), 1);
is($ebug->eval('$x2'), 2);

# set break points at line numbers and delete one
$ebug = Devel::ebug->new;
$ebug->program("t/calc.pl");
$ebug->load;
$ebug->break_point(6);
$ebug->break_point(12);
$ebug->break_point(9);
$ebug->break_point_delete(6);
$ebug->break_point_delete("t/calc.pl", 12);
is_deeply([$ebug->break_points], [9]);
$ebug->run;
is($ebug->line, 9);
is($ebug->pad->{'$e'}, 5);
$ebug->step;

