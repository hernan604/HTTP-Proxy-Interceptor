package HTTP::URL::Intercept::Proxy::Plugin::ImageInverter;
use Moose::Role;
use GD::Image;
use Data::Printer;

sub invert_image {
  my ( $self, $args ) = @_; 
  return 0 if $self->http_request->uri->as_string !~ m/(png|gif|jpg|jpeg|bmp)$/;
  my $req   = HTTP::Request->new( $self->http_request->method => $self->http_request->uri->as_string );
  my $res   = $self->ua->request( $req );
  my $image = GD::Image->new( $res->content );
  return 0 if ! defined $image;
  $image    = $image->copyRotate180();
  $self->content( $image->gif() );
  return 0;
}

after 'BUILD'=>sub {
    my ( $self ) = @_; 
    $self->append_plugin_method( "invert_image" );
};

1;

#
#   TODO
#
#   package HTTP::URL::Intercept::Proxy::Plugin::ContentModifier;
#   use Moose::Role;
#   after 'response' => sub {
#       my ( $self ) = @_; 
#       warn '$self->response->content =~ s/blablabla/xyz/';
#       warn 'or... config->{ opcao }->()  executa uma sub do arquivo de config';
#   };
#   1;

package HTTP::URL::Intercept::Proxy::Plugin::RelativePath;
use Moose::Role;

sub replace_for_relativepath {
  my ( $self, $args ) = @_; 
  foreach my $url ( keys $self->urls_to_proxy ) {
    next unless exists $self->urls_to_proxy->{ $url }->{ relative_path }
                    && $self->http_request->{ _uri }->as_string =~ m/$url/;
    my $arquivo          = $self->urls_to_proxy->{ $url }->{ relative_path } . $+{caminho}||$1;
    $arquivo =~ s/(\?.+$)//g; #tira os ?blablabla da url pois não é possível abrir arquivo
    if ( -e $arquivo ) {
      $self->print_file_as_request( $arquivo );
      return 1;
    } else {
        warn " ARQUIVO NAO ENCONTRADO: " . $arquivo;
    }
    return 0;
  }
}

after 'BUILD'=>sub {
    my ( $self ) = @_; 
    $self->append_plugin_method( "replace_for_relativepath" );
};

1;

package HTTP::URL::Intercept::Proxy::Plugin::UrlReplacer;
use Moose::Role;
use URI;
use Data::Printer;

sub replace_url {
  my ( $self, $args ) = @_; 
warn $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ url };
  if (  exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string } && 
        exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ url } ) {
    my $nova_url = 
        URI->new( $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{url} );
    if ( exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ use_random_var } 
             && $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ use_random_var } ) {
        $nova_url->query_param( "var".int(rand(99999999)) => int(rand(99999999)));
    }
    warn "  INTERCEPTED => " , $nova_url->as_string , "\n";
    my $req = HTTP::Request->new( $self->http_request->method => $nova_url->as_string );
    my $res = $self->ua->request( $req );
    $self->content( $res->content ) if $res->is_success || $res->is_redirect;

#   ->...self->response( $self->ua->request( $self->http_request ) );
#   my $res = $self->ua->get( $nova_url->as_string );
    return 0;
  }
}

after 'BUILD'=>sub {
    my ( $self ) = @_; 
    $self->append_plugin_method( "replace_url" );
};

1;

package HTTP::URL::Intercept::Proxy::Plugin::File;
use Moose::Role;

sub abre_arquivo {
  my ( $self, $args ) = @_; 
  if ( exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string } && 
       exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file } ) {
    if ( -e $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file } ) {
      $self->print_file_as_request( $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file } );
      return 1;
    } else {
      warn " ARQUIVO NAO ENCONTRADO: " . $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file };
    }
    return 0;
  }
}

after 'BUILD'=>sub {
    my ( $self ) = @_; 
    $self->append_plugin_method( "abre_arquivo" );
};

1;


package HTTP::URL::Intercept::Proxy;
use Moose;
use LWP::UserAgent;
use Data::Printer;
use Config::Any;
use File::Slurp;
use URI;
use URI::QueryParam;
use v5.10;
use Getopt::Long;
use base qw(Net::Server);

=head2 SYNOPSIS

