package Devel::ebug::HTTP;
use warnings;
use strict;
use Devel::ebug;
use Class::Accessor::Chained::Fast;
use HTTP::Server::Simple::CGI;
use PPI;
use PPI::HTML;
use PPI::Lexer;
use Template;
use List::Util qw(max);
use Scalar::Util qw(blessed);
use base qw(Class::Accessor::Chained::Fast HTTP::Server::Simple::CGI);
__PACKAGE__->mk_accessors(qw(program ebug));

my $tt = Template->new;
my $lines_visible_above_count = 10;
my $sequence = 1;

=head1 NAME

Devel::ebug::HTTP - webserver front end to Devel::ebug

=head1 SYNOPSIS

  # it's easier to use the 'ebug_httpd' script
  my $server = Devel::ebug::HTTP->new();
  $server->port(8080);
  $server->program($filename);
  $server->run();

=head1 DESCRIPTION

=head2 Accessors

In addition to the accessors defined by the
B<HTTP::Server::Simple::CGI>, the following get/set chanined
accessors are defined.

=over

=item program

The name of the program we're running.  When C<run> is called
an instance of B<Devel::ebug> is created that executes this
program.

=item ebug

The B<Devel::ebug> instance that this front end is displaying.

=back

=head2 Internals

Essentially this module is a B<HTTP::Server::Simple::CGI> subclass.
The main method is the C<handle_request> method which is called for
each request to the websever.

=over

=item handle_request

Method that's called each individual request that's made to the server
from the web browser.  This dispatches to all the other methods.

=cut

sub handle_request {
  my ($self, $cgi) = @_;

  # ignore requests that we don't want to handle
  if ($self->skip_request($cgi))
    { return }

  # start the ebug process if we need to
  unless ($self->ebug)
    { $self->create_ebug }

  # pass commands we've been passed to the ebug
  my $action = lc($cgi->param('myaction') || '');
  $self->tell_ebug($action);

  # check we're doing things in the right order
  my $cgi_sequence = $cgi->param('sequence');
  if (defined $cgi_sequence && $cgi_sequence < $sequence) {
    $self->ebug->undo($sequence - $cgi_sequence);
    $sequence = $cgi_sequence;
  }
  $sequence++;

  # start again if the process has completed
  if ($self->ebug->finished) {
    $self->ebug->load;
  }

  print $self->create_output;
}

=item skip_request

Returns true if we should skip the current request and return
a 404.  Currently used for not creating favicons.

=cut

sub skip_request {
  my ($self, $cgi) = @_;
  my $url = $cgi->self_url;

  # no, we don't have a favourite icon
  return 1 if $url =~ /favicon.ico/;

  # don't skip it
  return;
}

=back

=head2 Interacting with ebug

=over

=item create_ebug

Create a new ebug instance and store it via the C<ebug> accessor.

=cut

sub create_ebug {
  my ($self) = @_;

  my $ebug = Devel::ebug->new();
  $ebug->program($self->program);
  $ebug->load;
  $self->ebug($ebug);

  return $ebug;
}

=item tell_ebug($what);

Tell the ebug process what's going on.

=cut

sub tell_ebug {
  my ($self,$action) = @_;
  my $ebug = $self->ebug;

  if ($action eq 'step') {
    $ebug->step;
  } elsif ($action eq 'next') {
    $ebug->next;
  } elsif ($action eq 'return') {
    $ebug->return;
  } elsif ($action eq 'undo') {
    $ebug->undo;
  }
}

=back

=head2 Creating the HTML/HTTP response

=over

=item create_output

Create everything that's sent to the client.  Calls the other methods
documented below.

=cut

sub create_output {
  my $self = shift;

  # process the template
  my $html = $self->create_html;

  return $self->header($html)
         . "\r\n"
         . $html;
}

=item create_html

Create the html.

=cut

sub create_html {
  my $self = shift;
  my $ebug = $self->ebug;

  my $vars = {
    codelines => $self->codelines,
    ebug => $ebug,
    self => $self,
    sequence => $sequence,
    stack_trace_human => [$ebug->stack_trace_human],
    top_visible_line => max(1, $ebug->line - $lines_visible_above_count + 1),
  };

  my $html;
  my $template = $self->template();
  $tt->process(\$template, $vars, \$html) || die $tt->error();

  return $html;
}

=item codelines

Create the marked up perl code.

=cut

