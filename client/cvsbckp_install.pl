#!/usr/bin/perl -wW
eval
{
 system('cvs -v > /dev/null 2>&1');
 if ($? != 0)
 {
   print "Please install cvs first\n";
   exit 255;
 }
};

$cur_ver		= "0.31";
%components		= ('cvsbackup.pl' => '0.34',
		'cvsbackup_run.sh' => '0.35',
		'cvsbackup_ssh.sh' => $cur_ver,
		'wdogc.pl' => '0.36');
$dl			= 10;
$havecf			= 0;
$rev			= ();
$main_path		= "/root/bin/";
chomp($os = `uname`);
chomp($hostname = `hostname`);

$SIG{INT} = sub { print "SIGINT caught\nExiting\n"; exit; };

## Print out any came in respect to debug level ($dl)
sub outp {
 printf (STDOUT "+ %s\n", join " ", @_) if ($dl >= 2);
 return;
}
sub errp {
 printf(STDERR "- %s\n", join " ", @_) if ($dl >= 1);
 return;
}

## root check
if (!(getpwnam($ENV{USER}) == 0)){
  errp "Must be root!";
  exit 255;
}
## Linux
if ($os eq 'Linux') {
  $co_url		= "https://mnt.example.ru/pub/cvsbackup/bin/";
} elsif ($os eq 'FreeBSD') {
  $co_url		= "https://mnt.example.ru/pub/cvsbackup/bin/";
} else {
  errp "Unknown OS";
  exit 255;
}

## we just replace if needed ($cur_ver dependent)
sub replacer {
 $item = shift;
 @more = @_;
 $rev = 0;
 ## parse $item || fetch it
  if (open(ITEM,"<$main_path$item")) {
    $rev = (eval { while(<ITEM>){ return (/^\#\s?\$\s?\w{3}\s?(.{3,4})\$$/)[0] if /rev/;} }) || 0;
    close(ITEM);
    fetch($item) if ($rev ne $components{$item});
  } else {
    fetch($item);
  }
 ## recursive
  replacer(@more) if (@more);
 $havecf = 1 if (-f $main_path.".cvsbackup.cf");
 return;
}

sub fetch($) {
 $what = shift;
 $where = $main_path if ($what !~ /^cvsbackup_dsa$/i);
 $where = "/root/.ssh/" if ($what =~ /^cvsbackup_dsa$/i);
 if ($os eq 'Linux') {
   $fetch_string = "wget --no-check-certificate -O $where$what $co_url$what 2>/dev/null"; # -O $main_path$what
 } elsif ($os eq 'FreeBSD') {
   $fetch_string = "fetch -o $where$what $co_url$what 2>/dev/null"; # -o $main_path$what
 } else {
   errp "Unknown OS";
   exit 255;
 }
 system($fetch_string);
 chmod 0775, $where.$what if $what !~ /^cvsbackup_dsa$/;
 chmod 0600, $where.$what if $what =~ /^cvsbackup_dsa$/;
 outp "$what [",($? > 0)?"error":"done","]";
 return;
}

## Config generating
sub confgen {
    $cf = "set cvsroot :ext:cvsbackup\@cvsbackup.example.ru/www/cvs\nset cvspath $hostname\nset dl1 6\n";
 }
 if ($os eq 'Linux') {
   $fetch = "wget --no-check-certificate -O - ".$co_url."cvsbackup.cf 2>/dev/null";
 } elsif ($os eq 'FreeBSD') {
   $fetch = "fetch -o - ".$co_url."cvsbackup.cf 2>/dev/null";
 } else {
   errp "Unknown OS";
   exit 255;
 }
 open(CFFETCH,"$fetch |") || die "cannot fork to read config: $!\n";
  $cf .= join "", <CFFETCH>;
 close(CFFETCH);
 open(CONFIG, ">/root/bin/.cvsbackup.cf") || die "cannot open to write cf: $!\n";
  print CONFIG $cf;
 close(CONFIG);
 return;
}

sub crondo {
  $cronhas = 0;
  open(CRONTAB,"</etc/crontab") || die "cannot read crontab: $!\n";
  while(<CRONTAB>){
    $cronhas = 1 if /cvsbackup_run/;
  }
  close(CRONTAB);
  if ($cronhas == 1) {
   errp "cvsbackup_run.sh is already in cron tasks\n\tfix manually";
  } else {
   open(CRONTAB,">>/etc/crontab") || die "cannot write to crontab: $!\n";
   printf(CRONTAB "MAILTO=root\@example.ru\n*\t*\t*\t*\t*\troot\t/root/bin/cvsbackup_run.sh 2>/dev/null\n\n");
   close(CRONTAB);
  }
  return;
}

## RunTime
outp "[",scalar localtime(),"]","begin";
outp "+" x 10, " pre ", "+" x 10;
outp "os:",$os;
outp "hostname:", $hostname;
outp "checkout url:", $co_url;

outp "+" x 5, "versioning", "+" x 5;
#checkOld;
replacer(keys %components);

if ($havecf == 0) {
 outp "+" x 5, "new install", "+" x 5;
 outp "config generating";
 confgen;
 fetch("cvsbackup_dsa");
 chmod 0600, "/root/.ssh/cvsbackup_dsa";
 outp "crontab";
 crondo;
}

DONE:	outp "don't forget to:\n\trm -f /root/bin/cvsbckp_install.pl";
	outp "[",scalar localtime(),"]","done";
	exit;
