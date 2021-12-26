# radio-grabber-ICY
demonstrative usage of Perl to grab a MP3 stream using the ICY protocol

NAME

mp3streamcutter.pl

This program open an mp3 stream and save songs to distinct files. It's intended to understand the ICY protocol and not intended to save copirighted data.
SYNOPSIS

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

DESCRIPTION

This program was inspired by a post wrote by qbxk for perlmonks (see references). The core part of the program is just a rewrite of the original code by qbxk

The ICY protocol is not well documented. It's build on top of the HTTP one. This program can help you to understand it in a better way. Basically music chunks are intercalated with metadata chunks at the position given by the icy-metaint header value. At this position you will find a lone byte indicating the length of the following metadata. If this byte is not 0 but N, then the following N bytes will be of metadata. Normally in the metadata you find the StreamTitle containing the title of the current song. You can also find the StreamUrl generally empty and other things like adw_ad related to advertisements, followed by the duration of the advertisement and other characteristics of the advertisement.

So a typical chunk of metadata for a new song in the stream will be like:

StreamTitle='Beethoven - Goldberg Variations';StreamUrl='';

or sometimes just like:

StreamTitle='The Clash - Loose this skin';

without the StreamUrl part, while an advertisemente will look like:

StreamTitle='';StreamUrl='';adw_ad='true';durationMilliseconds='20009';adId='12161';insertionType='preroll';

The current version of the program will try to skip advertisements checking for empty StreamTitle and then using File::Spec's devnull() as filename to save the stream.

In the headers of the HTTP request you had to ask for Icy-MetaData, then the server will answer with various icy headers, notably icy-metaint that is the dimension of music chunks. After each chunk there will be a byte containing the lenght of the following metadata. If this is 0 it means no metadata will follow, but if it is a number a correnspondant number of bytes have to be read to have the metadata back, typically the title and the author.

The problem is that the title will arrive when the song already started, so I decided to add a cache (see --extraparts argument) to append and prepend chuncks to songs. This way you will have probably unneeded data at start and at the end of each file but for sure the entire song.

Let's say Icy-MetaData is 5 (generally is 16k), you have a situation like ( '=' it's a chunk):


<pre>

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

</pre>


REFERENCES

See the original post by qbxk at [perlmonks](perlmonks|https://www.perlmonks.org/index.pl?node_id=534645) 

[a post about ICY protocol](https://stackoverflow.com/questions/4911062/pulling-track-info-from-an-audio-stream-using-php/4914538#4914538)

[The ICY protocol explained](http://www.smackfu.com/stuff/programming/shoutcast.html)

[A very datailed tutorial](https://thecodeartist.blogspot.com/2013/02/shoutcast-internet-radio-protocol.html)

[a not complete but useful description of ICY](https://www.radiotoolbox.com/community/forums/viewtopic.php?t=74)

[a technical article about streaming networks](https://people.kth.se/~johanmon/dse/casty.pdf)


AUTHOR

This program is by Discipulus as found in perlmonks.org with the fundamental inspiration of the above mentioned qbxk

This program is licensed under the same terms of the Perl languange.
