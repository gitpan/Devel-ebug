package Devel::ebug::Backend::Plugin::Subroutine;

sub register_commands {
  return ( subroutine  => { sub => \&subroutine } );
}

sub subroutine {
  my($req, $context) = @_;
  foreach my $sub (keys %DB::sub) {
    my($filename, $start, $end) = $DB::sub{$sub} =~ m/^(.+):(\d+)-(\d+)$/;
    next if $filename ne $context->{filename};
    next unless $context->{line} >= $start && $context->{line} <= $end;

    return { subroutine => $sub };
  }
  return { subroutine => 'main' };
}

1;
