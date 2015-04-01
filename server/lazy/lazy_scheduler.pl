#!/usr/bin/perl
use lib "/root/bin/lazy";
use warnings;
use strict;
use DBI;
use POSIX;
use Glob::Glob qw/config_parse main_loop/;

die "no config\n" unless ($ARGV[0] && $ARGV[0] =~ /^config=/);
my (undef, $cf_file) = split /=/, $ARGV[0];

my %opt = (
	    config=>$cf_file,
	    aperiod=>30, # alarm period
	    speriod=>30, # sleep period
	    ALRM=>\&ALRM,
);

my %obj=();
my %cfg=();
if (config_parse(\%opt, \%cfg) != 0)
  {
	die "config parse error\n";
}

!(defined $cfg{'dbname'} or defined $cfg{'dbpass'} or defined $cfg{'dbuser'} or defined $cfg{'dbhost'}) && die "- no db settings\n";
print "configs done\n" if ($cfg{debug} > 0);
## eof memory allocation, config parsing and preflight checks
# subroutines to make all clear and readable
sub ALRM
 { return 1;}

sub mail_report
{
   my $j = shift;
   chomp(my $hostname = `hostname`);
   open MAIL, "| mail $cfg{maintainer} -r root\@example.ru";
    print MAIL <<EOF;
Subject: $hostname: swapping active/waiting error
To: $cfg{maintainer}

$j \@ $hostname reports:
SWAPPING places failed, please check if i'm alive

EOF
   close MAIL;
}

sub swap
{
  my $swp_id = shift;
  my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";

  $dbh->prepare("update servers set active='0', changed=NOW() where id='$swp_id'");
  return 1;
}

sub active_routine
{
  my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";
  my $k = $dbh->prepare("select id, hostname, UNIX_TIMESTAMP(changed) as ux from servers where active='1' or active='2' order by ux,id");
$k->execute or die "$dbh->errstr\n";
  while (my @j = $k->fetchrow_array())
  {
      my @time = gmtime(time());
      my @h_time = gmtime($j[2]);
      $h_time[0] = 0;
      $time[1] = $time[1] - $cfg{refresh}; # maybe config value? TODO
      $time[0] = 0;
      my $time = mktime(@time);
      my $h_time = mktime(@h_time);
      undef(@time); undef(@h_time);
      swap($j[0]) if ($h_time <= $time);
  }
  return 0;
}
# prog main run, it looped below in `main_loop()`
sub main_run
{
   my  $dbh = DBI->connect("DBI:mysql:$cfg{'dbname'}:$cfg{'dbhost'}:$cfg{'dbport'}",$cfg{'dbuser'},$cfg{'dbpass'})
	or die "cannot connect to mysql server/select database\n";

   my (@active, @wait);
   my $sth = $dbh->prepare("select id, active, hostname from servers order by changed");
$sth->execute or die "$dbh->errstr\n";
   while (my @r = $sth->fetchrow_array)
     {
       push @active, $r[0] if ($r[1] > 0);
       push @wait, $r[0] if ($r[1] <= 0);
     }

   if (!@active or scalar @active <= 0)
     {
       my $sth=$dbh->prepare("select id from servers where active='0' order by changed");
	$sth->execute or die "$dbh->errstr\n";
       @wait = $sth->fetchrow_array;
	if (@wait or scalar @wait > 0)
	{
       print "generating actives\n" if ($cfg{debug} > 10);
       for (0 .. ($cfg{concurent} - 1))
          {
		if (defined $wait[$_] and $wait[$_] ne '')
		{
		    $dbh->prepare("update servers set active='1',changed=NOW() where id='$wait[$_]'");
		    print "$_. done for $wait[$_]\n" if ($cfg{debug} > 0);
		}
          }
	}
     }
   elsif (scalar @active < $cfg{concurent})
     {
       my $sth = $dbh->prepare("select id from servers where active='0' order by changed");
	$sth->execute or die "$dbh->errstr\n";
       @wait = $sth->fetchrow_array(0);
	if (@wait and scalar @wait > 0)
	{
       for (0 .. (($cfg{concurent} - scalar @active) - 1))
	  {
		if (defined $wait[$_] and $wait[$_] ne '')
		{
		    $dbh->prepare("update servers set active='1',changed=NOW() where id='$wait[$_]'");
		    print "$_. done for $wait[$_]\n";
		}
	  }
	}
     }

   if (my $swap_pid = fork())
     {
	if (active_routine != 0) { mail_report "active_routine"; }
	exit;
     }

}
# main run
main_loop(\%opt);
exit;

__END__
=pod

=head1 lazy sheduler

=over 4

=item General

This sheduler runs queue forming subroutines for cvsbackup [by netch]
Generally it was designed to make host which is CVS server for backups run better and low load average at a high concurent requests of cvsbackuping machines.

=item Command line

 It takes only one argument `config=/path/to/config', parses config file and loops self.
 All subroutines must be described in main_run() sub, main_loop() just does periodical runs of main_run() subroutine.
 All configuration settings are described below in `Configuration' section

=item Command args

config=/path/to/your/config
 parses and uses values matched desirable

=item Configuration

debug - debug level wich must be used

	0 - no debuggin ever!
	1 - debug, but not verbose
	10 - higher verbosity level
	10+ - higher level

concurent - how many machines can be run one time

	is 

=back

=cut
