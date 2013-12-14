package HTTP::Proxy::Interceptor;

use 5.008_005;
our $VERSION = '0.01';
use Moose;
use LWP::UserAgent;
use Data::Printer;
use Config::Any;
use File::Slurp;
use URI;
use URI::QueryParam;
use v5.10;
use base qw(Net::Server);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

has plugin_methods                    => (  is => 'rw' , default => sub {[]}  );
has http_request                      => (  is => 'rw' );
has port                              => (  is => 'rw', default => sub { return 9999 } ) ;
has urls_to_proxy                     => (  is => 'rw' , default => sub {{}} );
has response                          => (  is => 'rw' , writer => 'set_response' );

has [ qw/
  override_content
  override_headers

  response_code
  response_msg

  config_file_name
  url
  config_path
/ ]                  => (  is => 'rw'  );

sub append_plugin_method {
    my ( $self, $method ) = @_; 
    warn "Plugin method add => $method\n";
    push( @{  $self->plugin_methods  } , $method );
}

sub load_config {
    my ( $self ) = @_; 
    if ( $self->config_path && -e $self->config_path ) {
       my $urls = Config::Any->load_files(
            {
                files           => [ $self->config_path ],
                use_ext         => 1,
                flatten_to_hash => 1
            }
        )->{ $self->config_path } ;
       $self->urls_to_proxy( $urls ); 
    }
}

has ua => ( is => 'rw', default => sub {
    my $ua = LWP::UserAgent->new(
        agent                   => "Mozilla/5.0",
        cookie_jar              => {},
        max_redirect            => 0,
        timeout                 => 60,
    #   ssl_opts                => { 
    #     verify_hostname => 0, 
    #     SSL_verify_mode => SSL_VERIFY_NONE, 
    #   }
    );
    return $ua;
} );

sub print_file_as_request {
  my ( $self, $path ) = @_; 
  my $content = read_file( $path ) if -e $path;
  warn "  INTERCEPTED => ", $path, "\n";
  $self->content_as_http_request( {
    content     => $content,
    status_line => "HTTP/1.1 200 OK\n",
  } );
}

sub content_as_http_request {
  my ( $self, $args ) = @_; 
  print        $args->{status_line};     # EX. HTTP/1.1 200 OK
  print "\r\n",$args->{headers}         if exists $args->{headers};
  print "\r\n",$args->{content}         if exists $args->{content};
# print "\n";
}

my $lines = [];
my $req_count = 0;
sub process_request {
    my $self    = shift;
    my $is_ssl  = 0 ;
    while (<STDIN>) {
        my $line = $_;
        $line =~ s/\r\n$//;
        push @$lines, $line;
        if ( length $line == 0 || ! defined $line ) {
            $self->load_config();
            $self->http_request(   HTTP::Request->parse( join( "\n", @$lines ) )   );
            ABORT_SSL_CONNECTIONS : {
                if ( exists $self->http_request->{ _uri } && 
                            $self->http_request->{ _uri }->as_string =~ m/^https|:443/g ) {
                    $lines = [];
                    last;
                }
            }
            $self->url( $self->http_request->{ _uri }->as_string );
            warn $req_count++ ." URL REQUEST => ", $self->http_request->{ _uri }->as_string ,"\n";
            foreach my $plugin_method ( @{   $self->plugin_methods  } ) {
                if ( $self->$plugin_method() == 1 ) {
                    $lines                = [];
                    $self->http_request(  undef  );
                }
            }
            last if ! defined $self->http_request;
            NORMAL_HTTP_REQUEST: {
                $self->set_response( $self->ua->request( $self->http_request ) );
                if ( $self->response->is_success || $self->response->is_redirect ) {
                    $self->response_code( $self->response->code );
                    $self->response_msg( $self->response->{ _msg } );
                    my $content = (defined $self->override_content ) ? $self->override_content : $self->response->content;
                    OVERRIDE_HEADERS : {
                        if ( defined $self->override_headers ) {
                            my $protocol = $self->response->protocol;
                            $self->set_response(
                                  HTTP::Response->new( 
                                      $self->response_code, 
                                      $self->response_msg, 
                                      $self->override_headers, 
                                  ) 
                            );
                            $self->response->protocol($protocol);
                        }
                    }
                    $self->response->headers->content_length( length $content ) if defined $content ;
                    $self->content_as_http_request( {
                        content     => $content,
                        headers     => $self->response->headers->as_string,
                        status_line => $self->response->protocol." ".$self->response->code." ".$self->response->message,
                    } );
                    CLEANUP: {
                        $self->override_content( undef );
                        $self->set_response( undef );
                        $self->response_code( undef );
                        $self->response_msg( undef );
                    }
                }
            }
            $lines = [];
            last;
        }
        last if /quit/i;
    }
}

