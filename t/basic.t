#use strict;
package Meu::Proxy;
use Test::More;
use HTTP::Proxy::Interceptor;
use lib 't/';
use TestServer;
use HTTP::Tiny;
use Data::Printer;
use TestsConfig;
use Moose;
extends qw/HTTP::Proxy::Interceptor/;

my $url_path;
my $proxy_port      = 32452;
my $tests_config    = TestsConfig->new();
my $server          = TestServer->new();
   $server->set_dispatch( $tests_config->conteudos );
my $pid_server      = $server->background();
my $proxy           = Meu::Proxy->new();
my $pid             = fork_proxy( $proxy );
my $ua              = HTTP::Tiny->new( );
my $ua_proxy        = HTTP::Tiny->new( proxy => "http://127.0.0.1:$proxy_port" );


my $res = $ua->get( $server->root . "/scripts.js");
ok( $res->{ content } eq $tests_config->conteudos->{ '/scripts.js' }->{args}->{ content }->{ original } , "original content is ok" );
#warn $res->{content};
#warn $tests_config->conteudos->{ '/scripts.js' }->{ args }->{ content }->{ original };

# Access url /scripts.js
$url_path       = "/scripts.js";
my $res_proxy   = $ua_proxy->get( $server->root . $url_path );
ok( $res_proxy->{ content } eq $tests_config->conteudos->{ $url_path }->{args}->{ content }->{ original } , "original content is ok" );

# Access url /teste.js
$url_path       = "/teste.js";
$res_proxy      = $ua_proxy->get( $server->root . $url_path );
ok( $res_proxy->{ content } eq $tests_config->conteudos->{ $url_path }->{args}->{ content }->{ original } , "content is ok" );

#kill webserver and proxyserver
kill 'HUP', $pid, $pid_server;

sub fork_proxy {
    my $proxy = shift;
#   my $sub   = shift;
    my $pid = fork;
    die "Unable to fork proxy" if not defined $pid;
    if ( $pid == 0 ) {
        $0 .= " (proxy)";
        # this is the http proxy
        $proxy->run(  port => $proxy_port );
#       $sub->() if ( defined $sub and ref $sub eq 'CODE' );
        exit 0;
    }
    # back to the parent
    return $pid;
}
done_testing;
