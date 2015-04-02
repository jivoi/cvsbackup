#!/usr/bin/perl
##
## Copyright (C) 2002 Valentin Nechayev. All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
##
## THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
## ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
## FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
## DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
## OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
## HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
## LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
## OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
## SUCH DAMAGE.
##
## cvsbackup
## $Id: cvsbackup.pl 49 2007-04-11 07:55:38Z killa $

## checks before we run
BEGIN {
  $VERSION = "0.2.2";
  $SIG{INT} = sub { print "SIGINT catched\n"; unlink $pidfile; die "\^C hit!\n"; };
  $pidfile = "/var/run/cvsbackup.pid";
  if (-f $pidfile) {
   exit;
  } else { # we normally continue, writing pidfile
   open(PIDFILE,">$pidfile") || die "cannot open $pidfile: $!\n";
    print PIDFILE $$;
   close(PIDFILE);
   sleep(1);
  }
}
## checks done, if not we just exit before running

use POSIX;

## We get directory in local tree, and directory in repository, and
## synchronize the second to be consistent with the first.

## Variables to get from config:
## localroot (optional)
## cvsroot (mandatory) - CVSROOT for CVS tools
## cvspath (mandatory) - path under CVSROOT to keep this particular tree
## tempdir (optional)

## Parse command line. We need $HOME for default config.

$| = 1;

#$ENV{CVS_IGNORE_REMOTE_ROOT} = 1;
#printf("---------------\n");
#system("env");

