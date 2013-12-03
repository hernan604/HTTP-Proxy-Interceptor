package TestsConfig;
use Moose;
use IO::Compress::Gzip qw(gzip $GzipError);

has conteudos => (
    is => 'ro',
    default => sub {
        return 
        {
            "/scripts.js" => {
                
                ref     => \&html_content,
                args    => {
                    content => {
                        original => <<SCRIPT
alert( "javascript original content" );
SCRIPT
                
                        ,altered => <<SCRIPT
var altered_content = "other content";
SCRIPT
                    }
                }
            },
            "/teste.js" => {
                ref     => \&html_content,
                args    => {
                    content => {
                        original => <<SCRIPT
alert( "BLAAAAAAAAAAAAAAAA" );
SCRIPT
                
                        ,altered => <<SCRIPT
var altered_content = "other content";
SCRIPT
                    }
                }
            },
            "/content-compressed.js" => {
                ref     => \&html_content,
                args    => {
                    headers => [
                      -content_type     => 'text/html',
#                     -expires  => '+3d',
                      -content_encoding => 'gzip'
                    ],
                    content => {
                        original => sub {
                            #returns a gzipped content
                            my $input = "some input to be compressed";
                            my $compressed_output;
                            my $status = gzip \$input => \$compressed_output or die "gzip failed: $GzipError\n";
                            return $compressed_output;
                          }->()
                        ,altered => <<SCRIPT
var altered_content = "other content";
SCRIPT
                    }
                }
            }
        };
    }
); 

sub html_content {
    my ( $cgi, $url_path, $args ) = @_;
    return if !ref $cgi;
    print
        $cgi->header( ( $args->{ headers } ) ? @{$args->{headers}} : () ),
        (   defined $args 
        and exists $args->{ content } 
        and exists $args->{ content }->{ original } )
        ? $args->{ content }->{ original } : ""
}


1;
