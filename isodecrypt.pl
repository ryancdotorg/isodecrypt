#!/usr/bin/perl -w
use strict;

use Fcntl;
use Term::ProgressBar;
use Data::Dumper;

use constant CHUNKSIZE => 1024 * 1024 * 10;

my $SECTORSIZE = 2048;

my $dev = $ARGV[0];

my $iso_pvd = `isoinfo -d -i $dev`;
$iso_pvd =~ /^Volume id: (.+)$/m;
my $volid = $1;
$iso_pvd =~ /^Volume size is: (\d+)$/m;
my $volsize = $1;
print "Volume id: '$volid'\n";
print "Volume size: $volsize\n";

my $iso_dir = `isoinfo -l -s -i $dev`;
my @iso_dir = split(/\n/,$iso_dir);

if (-e "$volid.iso")
{
  print "$volid.iso already exists.  You need to delete it first for this script to run.\n";
  exit 1;
}

if (-e $volid)
{
  print "$volid already exists.  You need to delete it first for this script to run.\n";
  exit 1;
} else {
  print "Decrypting DVD Video Data...\n";
  system('dvdbackup','-M','-i',$dev);
}

my $cur_dir = '';
my @layout;
print "Parsing disk layout...\n";
foreach my $line (@iso_dir)
{
  if ($line =~ /Directory listing of (\/.*)/)
  {
    $cur_dir = $1;
    next;
  }

  if ($cur_dir eq '/VIDEO_TS/')
  {
    #----------   0    0    0           16384 Mar 24 2004 [    354 00]  VIDEO_TS.BUP;1
#    if ($line =~ /\d+\s+\d+\s+\d+\s+    (\d+)\s+\w+\s+\d+\s+\d+\s+\[\s*(\d+)\ 00\]\s+(\w+\.(?:BUP|VOB|IFO))/x)
    if ($line =~ /\d+\s+\d+\s+\d+\s+    (\d+)\s+\w+\s+\d+\s+\d+\s+\[\s*(\d+)\ 00\]\s+(\w+\.(?:VOB))/x)
    {
      my $file   = $3;
      my $offset = int($2);
      my $size   = int($1);
      push(@layout, [$offset, $size, $file]);
    }
  }
}

# Sort by offset
@layout = sort {$a->[0] <=> $b->[0]} @layout;

print "Splicing data into iso...\n";
#print "Copying DVD          @ sectors 0-".($layout[0]->[0]-1)."\n";
writeiso($dev, 0, 0, $layout[0]->[0]*$SECTORSIZE);

foreach my $i (0..$#layout)
{
  my $offset = $layout[$i]->[0];
  my $size   = $layout[$i]->[1];
  my $name   = $layout[$i]->[2];

  my $end    = $offset + $size;
  my $nextoff= $layout[$i+1]->[0] || $end;

  #print "Copying $name @ sector $offset+$size\n";
  #print "Copying $name @ sectors $offset-".($offset+$size-1)."\n";
  if ($size > 0)
  {
    writeiso("$volid/VIDEO_TS/$name", 0, $offset*$SECTORSIZE, $size*$SECTORSIZE)
  }

  if ($i < $#layout && $nextoff > $end )
  {
    my $gap = $nextoff - $end;
    #print "Copying DVD @ sector $end+$gap\n";
    #print "Copying DVD          @ sectors $end-".($end+$gap-1)."\n";
    writeiso($dev, $end*$SECTORSIZE, $end*$SECTORSIZE, $gap*$SECTORSIZE);
  }
  if (!$layout[$i+1]->[2])
  {
    my $end = $layout[$i]->[0] + $layout[$i]->[1];
    my $gap = $volsize - $end;
    #print "Copying DVD @ sector $end+$gap\n";
    #print "Copying DVD          @ sectors $end-".($end+$gap-1)."\n";
    writeiso($dev, $end*$SECTORSIZE, $end*$SECTORSIZE, $gap*$SECTORSIZE);
  }
}

sub writeiso
{
  my $in_file = shift;
  my $ioffset = shift;
  my $ooffset = shift;
  my $length  = shift;

  sysopen(DIN, $in_file, O_RDONLY) or die "Can't open $in_file: $!";
  sysopen(ISO, "$volid.iso", O_RDWR|O_CREAT) or die "Can't open $volid.iso: $!";

  if ($in_file =~ /(?:IFO|BUP|VOB)/i)
  {  
    my @stat = stat(DIN);
    my $fsize = $stat[7];
    if ($length != $fsize)
    {
      print STDERR "specified size = $length file size = $fsize\n";
    }
  }

  sysseek(DIN, $ioffset, 0) or die "Can't seek $in_file: $!";
  sysseek(ISO, $ooffset, 0) or die "Can't seek $volid.iso: $!";

  my $start = time;
  # Remaining data to be copied
  my $rdata = $length;

  my $progress = Term::ProgressBar->new({count => $length, ETA => 'linear', name => $in_file});

  while ($rdata > 0)
  {
    my $cdata;
    my $csize = CHUNKSIZE;
    $csize = $rdata if ($rdata < $csize);

    sysread(DIN, $cdata, $csize);
    syswrite(ISO, $cdata, $csize);
    $rdata -= $csize;
    $progress->update($length - $rdata);
  }
  print "\n";

  if (time - $start >= 5)
  {
#    print 'Speed: ' . int(($length / (time - $start)) / 1024) . " KB/sec\n";
  }

  close(DIN);
  close(ISO);
}