sub codelines {
  my($self) = @_;
  my $ebug = $self->ebug;
  my $filename = $ebug->filename;
  return $self->{codelines_cache}->{$filename} if exists $self->{codelines_cache}->{$filename};

  my $lexer = PPI::Lexer->new;
  my $document = $lexer->lex_source(join "\n", $self->ebug->codelines);
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

  # link module names to search.cpan.org
  @lines = map {
    $_ =~ s{<span class="word">([^<]+?::[^<]+?)</span>}{<span class="word"><a href="http://search.cpan.org/perldoc?$1">$1</a></span>};
    $_;
  } @lines;

  $self->{codelines_cache}->{$filename} = \@lines;
  return \@lines;
}

=item header($html)

Return a string that contains the http header for the html that's
been passed (including the server status code.)

=cut

sub header {
  my ($self,$html) = @_;

  return "HTTP/1.0 200 OK\r\n"
    . "Content-Type: text/html\r\n"
    . "Content-Cache: No\r\n"
    . "Content-Length: " . length($html) . "\r\n";
}

=item template

Return the template toolkit template.

=cut

sub template {
  return q~
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
<style type="text/css">
body {
        margin: 0px;
        background-color: white;
        font-family: sans-serif;
        color: black;
}
#body {
        margin: 10px 240px 0px 10px;
        padding: 0px;
}
#pad {
        position: absolute;
        top: 30px;
        right: 0px;
        width: 200px;

        padding-right: 10px;
        padding-bottom: 0px;
        background-color: #ffffff;
}
#version {
        text-align: center;
        font-size: small;
        clear: both;

        margin-top: 10px;
        padding: 5px 0px 5px 0px;
        color: #aaaaaa;
}
#code {
  font-family: monospace;
/* margin-left: 30px; */
/* margin-right: 30px; */
  background: #eeeedd;
  border-width: 1px;
  border-style: solid solid solid solid;
  border-color: #ccc;
  padding: 10px 10px 10px 10px;
}
#current_line { background: #ffcccc; }
.line_number { color: #aaaaaa; }
.comment  { color: #228B22; }
.symbol  { color: #00688B; }
.word { color: #8B008B; font-weight:bold; }
.structure { color: #000000; }
.number { color: #B452CD; }
.single  { color: #CD5555;}
.double  { color: #CD5555;}

</style>
<script type="text/javascript">
<!--
window.onload = function() {
document.onkeypress = register;
}
function register(e) {
    var key;
    var myaction;
    if (e == null) {
        // IE
        key = event.keyCode
    }
    else {
        // Mozilla
        if (e.altKey || e.ctrlKey) {
            return true
        }
        key = e.which
    }
    letter = String.fromCharCode(key).toLowerCase();
    switch (letter) {
        case "n": myaction = "next"; break
        case "r": myaction = "return"; break
        case "s": myaction = "step"; break
        case "u": myaction = "undo"; break
    }
    if (myaction) {
      document.hiddenform.myaction.value = myaction;
      document.hiddenform.submit();
    }
}
// -->
</script>
<title>[% ebug.program | html %] [% ebug.subroutine %]([% ebug.filename | html %]#[% ebug.line %]) [% ebug.codeline | html %]</title>
</head>
<body>
<div id="body">
<p>
[% self.program | html %] [% ebug.subroutine %]([% ebug.filename | html %]#[% ebug.line %])
<br/>
<form name="myform" method="post">
 <input type="hidden" name="sequence" value="[% sequence %]">
 <input type="submit" name="myaction" value="Step">
 <input type="submit" name="myaction" value="Next">
 <input type="submit" name="myaction" value="Return">
 <input type="submit" name="myaction" value="Undo">
</form>
</p>

<div id="code">
[% FOREACH i IN [1..codelines.size] %]
[% IF i == top_visible_line %]<a name="top"></a>[% END %]
[% IF i == ebug.line %]<div id="current_line">[% END %]
  [% codelines.$i %]
[% IF i == ebug.line %]</div>[% END %]
[% END %]
</div>

<div id="pad">
<h3>Variables in [% ebug.subroutine | html %]</h3>
[% pad = ebug.pad %]
[% FOREACH k IN pad.keys.sort %]
  <span class="symbol">[% k | html %]</span> = <span class="number">[% pad.$k | html %]</span><br/>
[% END %]

<h3>Stack trace</h3>
<small>
[% FOREACH frame IN stack_trace_human %]
  [% frame %]<br/>
[% END %]
</small>
</div>

<div id="version">
<a href="http://search.cpan.org/dist/Devel-ebug/">Devel::ebug</a> [% ebug.VERSION %]
</div>

<form name="hiddenform" method="post" style="visibility:hidden;">
 <input type="hidden" name="myaction" value="nothing">
 <input type="hidden" name="sequence" value="[% sequence %]">
 <input type="submit" name="foo" value="Return">
</form>
</body>
</html>
~;
}

1;

