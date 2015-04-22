package Plack::App::PerfTest;
use strict;
use warnings;

use parent 'Plack::Component';
use URI;
use YAML 'Dump';
use HTML::Entities 'encode_entities';
use File::Slurp qw( read_dir slurp );

# Spot configs, the CGP-2014 way of doing it; my copy of that
our $JBROWSE_AUTOCONF = '/nfs/users/nfs_m/mca/gitwk-cgp/JBrowse-mca/autoconf';

# as configured in the conf/nginx.conf frontend proxy
our @EXPERIMENT = qw( a b c d );


=head1 NAME

Plack::App::PerfTest - launch a few web pages, collect subjective responsiveness

=head1 SYNOPSIS

  my $app = builder {
    # outermost = first call pre-response, last chance post-response
    mount "/jump/" => Plack::App::PerfTest->new->to_app;
    mount '/' => $other;
    # innermost = does its stuff, for the middlewares pre/post filter
  };

=head1 DESCRIPTION

This is a C<Plack::App> which sends the user off to visit something,
then dumps UX info to the F<access.log>.

=head1 CAVEATS

This is a quick hack.  There is no test suite.  It is for internal use
only.

=cut


sub call {
  my ($self, $env) = @_;

  my $req = Plack::Request->new($env);
  my $res = $req->new_response(200);
  $res->content_type('text/html; charset=UTF-8');
  $res->header('Cache-Control' => 'no-cache');
  $self->page($req, $res);
  return $res->finalize;
}


sub base {
  my ($self) = @_;
  die "No request?" unless $self->{__PT_req};
  return $self->{__PT_req}->base->clone;
}

sub Q {
  my ($self, $key) = @_;
  die "No request?" unless $self->{__PT_Q};
  return $self->{__PT_Q}->{$key};
}

sub res {
  my ($self) = @_;
  die "No response?" unless $self->{__PT_res};
  return $self->{__PT_res};
}


sub page {
  my ($self, $req, $res) = @_;
  my $P = $req->path;
  my $Q = $req->parameters; # mix GET and POST, we know which we want in the logs
  local $self->{__PT_req} = $req;
  local $self->{__PT_res} = $res;
  local $self->{__PT_Q} = $Q;

  # warn Dump({ P => $P, Q => $Q, base => $self->base }); # DEBUG
  if ($P eq '/RESULT') {
    # logged already.  now go back to the form.
    my $next = $self->base;
    my $k = $Q->{experiment};
    my $v = $Q->{result};
    my $done = $Q->{done};
    $done .= ',' if $done;
    $done .= "$k$v";
    $next->query_form({ user => $Q->{user}, test => $Q->{test}, done => $done }, ';');
    $self->res->redirect($next);

  } elsif ($P ne '/') {
    $res->status(404);
    $res->body('<html><head><title> Not found </title></head><body><h1> Not found </h1></body></html>');

  } elsif (not $Q->{user}) {
    # who is it?
    $self->hi();

  } else {
    # Doing a test
    # FIXME: XSS check on $Q->qw{user test}
    my $prev = $Q->{test};
    my ($test, %left) = $self->_next($Q);
    if (defined $prev && $prev eq $test) {
      $self->show($Q->{prev}, $test, %left);
    } else {
      # Jump to next test
      my $next = $self->base;
      my %next = (user => $Q->{user}, test => $test);
      $next{prev} = $prev if defined $prev;
      $next->query_form(%next);
      $self->res->redirect($next);
    }
  }
  return;
}

sub _next {
  my ($self, $Q) = @_;

  my %done = $self->_result($Q->{done});
  my %left = ((map {($_ => undef)} @EXPERIMENT), %done);
  my @todo = grep { !defined $left{$_} } keys %left;

  my $test = $Q->{test};
  $test = '' unless defined !$test;
  if (!$test || !@todo) {
    # new test
    %left = ();

    # (and not the same as the current one!)
    my $old = $test;
    while ($test eq $old) {
      $test = $self->_findtest;
    }
  }

  return ($test, %left);
}

sub _findtest {
  my ($self) = @_;
  my @conf = grep { -f "$JBROWSE_AUTOCONF/$_/trackList.json" }
    read_dir($JBROWSE_AUTOCONF);
  my $n = @conf;
  my $test;
  while(!defined $test) {
    $test = $conf[ int(rand($n)) ];
    my $txt = slurp("$JBROWSE_AUTOCONF/$test/trackList.json");
    # dev system is not presently available in irods lashup
    undef $test if $txt =~ m{/nfs/cancer_trk-dev};
  };
  return $test;
}

