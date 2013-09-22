

# NAME

HTTP::Proxy::Interceptor - Blah blah blah

# SYNOPSIS

    use HTTP::Proxy::Interceptor;

# DESCRIPTION

HTTP::Proxy::Interceptor is a proxy used to intercept browser http requests.

This tool makes easy to load local files for any url, so you could debug JS on some site you dont have access to for example.

## SYNOPSIS

Atenção: Este script funciona apenas para urls HTTP e não HTTPS
O proxy funciona bem liso, dá até pra ver vídeo no youtube! :)

Instruções de uso:

1\. Salvar as configurações abaixo no arquivo de nome: "urls.json"
   

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

2\. Salve e execute este script, ex:

    perl proxy-sem-ssl.pl -porta 9212

    * a porta padrão é 9999

3\. Configure seu browser para usar o proxy na porta espeificada

## DESCRIPTION

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

## CONFIGURAÇÃO

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

# AUTHOR

Hernan Lopes <hernan@cpan.org>

# COPYRIGHT

Copyright 2013- Hernan Lopes

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO
