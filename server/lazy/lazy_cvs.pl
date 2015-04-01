#!/usr/bin/env perl
# $Id$
use lib "/root/bin/lazy";
use warnings;
use strict;
use Cwd;
#use Mysql;
use DBI;
use Glob::Glob qw/config_parse/; # perldoc Glob/Glob.pm

die "no config\n" unless ($ARGV[0] && $ARGV[0] =~ /^config=/);

my (undef, $cf_file) = split /=/, $ARGV[0];
my %cfg=(config=>$cf_file); # compat with Glob::Glob
config_parse(\%cfg, \%cfg);

!(defined $cfg{'dbname'} or defined $cfg{'dbpass'} or defined $cfg{'dbuser'} or defined $cfg{'dbhost'}) && die "- no db settings\n";
print "configs done\n" if ($cfg{debug} > 0);
# eof config parsing and preflight checks

sub logmsg
{
  if ($cfg{'debug'} >= 1)
   {
     open(LFH, ">>$cfg{'log'}") or die "logmsg: $!\n";
     print LFH "[".scalar(localtime)."] ".$$." ".(join " ", @_)."\n";
     close(LFH); 
   }
}

sub deny
{
  my $who = shift;
  print "deny";
  logmsg "[client] $who denied [$who]";
  exit;
}

sub checkLoad($)
{
 my $who = shift;
 #my $la = (split /\s/, `/sbin/sysctl vm.loadavg`)[2] || "1000"; #for freebsd
 my $la = (split /\s/, `cat /proc/loadavg`)[2] || "1000"; #for linux
 $la = (split /\,/, $la)[0];
 if (defined $cfg{'load'} && ($la < $cfg{'load'}))
  { return 1; }
 else
  {
    logmsg "[system] la is $la [$who]";
    deny($who);
  }
}

sub checkHello($$$)
{
  my ($rhost, $who, $raddr) = @_;
  if (($rhost eq $who)|(index($cfg{'helo_ex'},$rhost)!=-1)){
  # helo_ex TODO
   return 1;
  } else {
   logmsg "[client] helo mismatch ( realhost: $rhost and helo: $who [$raddr] )";
   deny($who);
  }
}

sub checkNewbie($$)
{
 my $who = shift;
 my $repos = shift;
 my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";
 my $q = $dbh->prepare("select count(id) from servers where hostname='$who'");
 $q->execute or die "$dbh->errstr\n";
 my $res= $q->fetchrow;
 if (!defined $res or $res <= 0)
  {
    mkRecord('new',$who, $repos);
    deny($who);
  }
 return 1;
}

sub mkRecord($$$)
{
  my ($type, $who, $repos) = @_;
  if ($type eq 'new')
   {
     my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";
     logmsg "[software] adding: $who [$who]";
     my $q = $dbh->prepare("insert into servers (hostname, hello_date, changed, active) values ('$who', NOW(), NOW(), '0')");
     $q->execute or die "$dbh->errstr\n";
     my $ins_id = $q->insertid();
     logmsg "[software] added with id: $ins_id";
   }
  return 1;
}

sub checkMe
{
  my $who = shift;
  my $repos = shift;
  my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";
  my $q = $dbh->prepare("select id from servers where hostname='$who' and active='1'");
  $q->execute or die "$dbh->errstr\n";
  my $res = $q->fetchrow;
  if (defined $res and $res > 0)
    {
      logmsg "[client] $who accepted [$who]";
      print "accept";
      $dbh->query ("update servers set active='2' where id='$res'");
	if (my $find_pid = fork())
	{
	  logmsg "[software] run cleaning locks for $who in /www/$repos/$who";
	  `/usr/bin/find /www/$repos/$who -type f -name '#cvs*' | xargs rm -f`;
	  exit;
	}
      exit;
    }
  else
    { deny($who); }
  return 1;
}

sub submit
{
  my $who = shift;
  my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";
  my $p = $dbh->prepare("select id, active from servers where hostname='$who'");
  $p->execute or die "$dbh->errstr\n";	
  my ($id, $k) = $p->fetchrow;
  if (!defined $k or $k <= 0 or $k <= 1)
	{
	  logmsg "[debug] $who tried to submit without ask";
	  exit;
	}
  $dbh->query("update servers set changed=NOW(), commited=NOW(), active='0' where id='$id'");
  return 1;
}

sub work
{
 my ($rhost, $who, $step, $raddr, $repos) = @_;
 checkLoad($who) if ($cfg{'load'} != 0);
 checkHello($rhost, $who, $raddr) if ($cfg{'hello'} != 0);
 checkNewbie($who, $repos);
 checkMe($who,$repos);
 deny($who);
}

package wdogserver;
use strict;
use vars qw(@ISA);
use Net::Server::PreFork; # prefork seems better. unknown bug on much concurent requests - we coredumped
@ISA = qw(Net::Server::PreFork);
my $srv = wdogserver->new({
 conf_file => '/root/bin/lazy/.lazy.cf', # changed due to evo
});
main::logmsg "[core] starting";
$srv->run();
exit;

sub process_request {
  my $self = shift;
  eval {
    local $SIG{ALRM} = sub { exit; };
    my $timeout = 2;
    my $previous_alarm = alarm($timeout);
    while( <STDIN> ){
      s/\r?\n$//;
      my ($reqname, $query, $repos) = split /\s/;
      main::logmsg "[client] $reqname from $srv->{server}->{peerhost} ($query) [$srv->{server}->{peeraddr}]";
      main::submit($reqname) if ($query =~ /submit/i);
	if ($query =~ /ask/i)
        {
          main::work($srv->{server}->{peerhost},$reqname,0, $srv->{server}->{peeraddr}, $repos);
	}
      alarm($timeout);
    }
    alarm($previous_alarm);
  };
}

1;