sub _result {
  my ($self, $done) = @_;
  my %done;
  foreach my $d (split /,/, ($done || '')) {
    if ($d =~ m{^([a-z]+)(\d+)$}) {
      $done{$1} = $2;
    } else {
      die "Bad done element '$d' in '$done'";
    }
  }
  return %done;
}

sub __H {
  my ($txt) = @_;
  return encode_entities($txt);
}

sub headfoot {
  my ($self, $body) = @_;
  my $base = $self->base;
  $self->res->body(qq{<html><head>
      <title> CancerIT: JBrowse performance feedback tool </title>
      <style type="text/css">
 .flash {
   background: #ccffcc;
   padding: 1em;
 }
 .contact {
   font-style: italic;
   position: absolute;
   bottom: 0px;
   left:   0px;
   right:  0px;
   padding: 1em;
   border-top: 3px solid grey;
 }
 ul.expts li   {
   padding: 1em;
 }
 ul.expts li a {
   padding: 1ex;
   margin: 1em;
   background: #eeeeff;
 }
 ul.expts li a:focus {
   border: 3px green solid;
 }
 ul.expts li.done { color: grey }
 ul.expts li.done a { background: none; }
 button.selected {
   background: lightgreen;
   color: black;
   border-radius: 5px;
   border: thin black outset;
 }
 h1 a { color: black }
      </style>
    </head>
    <body> <h1> <a href="$base"> JBrowse PerfTest </a> </h1>
$body
      <div class="contact">
        Contact <a href="mailto:mca\@sanger.ac.uk?subject=JBrowse.PerfTest">Matthew Astley</a>
        for Cancer IT <a href="https://confluence.sanger.ac.uk/display/IT/JBrowse+performance">Re: JBrowse performance</a>. </div>
    </body></html>});
  return;
}

sub hi {
  my ($self) = @_;
  $self->headfoot(qq{ <h2> Hi </h2>
    <p> Thanks for coming to check on JBrowse performance. </p>
    <form method="get">
      <label> Please tell me your username so I can get back to you:
        <input name="user" type="text" width="20">
      </label>
      <button> Next &raquo; </button>
    </form> });
  return;
}

sub show {
  my ($self, $prev, $test, %left) = @_;
  my $flash = '';
  if ($prev) {
    $flash = qq{ <div class="flash"> Thanks for completing '@{[__H($prev)]}'.
      You can close the window or try another test project. </div>\n };
  }
  my $result = $self->base;
  $result->path_segments($result->path_segments, 'RESULT');

  my %hid = (user => $self->Q('user'), test => $test);
  if (my $done = $self->Q('done')) {
    $hid{done} = $done;
  }

  my %result = (Skipped => 0, Broken => 1, "Too slow" => 2, Slow => 3, OK => 4, Fast => 5, "Very fast" => 6);

  my @case;
  foreach my $expt (sort keys %left) {
    my $uri = $self->base;
    $uri->path("/$expt/index.html");
    $uri->query("data=autoconf/$test&tracks=dna");
    $hid{experiment} = $expt;
    my @form = map {qq{ <input type="hidden" name="$_" value="$hid{$_}"> }} sort keys %hid;
    foreach my $outcome (sort { $result{$a} <=> $result{$b} } keys %result) {
      my $sel = (defined $left{$expt} && $left{$expt} == $result{$outcome}) ? 'class="selected"' : '';
      push @form, qq{ <button $sel name="result" value="$result{$outcome}"> $outcome </button> };
    }
    my $sel = defined $left{$expt} ? 'class="done"' : '';
    push @case, qq{  <li $sel> <form method="get" action="$result">
      <a href="$uri" target="_blank">$expt</a> <label> Optional comment: <input type="text" name="comment" width="40"> </label>
      <br>
      @form
      </form> </li>\n};
  }
  $self->headfoot(qq{ <h2> Test on @{[__H($test)]} </h2> $flash
    <p> Please try each of these links (which will open in another tab) and let us know how they feel </p>
    <ul class="expts">
@case
    </ul>
    <form method="get">
      <input type="hidden" name="user" value="@{[ $self->Q('user') ]}">
      <p> Or <button> Jump! </button> to test another project </p>
      <ul>
        <li> <label> of your choice <input type="text" name="test" width=10> </label> </li>
        <li> or blank to choose at random </li>
      </ul>
    </form>
  });
  return;
}

1;
