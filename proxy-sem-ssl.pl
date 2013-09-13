package HTTP::Proxy::Interceptor;
use Moose;
use LWP::UserAgent;
use Data::Printer;
use Config::Any;
use File::Slurp;
use URI;
use URI::QueryParam;
use v5.10;

=head2 SYNOPSIS

Atenção: Este script funciona apenas para urls HTTP e não HTTPS

Instruções de uso:

1. Salvar as configurações abaixo no arquivo de nome: "urls.json"

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

2. Salve e execute este script, ex:

    perl proxy.pl

=head2 DESCRIPTION

Este script foi criado para auxiliar o debug de scripts em produção e scripts comitados.

As situações onde este proxy pode ser útil:

    1. Suponha que você quer debugar um JS de um site que você não tem acesso
        é possível usar este proxy e debugar um js

    2. Seu site esté em produção e você precisa alterar um JS, mas não existe ambiente DEV
        sugestão#1: alterar no ar com possibilidade de quebrar algo
                #2: usar um proxy e interceptar a url do javascript e carregar um arquivo local
                    isso permite testar bem antes de subir a nova versão


    DICA: O firefox junto com foxyproxy possibilita filtrar apenas algumas urls.

=head2 CONFIG

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

my $url_intercept = {};

sub load_config {
  if ( -e 'urls.json' ) {
     $url_intercept = Config::Any->load_files(
          {
              files           => ['urls.json'],
              use_ext         => 1,
              flatten_to_hash => 1
          }
      )->{'urls.json'};
  } 
  else {
      say " *** Atencao.. se quiser interceptar urls e alterar seu conteudo, crie o arquivo urls.json com o seguinte conteudo:";
      say 
        qq|
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
        |;
            
  };
}

use base qw(Net::Server);
my $ua = LWP::UserAgent->new(
    agent                   => "Mozilla",
    cookie_jar              => {},
    max_redirect            => 0,
#   ssl_opts                => { 
#     verify_hostname => 0, 
#     SSL_verify_mode => SSL_VERIFY_NONE, 
#   }
);


sub print_file_as_request {
  my ( $caminho ) = @_; 
  my $conteudo = read_file( $caminho ) if -e $caminho;
  warn "  INTERCEPTED => ", $caminho, "\n";
  if ( !-e $caminho )  {
    $conteudo = "";
    warn "  **** ERROR **** arquivo não existe: " . $caminho;
    warn "  **** ERROR **** arquivo não existe: " . $caminho;
    warn "  **** ERROR **** arquivo não existe: " . $caminho;
  }
  print "\r\n"."HTTP/1.1 200 OK\n";
  print "\r\n" . $conteudo;
  print "\n";
}

my $lines = [];
my $req_count = 0;
sub process_request {
    my $self = shift;
    my $is_ssl = 0 ;
    while (<STDIN>) {
        my $line = $_;
        $line =~ s/\r\n$//;
        push @$lines, $line;
        if ( length $line == 0 || !defined $line ) {
            load_config();
            my $req = HTTP::Request->new( );
            my $obj = HTTP::Request->parse( join( '\n', @$lines ) );
            warn $req_count++ ." URL REQUEST => ", $obj->{ _uri }->as_string ,"\n";
            ABRE_ARQUIVO: {
              if ( exists $url_intercept->{ $obj->{ _uri }->as_string } && 
                   exists $url_intercept->{ $obj->{ _uri }->as_string }->{ file } ) {
                if ( -e $url_intercept->{ $obj->{ _uri }->as_string }->{ file } ) {
                  print_file_as_request( $url_intercept->{ $obj->{ _uri }->as_string }->{ file } );
                  $lines  = [];
                  $obj    = undef;
                } else {
                  warn " ARQUIVO NAO ENCONTRADO: " . $url_intercept->{ $obj->{ _uri }->as_string }->{ file };
                }
              }
            }
            last if ! defined $obj;
            foreach my $url ( keys $url_intercept ) {
              next unless exists $url_intercept->{ $url }->{ relative_path }
                              && $obj->{ _uri }->as_string =~ m/$url/;
              my $arquivo          = $url_intercept->{ $url }->{ relative_path } . $+{caminho}||$1;
              $arquivo =~ s/(\?.+$)//g; #tira os ?blablabla da url pois não é possível abrir arquivo
              if ( -e $arquivo ) {
                print_file_as_request( $arquivo );
                $lines  = [];
                $obj    = undef;
              } else {
                  warn " ARQUIVO NAO ENCONTRADO: " . $arquivo;
              }
            }
            last if ! defined $obj;
            ALTERA_URL: {
              if (  exists $url_intercept->{ $obj->{ _uri }->as_string } && 
                    exists $url_intercept->{ $obj->{ _uri }->as_string }->{ url } ) {
                my $nova_url = 
                 URI->new( $url_intercept->{ $obj->{ _uri }->as_string }->{url} );
                $nova_url->query_param( "var".int(rand(99999999)) => int(rand(99999999)));
                warn "  INTERCEPTED => ", $nova_url->as_string, "\n";
                $obj->uri( $nova_url->as_string ); #troca a url
              }
              HTTP_REQUEST: { 
                my $response = $ua->request( $obj );
                if ( $response->is_success || $response->is_redirect ) {
                  print $response->protocol." ".$response->code." ".$response->message; # EX. HTTP/1.1 200 OK
                  print "\r\n".$response->headers->as_string;
                  print "\r\n".$response->content;
                  print "\n";
                }
              }
            }
            $lines = [];
            last;
        }
        last if /quit/i;
    }
}

HTTP::Proxy::Interceptor->run(port => 9999);

