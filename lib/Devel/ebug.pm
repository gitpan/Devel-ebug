package Devel::ebug;
use strict;
use warnings;
use Class::Accessor::Chained::Fast;
use IO::Socket::INET;
use Proc::Background;
use Storable qw(nfreeze thaw);
use base qw(Class::Accessor::Chained::Fast);
__PACKAGE__->mk_accessors(qw(
program socket proc
package filename line codeline));
our $VERSION = "0.29";

# let's run the code under our debugger and connect to the server it
# starts up
sub load {
  my $self = shift;
  my $program = $self->program;

  my $command = "$^X -Ilib -d:ebug $program";
#  warn "Running: $command\n";

  my $proc = Proc::Background->new($command);
  $self->proc($proc);

  # Lets
  my $socket;
  foreach (1..10) {
    $socket = IO::Socket::INET->new(
      PeerAddr => "localhost",
      PeerPort => '9000',
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
  });
  my $version = $response->{version};
  die "Client version $version != our version $VERSION" unless $version eq $VERSION;
  $self->basic; # get basic information for the first line
}

# get basic debugging information
sub basic {
  my($self) = @_;
  my $response = $self->talk({ command => "basic" });
  if (not defined $response) {
    # it dropped off the end of the program
  } else {
    $self->package ($response->{package });
    $self->filename($response->{filename});
    $self->line    ($response->{line    });
    $self->codeline($response->{codeline});
  }
}

# find the subroutine we're in
sub subroutine {
  my($self) = @_;
  my $response = $self->talk({ command => "subroutine" });
  if (not defined $response) {
    # it dropped off the end of the program
  } else {
    return $response->{subroutine};
  }
}

# set a watch point
sub watch_point {
  my($self, $watch_point) = @_;
  my $response = $self->talk({
    command => "watch_point",
    watch_point => $watch_point,
  });
}

# eval
sub eval {
  my($self, $eval) = @_;
  my $response = $self->talk({
    command => "eval",
    eval    => $eval,
  });
  return $response->{eval};
}

# set a break point (by default in the current file)
sub break_point {
  my($self) = shift;
  my($filename, $line, $condition);
  if ($_[0] =~ /^\d+$/) {
    $filename = $self->filename;
  } else {
    $filename = shift;
  }
  ($line, $condition) = @_;
  my $response = $self->talk({
    command   => "break_point",
    filename  => $filename,
    line      => $line,
    condition => $condition,
  });
}

# set a break point
sub break_point_subroutine {
  my($self, $subroutine) = @_;
  my $response = $self->talk({
    command    => "break_point_subroutine",
    subroutine => $subroutine,
  });
}

# list break points
sub break_points {
  my($self) = @_;
  my $response = $self->talk({ command => "break_points" });
  return @{$response->{break_points}};
}

# run until a breakpoint
sub run {
  my($self) = @_;
  my $response = $self->talk({ command => "run" });
  $self->basic; # get basic information for the new line
}

# find the pad
sub pad {
  my($self) = @_;
  my $response = $self->talk({ command => "pad" });
  return $response->{pad};
}

# return some lines of code
sub codelines {
  my($self, @lines) = @_;
  my $response = $self->talk({
    command => "codelines",
    codelines => \@lines,
  });
  return $response->{codelines};
}

# step onto the next line (going into subroutines)
sub step {
  my($self) = @_;
  my $response = $self->talk({ command => "step" });
  $self->basic; # get basic information for the new line
}

# step onto the next line (going over subroutines)
sub next {
  my($self) = @_;
  my $response = $self->talk({ command => "next" });
  $self->basic; # get basic information for the new line
}

# at the moment, we talk hex-encoded Storable object
# Don't worry about this too much
sub talk {
  my($self, $req) = @_;
  my $socket = $self->socket;
  my $data = unpack("h*", nfreeze($req));
  $socket->print($data . "\n");
  $data = <$socket>;
  if ($data) {
    my $res = thaw(pack("h*", $data));
    return $res;
  }
}

# be sure to kill the background process
sub DESTROY {
  my $self = shift;
  my $proc = $self->proc;
  $proc->die;
}


1;

package DB;
use strict;
use warnings;
use IO::Socket::INET;
use PadWalker;
use Storable qw(nfreeze thaw);
my $socket;
my $start_server = 1;

sub start_server {
  my $server = IO::Socket::INET->new(
    Listen    => 5,
    LocalAddr => 'localhost',
    LocalPort => '9000',
    Proto     => 'tcp',
    ReuseAddr => 1,
    Reuse     => 1,
  ) || die $!;
  $socket = $server->accept;
  $start_server = 0;
}

sub put {
  my($res) = @_;
  my $data = unpack("h*", nfreeze($res));
  $socket->print($data . "\n");
}

sub get {
  exit unless $socket;
  my $data = <$socket>;
  my $req = thaw(pack("h*", $data));
  return $req;
}

my @watch_points;
my $watch_single;

