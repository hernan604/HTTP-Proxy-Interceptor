

# NAME

HTTP::Proxy::Interceptor - Intercept and modify http requests w/ custom plugins

## SYNOPSIS

Important: This script works with HTTP requests and not HTTPS requests.
Its working well and as a matter of fact its possible to watch youtube video.

You need 4 steps to setup your custom proxy.

Instructions:

1\. Create your custom proxy with the plugins you need.

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

2\. Create a config file, choose a format and name your config. 

It will be loaded using Config::Any, so you can name it your\_config.json, your\_config.pl, your\_config.yamls, anyname.json

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

See this urls\_config.pl file example:

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

3\. Having done that, make sure you installed the desired plugins and start your proxy with:

    perl proxy.pl

or if you prefer, download the plugins and start the proxy with:

    perl -I../HTTP-Proxy-Interceptor/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-ContentModifier/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-File/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-ImageInverter/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-RelativePath/lib/ -I../HTTP-Proxy-InterceptorX-Plugin-UrlReplacer/lib/      proxy.pl

4\. Configure your browser and point to the proxy with the specified port

## DESCRIPTION

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

# AUTHOR

Hernan Lopes <hernan@cpan.org>

# CONTRIBUTORS

Fixed something? Created or fixed a feature ? add your name here

# COPYRIGHT

Copyright 2013 - Hernan Lopes

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO
