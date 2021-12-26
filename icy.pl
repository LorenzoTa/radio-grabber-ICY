use strict;
use warnings;

use Net::HTTP;
use URI;
use File::Spec;
use Getopt::Long;
$|++;
my $VERSION = 23;
# SOME DEFAULTS
my $debug = 0;
# --extraparts default value
my $cache_size = 2;
my $url;
my $agent = 'Stream-Cutter-v'.$VERSION;

unless ( GetOptions (
                        'url=s'     =>  \$url,
                        'agent=s'    =>    \$agent,
                        'extraparts|cache=i' =>  \$cache_size,
                        'debug=i'     =>  \$debug,                        
        )) {die "$0 -url URL [-agent STRING -extraparts N -debug [0-2]]"}

unless ( $url ){
    print "which URL you want to open?";
    $url = <STDIN>;
    chomp $url;
}
# OTHER VARIABLES 
# chunk number for debug purpose
my $num = 0;
# cache used to have more chunks wrote to a file when new song starts
my @cache;
# used to append to previous file
# how_many parts will be equal to $cache_size when new song begin
my %previous_file = ( name => undef, how_many => 0);

my ( $socket, $icymetaint ) = open_connection( $url );

die "unable to get icy-metaint!" unless defined $icymetaint 
                                        and $icymetaint > 0;
read_stream( $socket, $icymetaint );

###############################################################################
sub open_connection {   
    my $url = shift;
    my $uri = URI->new( $url );
       
    my $sock = Net::HTTP->new(     
                                Host     => $uri->host, 
                                PeerPort => $uri->port,
    ) or die $@;
                                
    $sock->write_request(    
                            GET            => $uri->path, 
                            'User-Agent'   => $agent,
                            # very important: ask for metadata!
                            'Icy-MetaData' => 1
    ) or die $@;
   
    my ($http_code, $http_mess, %headers) = $sock->read_response_headers;
    print join ' ', "\nConnecting to:\t",$uri->as_string,
                    "\nStatus:\t",$http_code,$http_mess,"\n";
    # go on if everything is OK 200
    if ( $http_code == 200){
        # grab useful headers and set them to empty string if undefined
        map {$headers{$_} =  $headers{$_} // ''} 'Server','icy-name','icy-name',
                                                 'icy-genre','icy-br';
        print join "\n","Server:\t".$headers{'Server'},
                        "name:\t".$headers{'icy-name'},
                        "genre:\t".$headers{'icy-genre'},
                        "byte rate:\t".$headers{'icy-br'}."kb/s\n\n";
        if ( $debug ){
                print  "HEADERS:\n",
                       (map {qq(\t$_\t=>\t$headers{$_}\n)}
                       grep{defined $headers{$_}} %headers),"\n\n";
        }
        return ($sock, $headers{'icy-metaint'});
    }
    # return undef if not OK 200
    else {
        print "Errors opening the given site..\n";
        return undef;
    }
}
###############################################################################   
sub read_stream {
    my ($socket, $metaint) = @_;
    # output filehandle
    my $out;
    my $new_metadata;
    my $file_name;
    
    while( 1 ) {   
        my $buffer;
        # READ the chunk of music
        $socket->read($buffer, $metaint);
        # CHECK for new metadata 
        if ( $new_metadata = read_meta($socket)){            
            # WRITE and get back the NEW filehadle 
            $out = write_stream( $buffer, $out, $new_metadata );            
        }
        else{
            # WRITE and get back the OLD filehadle
            $out = write_stream( $buffer, $out );        
        }      
    }
}
###############################################################################
sub read_meta{
    my $socket = shift;    
    my ( $metalen, $metabyte);      
    $socket->read($metabyte, 1);
    $metalen = unpack("C",$metabyte) * 16;
	unless ($metabyte){
		$debug = 1;
		warn "Nothing received by the socket! Turning debug on and..";
		sleep 1;
		warn "Retrying..";
		read_meta( $socket );
	}
	# if no networks
	# Use of uninitialized value in multiplication (*) at icy.pl line 114, <STDIN> line 1.
    if( $metalen > 0) {
        # We have NEW metadata! JOY
        print "[$metalen metadata] " if $debug > 1;
        my $metadata;
        $socket->read($metadata, $metalen);
        $metadata = unpack("A$metalen", $metadata);
        print "\nMETADATA: [",$metadata,"]\n" if $debug > 1;
        return $metadata;         
    }
    else { return undef; }    
}
###############################################################################
sub write_stream{
    my ($buf, $out, $new_metadata) = @_;
    # count the overall chunk count for debug purpose
    $num ++;
    # NEW song got from metadata
    if ( $new_metadata ){
            my $track_name = $1 if $new_metadata =~ /^StreamTitle='([^;]*)';/i;
            # if StreamTitle is empty probably is an advertisement. Fore example:
            # METADATA: [StreamTitle='';StreamUrl='';adw_ad='true';
            # durationMilliseconds='20009';adId='12161';insertionType='preroll';
            print "\ncurrently playing:\t".
                    ($track_name ? $track_name : '**advertisement**')."\n";
            
            if ($out and fileno $out and $cache_size){
                print "writing part number [$num] to current file\n" if $debug;
                # DOUBLE write of the current buff
                print $out $buf ;                
            }            
            my $file_name;
            ($file_name = $track_name) =~ s/\s+/_/g;
			exit "filename undefined!" unless $file_name;
            $file_name =~ s/\/\\:\*\?\"'<>\|//g;
# currently playing:      **advertisement**
# Use of uninitialized value $file_name in substitution (s///) at icy.pl line 148, <STDIN> line 1.
# Use of uninitialized value $file_name in substitution (s///) at icy.pl line 149, <STDIN> line 1.
            # $file_name.='.mp3';
            # if StreamTitle is empty probably is an advertisement
            $file_name = File::Spec->devnull() unless $track_name;
            # set previous filename, but still how_many = 0
            $previous_file{name} = $file_name;
            # the new file
            open $out, '>', $file_name or die "unable to write to $file_name!"; # currently playing:      Various Artists - Henry Gray / How Can You Do It? [2wCQ]
																				# unable to write to Various_Artists_-_Henry_Gray_/_How_Can_You_Do_It?_[2wCQ].mp3! at icy.pl line 154, <STDIN> line 1.
            binmode $out;
            
            if ( $cache_size > 0 ){
                # PREPEND cache items to the new opened file
                while ( my $cache_item = shift @cache ) {
                    print "writing cached part to new file: $file_name\n" if $debug;
                    print $out $cache_item;        
                }        
            }            
            # WRITE $buf to a new file
            print "writing part number [$num] to new file: $file_name\n" if $debug;
            print $out $buf;
    }
    # no new track..
    else {
        print "$num " if $debug > 1;
        # WRITE $buf to the already opened file
        if  ( $out and fileno $out ){ 
                print $out $buf or die;
        }
        # check previous_file if needed to be appended
        if ( $previous_file{name} and $previous_file{how_many} ){
            print "appending part to previous file too\n" if $debug;
            open my $oldfh, '>>', $previous_file{name} or 
                        die "unable to open $previous_file{name} in append mode!";
            binmode $oldfh;
            print $oldfh $buf or die "unable to write!";
            close $oldfh or die "unable to close filehandle!";
            $previous_file{how_many}--;
        }
        else{
            $previous_file{name} = undef;
            $previous_file{how_many} = $cache_size ;
        }
    }
    # cache rotates..
    if ( $#cache == $cache_size - 1 ){
        shift @cache,
    }
    push @cache, $buf;
    # return the current file handle
    return $out;
}
__DATA__

=head1 NAME 

C<mp3streamcutter.pl>

This program open an mp3 stream and save songs to distinct files. It's intended
to understand the ICY protocol and not intended to save copirighted data.

=head1 SYNOPSIS

    mp3streamcutter.pl -url URL [-agent STRING -extraparts N -debug 0-2]
    

    --url URL
    is the only necessary argument. Url must be complete of the protocol
    
    --agent STRING
    you can use a custom user-agent to send to server during the connection.
    Agent defaults to Stream-Cutter-v with the version number of the program
    appended. You can find useful to use the string WinampMPEG/2.9 if refused
    by some server
    
    --extraparts N
    This parameter governs how many extra parts of the stream have to be prepended
    to a new file (via cache) and appended to the previous file (via 
    reopening and appending). --extraparts defaults to 2 that is the best I found
    to have an entire song to the correct file and not to much junk in it (parts
    of other songs). --cache is an alias for --extraparts
    
    --debug 0-2
    With -debug 0 only few details of the server and the title of the current song
    will be displayed.
    With -debug 1 also headers received from the server are shown and all operations
    involving new files creation and extra parts possibly (see --extraparts) wrote
    to these files
    Debug level 2 will display also each metadata received (if it contains data) and
    a progressive number for each chunk of music received

=head1 DESCRIPTION

This program was inspired by a post wrote by qbxk for perlmonks (see references).
The core part of the program is just a rewrite of the original code by qbxk

The ICY protocol is not well documented. It's build on top of the HTTP one. This
program can help you to understand it in a better way. Basically music chunks are
intercalated with metadata chunks at the position given by the C<icy-metaint> header
value. At this position you will find a lone byte indicating the length of the 
following metadata. If this byte is not 0 but N, then the following N bytes will be
of metadata. Normally in the metadata you find the C<StreamTitle> containing the title
of the current song. You can also find the C<StreamUrl> generally empty and other things
like C<adw_ad> related to advertisements, followed by the duration of the advertisement
and other characteristics of the advertisement.

So a typical chunk of metadata for a new song in the stream will be like:

C<StreamTitle='Beethoven  - Goldberg Variations';StreamUrl='';>

or sometimes just like:

C<StreamTitle='The Clash  - Loose this skin';>

without the C<StreamUrl> part, while an advertisemente will look like:

C<StreamTitle='';StreamUrl='';adw_ad='true';durationMilliseconds='20009';adId='12161';insertionType='preroll';>

The current version of the program will try to skip advertisements checking
for empty C<StreamTitle> and then using C<File::Spec>'s C<devnull()> as filename to save the stream.

In the headers of the HTTP request you had to ask for C<Icy-MetaData>, then the server will answer
with various icy headers, notably C<icy-metaint> that is the dimension of music chunks.
After each chunk there will be a byte containing the lenght of the following metadata.
If this is 0 it means no metadata will follow, but if it is a number a correnspondant
number of bytes have to be read to have the metadata back, typically the title and the author.

The problem is that the title will arrive when the song already started, so I decided to
add a cache (see C<--extraparts> argument) to append and prepend chuncks to songs. 
This way you will have probably unneeded data at start and at the end of each file but for 
sure the entire song.

Let's say Icy-MetaData is 5 (generally is 16k), you have a situation like ( '=' it's a chunk):

  -unknown song(1)------  -------------- The Clash - Loose This Skin ------- ...
                       |  |
                       |  |
  STREAM-> = = = [0] = = = = = [3][*][*][*] = = = = = [0] = = = = = [0] = = = ...
             |    |      |      |  |  |  |      |             |           |
    unknown song  |  new song   |  |  |  |      ------ The Clash - Loose This Skin 
                  |             |  |  |  |
        empty metadata          |  ------------- metadata with new title
                                |
                         length of metadata

  (1) about unknown song: probably you never get an unknown song: I suspect that ICY protocol
  will send icy metadata as first part of a brand new response.

  
=head1 REFERENCES

See the original post by qbxk at L<perlmonks|https://www.perlmonks.org/index.pl?node_id=534645>

L<a post about ICY protocol|https://stackoverflow.com/questions/4911062/pulling-track-info-from-an-audio-stream-using-php/4914538#4914538>

L<The ICY protocol explained|http://www.smackfu.com/stuff/programming/shoutcast.html>

L<A very datailed tutorial|https://thecodeartist.blogspot.com/2013/02/shoutcast-internet-radio-protocol.html>

L<a not complete but useful description of ICY|https://www.radiotoolbox.com/community/forums/viewtopic.php?t=74>

L<a technical article about streaming networks|https://people.kth.se/~johanmon/dse/casty.pdf>


=head1 AUTHOR

This program is  by Discipulus as found in perlmonks.org with the fundamental
inspiration of the above mentioned qbxk

This program is licensed under the same terms of the Perl languange.
