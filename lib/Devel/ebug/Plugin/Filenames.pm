package Devel::ebug::Plugin::Filenames;
use base qw(Exporter);
our @EXPORT = qw(filenames);

# list filenames
sub filenames {
  my($self) = @_;
  my $response = $self->talk({ command => "filenames" });
  return @{$response->{filenames}};
}


1;
