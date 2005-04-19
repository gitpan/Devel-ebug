package Devel::ebug::HTTP;
use strict;
use warnings;
use Catalyst qw/Static/;
#use Catalyst qw/-Debug Static/;
use Catalyst::View::TT;
use Cwd;
use Devel::ebug;
use HTML::Prototype;
use List::Util qw(max);
use Path::Class;
use PPI;
use PPI::HTML;
use Storable qw(dclone);

# globals for now, sigh
my $codelines_cache;
our $ebug;
my $lines_visible_above_count = 10;
my $root;
my $sequence = 1;
my $vars;

BEGIN {
  my $path = $INC{'Devel/ebug.pm'};
  if ($path eq 'lib/Devel/ebug.pm') {
    # we're not installed
    $root = file($path)->absolute->dir->parent->parent->subdir("root");
  } else {
    # we are installed
    $root = file($path)->dir->subdir("ebug")->subdir("root");
  }
  die "Failed to find root at $root!" unless -d $root;
}

Devel::ebug::HTTP->config(
  name => 'Devel::ebug::HTTP',
  root => $root,
);

Devel::ebug::HTTP->setup;

sub default : Private {
  my($self, $c) = @_;
  $c->stash->{template} = 'index';
  $c->forward('handle_request');
}

sub ajax_variable : Regex('^ajax_variable$') {
  my ($self, $context, $variable) = @_;
  my $value = $ebug->yaml($variable);
  $value =~ s{\n}{<br/>}g;
  my $xml = qq{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<response>
  <variable>$variable</variable>
  <value><![CDATA[$value]]></value>
</response>
  };
  $context->response->content_type("text/xml");
  $context->response->output($xml);
}

sub css : Regex('(?i)\.(?:css)') {
  my($self, $c) = @_;
  $c->serve_static("text/css");
}

sub js : Regex('(?i)\.(?:js)') {
   my($self, $c) = @_;
   $c->serve_static("application/x-javascript");
}

sub ico : Regex('(?i)\.(?:ico)') {
  my($self, $c) = @_;
  $c->serve_static("image/vnd.microsoft.icon");
}

sub images : Regex('(?i)\.(?:gif|jpg|png)') {
  my($self, $c) = @_;
  $c->serve_static;
}

sub end : Private {
  my($self, $c) = @_;
  if ($c->stash->{template}) {
    $c->response->content_type("text/html");
    $c->forward('Devel::ebug::HTTP::View::TT');
  }
}

sub handle_request : Private {
  my($self, $c) = @_;
  my $params = $c->request->parameters;

  # clear out template variables
  $vars = {};

  # pass commands we've been passed to the ebug
  my $action = lc($params->{myaction} || '');
  tell_ebug($c, $action);

  # check we're doing things in the right order
  my $cgi_sequence = $params->{sequence};
  if (defined $cgi_sequence && $cgi_sequence < $sequence) {
    $ebug->undo($sequence - $cgi_sequence);
    $sequence = $cgi_sequence;
  }
  $sequence++;

  set_up_stash($c);
}

=head2 Interacting with ebug

=over

=item tell_ebug($what);

Tell the ebug process what's going on.

=cut

sub tell_ebug {
  my ($c, $action) = @_;
  my $params = $c->request->parameters;

  if ($action eq 'break point:') {
    $ebug->break_point($params->{'break_point'});
  } elsif ($action eq 'examine') {
    my $variable = $params->{'variable'};
    my $value   = $ebug->yaml($variable) || "";
    $vars->{examine} = {
      variable => $variable,
      value    => $value,
    };
  } if ($action eq 'next') {
    $ebug->next;
  } elsif ($action eq 'restart') {
    $ebug->load;
  } elsif ($action eq 'return') {
    $ebug->return;
  } elsif ($action eq 'run') {
    $ebug->run;
  } if ($action eq 'step') {
    $ebug->step;
  } elsif ($action eq 'undo') {
    $ebug->undo;
  }
}

sub set_up_stash {
  my($c) = @_;
  my $params = $c->request->parameters;

  my $break_points;
  $break_points->{$_}++ foreach $ebug->break_points;

  my $url = $c->request->base;

  my($stdout, $stderr) = $ebug->output;

  my $codelines = codelines($c);

  $vars = {
    %$vars,
    break_points => $break_points,
    codelines => $codelines,
    ebug => $ebug,
    sequence => $sequence,
    stack_trace_human => [$ebug->stack_trace_human],
    stdout => $stdout,
    stderr => $stderr,
    subroutine => $ebug->subroutine,
    top_visible_line => max(1, $ebug->line - $lines_visible_above_count + 1),
    url => $url,
  };

  foreach my $k (keys %$vars) {
    $c->stash->{$k} = $vars->{$k};
  }
}


=item codelines

Create the marked up perl code.

=cut

sub codelines {
  my($c) = @_;
  my $filename = $ebug->filename;
  return $codelines_cache->{$filename} if exists $codelines_cache->{$filename};

  my $code = join "\n", $ebug->codelines;
  my $document = PPI::Document->new($code);
  my $highlight = PPI::HTML->new(line_numbers => 1);
  my $pretty =  $highlight->html($document);

  my $split = '<span class="line_number">';

  # turn significant whitespace into &nbsp;
  my @lines = map {
    $_ =~ s{</span>( +)}{"</span>" . ("&nbsp;" x length($1))}e;
    "$split$_";
  } split /$split/, $pretty;

  # right-justify the line number
  @lines = map {
    s{<span class="line_number">(\d+):}{
      my $size = 4 - (length($1));
      $size = 0 if $size < 0;
      '<span class="line_number">' . ("&nbsp;" x $size) . "$1:"}e;
    $_;
  } @lines;

  # add the dynamic tooltips
  my $url = $c->request->base;
  @lines = map {
    s{<span class="symbol">(.+?)</span>}{
      '<span class="symbol" ' . variable_html($url, $1) . "</span>"
      }eg;
    $_;
  } @lines;

  # make us slightly more XHTML
  $_ =~ s{<br>}{<br/>} foreach @lines;

  # link module names to search.cpan.org
  @lines = map {
    $_ =~ s{<span class="word">([^<]+?::[^<]+?)</span>}{<span class="word"><a href="http://search.cpan.org/perldoc?$1">$1</a></span>};
    $_;
  } @lines;

  $codelines_cache->{$filename} = \@lines;
  return \@lines;
}

sub variable_html {
  my($url, $variable) = @_;
  return qq{
<a style="text-decoration: none" href="#" onmouseover="return tooltip('$variable')" onmouseout="return nd();">$variable</a>};
}


1;

__END__
