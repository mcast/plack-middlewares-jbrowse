package Plack::App::Debug::Snore;
use strict;
use warnings;

use parent 'Plack::Component';
use YAML 'Dump';


=head1 NAME

Plack::App::Debug::Snore - exercise parallel connections

=head1 SYNOPSIS

  my $app = builder {
    # outermost = first call pre-response, last chance post-response
    mount "/sleep/" => Plack::App::Debug::Snore->new->to_app;
    mount '/' => $other;
    # innermost = does its stuff, for the middlewares pre/post filter
  };

=head1 DESCRIPTION

This is a C<Plack::App> designed to exercise parallel connections.

Each request can sleep, or generate an HTML pageful of further
requests that will sleep.

Watch them load, in Firefox ~v35 with the Web Console (Network tab);
or via the server's access log.

=head1 CAVEATS

This is a quick hack.  There is no test suite.

=head1 LICENCE

 This file is part of plack-middlewares-jbrowse which extends Plack to
 support the needs of JBrowse.

 Copyright (c) 2015 Genome Research Ltd.

 Author: Matthew Astley <mca@sanger.ac.uk>

 This program is free software: you can redistribute it and/or modify it
 under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or (at your
 option) any later version.

 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
 License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut


sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env); # docs say apps shouldn't use it..?
  my $base = $req->base;
  my $P = $env->{PATH_INFO};

  if ($env->{QUERY_STRING} eq 'dump') {
    return [ 200,
             [ 'Content-Type', 'text/plain' ],
             [Dump({env => $env, base => $base, req => $req })] ];
  } elsif ($P eq '') {
    return [ 302, [ Location => "$base/" ], [] ];
  } elsif ($P eq '/') {
    my $help = qq{<html><head><title> $self </title><body><h1>$self</h1>
 <p>This works by GET requests.  Cook some up in the URL bar.</p><ul>
 <li><a href="5"> sleep 5 seconds </a>
 <li><a href="5,7"> generate a page which will sleep for 5 and 7 seconds </a>
 <li><a href="1*5,2"> generate a page which will sleep for 1 second (x5) and 2 seconds </a>
 <li><a href="foo/bar?dump"> dump \$env </a>
</ul></body></html> };
    return [ 200, [ 'Content-Type', 'text/html' ], [ $help ] ];
  } elsif (my ($delay, $cachebust) = $P =~ m{^/(\d+)(\?\d+)?$}) {
    sleep $delay;
    return [ 200, [ 'Content-Type', 'text/plain' ], [ "zzzZZZ $delay sec\n" ] ];
  } elsif ($P =~ m{^/([0-9,*]+)$}) {
    my @delay = split ',', $1;
    @delay = map { /^(\d+)\*(\d{1,2})$/ ? ($1) x $2 : $_ } @delay;
    my @img = map { my $rnd = int(rand(1E9)); qq{ <img src="$_?$rnd" width=4 height=4 border=1> } } @delay;
    my $parallel = qq{<html><head><title> Wait @delay </title></head><body>@img</body></html>\n};
    return [ 200, [ 'Content-Type', 'text/html' ], [ $parallel ] ];
  } else {
    return [ 400, [ 'Content-Type', 'text/plain' ], [ "Bad request ...$P\n" ] ];
  }
}

1;
