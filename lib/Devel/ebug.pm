package Devel::ebug;
use strict;
use warnings;
use Carp;
use Class::Accessor::Chained::Fast;
use Devel::StackTrace;
use IO::Socket::INET;
use Proc::Background;
use String::Koremutake;
use YAML;
use Module::Pluggable require => 1;

use base qw(Class::Accessor::Chained::Fast);
__PACKAGE__->mk_accessors(qw(
program socket proc
package filename line codeline finished));
our $VERSION = "0.38";

# let's run the code under our debugger and connect to the server it
# starts up
sub load {
  my $self = shift;
  my $program = $self->program;

  # import all the plugins into our namespace
  do { eval "use $_ " } for $self->plugins;

  my $k = String::Koremutake->new;
  my $rand = int(rand(100_000));
  my $secret = $k->integer_to_koremutake($rand);
  my $port   = 3141 + ($rand % 1024);

  $ENV{SECRET} = $secret;
  my $command = "$^X -Ilib -d:ebug::Backend $program";
#  warn "Running: $command\n";
  my $proc = Proc::Background->new(
    {'die_upon_destroy' => 1},
    $command
  );
  croak(qq{Devel::ebug: Failed to start up "$program" in load()}) unless $proc->alive;
  $self->proc($proc);
  $ENV{SECRET} = "";

  # try and connect to the server
  my $socket;
  foreach (1..10) {
    $socket = IO::Socket::INET->new(
      PeerAddr => "localhost",
      PeerPort => $port,
      Proto    => 'tcp',
      Reuse      => 1,
      ReuserAddr => 1,
    );
    last if $socket;
    sleep 1;
  }
  die "Could not connect: $!" unless $socket;
  $self->socket($socket);

  my $response = $self->talk({
    command => "ping",
    version => $VERSION,
    secret  => $secret,
  });
  my $version = $response->{version};
  die "Client version $version != our version $VERSION" unless $version eq $VERSION;
  $self->basic; # get basic information for the first line
}

#
# FIXME : this would mean that plugin writers don't need to Export stuff
#
#sub load_plugins {
#    my $self = shift;    
#    my $obj = Devel::Symdump->new($self->plugins);
#    
#    for ($obj->functions) {
#        my $name = (split /::/)[-1];
#        next if substr($name,0,1) eq '_';
#        *basic = \&$_;
#    }
#    
#}



# at the moment, we talk hex-encoded YAML serialisation
# don't worry about this too much
sub talk {
  my($self, $req) = @_;
  my $socket = $self->socket;

  my $data = unpack("h*", Dump($req));
  $socket->print($data . "\n");
  $data = <$socket>;
  if ($data) {
    my $res = Load(pack("h*", $data));
    return $res;
  }
}

1;

__END__

=head1 NAME

Devel::ebug - A simple, extensible Perl debugger

=head1 SYNOPSIS

  use Devel::ebug;
  my $ebug = Devel::ebug->new;
  $ebug->program("calc.pl");
  $ebug->load;

  print "At line: "       . $ebug->line       . "\n";
  print "In subroutine: " . $ebug->subroutine . "\n";
  print "In package: "    . $ebug->package    . "\n";
  print "In filename: "   . $ebug->filename   . "\n";
  print "Code: "          . $ebug->codeline   . "\n";
  $ebug->step;
  $ebug->step;
  $ebug->next;
  $ebug->break_point(6);
  $ebug->break_point(6, '$e = 4');
  $ebug->break_point("t/Calc.pm", 29);
  $ebug->break_point("t/Calc.pm", 29, '$i == 2');
  $ebug->break_point_subroutine("main::add");
  $ebug->break_point_delete(29);
  $ebug->break_point_delete("t/Calc.pm", 29);
  my @filenames    = $ebug->filenames();
  my @break_points = $ebug->break_points();
  $ebug->watch_point('$x > 100');
  my $codelines = $ebug->codelines(@span);
  $ebug->run;
  my $pad  = $ebug->pad;
  foreach my $k (sort keys %$pad) {
    my $v = $pad->{$k};
    print "Variable: $k = $v\n";
  }
  my $v = $ebug->eval('2 ** $exp');
  my @frames = $ebug->stack_trace;
  my @frames2 = $ebug->stack_trace_human;
  $ebug->undo;
  $ebug->return;
  print "Finished!\n" if $ebug->finished;

=head1 DESCRIPTION

A debugger is a computer program that is used to debug other
programs. L<Devel::ebug> is a simple, extensible Perl debugger with a
clean API. Using this module, you may easily write a Perl debugger to
debug your programs. Alternatively, it comes with an interactive
debugger, L<ebug>.

perl5db.pl, Perl's current debugger is currently 2,600 lines of magic
and special cases. The code is nearly unreadable: fixing bugs and
adding new features is fraught with difficulties. The debugger has no
test suite which has caused breakage with changes that couldn't be
properly tested. It will also not debug regexes. L<Devel::ebug> is
aimed at fixing these problems and delivering a replacement debugger
which provides a well-tested simple programmatic interface to
debugging programs. This makes it easier to build debuggers on top of
L<Devel::ebug>, be they console-, curses-, GUI- or Ajax-based.

There are currently two user interfaces to L<Devel::debug>, L<ebug>
and L<ebug_http>. L<ebug> is a console-based interface to debugging
programs, much like perl5db.pl. L<ebug_http> is an innovative
web-based interface to debugging programs.

Note that if you're debugging a program, you can invoke the debugger
in the program itself by using the INT signal:

  kill 2, $$ if $square > 100;

L<Devel::ebug> is a work in progress.