sub DB {
  my($package, $filename, $line) = caller;
  start_server() if $start_server;
  # single step
  my $old_single = $DB::single;
  $DB::single = 1;

  if (@watch_points) {
    my %delete;
    foreach my $watch_point (@watch_points) {
      local $SIG{__WARN__} = sub {};
      my $v = eval "package $package; $watch_point";
      if ($v) {
	$watch_single = 1;
	$delete{$watch_point} = 1;
      }
    }
    if ($watch_single == 0) {
      return;
    } else {
      @watch_points = grep { !$delete{$_} } @watch_points;
    }
  }

  use vars qw(@dbline %dbline);
  *dbline = $main::{ '_<' . $filename };

  if ($old_single == 0) {
    my $condition = $dbline{$line};
    if ($condition) {
      local $SIG{__WARN__} = sub {};
      my $v = eval "package $package; $condition";
      unless ($v) {
	$DB::single = 0;
	return;
      }
    }
  }

  $watch_single = 1;
  my $codeline = $dbline[$line];
  chomp $codeline;

  while (1) {
    my $req = get();
    my $command = $req->{command};
    if ($command eq 'ping') {
      put({
	version => $Devel::ebug::VERSION,
      });
    } elsif ($command eq 'basic') {
      put ({
	package  => $package,
	filename => $filename,
	line     => $line,
	codeline => $codeline,
      });
    } elsif ($command eq 'codelines') {
      my $codelines;
      foreach my $line (@{$req->{codelines}}) {
	my $codeline = $dbline[$line];
	next unless defined $codeline;
	chomp $codeline;
	$codelines->{$line} = $codeline;
      }
      put ({
	codelines => $codelines,
      });
    } elsif ($command eq 'subroutine') {
      put ({
	subroutine => find_subroutine($filename, $line) || 'main',
      });
    } elsif ($command eq 'pad') {
      put ({
	pad => find_pad($package),
      });
    } elsif ($command eq 'step') {
      put({});
      last; # and out of the loop, onto the next command
    } elsif ($command eq 'next') {
      put({});
      $DB::single = 2; # single step (but over subroutines)
      last; # and out of the loop, onto the next command
    } elsif ($command eq 'run') {
      put ({});
      if (@watch_points) {
	# watch points, let's go slow
	$watch_single = 0;
      } else {
	# no watch points? let's go fast!
	$DB::single = 0; # run until next break point
      }
      last; # and out of the loop
    } elsif ($command eq 'watch_point') {
      my $watch_point = $req->{watch_point};
      push @watch_points, $watch_point;
      put ({});
    } elsif ($command eq 'eval') {
      my $eval = $req->{eval};
      local $SIG{__WARN__} = sub {};
      my $v = eval "package $package; $eval";
      put ({eval => $v });
    } elsif ($command eq 'break_point') {
      set_break_point($req->{filename}, $req->{line}, $req->{condition});
      put ({});
    } elsif ($command eq 'break_point_subroutine') {
      my($filename, $start, $end) = $DB::sub{$req->{subroutine}} =~ m/^(.+):(\d+)-(\d+)$/;
      set_break_point($filename, $start);
      put({});
    } elsif ($command eq 'break_points') {
      put({
	break_points => [sort { $a <=> $b } keys %dbline],
      });
    } else {
      die "unknown command $command";
    }
  }
}

my @single_stack;
my $stack_depth = 0;

sub sub {
  my(@args) = @_;
  my $sub = $DB::sub;

  my $step_over = $DB::single == 2;
  $DB::single = 1 if $step_over;

  push @single_stack, $DB::single;
  $stack_depth++;;

  $DB::single = 0 if $step_over;

  no strict 'refs';
  if (wantarray) {
    my @ret = &$sub;
    $DB::single = 1 if $DB::single == 2;
    $DB::single = pop @single_stack;
    $stack_depth--;
    return @ret;
  } else {
    my $ret = &$sub;
    $DB::single = 1 if $DB::single == 2;
    $DB::single = pop @single_stack;
    $stack_depth--;
    return $ret;
  }

}

# find lexical variables
sub find_pad {
  my($package) = @_;
  my $pad;
  my $h = eval { PadWalker::peek_my(2) };
  foreach my $k (sort keys %$h) {
    my $v = eval "package $package; $k" || "undef";
    $pad->{$k} = $v;
  }
  return $pad;
}

# find the subroutine we're in
sub find_subroutine {
  my($ourfilename, $ourline) = @_;
  foreach my $sub (keys %DB::sub) {
    my($filename, $start, $end) = $DB::sub{$sub} =~ m/^(.+):(\d+)-(\d+)$/;
    next if $filename ne $ourfilename;
    next unless $ourline >= $start && $ourline <= $end;
    return $sub;
  }
  return '';
}

# set a break point
sub set_break_point {
  my($filename, $line, $condition) = @_;
  $condition ||= 1;
  use vars qw(@dbline %dbline);
  *dbline = $main::{ '_<' . $filename };

  # move forward until a line we can actually break on
  while (1) {
    last if not defined $dbline[$line]; # end of code
    last unless $dbline[$line] == 0; # not breakable
    $line++;
  }
  $dbline{$line} = $condition;
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

=head1 DESCRIPTION

A debugger is a computer program that is used to debug other
programs. L<Devel::ebug> is a simple, extensible Perl debugger with a
clean API. Using this module, you may easily write a Perl debugger to
debug your programs. Alternatively, it comes with an interactive
debugger, L<ebug>.

The reasoning behind building L<Devel::ebug> is that the current Perl
debugger, perl5db.pl, is very crufty, hard to use and extend and has
no tests. L<Devel::ebug> provides a simple programmatic interface to
debugging programs, which is well tested. This makes it easier to
build debuggers on top of L<Devel::ebug>, be they console-, curses-,
GUI- or Ajax-based.

L<Devel::ebug> is a work in progress.

Internally, L<Devel::ebug> consists of two parts. The frontend is
L<Devel::ebug>, which you interact with. The frontend starts the code
you are debugging in the background under the backend (running it
under perl -d:ebug code.pl). The backend starts a TCP server, which
the frontend then connects to, and uses this to drive the
backend. This adds some flexibilty in the debugger.

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

The codelines method returns a span of lines from the current file:

  my $codelines = $ebug->codelines(10 .. 20);

=head2 eval

The eval method evaluates Perl code in the current program and returns
the result:

  my $v = $ebug->eval('2 ** $exp');

=head2 filename

The filename method returns the filename of the currently running code:

  print "In filename: "   . $ebug->filename   . "\n";

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
