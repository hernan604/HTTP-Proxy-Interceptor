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
my $proxy_port      = int(rand(9999))+50000;

# tests config, webserver config
my $tests_config    = TestsConfig->new();

# web server
my $server          = TestServer->new();
   $server->set_dispatch( $tests_config->conteudos );
my $pid_server      = $server->background();

# proxy server
my $proxy           = Meu::Proxy->new();
my $pid_proxy       = fork_proxy( $proxy );

#user agents: 1 normal, 1 with proxy
my $ua              = HTTP::Tiny->new( ); #normal user agent
my $ua_proxy        = HTTP::Tiny->new( proxy => "http://127.0.0.1:$proxy_port" ); #user agent with proxy

# Access url /teste.js
$url_path       = "/teste.js";
my $res         = $ua->get( $server->root . $url_path );
ok( $res->{ content } eq $tests_config->conteudos->{ $url_path }->{args}->{ content }->{ original } , "content is ok" );

# Access url /scripts.js
$url_path       = "/scripts.js";
my $res_proxy   = $ua_proxy->get( $server->root . $url_path );
ok( $res_proxy->{ content } eq $tests_config->conteudos->{ $url_path }->{args}->{ content }->{ original } , "original content is ok" );



#kill webserver and proxyserver
kill 'KILL', $pid_proxy, $pid_server;

sub fork_proxy {
    my $proxy = shift;
    my $pid = fork;
    die "Unable to fork proxy" if not defined $pid;
    if ( $pid == 0 ) {
        $0 .= " (proxy)";
        $proxy->run(  port => $proxy_port );
        exit 0;
    }
    return $pid;
}

done_testing;
