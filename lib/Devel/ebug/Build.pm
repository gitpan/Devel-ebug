package Devel::ebug::Build;
use strict;
use Module::Build;
use File::Find qw(find);
use Path::Class;
use base 'Module::Build';
use vars qw/$FAKE/;
# handily ripped from Siesta::Build, thanks richardc

sub ACTION_install {
    my $self = shift;
    $self->SUPER::ACTION_install;
    $self->ACTION_install_extras;
}

sub ACTION_fakeinstall {
    my $self = shift;
    $self->SUPER::ACTION_fakeinstall;
    local $FAKE = 1;
    $self->ACTION_install_extras;
}

sub ACTION_install_extras {
    my $self = shift;
    my $path = dir($self->{config}{installsitelib}, "Devel", "ebug");
    my @files = $self->_find_extras;
    print "Installing extras to $path\n";
    for (@files) {
        $FAKE
          ? print "$_ -> $path/$_ (FAKE)\n"
          : $self->copy_if_modified($_, $path);
    }
}

sub _find_extras {
    my $self = shift;
    my @files;
    find(sub {
             $File::Find::prune = 1 if -d && /^\.svn$/;
             return if -d;
             return if /~$/;
             push @files, $File::Find::name;
         }, @{ $self->{config}{__extras_from} });
    return @files;
}

1;
