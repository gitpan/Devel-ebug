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
use List::Util qw/max/;
use base qw(Class::Accessor::Chained::Fast HTTP::Server::Simple::CGI);
__PACKAGE__->mk_accessors(qw(program ebug));

my $tt = Template->new;
my $lines_visible_above_count = 10;

sub handle_request {
  my ($self, $cgi) = @_;

  unless (defined $self->ebug) {
    my $ebug = Devel::ebug->new();
    $ebug->program($self->program);
    $ebug->load;
    $self->ebug($ebug);
  }

  my $ebug = $self->ebug;
  my $action = lc($cgi->param('myaction') || '');
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
    codelines => $self->codelines,
    stack_trace => [$ebug->stack_trace],
    top_visible_line => max(1, $ebug->line - $lines_visible_above_count + 1),
  };

  my $html;
  my $template = $self->template();
  $tt->process(\$template, $vars, \$html) || die $tt->error();

  print "HTTP/1.0 200 OK\r\n";
  print "Content-Type: text/html\r\nContent-Length: ",
  length($html), "\r\n\r\n", $html;
}

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

  # link module names to search.cpan.org
  @lines = map {
    $_ =~ s{<span class="word">([^<]+?::[^<]+?)</span>}{<span class="word"><a href="http://search.cpan.org/perldoc?$1">$1</a></span>};
    $_;
} @lines;

  $self->{codelines_cache}->{$filename} = \@lines;
  return \@lines;
}

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
        case "s": myaction = "step"; break
        case "r": myaction = "return"; break
    }
    if (myaction) {
      document.hiddenform.myaction.value = myaction;
      document.hiddenform.submit();
    }
}
// -->
</script>
<title>[% ebug.program %] [% ebug.subroutine %]([% ebug.filename %]#[% ebug.line %]) [% ebug.codeline %]</title>
</head>
<body>
<div id="body">
<p>
[% self.program %] [% ebug.subroutine %]([% ebug.filename %]#[% ebug.line %])
<br/>
<form name="myform" method="post">
 <input type="submit" name="myaction" value="Step">
 <input type="submit" name="myaction" value="Next">
 <input type="submit" name="myaction" value="Return">
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
<h3>Variables in [% ebug.subroutine %]</h3>
[% pad = ebug.pad %]
[% FOREACH k IN pad.keys.sort %]
  <span class="symbol">[% k %]</span> = <span class="number">[% pad.$k %]</span><br/>
[% END %]

<h3>Stack trace</h3>
[% FOREACH frame IN stack_trace %]
  [% frame.subroutine -%]
([%- FOREACH arg IN frame.args %][% arg %][% UNLESS loop.last %], [% END %][% END %])
<br/>
[% END %]
</div>

<div id="version">
<a href="http://search.cpan.org/dist/Devel-ebug/">Devel::ebug</a> [% ebug.VERSION %]
</div>

<form name="hiddenform" method="post" style="visibility:hidden;">
 <input type="hidden" name="myaction" value="nothing">
 <input type="submit" name="foo" value="Return">
</form>
</body>
</html>
~;
}

1;

