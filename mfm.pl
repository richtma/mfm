use strict;
use warnings qw(FATAL all);
use Error::Die; # DEPEND
use MFM; # DEPEND
use SimpleIO::Cat; # DEPEND
use SimpleIO::Write; # DEPEND
use SimpleIO::Copy; # DEPEND
use File::Path;
use File::Basename;

my $cmd = @ARGV ? shift : 'build';

if($cmd eq 'build' || $cmd eq 'dist') {
  do_clean();

  push @Error::Die::CLEANUP, sub { eval { rmtree("$_") } foreach @CLEAN };
  get('MFM-BUILD')->run_rules;
  get('MFM-VERSION')->run_rules if $cmd eq 'dist';
  get($_)->run_rules foreach cat('MFM-BUILD');
  $_->run_finalize foreach targets;

  write_makefile('Makefile',
    sort { $a->{priority} <=> $b->{priority} || $a cmp $b } targets
  );
  write_file('MFM-FILES', sort(@FILES)) if @FILES;
  write_file('MFM-CLEAN', sort(@CLEAN)) if @CLEAN;
  write_file('MFM-REALLYCLEAN', sort(@REALLYCLEAN)) if @REALLYCLEAN;

  do_dist() if $cmd eq 'dist';
}

elsif($cmd eq 'clean') {
  do_clean();
}

elsif($cmd eq 'reallyclean') {
  do_clean();
  foreach my $f (eval { cat('MFM-REALLYCLEAN') }, qw(REALLYCLEAN)) {
    eval { rmtree($f) }
  };
}

elsif($cmd eq 'borrow') {
  borrow($_) foreach @ARGV;
}

elsif($cmd eq 'install') {
  my $from = shift || '.';
  my $to = shift || "$AutoHome::HOME/share/mfm";
  recursive_copy($from, $to);
}

elsif($cmd eq 'rulesets') {
  print "$_\n" foreach MFM::Path::rule;
}

elsif ($cmd eq 'version') {
  print "$PACKAGE $VERSION\n";
}

else {
  die "unknown command: $cmd";
}

exit 0;

sub do_clean {
  foreach my $f (
      eval { cat('MFM-CLEAN') },
      qw(Makefile MFM-FILES MFM-CLEAN)) {
    eval { rmtree($f) };
  }
}

sub distfiles {
  return (map { "$_" } @FILES),
         (-e 'MFM-EXTRA' ? cat('MFM-EXTRA') : ()),
         qw(
           MFM-VERSION
           Makefile
         );
}

sub do_dist {
  my ($package) = cat('MFM-VERSION');
  $package =~ y/ /-/;

  rmtree($package);
  mkpath($package);
  foreach my $from (distfiles()) {
    my $to = "$package/$from";
    mkpath(dirname($to));
    if (-d $from) {
      recursive_copy($from, $to);
    }
    else {
      safe_copy($from, $to);
    }
  }

  system(qw(tar cf), "$package.tar", $package)
    and die "unable to create tar archive";
  system(qw(gzip -9 -f), "$package.tar")
    and die "unable to compress tar archive";
  rmtree($package);
}

sub write_makefile {
  my $fn = shift;

  my $fh = IO::File->new("$fn.tmp", 'w')
    or die "unable to open $fn for writing: $!";

  print $fh "# Automatically generated by mfm; do not edit!\n";
  $_->write_makefile($fh) foreach @_;

  $fh->close
    or die "unable to write to $fn: $!";
  rename("$fn.tmp", $fn)
    or die "unable to rename $fn.tmp to $fn: $!";
}
