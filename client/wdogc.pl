#!/usr/bin/perl
use IO::Socket;
my $answer;
my ($remote_host, $remote_port) = ("cvsbackup.example.ru", '11211');
my $socket = IO::Socket::INET->new(PeerAddr => $remote_host, 
                                   PeerPort => $remote_port, 
                                   Proto    => "tcp", 
                                   Type     => SOCK_STREAM) 
        or eval { (print "deny") && exit;};

my $req = sprintf("%s", ($ARGV[0] eq 'a')?"ask":($ARGV[0] eq 's')?"submit":"none");
chomp(my $name = (split /\s/, `grep cvspath /root/bin/.cvsbackup.cf`)[-1]);
chomp(my $repos = (split /\//, `grep cvsroot /root/bin/.cvsbackup.cf`)[-1] || "cvs");
print $socket "$name $req $repos\n";
chomp($answer = <$socket> || "deny");
print $answer if ($ARGV[0] ne 's');