sub BUILD {
  my ( $self ) = @_; 
  $self->load_config();
}

sub start {
  my ( $self ) = @_; 
  $self->run( 
    port => $self->port
  );
}

after 'set_response' => sub {
    my ( $self, $http_request ) = @_;
    DECOMPRESS_CONTENT: {
        #always decompress the response so plugins dont need to
        if ( defined $http_request and
             defined $http_request->content and
             exists  $http_request->{ _headers }->{ "content-encoding" } and
                     $http_request->{ _headers }->{ "content-encoding" } =~ m/gzip/ig ) {
            my   $content             = $http_request->content;
            my ( $content_decompressed, $scalar, $GunzipError );
            gunzip \$content => \$content_decompressed,
                        MultiStream => 1, Append => 1, TrailingData => \$scalar
               or die "gunzip failed: $GunzipError\n";
               $content = $content_decompressed;
                delete $http_request->{ _headers }->{ "content-encoding" };
                       $http_request->{ _headers }->{ "content-length" } = length $content_decompressed;
            $http_request->{ _content } = $content;
        }
    }
};


1;
__END__

=encoding utf-8


=head1 NAME

HTTP::Proxy::Interceptor - Intercept and modify http requests w/ custom plugins

=head2 SYNOPSIS

Important: This script works with HTTP requests and not HTTPS requests.
Its working well and as a matter of fact its possible to watch youtube video.

You need 4 steps to setup your custom proxy.

Instructions:

1. Create your custom proxy with the plugins you need.

I will name it proxy.pl:

    package My::Custom::Proxy;
    use Moose;
    extends qw/HTTP::Proxy::Interceptor/;
    with qw/
      HTTP::Proxy::InterceptorX::Plugin::File
      HTTP::Proxy::InterceptorX::Plugin::ContentModifier
      HTTP::Proxy::InterceptorX::Plugin::ImageInverter
      HTTP::Proxy::InterceptorX::Plugin::RelativePath
      HTTP::Proxy::InterceptorX::Plugin::UrlReplacer
    /;
     
    1;

    my $p = My::Custom::Proxy->new(
      config_path => 'teste_config.pl',
      port        => 9919,
    );

    $p->start ;
    1;

2. Create a config file, choose a format and name your config. 

It will be loaded using Config::Any, so you can name it your_config.json, your_config.pl, your_config.yamls, anyname.json

Here is a urls.json config file example:
   
    {
      "http://www.site.com.br/js/script.js?v=136" : {
          "File" : "/home/user/replace/response/content/with/teste.js"
      },
      "http://www.site.com.br/some/c/coolscript.js?ABC=xyz" : {
          "UrlReplacer"      : "http://www.outra-url.com.br/por-este-arquivo-no-lugar/novo_coolscripts.js?nome=maria",
          "use_random_var"   : true             <- optional, will append ?var3271587=672317 on the end of url, good for cache
      },
      "http://publicador.intranet/resources/(?<caminho>.+)" : {
          "RelativePath" : "/home/hernan/publicador/resources/"
      }
    }

Some plugins (such as ContentModifier) might expect a coderef inside your config file, so json will not work. In that case you will need to save your config as pl file. 