Internally, L<Devel::ebug> consists of two parts. The frontend is
L<Devel::ebug>, which you interact with. The frontend starts the code
you are debugging in the background under the backend (running it
under perl -d:ebug code.pl). The backend starts a TCP server, which
the frontend then connects to, and uses this to drive the
backend. This adds some flexibilty in the debugger. There is some
minor security in the client/server startup (a secret word), and a
random port is used from 3141-4165 so that multiple debugging sessions
can happen concurrently.

=head1 CONSTRUCTOR

=head2 new

The constructor creats a Devel::ebug object:

  my $ebug = Devel::ebug->new;

=head2 program

The program method selects which program to load:

  $ebug->program("calc.pl");

=head2 load

The load method loads the program and gets ready to debug it:

  $ebug->load;

=head1 METHODS

=head2 break_point

The break_point method sets a break point in a program. If you are
run-ing through a program, the execution will stop at a break point.
Break points can be set in a few ways.

A break point can be set at a line number in the current file:

  $ebug->break_point(6);

A break point can be set at a line number in the current file with a
condition that must be true for execution to stop at the break point:

  $ebug->break_point(6, '$e = 4');

A break point can be set at a line number in a file:

  $ebug->break_point("t/Calc.pm", 29);

A break point can be set at a line number in a file with a condition
that must be true for execution to stop at the break point:

  $ebug->break_point("t/Calc.pm", 29, '$i == 2');

=head2 break_point_delete

The break_point_delete method deletes an existing break point. A break
point at a line number in the current file can be deleted:

  $ebug->break_point_delete(29);

A break point at a line number in a file can be deleted:

  $ebug->break_point_delete("t/Calc.pm", 29);

=head2 break_point_subroutine

The break_point_subroutine method sets a break point in a program
right at the beginning of the subroutine. The subroutine is specified
with the full package name:

  $ebug->break_point_subroutine("main::add");
  $ebug->break_point_subroutine("Calc::fib");

=head2 break_points

The break_points method returns a list of all the line numbers in the
current file that have a break point set.

  my @break_points = $ebug->break_points();

=head2 codeline

The codeline method returns the line of code that is just about to be
executed:

  print "Code: "          . $ebug->codeline   . "\n";

=head2 codelines

The codelines method returns lines of code.

It can return all the code lines in the current file:

  my @codelines = $ebug->codelines();

It can return a span of code lines from the current file:

  my @codelines = $ebug->codelines(1, 3, 4, 5);

It can return all the code lines in a file:

  my @codelines = $ebug->codelines("t/Calc.pm");

It can return a span of code lines in a file:

  my @codelines = $ebug->codelines("t/Calc.pm", 5, 6);

=head2 eval

The eval method evaluates Perl code in the current program and returns
the result:

  my $v = $ebug->eval('2 ** $exp');

=head2 filename

The filename method returns the filename of the currently running code:

  print "In filename: "   . $ebug->filename   . "\n";

=head2 filenames

The filenames method returns a list of the filenames of all the files
currently loaded:

  my @filenames = $ebug->filenames();

=head2 finished

The finished method returns whether the program has finished running:

  print "Finished!\n" if $ebug->finished;

=head2 line

The line method returns the line number of the statement about to be
executed:

  print "At line: "       . $ebug->line       . "\n";

=head2 next

The next method steps onto the next line in the program. It executes
any subroutine calls but does not step through them.

  $ebug->next;

=head2 package

The package method returns the package of the currently running code:

  print "In package: "    . $ebug->package    . "\n";

=head2 pad

  my $pad  = $ebug->pad;
  foreach my $k (sort keys %$pad) {
    my $v = $pad->{$k};
    print "Variable: $k = $v\n";
  }

=head2 return

The return subroutine returns from a subroutine. It continues running
the subroutine, then single steps when the program flow has exited the
subroutine:

  $ebug->return;

It can also return your own values from a subroutine, for testing
purposes:

  $ebug->return(3.141);

=head2 run

The run subroutine starts executing the code. It will only stop on a
break point or watch point.

  $ebug->run;

=head2 step

The step method steps onto the next line in the program. It steps
through into any subroutine calls.

  $ebug->step;

=head2 subroutine

The subroutine method returns the subroutine of the currently working
code:

  print "In subroutine: " . $ebug->subroutine . "\n";

=head2 stack_trace

The stack_trace method returns the current stack trace, using
L<Devel::StackTrace>. It returns a list of L<Devel::StackTraceFrame>
methods:

  my @frames = $ebug->stack_trace;
  foreach my $frame (@trace) {
    print $frame->package, "->",$frame->subroutine, 
    "(", $frame->filename, "#", $frame->line, ")\n";
  }

=head2 stack_trace_human

The stack_trace_human method returns the current stack trace in a human-readable format:

  my @frames = $ebug->stack_trace_human;
  foreach my $frame (@trace) {
    print "$frame\n";
  }

=head2 undo

The undo method undos the last action. It accomplishes this by
restarting the process and passing (almost) all the previous commands
to it. Note that commands which do not change state are
ignored. Commands that change state are: break_point, break_point_delete,
break_point_subroutine, eval, next, step, return, run and watch_point.

  $ebug->undo;

It can also undo multiple commands:

  $ebug->undo(3);

=head2 watch_point

The watch point method sets a watch point. A watch point has a
condition, and the debugger will stop run-ing as soon as this
condition is true:

  $ebug->watch_point('$x > 100');

=head1 SEE ALSO

L<perldebguts>

=head1 AUTHOR

Leon Brocard, C<< <acme@astray.com> >>

=head1 COPYRIGHT

Copyright (C) 2005, Leon Brocard

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