$home = $ENV{HOME};
$f_no_remove_tempdir = 0;
unless( $home ) {
  @tmpf = getpwuid( $< );
  die unless @tmpf;
  $home = $tmpf[7];
  die unless $home;
  undef @tmpf;
}
$home =~ s/\/{2,}$/\//;
$home =~ s/\/$// unless $home eq "/";
$config = $home ? $ home . "/.cvsbackup.cf" : undef;
foreach $arg( @ARGV ) {
  if( $arg =~ /^config=/ ) { $config = $'; }
  elsif( $arg eq "no-remove-tempdir" ) { $f_no_remove_tempdir = 1; }
  else { die "unknown command line argument: $arg"; }
}
$os=`uname -s`;
#default cp args
$cp_args = "-p";
if ($os eq "Linux\n") {
	$cp_args = "-pr";
}
## Defaults, before reading config.

$cf_tempdir = "/tmp";
if( defined $ENV{TMPDIR} && $ENV{TMPDIR} ) { $cf_tempdir = $ENV{TMPDIR}; }
#$dl1 = 6; ## errors

## Read config

%localfiles = ();
%cx = ();
$cm_cnt = 0;

open( CONFIG, "< $config" ) or die "cannot open config file!";
while( <CONFIG> ) {
  chomp;
  next if( /^$/ || /^\s*#/ );
  while( /\\$/ ) {
    chop;
    $line2 = <CONFIG>;
    die "cannot read continuation line" unless defined $line2;
    chomp $line2;
    $_ .= $line2;
  }
  s/^\s+//; s/\s+$//;
  ## What we get?
  if( /^set\s+/ ) {
    $r = $';
    if( $r =~ /^(\w+)\s+/ ) {
      ## Set any Perl variable here directly from config.
      ${$1} = $';
    }
    else { die "incorrect <set> command at line: $_\n"; }
  }
  elsif( /^include_tree\s+/ ) {
    $ldir = $';
    die "not absolute path in include_tree command" unless $ldir =~ /^\//;
    &do_input_tree( $ldir, "include" );
  }
  elsif( /^exclude_tree\s+/ ) {
    &do_input_tree( $', "exclude" );
  }
  elsif( /^deexclude_tree\s+/ ) {
    &do_input_tree( $', "deexclude" );
  }
  elsif( /^include_glob\s+/ ) {
    &do_input_glob( $', "include" );
  }
  elsif( /^exclude_glob\s+/ ) {
    &do_input_glob( $', "exclude" );
  }
  elsif( /^deexclude_glob\s+/ ) {
    &do_input_glob( $', "deexclude" );
  }
  elsif( /^exclude_rx\s+/ ) {
    &do_input_rx( $', "exclude" );
  }
  elsif( /^deexclude_rx\s+/ ) {
    &do_input_rx( $', "deexclude" );
  }
  elsif( /^copy_match\s+/ ) {
    $tmp1 = $';
    $tmp1 =~ s/\s+$//;
    die "incorrect copy_match syntax" unless $tmp1 =~ /^(\S+)\s+(\S+)\s+/;
    $cm_key = $1;
    $cm_type = $2;
    $cm_args = $';
    ## Add entry for it. Entries are numbered.
    ++$cm_cnt;
    $cx{"cm.$cm_cnt.key"} = $cm_key;
    $cx{"cm.$cm_cnt.type"} = $cm_type;
    $cx{"cm.$cm_cnt.args"} = $cm_args;
  }
  elsif( /^copy_action\s+/ ) {
    $tmp1 = $';
    $tmp1 =~ s/\s+$//;
    die "incorrect copy_action syntax" unless $tmp1 =~ /^(\S+)\s+(\S+)\s+/;
    $ca_key = $1;
    $ca_type = $2;
    $ca_args = $';
    $cx{"ca.$ca_key.type"} = $ca_type;
    $cx{"ca.$ca_key.args"} = $ca_args;
  }
  else { die "unknown config line: $_\n"; }
}
close CONFIG;

## Check vital parameters
die "no cf_tempdir" unless $cf_tempdir;
die "no cvsroot" unless $cvsroot;
die "no cvspath" unless $cvspath;
## Prepare localroot. It must terminate with '/'
$localroot = "/" unless $localroot;
unless( $localroot =~ /\/$/ ) { $localroot .= '/'; }
$cvsbinpath = 'cvs' unless $cvsbinpath;

## Convert local names to relative form. No absolute paths.
## If localroot wasn't explicitly specified, it is "/",
## and file names only lose their first "/"
%tmph = ();
foreach $lfile( sort keys %localfiles ) {
  $v = $localfiles{$lfile};
  if( $lfile =~ /^\Q$localroot\E\/*/ ) {
    $tmph{$'} = $v;
    if( $dl1 >= 30 ) {
      printf "_: delocalroot: local file: `%s' -> `%s'\n", $lfile, $';
    }
  }
  else {
    die sprintf( "fatal: file `%s' isn't under local root `%s'",
        $lfile, $localroot );
  }
}
%localfiles = %tmph;
undef %tmph;

## Prepare working directory

#- srand();

if( $dl1 >= 15 ) { print "_: prepare working directory\n"; }

die if $cf_tempdir =~ /^\/+$/;
$cf_tempdir =~ s/\/+$//;
$tempdir = sprintf( "%s/cvstmp.%10d.%05d", $cf_tempdir, time(), $$ );
if( $dl1 >= 15 ) { print "_: tempdir is $tempdir\n"; }
$ttreedir = $tempdir . "/tree";
mkdir( $cf_tempdir, 0755 ); ## paranoia
&rm_rf( $tempdir );
umask( 077 );
mkdir( $tempdir, 0700 ) or die "cannot mkdir $tempdir";
chmod( 0700, $tempdir ) or die "cannot chmod $tempdir";
chdir( $tempdir ) or die "cannot chdir $tempdir";
mkdir( $ttreedir, 0700 ) or die;
mkdir( $tempdir . "/import-empty", 0700 ) or die;
umask( 022 );

## Count local directories
%localdirs = ();
foreach $lfile( sort keys %localfiles ) {
  $ldir = &dirname($lfile);
  next unless $ldir;
  $localdirs{$ldir} = 1;
  print "_: adding local directory `$ldir'\n" if $dl1 >= 30;
}

## Prepare destination directory
if( $dl1 >= 15 ) { print "_: create target directory via import\n"; }
chdir( $tempdir . "/import-empty" ) or die;
@cmd = ( '-quiet1', '-quiet2', '-anyrc',
    'import', '-m', '', $cvspath, 'backup', 'none' );
#system( 'cvs', '-Q', '-d', $cvsroot, 'import', '-m', "", $cvspath,
#    'backup', 'none' );
&cvs_command( @cmd );

## Checkout current state
if( $dl1 >= 15 ) { print "_: checkout current state\n"; }
chdir( $ttreedir ) or die;
$rc = system( 'cvs', '-Q', '-d', $cvsroot,
    'checkout', '-ko', $cvspath );
die "fatal: rc( cvs checkout ) = $rc" if $rc;

## Set new tree directory
$ttreedir = $ttreedir . "/" . $cvspath;
$ttreedir =~ s/\/{2,}/\//g;
print "_: new ttreedir is $ttreedir\n" if $dl1 >= 15;
chdir( $ttreedir ) or die "cannot chdir new tree directory";

## Get list of checked-out files, relatively to $ttreedir.
## Prepare hash of usable forms.
print "_: get remote files\n" if $dl1 >= 15;
@tmpf = do_input_tree_recurse( $ttreedir );
%remotefiles = ();
%rem_usb = ();
for(;;) {
  last if $#tmpf < 0;
  $file = shift @tmpf;
  $file =~ s/^\Q$ttreedir\E\///;
  $remotefiles{$file} = 1;
  $t1 = &unusable_name( $file );
  if( defined( $rem_usb{$t1} ) && $rem_usb{$t1} ne $file ) {
    printf "_: error: conflict of usable names: `%s' `%s'\n",
      $file, $rem_usb{$t1};
  }
  else {
    $rem_usb{$t1} = $file;
  }
}

## Count remote directories
print "_: count remote directories\n" if $dl1 >= 15;
%remotedirs = ();
foreach $rfile( keys %remotefiles ) {
  $rdir = &dirname($rfile);
  next unless $rdir;
  next if( $remotedirs{$rdir} );
  $remotedirs{$rdir} = 1;
  $t1 = &unusable_name( $rdir );
  if( defined( $rem_usb{$t1} ) && $rem_usb{$t1} ne $rdir ) {
    printf "_: error: conflict of usable names: `%s' `%s'\n",
        $rdir, $rem_usb{$t1};
  }
  else {
    $rem_usb{$t1} = $rdir;
  }
}

&pass1();

## Real work pass 2: delete directories which are unused
#- print "_: pass 2: notyet!\n";

&pass3();

&pass4();

&pass5();

## Terminate
&rm_rf( $tempdir ) if( $tempdir && !$f_no_remove_tempdir );
exit 0;

######################## end: main #############################

################################################################
##  pass1()
##  remove files deleted locally

sub pass1 {
  my %clh;
  my @cla;
  my %bins;
  local( *TEMP );
  ## Real work pass 1: delete files which are removed from local directory
  print "_: going to pass 1\n" if $dl1 >= 20;
  %clh = ();
  foreach $rfile( keys %remotefiles ) {
    $lfile = &unusable_name( $rfile );
    if( !defined $localfiles{$lfile} || ( $localfiles{$lfile} != 1 &&
        $localfiles{$lfile} != 3 ) )
    {
      $clh{$rfile} = 1;
      if( $dl1 >= 20 ) { print "Scheduled to delete: $rfile\n"; }
    }
  }
  @cla = sort keys %clh;
  if( $#cla < 0 && $dl1 >= 15 ) { print "_: no files to delete at pass 1\n"; }
  chdir( $ttreedir ) or die;
  ## Checking for binary.
  ## Empty all files which are to be deleted
  foreach $rfile( @cla ) {
    if( -B $rfile ) {
      $bins{$rfile} = 1;
      if( $dl1 >= 30 ) { print "file `$rfile' is binary, skipping diff\n"; }
    }
    else {
      open( TEMP, "> $rfile" ) or die;
      close TEMP;
      if( $dl1 >= 30 ) { print "emptied file: $rfile\n"; }
    }
  }
  ## Run diffs
  foreach $rfile( @cla ) {
    print "\nFile $rfile: deleted locally\n";
    if( !$bins{$rfile} ) {
      @cmd = ( '-anyrc', '-no-quiet1', 'diff', '-Nu', '--', $rfile );
      &cvs_command( @cmd );
      print "\n";
    }
  }
  ## Delete files locally
  $rc = unlink @cla;
  die "fatal: unlink failed" if $rc != $#cla + 1;
  ## Mark files as deleted in repository
  if( @cla ) {
    @cmd = ( '-quiet1', '-quiet2', 'delete', '--' );
    &cvs_command_splitted( \@cmd, \@cla );
  }
  ## Commit files as deleted
  if( @cla ) {
    @cmd = ( '-quiet1', '-quiet2', 'ci', '-m', '', '--' );
    &cvs_command_splitted( \@cmd, \@cla );
  }
  print "_: pass 1: finished\n" if $dl1 >= 15;
  undef %clh;
  undef @cla;
}

################################################################
##  pass3()

sub pass3 {
  my %clh;
  my @cla;
  my( $lfile, $rfile );
  my $cmd;
  my @cmd;
  my $l;
  local( *UP );
  ## Real work pass 3: compare files which exist in both
  %clh = ();
  print "_: going to pass 3\n" if $dl1 >= 15;
  ## Copy files to their destinations
  foreach $lfile( sort keys %localfiles ) {
    if( $rem_usb{$lfile} ) { $rfile = $rem_usb{$lfile}; }
    else {
      $rfile = &usable_name( $lfile );
      die unless $lfile eq &unusable_name( $rfile );
    }
    next unless $remotefiles{$rfile};
    print "_: sending `$lfile' as `$rfile'\n" if $dl1 >= 30;
    die if( $lfile =~ /^\// );
    die if( $rfile =~ /^\// );
    $clh{$lfile} = $rfile;
    $t1 = $localroot . $lfile;
    $t2 = $ttreedir . "/" . $rfile;
    &my_copyfile( $t1, $t2 );
  }
  ## Run cvs update; get modified
  print "_: pass3(): calling cvs update\n" if $dl1 >= 20;
  $cmd = sprintf( '%s update 2>&1 |', &shellparseable( $cvsbinpath ) );
  open( UP, $cmd ) or die "cannot run cvs update";
  @cla = ();
  while($l=<UP>) {
    chomp $l;
    print "_: got line: $l\n" if $dl1 >= 25;
    $l =~ s/\s+$//;
    if( $l =~ m/^M\s+/ ) { push @cla, $'; }
  }
  for $rfile( @cla ) {
    print "\nFile $rfile: changed locally\n";
    if( -T $rfile ) {
      @cmd = ( '-no-quiet1', '-anyrc', 'diff', '-u', '--', $rfile );
      &cvs_command( @cmd );
      print "\n";
    }
    else {
      print "File $rfile: is binary, no diff printed\n";
    }
  }
  if( @cla ) {
    @cmd = ( '-quiet1', '-quiet2', 'ci', '-m', '', '--' );
    &cvs_command_splitted( \@cmd, \@cla );
  }
  print "_: pass 3: finished\n" if $dl1 >= 15;
  undef %clh;
}

################################################################
##  pass4()

sub pass4 {
  my %clh;
  my @cla;
  my @cla2;
  my( $ldir, $rdir, $f_call_add );
  ## Real work pass 4: add directories which appeared in local tree
  print "_: going to pass 4\n" if $dl1 >= 20;
  %clh = ();
  foreach $ldir( sort keys %localdirs ) {
    if( $rem_usb{$ldir} ) { $rdir = $rem_usb{$ldir}; }
    else {
      $rdir = &usable_name( $ldir );
      die unless $ldir eq &unusable_name( $rdir );
    }
    unless( $remotedirs{$rdir} ) {
      $clh{$rdir} = 1;
      printf( "_: scheduling directory to add: `%s'\n", $rdir ) if $dl1 >= 30;
    }
  }
  @cla = sort keys %clh;
  chdir( $ttreedir ) or die;
  foreach $rdir( @cla ) {
    $t2 = $ttreedir . "/" . $rdir;
    $rc = mkdir( $t2, 0755 );
    system( sprintf( "mkdir -p %s", &shellparseable( $t2 ) ) );
    die "mkdir failed for $rdir" unless -d $t2;
  }
  foreach $rdir( @cla ) {
    $t2 = $ttreedir . "/" . $rdir;
    die unless -d $t2;
    unless( -d "$t2/CVS" ) {
      if( $dl1 >= 30 ) {
        print "_: need to create dir $rdir with all parents\n";
      }
      &rec_cvs_add_dir( $rdir );
    }
  }
  if( $#cla >= 0 ) {
    chdir( $ttreedir ) or die;
    $f_call_add = 0;
    @cla2 = ();
    for $rdir( @cla ) {
      $t2 = $ttreedir . "/" . $rdir;
      next if( -d "$t2/CVS" );
      push @cla2, $rdir;
      $f_call_add = 1;
    }
    if( $f_call_add ) {
      @cmd = ( '-Q', '-quiet1', '-quiet2', 'add', '--' );
      &cvs_command_splitted( \@cmd, \@cla2 );
    }
    if( @cla ) {
      chdir( $ttreedir ) or die;
      @cmd = ( '-Q', '-quiet1', '-quiet2', 'ci', '-m', '', '--' );
      &cvs_command_splitted( \@cmd, \@cla );
    }
  }
  print "_: pass 4: finished\n" if $dl1 >= 15;
  undef %clh;
  undef @cla;
}

################################################################
##  rec_cvs_add_dir()

sub rec_cvs_add_dir {
  my $rdir = shift;
  die unless $rdir;
  if( $dl1 >= 30 ) { print "_: rec_cvs_add_dir(): rdir=$rdir\n"; }
  my $t2 = $ttreedir . "/" . $rdir;
  return if( -d "$t2/CVS" );
  my $prevdir = &dirname( $rdir );
  if( $prevdir ) {
    if( $dl1 >= 30 ) {
      print "_: rec_cvs_add_dir(): recurse for $prevdir\n";
    }
    &rec_cvs_add_dir( $prevdir );
  }
  my @cmd;
  @cmd = ( '-quiet1', '-quiet2', 'add', '--', $rdir );
  &cvs_command( @cmd );
}

################################################################
##  pass5()

sub pass5 {
  my %clh;
  my @cla;
  my( $lfile, $rfile );
  my @cmd;
  ## Real work pass 5: add files which appeared in local tree
  if( $dl1 >= 20 ) { print "_: going to pass 5\n"; }
  %clh = ();
  foreach $lfile( sort keys %localfiles ) {
    next if( $localfiles{$lfile} != 1 && $localfiles{$lfile} != 3 );
    next if( $rem_usb{$lfile} ); ## already exists
    $clh{$lfile} = &usable_name( $lfile );
    die unless $lfile eq &unusable_name( $clh{$lfile} );
    $rem_usb{$lfile} = $clh{$lfile};
    if( $dl1 >= 20 ) {
      printf "_: file to add: `%s' -> `%s'\n", $lfile, $clh{$lfile};
    }
  }
  @cla = ();
  foreach $lfile( sort keys %clh ) {
    die if $lfile =~ /^\//;
    $rfile = $clh{$lfile};
    die if $rfile =~ /^\//;
    $t1 = $localroot . $lfile;
    $t2 = $ttreedir . "/" . $rfile;
    if( $dl1 >= 20 ) { printf "_: copying `%s' to `%s'\n", $t1, $t2; }
    &my_copyfile( $t1, $t2 );
    push @cla, $rfile;
  }
  if( $#cla >= 0 ) {
    chdir( $ttreedir ) or die;
    @cmd = ( '-Q', '-quiet1', '-quiet2', 'add', '-ko', '--' );
    &cvs_command_splitted( \@cmd, \@cla );
  }
  foreach $lfile( sort keys %clh ) {
    $rfile = $clh{$lfile};
    $t1 = ( $localroot ? $localroot : "" ) . "/" . $lfile;
    $t2 = $ttreedir . "/" . $rfile;
    if( -T $t2 ) {
      @cmd = ( 'cvs', '-q', '-d', $cvsroot, 'diff', '-N', '-u', '--', $rfile );
      ## Don't check `cvs diff' return code, it always will be 1 here
      print "\nShow new file `$lfile' in diff...\n";
      system( @cmd );
      print "\n";
    }
    else {
      print "\nNew file `$lfile' is detected binary => don't show it\n";
    }
  }
  ## And nareshti commit it
  if( $#cla >= 0 ) {
    chdir( $ttreedir ) or die;
    @cmd = ( '-quiet1', '-quiet2', 'ci', '-m', '', '--' );
    &cvs_command_splitted( \@cmd, \@cla );
  }
  print "_: pass 5: finished\n" if $dl1 >= 15;
  undef %clh;
  undef @cla;
}

################################################################
##  cvs_command_splitted()

sub cvs_command_splitted {
  my $r_hdr = shift;
  my $r_lst = shift;
  my @args;
  my ( $i, $slen, $targ, $nlst, $nargslocal );
  $nlst = scalar @{$r_lst};
  if( $dl1 >= 30 ) {
    printf( "_: cvs_command_splitted(): cmd=`%s', nlst=%d\n",
        join( ' ', @{$r_hdr} ), $nlst );
  }
  return if $nlst <= 0;
  @args = @{$r_hdr};
  $nargslocal = $slen = 0;
  $i = 0;
  for(;;) {
    ## Beginning of iteration. If we added all arguments, or current length
    ## is over limit, execute current list.
    ## 16384 is arbirary value, which is possibly less than ARG_MAX
    ## for all existing platforms. Of course, MS-DOS is ignored.
    if( $slen >= 16384 || $i >= $nlst ) {
      if( $dl1 >= 30 ) {
        printf(
            "_: cvs_command_splitted(): call cvs_command(), i=%d, slen=%d\n",
            $i, $slen );
      }
      if( $nargslocal > 0 ) {
        &cvs_command( @args );
      }
      ## Reset argument list to its initial state.
      @args = @{$r_hdr};
      $nargslocal = $slen = 0;
    }
    ## If we haven't arguments, exit from cycle.
    if( $i >= $nlst ) { last; }
    ## Add argument and apply its length.
    $targ = ${$r_lst}[$i];
    push @args, $targ;
    $slen += 1 + length( $targ );
    ++$nargslocal;
    ## To next iteration
    ++$i;
  }
}

################################################################
##  my_copyfile()

sub my_copyfile {
  my $p_from = shift;
  my $p_to = shift;
  my $rc;
  my( $cm_key, $cm_type, $cm_args, $ca_type, $ca_args, $i, $j, $jlim );
  ## Iterate copy rule groups. Find first that matches.
  if( $dl1 >= 30 ) {
     printf( "_: my_copyfile(): call: $p_from -> $p_to\n" );
  }
  $f_this = 0;
  for( $i = 1; $i <= $cm_cnt; ++$i ) {
    $cm_key = $cx{"cm.$i.key"};
    die unless $cm_key;
    $cm_type = $cx{"cm.$i.type"};
    die unless $cm_type;
    $cm_args = $cx{"cm.$i.args"}; ## $cm_args can be empty
    if( $cm_type eq "rx" ) {
      if( $p_from =~ /$cm_args/ ) {
        $f_this = 1; last;
      }
    }
    else { die; }
  }
  if( $f_this ) {
    $ca_type = $cx{"ca.$cm_key.type"};
    die unless $ca_type;
    $ca_args = $cx{"ca.$cm_key.args"};
    if( $ca_type eq "default" ) {
      $f_this = 0;
      ## Pass to default action
    }
    elsif( $ca_type eq "filter" ) {
      $rc = system( "$ca_args <$p_from >$p_to" );
      die "my_copyfile(): filter failed: rc=$rc" if $rc;
      return 1;
    }
    else { die; }
  }
  ## Default action
  #XXX check if file or directory not exit, skip, not die :>
  if ( !-d $p_from && !-f $p_from) {
        return;
  }
  $rc = system( 'cp', $cp_args, '--', $p_from, $p_to );
  die "my_copyfile(): cp failed: rc=$rc" if $rc;
}

################################################################
##  do_input_tree()

sub do_input_tree {
  my $dir = shift;
  my $fl_command = shift;
  my $file;
  die unless $dir;
  my @res;
  @res = do_input_tree_recurse( $dir );
  for $file( @res ) {
    if( $fl_command eq "include" ) {
      $localfiles{$file} = 1;
    }
    elsif( $fl_command eq "exclude" ) {
      if( defined $localfiles{$file} &&
          ( $localfiles{$file} == 1 || $localfiles{$file} == 3 ) )
      { $localfiles{$file} = 2; }
    }
    elsif( $fl_command eq "deexclude" ) {
      if( defined $localfiles{$file} && $localfiles{$file} == 2 )
      { $localfiles{$file} = 3; }
    }
    else { die "do_input_tree: unknown command: $fl_command\n"; }
  }
}

sub do_input_tree_recurse {
  my $orgdir = shift;
  my @res = ();
  my $sdir;
  my $entry;
  my @entries;
  my $ep;
  print "_: do_input_tree_recurse($orgdir)\n" if $dl1 >= 20;
  $orgdir =~ s/\/{2,}$/\//; $orgdir =~ s/\/+$// unless $orgdir eq "";
  $sdir = getcwd(); die unless $sdir;
  return () unless chdir( $orgdir );
  local( *DIR );
  opendir( DIR, $orgdir ) or die;
  print "_: reading directory $orgdir\n" if $dl1 >= 20;
  for(;;) {
    @entries = sort readdir( DIR );
    printf "_: do_input_tree($orgdir): got entries: %s\n",
        join( ' ', @entries )
      if $dl1 >= 20;
    last unless @entries;
    foreach $entry( @entries ) {
      next if( $entry eq "." || $entry eq ".." ||
          $entry eq "CVS" || $entry eq "" );
      $ep = $orgdir . "/" . $entry;
      print "_: parsing entry: $entry; path: $ep\n" if $dl1 >= 20;
      if( -l $ep ) {}
      elsif( -f $ep ) {
        print "_: pushing file $ep\n" if $dl1 >= 30; push @res, $ep;
      }
      elsif( -d $ep ) {
        print "_: calling for directory $ep\n" if $dl1 >= 20;
        push @res, &do_input_tree_recurse( $ep );
        chdir( $orgdir ) or die;
      }
    }
  }
  closedir( DIR );
  chdir( $sdir ) or die;
  print "_: do_input_tree_recurse($orgdir) finished\n" if $dl1 >= 20;
  return @res;
}

################################################################
##  do_input_glob()

sub do_input_glob {
## Reparse globs
  my $fl_pattern = shift;
  my $fl_command = shift;
  if( $fl_pattern =~ /^\// ) {
    $fl_pattern =~ s/^\/{2,}/\//;
  }
  elsif( $fl_pattern =~ /^~(?=(?:$|\/))/ ) {
    $fl_pattern =~ s/^~/\Q$home\E/;
  }
  else {
    $fl_pattern = $home . "/" . $fl_pattern;
  }
  my @llist = glob( $fl_pattern );
  for $file( @llist ) {
    if( $fl_command eq "include" ) {
      $localfiles{$file} = 1;
    }
    elsif( $fl_command eq "exclude" ) {
      $localfiles{$file} = 2 if(
          defined $localfiles{$file} &&
              ( $localfiles{$file} == 1 || $localfiles{$file} == 3 ) );
    }
    elsif( $fl_command eq "deexclude" ) {
      $localfiles{$file} = 3 if(
          defined $localfiles{$file} && $localfiles{$file} == 2 );
    }
    else { die "do_input_glob(): unknown command $fl_command"; }
  }
}

################################################################
##  do_input_rx()

sub do_input_rx {
  my $fl_pattern = shift;
  my $fl_command = shift;
  my( $file, $v );
  ## pattern must be enclosed as `/.../'
  $fl_pattern =~ s/^\///; $fl_pattern =~ s/\/$//;
  foreach $file( keys %localfiles ) {
    if( $file =~ m/$fl_pattern/ ) {
      next unless defined $localfiles{$file};
      $v = $localfiles{$file};
      if( $fl_command eq "exclude" ) {
        $localfiles{$file} = 2 if( $v == 1 || $v == 3 );
      }
      elsif( $fl_command eq "deexclude" ) {
        $localfiles{$file} = 3 if( $v == 2 );
      }
      else { die "do_input_rx(): unknown command: $fl_command\n"; }
    }
  }
}

################################################################
##  rm_rf()

sub rm_rf {
  my $dir = shift;
  die "rm_rf(): inworkable file name" if(
      $dir =~ /\s/ || $dir =~ /\'/ || $dir =~ /\"/ );
  system( "/bin/rm -rf -- $dir" );
}

################################################################
##  usable_name()
##  This function converts name from local directory (which can
##  consist any ASCII character except '\0' and '/') to name
##  used in CVS repository

sub usable_name {
  my $from = shift;
  my $to = "";
  my $ofrom = $from;
  while( length( $from ) > 0 ) {
    ## Simple case
    if( $from =~ /^([A-Za-z0-9+,.\/\@:=^_]+)/ ) {
      $to .= $1;
      $from = $';
      next;
    }
    ## Minus char should be quoted after '/' and empty case
    if( substr( $from, 0, 1 ) eq '-' &&
        ( $to ne "" && $to !~ /\/$/ ) )
    {
      $to .= '-';
      $from = substr( $from, 1 );
      next;
    }
    ## Default in unprintable case - make %XX
    $to .= '%'. sprintf( "%02X", ord( $from ) );
    $from = substr( $from, 1 );
  }
  if( $dl1 >= 20 && $ofrom ne $to ) {
    printf "_: usable_name(): `%s' -> `%s'\n", $ofrom, $to;
  }
  return $to;
}

################################################################
##  unusable_name()

sub unusable_name {
  my $from = shift;
  my $ofrom = $from;
  my $to = "";
  my $t;
  while( $from ne "" ) {
    if( $from =~ /^([^%]+)/ ) {
      $to .= $1;
      $from = $';
      next;
    }
    elsif( $from =~ /^%([A-Za-z0-9])([A-Za-z0-9])/ ) {
      $from = $';
      $to .= chr( 16*fromhex($1) + fromhex($2) );
      next;
    }
    else { die "unusable_name(): incorrect %xx specification\n" };
  }
  if( $dl1 >= 20 && $ofrom ne $to ) {
    printf "_: unusable_name(): `%s' -> `%s'\n", $ofrom, $to;
  }
  return $to;
}

################################################################
##  fromhex()

sub fromhex {
  my $c = shift;
  if( $c ge '0' && $c le '9' ) { return ord($c) - ord('0'); }
  if( $c ge 'a' && $c le 'z' ) { return ord($c) - ord('a') + 10; }
  if( $c ge 'A' && $c le 'Z' ) { return ord($c) - ord('A') + 10; }
  return 0;
}

################################################################
##  dirname()

sub dirname {
  my $p = shift;
  return "" unless $p =~ /\//;
  if( $p =~ /\/+[^\/]+$/ ) { return $`; }
  die "cannot get dirname from file: $p";
}

################################################################
##  cvs_command()

sub cvs_command {
  my( $rc, $cmdline, $arg, $f_anyrc, $f_quiet1, $f_quiet2, $tmpf );
  local( *TEMP );
  $f_anyrc = 0;
  $f_quiet1 = 1;
  $f_quiet2 = 0;
  if( $dl1 >= 20 ) {
    printf( "_: cvs_command(): args = %s\n",
        join( ' ', @_ ) );
  }
  $cvsbinpath = 'cvs' unless $cvsbinpath;
  $cmdline = &shellparseable( $cvsbinpath );
  $cmdline .= ' -d ' . &shellparseable( $cvsroot );
  for(;;) {
    last unless defined $_[0];
    $arg = $_[0];
    if( $arg eq '-Q' ) { $cmdline .= ' -Q'; shift; next; }
    elsif( $arg eq '-q' ) { $cmdline .= ' -q'; shift; next; }
    elsif( $arg eq '-quiet1' ) { $f_quiet1 = 1; shift; next; }
    elsif( $arg eq '-no-quiet1' ) { $f_quiet1 = 0; shift; next; }
    elsif( $arg eq '-quiet2' ) { $f_quiet2 = 1; shift; next; }
    elsif( $arg eq '-no-quiet2' ) { $f_quiet2 = 0; shift; next; }
    elsif( $arg eq '-anyrc' ) { $f_anyrc = 1; shift; next; }
    elsif( $arg eq '-no-anyrc' ) { $f_anyrc = 0; shift; next; }
    elsif( $arg =~ /^-/ ) { die; }
    else { last; }
  }
  foreach $arg( @_ ) {
    $cmdline .= ' ' . &shellparseable( $arg );
  }
  $tmpf = $tempdir . "/cvscmdout";
  if( $f_quiet1 ) {
    $cmdline .= sprintf( ' >%s', &shellparseable( $tmpf ) );
  }
  if( $f_quiet2 ) {
    $cmdline .= sprintf( ' 2>%s', &shellparseable( $tmpf ) );
  }
  $cmdline .= ' </dev/null';
  print "_: cvs_command(): send command: $cmdline\n" if( $dl1 >= 20 );
  open( TEMP, "> $tmpf" ) and close( TEMP );
  $rc = system( $cmdline );
  if( $rc && !f_anyrc ) {
    print "cvs command `$cmdline' failed: rc=$rc\n";
  }
  if( ( $rc && !f_anyrc ) || $dl1 >= 30 ) {
    print "=== cut cvs output ===\n";
    system( 'cat', '--', $tmpf );
    print "=== end cut ===\n";
  }
  if( $rc && !f_anyrc ) {
    die "cannot continue";
  }
  return $rc;
}

################################################################
##  shellparseable()
##  It prints form of this line adoptable by shell as single argument

sub shellparseable {
  my $s = shift;
  return "" unless defined $s; ## ?
  return "''" if $s eq "";
  return $s if $s =~ /^[A-Za-z0-9+,.\/\@:=^_]+$/;
  return "'$s'" unless $s =~ /['\\]/;
  return '"'.$s.'"' unless $s =~ /["\\\$]/;
  my $to;
  my $old = $s;
  my $c;
  my $cc;
  $to = "";
  while( $s ne "" ) {
    $c = substr( $s, 0, 1 );
    $s = substr( $s, 1 );
    if( $c eq "\n" ) { $to .= '"'."\n".'"'; next; }
    $to .= "\\" unless $c =~ /[A-Za-z0-9+,.\/\@:=^_-]/;
    $to .= $c;
  }
  if( $dl1 >= 25 ) {
    printf( "shellparseable(): `%s' -> `%s'\n", $old, $to );
  }
  return $to;
}

## self destruct
END {
 unlink $pidfile;
 exit 0;
};