See this urls_config.pl file example:

    {
      #replaces the response-content with content from a specified file.
      #plugin used: HTTP-Proxy-InterceptorX-Plugin-File
      "http://www.site.com.br/js/script.js?v=136" => {
          "File"            => "/home/webdev/teste.js"
      },

      #replace the response-content with the content from another url
      #plugin used: HTTP-Proxy-InterceptorX-Plugin-UrlReplacer
      "http://um.site.com.br/arquivo.js" => {
          "UrlReplacer"     => "http://outro.site.com.br/outro.arquivo.js",
          "use_random_var"  => false #opcional, para colocar variavel randomica ao final da url
      },

      #replaces an image with another image from another url.
      #plugin used: HTTP-Proxy-InterceptorX-Plugin-UrlReplacer
      "http://p1-cdn.trrsf.com/image/fget/cf/742/556/0/55/407/305/images.terra.com/2013/09/04/italianomortebrasileirafacereprod.jpg" => {
          "UrlReplacer"     => "http://h.imguol.com/1309/14beyonce23-gb.jpg"
      },

      #Loads the content from local files instead of files from the website.
      #will read files from the relative path you specify
      #plugin used: HTTP-Proxy-InterceptorX-Plugin-RelativePath
      "http://publicador.intranet/resources/(?<caminho>.+)" => {
          "RelativePath"   => "/home/hernan/publicador/resources/"
      },

      #replace the response-content with the content from another url
      #plugin used: HTTP-Proxy-InterceptorX-Plugin-UrlReplacer
      "http://www.site1.com.br/" => {
          "UrlReplacer" => "http://www.site2.com.br/"
      },

      #modify the response-content, but only some words.
      #plugin used: HTTP-Proxy-InterceptorX-Plugin-ContentModifier
      "http://www.w3schools.com/" => {
          "ContentModifier" => sub {
            my ( $self, $content ) = @_;
            $content =~ s/Learn/CLICK FOR WRONG/gix;
            return $content;
          }
      },
    }

3. Having done that, make sure you installed the desired plugins and start your proxy with:

    perl proxy.pl

or if you prefer, download the plugins and start the proxy with:

    perl -I../HTTP-Proxy-Interceptor/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-ContentModifier/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-File/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-ImageInverter/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-RelativePath/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-UrlReplacer/lib/      proxy.pl

4. Configure your browser and point to the proxy with the specified port

=head2 DESCRIPTION

HTTP::Proxy::Interceptor is a proxy you can use to intercept browser http requests and debug production scripts and commited scripts. 

This tool makes easy to trick the browser to load local files for a given url. That way you can debug JS, or modify content on a site you dont have access to for example, or maybe a js in your site stopped working and you want to find out why.

If there is not a plugin to do what you want, just create a plugin an use it.

The plugin HTTP::Proxy::InterceptorX::Plugin::ImageInverter will invert everyimage.

After trying a couple proxy solutions, i noticed none of them satisfied my needs, some of them would just hang when hit with too many requests. 

So i thought, why not create a newer proxy that can be extended with plugins created by anyone ? Would be great if we have that. Thats when HTTP::Proxy::Interceptor was born.

Its reinventing the wheel, but the wheel is smoother. If you find a bug, feel free to contact me, or fix them yourself and submit a pull request.

Useful situations to run this proxy:

    1. Suppose you must debug a JS on a site you dont have access to
        its possible with this proxy

    2. Your site is 100% in production and you must modify a JS, however the DEV environment
       is not ready yet. The only way is saving the file live, on the server. 
       You can do that, and cross your fingers everything will work. Or, test using a
       proxy and save only after testing locally.
    
    3. A script is in production and you dont have access to 'save' the file. Then you
       must send the file to someone so they replace it for you.

    TIP: In Firefox with FoxyProxy you can filter out which urls must pass over the proxy

=head1 CONFIGURATION

You can have the configuration in json, perl, yaml etc. Config::Any will be used to read config.
    
    my $p = My::Custom::Proxy->new(
      config_path => 'teste_config.pl',
      port        => 9919,
    );

However, if you prefer not having a config file, just pass it to your instance ie:

    my $p = My::Custom::Proxy->new(
      port        => 9919,
      urls_to_proxy=> {
          .... the configuration here ...
      }
    );


=head1 AUTHOR

Hernan Lopes E<lt>hernan@cpan.orgE<gt>

=head1 CONTRIBUTORS

Fixed something? Created or fixed a feature ? add your name here

=head1 COPYRIGHT

Copyright 2013 - Hernan Lopes

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