Atenção: Este script funciona apenas para urls HTTP e não HTTPS
O proxy funciona bem liso, dá até pra ver vídeo no youtube! :)

Instruções de uso:

1. Salvar as configurações abaixo no arquivo de nome: "urls.json"

    {
      "http://www.site.com.br/js/script.js?v=136" : {
          "file" : "/home/hernan/teste.js"
      },
      "http://www.site.com.br/some/c/coolscript.js?ABC=xyz" : {
          "url" : "http://www.outra-url.com.br/por-este-arquivo-no-lugar/novo_coolscripts.js?nome=maria",
          "use_random_var"  : true             <- opcional, vai colocar ?var3271587=672317 no fim da url
      },
      "http://publicador.intranet/resources/(?<caminho>.+)" : {
          "relative_path" : "/home/hernan/publicador/resources/"
      }
    }

2. Salve e execute este script, ex:

    perl proxy-sem-ssl.pl -porta 9212

    * a porta padrão é 9999

3. Configure seu browser para usar o proxy na porta espeificada

=head2 DESCRIPTION

Este script foi criado para auxiliar o debug de scripts em produção e scripts comitados.

As situações onde este proxy pode ser útil:

    1. Suponha que você quer debugar um JS de um site que você não tem acesso
        é possível usar este proxy e debugar um js

    2. Seu site esté em produção e você precisa alterar um JS, mas o ambiente DEV ainda 
        não está 100% pronto e o único jeito é alterar direto no servidor

        sugestão#1: alterar e debugar no ar com possibilidade de quebrar algo
                #2: usar um proxy e interceptar a url do javascript e carregar um arquivo local
                    isso permite testar localmente antes de subir a nova versão
    
    3. Um script roda em produção e o ambiente de desenvolvimento não está preparado. Você
       precisa arrumar um determinado JS e não vai ter acesso completo no site... vai 
       ter que enviar a solução pronta por email para substituir o JS de prod.

        sugestão#1: usar um proxy que altera o conteudo do js, assim é possível debugar
                    o js do site em produção sem ter necessariamente acesso a esse arquivo.
                    Tudo é feito localmente enquanto o browser pensa que está acessando o
                    conteúdo verdadeiro, mas você na verdade serve conteúdo modificado com 
                    seu código.

    DICA: O firefox junto com foxyproxy possibilita filtrar apenas algumas urls específicas.

=head2 CONFIGURAÇÃO

O arquivo de configuração padrão é o urls.json 

