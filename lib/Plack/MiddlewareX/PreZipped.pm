package Plack::MiddlewareX::PreZipped;
use strict;
use warnings;

use parent qw(Plack::Middleware);
use Plack::Util;
#use YAML 'Dump'; # for debug


=head1 NAME

Plack::MiddlewareX::PreZipped - serve pre-gzipped files

=head1 SYNOPSIS

  my $content = Plack::App::Directory->new({ root => $root })->to_app;

  # headers for pre-compressed files
  my $app = builder {
    enable 'Plack::MiddlewareX::PreZipped';
    enable 'Plack::MiddlewareX::HttpRangeBytes';
    $content;
  };

=head1 DESCRIPTION

This L<Plack::Middleware> module supplies necessary headers to allow
gzipped files on disk to be served as if they were uncompressed files
with the correct C<Content-Type> plus a C<Content-Encoding>.

It is enough to serve L<JBrowse|http://jbrowse.org/> v1.11.6 as I had
it configured.

In terms of an L<nginx.conf(5)> configuration, it does this

  location ~* "\.(json|txt)z$" {
     add_header Content-Encoding  gzip;
     gzip off;
     types { application/json jsonz; }
  }

=head1 CAVEATS

This code lacks configuration - it is hardwired to how we use it for
JBrowse.

There is no test suite.

=cut


sub call {
  my($self, $env) = @_;
  my $res  = $self->app->($env);
  if ($env->{REQUEST_URI} =~ m{\.(json|txt)z$}) {
    my $suffix = $1;
    return Plack::Util::response_cb($res, sub { $self->_fix_headers($suffix, @_) });
  } else {
    return $res;
  }
}

sub _fix_headers {
  my ($self, $suffix, $res) = @_;
  my $mime_type = Plack::MIME->mime_type(".$suffix");
  my ($status, $headers, $body) = @$res;
  $headers = Plack::Util::headers($headers);
#  warn Dump({ res_in => $res, _fix_headers => \@_ });
  $headers->set('Content-Encoding' => 'gzip');
  $headers->set('Content-Type' => $mime_type) if defined $mime_type;
  return;
}

1;
