package Devel::ebug;
use strict;
use warnings;
use Class::Accessor::Chained::Fast;
use IO::Socket::INET;
use Proc::Background;
use Scalar::Util qw(blessed);
use Storable qw(nfreeze thaw);
use String::Koremutake;
use base qw(Class::Accessor::Chained::Fast);
__PACKAGE__->mk_accessors(qw(
program socket proc
package filename line codeline finished));
our $VERSION = "0.36";

# let's run the code under our debugger and connect to the server it
# starts up
sub load {
  my $self = shift;
  my $program = $self->program;

  my $k = String::Koremutake->new;
  my $rand = int(rand(100_000));
  my $secret = $k->integer_to_koremutake($rand);
  my $port   = 3141 + ($rand % 1024);

  $ENV{SECRET} = $secret;
  my $command = "$^X -Ilib -d:ebug $program";
#  warn "Running: $command\n";
  my $proc = Proc::Background->new($command);
  $self->proc($proc);
  $ENV{SECRET} = "";

  # Lets
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

# get basic debugging information
sub basic {
  my($self) = @_;
  my $response = $self->talk({ command => "basic" });
  if (not defined $response) {
    # it dropped off the end of the program
    $self->finished(1);
  } else {
    $self->finished(0);
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

# undo
sub undo {
  my($self, $levels) = @_;
  $levels ||= 1;
  my $response = $self->talk({ command => "commands" });
  my @commands = @{$response->{commands}};
  pop @commands foreach 1..$levels;

  my $proc = $self->proc;
  $proc->die;
  $self->load;
  $self->talk($_) foreach @commands;
  $self->basic;
}

# set a break point (by default in the current file)
sub break_point {
  my $self = shift;
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

# delete a break point (by default in the current file)
sub break_point_delete {
  my $self = shift;
  my($filename, $line);
  my $first = shift;
  if ($first =~ /^\d+$/) {
    $line = $first;
    $filename = $self->filename;
  } else {
    $filename = $first;
    $line = shift;
  }

  my $response = $self->talk({
    command   => "break_point_delete",
    filename  => $filename,
    line      => $line,
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

# list filenames
sub filenames {
  my($self) = @_;
  my $response = $self->talk({ command => "filenames" });
  return @{$response->{filenames}};
}

# run until a breakpoint
sub run {
  my($self) = @_;
  my $response = $self->talk({ command => "run" });
  $self->basic; # get basic information for the new line
}

# return the stack trace
sub stack_trace {
  my($self) = @_;
  my $response = $self->talk({ command => "stack_trace" });
  return @{$response->{stack_trace}};
}

# return the stack trace in a human-readable format
sub stack_trace_human {
  my($self) = @_;
  my @human;
  my @stack = $self->stack_trace;
  foreach my $frame (@stack) {
    my $subroutine = $frame->subroutine;
    my $package = $frame->package;
    my @args = $frame->args;
    my $first = $args[0];
    my $first_class = ref($first);
    my($subroutine_class, $subroutine_method) = $subroutine =~ /^(.+)::([^:])+?$/;
#    warn "first: $first, first class: $first_class, package: $package, subroutine: $subroutine ($subroutine_class :: $subroutine_method)\n";

    if (defined $first && blessed($first) && $subroutine =~ /^${first_class}::/ &&
	$subroutine =~ /^$package/) {
      $subroutine =~ s/^${first_class}:://;
      shift @args;
      push @human, "\$self->$subroutine" . $self->stack_trace_human_args(@args);
    } elsif (defined $first && blessed($first) && $subroutine =~ /^${first_class}::/) {
      $subroutine =~ s/^${first_class}:://;
      shift @args;
      my($name) = $first_class =~ /([^:]+)$/;
      $first = '$' . lc($name);
      push @human, "$first->$subroutine" . $self->stack_trace_human_args(@args);
    } elsif ($subroutine =~ s/^${package}:://) {
      push @human, "$subroutine" . $self->stack_trace_human_args(@args);
    } elsif ($subroutine_class eq $first) {
      shift @args;
      push @human, "$first->new" . $self->stack_trace_human_args(@args);
    } else {
      push @human, "$subroutine" . $self->stack_trace_human_args(@args);
    }
  }
  return @human;
}

sub stack_trace_human_args {
  my($self, @args) = @_;
  return '(' . join(", ", @args) . ')';
}

# return from a subroutine
sub return {
  my($self, @values) = @_;
  my $values;
  $values = \@values if @values;
  my $response = $self->talk({
    command => "return",
    values  => $values,
 });
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
  my($self) = shift;
  my($filename, @lines);
  if (!defined($_[0]) || $_[0] =~ /^\d+$/) {
    $filename = $self->filename;
  } else {
    $filename = shift;
  }
  @lines = map { $_ -1 } @_;
  my $response = $self->talk({
    command  => "codelines",
    filename => $filename,
    lines    => \@lines,
  });
  return @{$response->{codelines}};
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
use Devel::StackTrace;
use PadWalker;
use Storable qw(nfreeze thaw);
use String::Koremutake;
my $socket;
my $start_server = 1;
my $mode = "step";
my @commands;

sub start_server {
  my $k = String::Koremutake->new;
  my $int = $k->koremutake_to_integer($ENV{SECRET});
  my $port   = 3141 + ($int % 1024);
  my $server = IO::Socket::INET->new(
    Listen    => 5,
    LocalAddr => 'localhost',
    LocalPort => $port,
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

# Commands that change state, so record them in case we need to undo
my @command_record = qw(break_point break_point_delete
  break_point_subroutine eval next step return run watch_point);
my %command_record;
$command_record{$_}++ foreach @command_record;

sub get {
  exit unless $socket;
  my $data = <$socket>;
  my $req = thaw(pack("h*", $data));
  push @commands, $req if $command_record{$req->{command}};
  return $req;
}

my @watch_points;
my $watch_single;
my @stack;

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
      my $secret = $ENV{SECRET};
      die "Did not pass secret" unless $req->{secret} eq $secret;
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
    } elsif ($command eq 'filenames') {
      my %filenames;
      foreach my $sub (keys %DB::sub) {
	my($filename, $start, $end) = $DB::sub{$sub} =~ m/^(.+):(\d+)-(\d+)$/;
	next if $filename =~ /^\(eval/;
	$filenames{$filename}++;
      }
      put({ filenames => [sort keys %filenames] });
    } elsif ($command eq 'codelines') {
      my $filename = $req->{filename};
      my @lines    = @{$req->{lines}};
      my @codelines = fetch_codelines($filename, @lines);
      put ({
	codelines => \@codelines,
      });
    } elsif ($command eq 'subroutine') {
      put ({
	subroutine => find_subroutine($filename, $line) || 'main',
      });
    } elsif ($command eq 'pad') {
      put ({
	pad => find_pad($package),
      });
    } elsif ($command eq 'commands') {
      put ({
	commands => \@commands,
      });
    } elsif ($command eq 'step') {
      put({});
      $mode = "step"; # single step (into subroutines)
      last; # and out of the loop, onto the next command
    } elsif ($command eq 'next') {
      put({});
      $mode = "next"; # single step (but over subroutines)
      last; # and out of the loop, onto the next command
    } elsif ($command eq 'return') {
      if ($req->{values}) {
	$stack[0]->{return} = $req->{values};
      }
      put({});
      $mode = "run"; # run until returned from subroutine
      $DB::single = 0; # run
      $stack[-1]->{single} = 1; # single step higher up
      last; # and out of the loop, onto the next command
    } elsif ($command eq 'run') {
      $mode = "run"; # run until break point
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
      put ({eval => $@ }) if $@;
      put ({eval => $v });
    } elsif ($command eq 'break_point') {
      set_break_point($req->{filename}, $req->{line}, $req->{condition});
      put ({});
    } elsif ($command eq 'break_point_delete') {
      delete_break_point($req->{filename}, $req->{line});
      put ({});
    } elsif ($command eq 'break_point_subroutine') {
      my($filename, $start, $end) = $DB::sub{$req->{subroutine}} =~ m/^(.+):(\d+)-(\d+)$/;
      set_break_point($filename, $start);
      put({});
    } elsif ($command eq 'break_points') {
      put({ break_points => break_points() });
    } elsif ($command eq 'stack_trace') {
      my $trace = Devel::StackTrace->new;
      my @frames = $trace->frames;
      # remove our internal frames
      shift @frames;
      shift @frames;
      put({ stack_trace => \@frames });
    } else {
      die "unknown command $command";
    }
  }
}

sub sub {
  my(@args) = @_;
  my $sub = $DB::sub;

  my $frame = {
    single     => $DB::single,
  };
  push @stack, $frame;

  $DB::single = 0 if defined $mode && $mode eq 'next';

  no strict 'refs';
  if (wantarray) {
    my @ret = &$sub;
    my $frame = pop @stack;
    $DB::single = $frame->{single};

    if ($frame->{return}) {
      return @{$frame->{return}};
    } else {
      return @ret;
    }
  } else {
    my $ret = &$sub;
    my $frame = pop @stack;
    $DB::single = $frame->{single};
    if ($frame->{return}) {
      return $frame->{return}->[0];
    } else {
      return $ret;
    }
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

sub fetch_codelines {
  my($filename, @lines) = @_;
  use vars qw(@dbline %dbline);
  *dbline = $main::{ '_<' . $filename };
  my @codelines = @dbline;

  # for modules, not sure why
  shift @codelines if not defined $codelines[0];

  # defined!
  @codelines = map  { defined($_) ? $_ : ""  } @codelines;
  # remove newlines
  @codelines = map { $_ =~ s/\s+$//; $_ } @codelines;
  # we run it with -d:ebug, so remove this extra line
  @codelines = grep  { $_ ne 'use Devel::ebug;' } @codelines;
  if (@lines) {
    @codelines = @codelines[@lines];
  }
  return @codelines;
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

# delete a break point
sub delete_break_point {
  my($filename, $line) = @_;
  use vars qw(@dbline %dbline);
  *dbline = $main::{ '_<' . $filename };

  $dbline{$line} = 0;
}

# return a listref of break points
sub break_points {
  return [
    sort { $a <=> $b }
    grep { $dbline{$_} }
    keys %dbline
  ];
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
