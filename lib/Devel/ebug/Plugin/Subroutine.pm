package Devel::ebug::Plugin::Subroutine;
use strict;
use warnings;
use base qw(Exporter);
our @EXPORT = qw(subroutine);

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

1;
