package Devel::ebug::Plugin::Basic;
use base qw(Exporter);
our @EXPORT = qw(basic);

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

1;