Neste momento são permitidas 3 tipos de configuração.

    1.  url   =>  file
        Aqui o proxy vai trocar o conteúdo de uma url pelo conteúdo de um arquivo local

    ex: "http://www.site.com.br/js/script.js?v=136" : {
            "file" : "/home/hernan/teste.js"
        }

    2.  url   =>  outra url
        Aqui o proxy vai trocar o conteúdo de uma url pelo conteúdo de outra url

    ex: "http://www.site.com.br/some/c/coolscript.js?ABC=xyz" : {
            "url" : "http://www.outra-url.com.br/por-este-arquivo-no-lugar/novo_coolscripts.js?nome=maria"
        }

    3.  url*  =>  relative_path*
        Aqui o proxy vai associar uma url/* com diretorios/* e vai abrir arquivos locais respectivamente
      
    ex: "http://publicador.intranet/resources/(?<caminho>.+)" : {
            "relative_path" : "/home/hernan/publicador/resources/"
        }

    Arquivo de configuração com as 3 opções: ( salvar como urls.json )

    {
      "http://www.site.com.br/js/script.js?v=136" : {
          "file" : "/home/hernan/teste.js"
      },
      "http://www.site.com.br/some/c/coolscript.js?ABC=xyz" : {
          "url" : "http://www.outra-url.com.br/por-este-arquivo-no-lugar/novo_coolscripts.js?nome=maria"
      },
      "http://publicador.intranet/resources/(?<caminho>.+)" : {
          "relative_path" : "/home/hernan/publicador/resources/"
      }
    }

=head2 AUTHORS

Hernan Lopes

=cut

has plugin_methods                    => (  is => 'rw' , default => sub {[]}  );

sub append_plugin_method {
    my ( $self, $method ) = @_; 
    warn "Plugin method add => $method\n";
    push( @{  $self->plugin_methods  } , $method );
}

has http_request                      => ( is => 'rw' );

has porta => ( is => 'rw', default => sub { return 9999 } ) ;

my $_arg_port                         = 9999;
my $config_file_name                  = "urls.json";
GetOptions("porta=i"                  => \$_arg_port , 
           "config=s"                 => \$config_file_name );

has urls_to_proxy                     => (  is => 'rw' , default => sub {{}} );
has response                          => (  is => 'rw'  );
has content                           => (  is => 'rw'  );
has config_file_name                  => (  is => 'rw'  );

sub load_config {
  my ( $self ) = @_; 
  if ( -e $self->config_file_name ) {
     my $urls = Config::Any->load_files(
          {
              files           => [ $self->config_file_name ],
              use_ext         => 1,
              flatten_to_hash => 1
          }
      )->{ $self->config_file_name } ;
     $self->urls_to_proxy( $urls ); 
  }
  else {
      my $msg_ajuda = <<'AJUDA';

    *   Atencao.. se quiser interceptar urls e alterar seu conteudo, 
        crie o arquivo urls.json ou outro nome com o seguinte conteudo:

    {
      "http://www.site.com.br/js/script.js?v=136" : {
          "file" : "/home/hernan/teste.js"
      },
      "http://www.site.com.br/some/c/coolscript.js?ABC=xyz" : {
          "url" : "http://www.outra-url.com.br/por-este-arquivo-no-lugar/novo_coolscripts.js?nome=maria"
      },
      "http://publicador.intranet/resources/(?<caminho>.+)" : {
          "relative_path" : "/home/hernan/publicador/resources/"
      }
    }


    feito isso, execute o proxy com o comando:

    perl proxy-sem-ssl.pl -config nome_arquivo.json -porta 9000

AJUDA
      warn $msg_ajuda; 
  };
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
}  );

sub print_file_as_request {
  my ( $self, $caminho ) = @_; 
  my $conteudo = read_file( $caminho ) if -e $caminho;
  warn "  INTERCEPTED => ", $caminho, "\n";
  $self->string_content_as_http_request( $conteudo );
}

sub string_content_as_http_request {
  my ( $self, $conteudo ) = @_; 
  print "\r\n"."HTTP/1.1 200 OK\n";
  print "\r\n" . $conteudo;
  print "\n";
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
            $self->http_request(  HTTP::Request->parse( join( "\n", @$lines ) )   );
            return if $self->http_request->{ _uri }->as_string =~ m/^https/;
            warn $req_count++ ." URL REQUEST => ", $self->http_request->{ _uri }->as_string ,"\n";
            foreach my $plugin_method ( @{   $self->plugin_methods  } ) {
                my $result                 = 0;
                $result                    = $self->$plugin_method( {} );
                if ( $result == 1 ) {
                    $lines                = [];
                    $self->http_request(  undef  );
                }
            }
            last if ! defined $self->http_request;
            NORMAL_HTTP_REQUEST: {
              $self->response( $self->ua->request( $self->http_request ) );
              if ( $self->response->is_success || $self->response->is_redirect ) {
                my $content = $self->content || $self->response->content;
                $self->content( undef );
                print $self->response->protocol." ".$self->response->code." ".$self->response->message; # EX. HTTP/1.1 200 OK
                print "\r\n",$self->response->headers->as_string;
                print "\r\n",$content;
                print "\n";
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
  $self->porta( $_arg_port );
}

before 'load_config' => sub {
  my ( $self ) = @_; 
  $self->config_file_name( $config_file_name );
};

1;

package Meu::Proxy;
use Moose;
extends qw/HTTP::URL::Intercept::Proxy/;
with qw/
  HTTP::URL::Intercept::Proxy::Plugin::RelativePath
  HTTP::URL::Intercept::Proxy::Plugin::UrlReplacer
  HTTP::URL::Intercept::Proxy::Plugin::File
/;
# HTTP::URL::Intercept::Proxy::Plugin::ImageInverter
#IMAGE INVERTER

1;

my $proxy = Meu::Proxy->new();
Meu::Proxy->run(  port => $proxy->porta );
