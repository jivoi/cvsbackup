package Glob::Glob;
#use strict;
use Exporter;
use vars qw/@ISA @EXPORT @EXPORT_OK $cpid/;

@ISA = qw/Exporter/;
@EXPORT_OK = qw(
	main_loop
	config_parse
);

sub config_parse
{
  my ($r, $cf) = @_; # $r = ref to $configfile, $cf = ref to %config
  open CONF, $r->{config}
	or die "cannot read config: $!\n";
  while (<CONF>)
  {
    next if /^#|^\s+$/;
    /^\s?(\S+)\s+?(\S+)/;
    $cf->{$1} = $2;
  }
  close CONF;
  return 0;
}

sub main_loop # needs a hashref as an argument
{
  my ($c_ref) = shift;
  	die 
". main_loop is not configured correctly\n. please read perldoc Glob.pm\n\n"
  unless (scalar $c_ref =~ /^HASH/);
  
  if(defined($cpid = fork))
	{
	  print scalar(time()), " daemonized with ", ($$ || $cpid), "\n" if ($c_ref->{debug} > 0);
	  $cpid and exit(0);
	SHED: {
	  local $SIG{ALRM} = $c_ref->{ALRM};
	  alarm($c_ref->{aperiod});
	  &main::main_run;
	  sleep($c_ref->{speriod});
	  alarm(0);
	  redo SHED;
	}
	}
  else
	{
	  die "cannot fork: $!\n";
	}
}

return 1;

__END__

=pod

=head1 Global function by killa for killa

=over 4

=item Glob

use Glob::Glob qw/main_loop p_config/;

Needed items usually are:

	main_loop() - to make program loop forever
	config_parse() - to make program parse and return to a
hashref values we get from config

=item Synopsis

Daemonizes and do loops main_run() executions

Define your jobs in main_run()

=item Usage

You need to have ALRM() and main_run() to let it work

=item Example

	use Glob::Glob qw/main_loop/;

	my %obj = (
		aperiod => 10, # alarm period
		speriod => 20, # sleep period
		ALRM => \&ALRM, # what to do when alarm comes
	);

	sub ALRM
	{
	  return;
	}
	sub main_run
	{
	  print "Prints this directly $obj{aperiod} periodically\n"
	}

	main_loop(\%obj);
	exit 0;

=cut
