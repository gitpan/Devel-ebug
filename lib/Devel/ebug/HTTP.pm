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
use base qw(Class::Accessor::Chained::Fast HTTP::Server::Simple::CGI);
__PACKAGE__->mk_accessors(qw(program ebug));

my $tt = Template->new;

sub handle_request {
  my ($self, $cgi) = @_;

  unless (defined $self->ebug) {
    my $ebug = Devel::ebug->new();
    $ebug->program($self->program);
    $ebug->load;
    $self->ebug($ebug);
  }

  my $ebug = $self->ebug;
  my $action = $cgi->param('action') || '';
  if ($action eq 'step') {
    $ebug->step;
  } elsif ($action eq 'next') {
    $ebug->next;
  } elsif ($action eq 'return') {
    $ebug->return;
  }

  my $vars = {
    self => $self,
    ebug => $ebug,
    codelines => [$self->codelines],
  };

  my $template = $self->template();
  $tt->process(\$template, $vars) || die $tt->error();
}

sub codelines {
  my($self) = @_;
  my $ebug = $self->ebug;

  my $lexer = PPI::Lexer->new;
  my $document = $lexer->lex_source(join "\n", $self->ebug->codelines);
  my $highlight = PPI::HTML->new(line_numbers => 1);
  my $pretty =  $highlight->html($document);

  my $split = '<span class="line_number">';
  my @lines = map { 
    $_ =~ s{</span>( +)}{"</span>" . ("&nbsp;" x length($1))}e;
    "$split$_";
  } split /$split/, $pretty;
  return @lines;
}

sub template {
  return q~
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
<script type="text/javascript">
<!--
window.onload = function() {
document.onkeypress = register;
}
function register(e) {
    var key;
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
    switch(letter) {
        case "n": window.location="?action=next"; break
        case "s": window.location="?action=step"; break
        case "r": window.location="?action=return"; break
    }
}
// -->
</script>
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

</style>
<title>[% ebug.program %] [% ebug.subroutine %]([% ebug.filename %]#[% ebug.line %]) [% ebug.codeline %]</title>
</head>
<body>
<div id="body">
<p>
[% self.program %] [% ebug.subroutine %]([% ebug.filename %]#[% ebug.line %])
<br/>
<a href="?action=step"><b>S</b>tep</a>
<a href="?action=next"><b>N</b>ext</a>
<a href="?action=return"><b>R</b>eturn</a>
</p>

<div id="code">
[% FOREACH i IN [1..codelines.size] %]
[% IF i == ebug.line %]<div id="current_line">[% END %]
  [% codelines.$i %]
[% IF i == ebug.line %]</div>[% END %]
[% END %]
</div>

<div id="pad">
<h3>Variables in [% ebug.subroutine %]</h3>
[% pad = ebug.pad %]
[% FOREACH k IN pad.keys.sort %]
  <span class="symbol">[% k %]</span> = <span class="number">[% pad.$k %]</span><br/>
[% END %]
</div>

<div id="version">
<a href="http://search.cpan.org/dist/Devel-ebug/">Devel::ebug</a> [% ebug.VERSION %]
</div>
</body>
</html>
~;
}

1;

