package Devel::ebug::Plugin::ActionPoints;
use base qw(Exporter);
our @EXPORT = qw(break_point break_point_delete break_point_subroutine break_points watch_point);


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


# set a watch point
sub watch_point {
  my($self, $watch_point) = @_;
  my $response = $self->talk({
    command => "watch_point",
    watch_point => $watch_point,
  });
}

1;
