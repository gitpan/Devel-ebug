package Devel::ebug::Backend::Plugin::ActionPoints;
use strict;
use warnings;

sub register_commands {
  return (
  break_point => { sub => \&break_point, record => 1 },
  break_points => { sub => \&break_points },
  break_point_delete => { sub => \&break_point_delete, record => 1 },
  break_point_subroutine => { sub => \&break_point_subroutine, record => 1 },  
  watch_point => { sub => \&watch_point, record => 1 },
  );
}
sub break_point {
  my($req, $context) = @_;
  set_break_point($req->{filename}, $req->{line}, $req->{condition});
  return {};
}

sub break_points {
  my($req, $context) = @_;
  use vars qw(@dbline %dbline);
  *DB::dbline = $main::{ '_<' . $context->{filename} };
  my $break_points = [
    sort { $a <=> $b }
    grep { $DB::dbline{$_} }
    keys %DB::dbline
  ];
  return { break_points => $break_points };
}

sub break_point_delete {
  my($req, $context) = @_;
  use vars qw(@dbline %dbline);
  *DB::dbline = $main::{ '_<' . $req->{filename} };
  $DB::dbline{$req->{line}} = 0;
  return {};
}

sub break_point_subroutine {
  my($req, $context) = @_;
  my($filename, $start, $end) = $DB::sub{$req->{subroutine}} =~ m/^(.+):(\d+)-(\d+)$/;
  set_break_point($filename, $start);
  return {};
}

sub watch_point {
  my($req, $context) = @_;
  my $watch_point = $req->{watch_point};
  push @{$context->{watch_points}}, $watch_point;
  return {};
}


# set a break point
sub set_break_point {
  my($filename, $line, $condition) = @_;
  $condition ||= 1;
  *DB::dbline = $main::{ '_<' . $filename };

  # move forward until a line we can actually break on
  while (1) {
    last if not defined $DB::dbline[$line]; # end of code
    last unless $DB::dbline[$line] == 0; # not breakable
    $line++;
  }
  $DB::dbline{$line} = $condition;
}




1;
