package Plack::MiddlewareX::PreZipped;
use parent qw(Plack::Middleware);
use Plack::Util;
#use YAML 'Dump'; # for debug

### nginx.conf
#
#        location ~* "\.(json|txt)z$" {
#           add_header Content-Encoding  gzip;
#           gzip off;
#           types { application/json jsonz; }
#        }

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
