=head2
Plugin que inverte todas as imagens em todas as páginas e as faz aparecer de ponta cabeça
=cut 

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
  $self->content( $image->png() );
  return 0;
}

after 'BUILD' => sub {
    my ( $self ) = @_; 
    $self->append_plugin_method( "invert_image" );
};

1;

package HTTP::URL::Intercept::Proxy::Plugin::ContentModifier;

=head2

Plugin para permite alterar o conteúdo de uma página. 

Uma exigencia é usar perl no seu config.pl ao inves de config.json

    "http://www.w3schools.com/" => {
        "code" => sub {
          my ( $self, $content ) = @_;
          $content =~ s/Learn/CLICK FOR WRONG/gix;
          return $content;
        }
    },

No caso acima, sempte que abrir o site www.w3schools vai trocar a palavra "Learn" por "CLICK FOR WRONG"

mas poderia ser usado para trocar caminhos de scripts, ou de imagens.

=cut

use Moose::Role;
use Data::Printer;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

after 'set_response' => sub {
    my ( $self, $http_request ) = @_; 
    if ( defined $http_request and
         exists $self->urls_to_proxy->{ $self->url } and 
         exists $self->urls_to_proxy->{ $self->url }->{ code } ) {
        if ( exists $http_request->{ _headers }->{ "content-encoding" } and
                    $http_request->{ _headers }->{ "content-encoding" } =~ m/gzip/ig ) {
            my   $content             = $http_request->content;
            my ( $content_decompressed, $scalar, $GunzipError );
            gunzip \$content => \$content_decompressed,
                        MultiStream => 1, Append => 1, TrailingData => \$scalar
               or die "gunzip failed: $GunzipError\n";
            if ( defined $content_decompressed ) {
                $http_request->content( $content_decompressed );
            }
        }
        warn "  INTERCEPTED => " , $self->url , "\n";
        my $new_content = $self->urls_to_proxy->{ $self->url }->{ code }( $self, $http_request->content );
        delete $http_request->{ _headers }->{ "content-encoding" };
               $http_request->{ _headers }->{ "content-length" } = length $new_content;
        $self->content( $new_content );
    }
};

1;

package HTTP::URL::Intercept::Proxy::Plugin::RelativePath;
use Moose::Role;

=head2

Este plugin permite mapear um diretório remoto para um diretório local, ex:

    dir remoto: http://www.site.com.br/scripts/js/(.+)
    dir local:                      /home/user/js/....

Vai tentar pegar nos mesmos diretórios mas vai abrir arquivos locais ao invés de remotos

=cut

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

=head2

Permite mapear uma url em outra url.. ou seja, quando seu browser tentar abrir uma url,

ele vai pensar que está abrindo essa url mas na verdade o conteúdo que o browser receber terá 

vindo da outra url que você mapeou.

=cut

sub replace_url {
  my ( $self, $args ) = @_; 
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

=head2

Plugin para abrir o conteudo de um arquivo e sobreescrever o conteúdo de uma url

=cut

sub abre_arquivo {
    my ( $self, $args ) = @_; 
    if ( exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string } && 
         exists $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file } ) {
        if ( -e $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file } ) {
          $self->print_file_as_request( $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file } );
          return 1;
        } else {
          warn " FILE NOT FOUND: " . $self->urls_to_proxy->{ $self->http_request->{ _uri }->as_string }->{ file };
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
   
OBS: Apague os comentários

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

OBS: Tambem é possivel usar estrutura perl para a configuracao. Utilize extensao .pl ex config.pl, e o exemplo:

    {
        #   Serve o conteudo de um arquivo local no lugar do conteudo de uma url
      "http://www.site.com.br/js/script.js?v=136" => {
          "file"            => "/home/webdev/teste.js"
      },
        #   Troca uma url pelo conteudo de outra url
      "http://um.site.com.br/arquivo.js" => {
          "url"             => "http://outro.site.com.br/outro.arquivo.js",
          "use_random_var"  => false #opcional, para colocar variavel randomica ao final da url
      },
        #   Troca o conteudo de uma imagem pela imagem de outra url
      "http://p1-cdn.trrsf.com/image/fget/cf/742/556/0/55/407/305/images.terra.com/2013/09/04/italianomortebrasileirafacereprod.jpg" => {
          "url"             => "http://h.imguol.com/1309/14beyonce23-gb.jpg"
      },
        #   Carrega conteudo de arquivos locais ao inves do arquivo do site.
        #   Pega o caminho relativamente igual aos diretorios do site.
      "http://publicador.intranet/resources/(?<caminho>.+)" => {
          "relative_path"   => "/home/hernan/publicador/resources/"
      },
        #   Troca o conteudo de um site pelo conteudo de ouro site
      "http://www.site1.com.br/" => {
          "url" => "http://www.site2.com.br/"
      },
        #   Altera o conteudo com o plugin de alterar conteudo
      "http://www.w3schools.com/" => {
          "code" => sub {
            my ( $self, $content ) = @_;
            $content =~ s/Learn/CLICK FOR WRONG/gix;
            return $content;
          }
      },
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
has response                          => (  is => 'rw' , writer => 'set_response' );
has content                           => (  is => 'rw'  );
has config_file_name                  => (  is => 'rw'  );
has url                               => (  is => 'rw'  );

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
        crie o arquivo urls.json/config.json/config.pl ou outro nome com o seguinte conteudo:

    {
      "http://www.site.com.br/js/script.js?v=136" : {
          "file" : "/home/hernan/teste.js"
      },
      "http://www.site.com.br/some/c/coolscript.js?ABC=xyz" : {
          "url" : "http://www.outra-url.com.br/por-este-arquivo-no-lugar/novo_coolscripts.js?nome=maria",
          "use_random_var"  : false
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
  $self->content_as_http_request( {
    conteudo    => $conteudo,
    status_line => "HTTP/1.1 200 OK\n",
  } );
}

sub content_as_http_request {
  my ( $self, $args ) = @_; 
  print        $args->{status_line};     # EX. HTTP/1.1 200 OK
  $args->{ headers }->content_length( length $args->{ conteudo } ) if exists $args->{ conteudo };
  print "\r\n",$args->{headers}->as_string         if exists $args->{headers};
  print "\r\n",$args->{conteudo}        if exists $args->{conteudo};
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
            $lines = [] and last if (exists $self->http_request->{ _uri } && $self->http_request->{ _uri }->as_string =~ m/^https|:443/g);
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
                my $content = $self->content || $self->response->content;
                $self->content_as_http_request( {
                  conteudo    => $content,
                  headers     => $self->response->headers,
                  status_line => $self->response->protocol." ".$self->response->code." ".$self->response->message,
                } );
                $self->content( undef );
                $self->set_response( undef );
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
  HTTP::URL::Intercept::Proxy::Plugin::ImageInverter
/;

# HTTP::URL::Intercept::Proxy::Plugin::ContentModifier
# HTTP::URL::Intercept::Proxy::Plugin::ImageInverter
#IMAGE INVERTER

1;

my $proxy = Meu::Proxy->new();
Meu::Proxy->run(  port => $proxy->porta );
