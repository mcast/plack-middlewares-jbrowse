package Plack::MiddlewareX::HttpRangeBytes;
use strict;
use warnings;

use parent qw(Plack::Middleware);
use Plack::Util;
use YAML 'Dump'; # for debug


=head1 NAME

Plack::MiddlewareX::HttpRangeBytes - serve part of a file

=head1 SYNOPSIS

  my $content = Plack::App::Directory->new({ root => $root })->to_app;

  # headers for pre-compressed files
  my $app = builder {
    enable 'Plack::MiddlewareX::PreZipped';
    enable 'Plack::MiddlewareX::HttpRangeBytes';
    $content;
  };

=head1 DESCRIPTION

This L<Plack::Middleware> module converts C<200 OK> responses to C<206
Partial Content> responses, if the request specifies.

It works with filehandles open for reading a file on disk, when
restricted to a single byte range defined with numbers at both ends.
This is enough to serve L<JBrowse|http://jbrowse.org/> v1.11.6 as I
had it configured.

=head1 CAVEATS

Several parts of RFC2616 are ignored, only partially implemented or
interpreted rather liberally.  I marked the code where I know I have
done this.

Implicit range endpoints (e.g. C<bytes -500> or C<bytes 500->) are not
supported.

The multipart media type C<multipart/byteranges> for multiple ranges
is not supported.

Partial responses from streams are unlikely to work.

Partial responses from list-of-scalars is broken.

There is no test suite.

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
  my($self, $env) = @_;
  my $res  = $self->app->($env);
  return Plack::Util::response_cb($res, sub { $self->_rangify(shift, $env->{HTTP_RANGE}) });
}

sub _rangify {
  my ($self, $res, $RANGE) = @_;
  my ($status, $headers, $body) = @$res;
  my $hout = Plack::Util::headers($headers);
  $hout->set('Accept-Ranges', 'bytes'); # per http://tools.ietf.org/html/rfc2616#section-14.5

  # If-Range: not handled (14.27)
  return unless $status == 200 && defined $RANGE;

  # Range: simple case only http://tools.ietf.org/html/rfc2616#section-14.35
  # XXX: multi-range and multipart/byteranges not handled (19.2)
  my ($start, $end) = $RANGE =~ m{^bytes=(\d+)-(\d+)$};
  if (!defined $start || !defined $end) {
    $self->_badrange($res, "Cannot parse HTTP_RANGE='$RANGE'");
  } elsif ($end-$start+1 > 30*1024*1024) { # arbitrary limit
    $self->_badrange($res, "Range request $RANGE is too long");
  } else {
    $self->_make_range($res, $hout, $body, $start, $end);
  }

  return;
}

sub _badrange {
  my ($self, $res, $msg) = @_;
  # whinge - probably violating http://tools.ietf.org/html/rfc2616#section-10.4.17
  warn "_badrange: $msg";
  @$res = (416, [ 'Content-Type', 'text/plain' ], [ "$msg\n" ]);
  return;
}

sub _make_range {
  my ($self, $res, $hout, $body, $start, $end) = @_;
  my $wantlen = $end - $start + 1;
  my $len;

  if (ref($body) eq 'ARRAY' && 1 == @$body) { # XXX: need to allow multiple elements
    $len = length($body->[0]);
    if ($end + 1 > $len) {
      $self->_badrange($res, "Range $start-$end outside object of size $len");
      undef $len;
    } else {
      $body = [ substr($body->[0], $start, $len) ];
    }
  } elsif (Plack::Util::is_real_fh($body)) {
    my $fh = $body;
    $body = [];
    $len = $self->_file_chunk($res, $fh, $body, $start, $end);
  } else {
    die Dump({ body_type_unhandled => $body }); # XXX: lame
  }

  if (defined $len) { # i.e. we haven't called _badrange
    # selective compliance with http://tools.ietf.org/html/rfc2616#section-10.2.7
    my $len_sfx = defined $len ? "/$len" : '';
    $res->[0] = 206; # "Partial Content"
    $hout->set('Content-Length', $wantlen);
    $hout->set('Content-Range', "bytes $start-$end$len_sfx");
    $res->[2] = $body;
  }

  return;
}

# modifies @$res or @$body
sub _file_chunk {
  my ($self, $res, $fh, $body, $start, $end) = @_;
  my $wantlen = $end - $start + 1;
  my $len = -s $fh; # XXX: hoping it is not a stream

  my $path = eval { $fh->can('path') } ? $fh->path : '[data]';
  if ($end + 1 > $len) {
    $self->_badrange($res, "Range $start-$end outside file size $len");
    return ();
  } else {
    seek($fh, $start, 0) or die "Seek($path, $start, SEEK_SET): $!";
    my $txt = '';
    my $nread = read($fh, $txt, $wantlen);
    die "Read $path at $start+$wantlen: $!" unless defined $nread;
    die "Read $path at $start+$wantlen: want $wantlen, got $nread" unless $nread == $wantlen;
    push @$body, $txt;
    return $len;
  }
}


1;
