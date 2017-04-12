#!/bin/perl -w
use Win32API::File 0.08 qw( :ALL );


# Variables
$RepeatCount=1;        # Do only one cycle on a default, set to zero to loop infinite times
#$FileName="//./X:";    # Read from drive X: as a default
$StartSector=0;        # Start from the beginning of the disk
$EndSector=-1;         # Number of last sector to check, use -1 to check full disk
$StartPhase=1;         # Way to skip some test phases
$CheckStringLength=8;  # How many bytes check string uses
#$CheckStringLength=16;
#$CheckStringLength=32;
$ForceWrite=0;         # If this is true, then failed sectors will be skipped
$Skipped=0;

# Read arguments
while (@ARGV)
  {
  # Read first argument
  $Arg=shift(@ARGV);

  # Is it filename
  $FileName="//./".$1.":" if ($Arg =~ /^([a-zA-Z])\:$/);

  # Is it repeat count - give zero to loop until card is broken
  $RepeatCount=$1 if ($Arg =~ /([0-9]+)/);

  # Option to skip "are you sure" question
  $DoNotAskConfirmation=1 if ($Arg =~ /^-Y$/);

  # Skip compare
  $SkipComparePhase=1 if ($Arg =~ /^-nocompare$/i);

  # Way to change start and end sectors
  $StartSector=shift(@ARGV) if ($Arg =~ /-start/i);
  $EndSector=shift(@ARGV) if ($Arg =~ /-end/i);
  $ForceWrite=1 if ($Arg =~ /-force/i);
  }

# Check that filename was given
if (!$FileName)
  {
  # There was no filename, inform user how to do it
  print "\nPlease specify which drive should be checked.\n";
  print "\nFor example:\n";
  print " perl DumpCheck.pl x:\n";
  exit;
  }

# Ask if user is sure of filename - this would do bad things for harddisk :)
if (!$DoNotAskConfirmation)
  {
  $FileName=~/([a-zA-Z]:)/;
  print "All data from drive ",uc $1," will be lost!\n";
  print "Is this OK? [y/N]\n";
  $Val=getc(STDIN);
  # Quit if answer is not accetable
  exit if (lc $Val ne "y");
  }

# Resolve sector count (not so beautiful way to do, but output looks better)
&MyOpen;
CloseHandle($hIN);

# Loop until card failure is found
for ($RepeatLoop=0;;$RepeatLoop++)
  {
  # Quit if enough loops are done
  last if ($RepeatCount && $RepeatLoop>=$RepeatCount);
  print "\n** Cycle: $RepeatLoop";
  print " / $RepeatCount" if ($RepeatCount);
  print " **\n";

  # (Re)make random ID
  &GenerateRandomId;

  # Do disk checking
  for ($Phase=$StartPhase; ; $Phase++)
    {
    # Open logical disk
    &MyOpen;

    # Print info of current phase
    print "\nPhase $Phase - ";
    if ($Phase==1)
      {
      print "Write and compare\n";
      $CompareOnly=0;
      }
    elsif ($Phase==2)
      {
      last if ($SkipComparePhase); # Way to skip compare phase
      print "Compare\n";
      $CompareOnly=1;
      }  
    else
      {
      print "End\n";
      last;
      }

    $StartTime=time;
    $TargetTime=0;

    # Change sector count, if last sector was defined
    $Sectors=$EndSector if ($EndSector!=-1);

    # Loop all sectors
    for ($Sec=$StartSector; $Sec<$Sectors; $Sec++)
      {
      # Skip PBR
      if ($Sec==0)
        {
        SetFilePointer($hIN,$BytesPerSector,[],FILE_CURRENT()) or die "\nCan't seek forward: $^E\n";
        next;
        }

      print "\rSector $Sec";
      print " ",$UsedTime,"/",$TargetTime,"sec" if ($TargetTime);

      # Write data to sector and compare it
      $Id=&MakeSectorId($Sec+1);
      &MyWrite($Id);
      $FullId=&MyRead();
      for ($c=0; $c<$BytesPerSector; $c+=$CheckStringLength)
        {
        $CompareId=substr($FullId,$c,$CheckStringLength);
        if ($Id ne $CompareId)
          {
          # Error occured
          print "\nError on sector $Sec, offset $c\n";

          # Print written and read data 
          my (@Tmp,$Str);
          $Str.="H2" for (1..$CheckStringLength);
          @Tmp=unpack($Str,$Id);
          print "Wrote ->@Tmp<-\n";
          @Tmp=unpack($Str,$CompareId);
          print "Read  ->@Tmp<-\n";

          # End check-loop if write was forced
          if ($ForceWrite)
            {
            $Skipped++;
            last;
            }

          # Close disk handle and quit
          CloseHandle($hIN);
          exit;
          }
        }

      # Calculate estimated time
      $UsedTime=time-$StartTime;
      $NewTargetTime=($Sectors-$StartSector)*($UsedTime/(($Sec-$StartSector)+1));
      $TargetTime=int(($NewTargetTime+$TargetTime)/2+0.5);
      }
    CloseHandle($hIN);
    }
 
  }

# Print number of skipped sectors
if ($ForceWrite)
  {
  print "$Skipped sectors were broken\n";
  }

exit;

sub MyOpen
  {
  # Open drive
  $hIN= CreateFile( $FileName, GENERIC_READ()|GENERIC_WRITE(), FILE_SHARE_READ()|FILE_SHARE_WRITE(), [], OPEN_EXISTING(), 0, [] ) or  die "Can't open \"$FileName\": $^E\n";

  # Resolve partition size
  DeviceIoControl($hIN,IOCTL_DISK_GET_PARTITION_INFO(),[],[], $opOutBuf,[], [],[]) or die "\nCan't open \"$FileName\": $^E\n";
  ( $uStartLow, $ivStartHigh, $ucHiddenSects, $uPartitionSeqNumber, $uPartitionType, $bActive, $bRecognized, $bToRewrite )= unpack( "L l L L C c c c", $opOutBuf );
  $uStartLow=$uStartLow; $ivStartHigh=$ivStartHigh;$uPartitionSeqNumber=$uPartitionSeqNumber; # Remove warning of unused variables
  $uPartitionType=$uPartitionType;$bActive=$bActive;$bRecognized=$bRecognized;$bToRewrite=$bToRewrite; # Remove warning of unused variables

  # Resolve how many bytes are per sector - needed for disk read
  DeviceIoControl($hIN,IOCTL_DISK_GET_DRIVE_GEOMETRY(),[],[], $opOutBuf,[], [],[]) or die "\nCan't open \"$FileName\": $^E\n";
  ( $CylindersLow, $CylindersHigh, $MediaType, $TracksPerCylinder, $SectorsPerTrack, $BytesPerSector )= unpack( "L l I L L L", $opOutBuf );
  $CylindersLow=$CylindersLow;$CylindersHigh=$CylindersHigh;$MediaType=$MediaType;  # Remove warning of unused variables
  $TracksPerCylinder=$TracksPerCylinder;$SectorsPerTrack=$SectorsPerTrack; # Remove warning of unused variables

  # Calculate the number of sectors
#  $Cylinders=($CylindersHigh<<8) + $CylindersLow;
#  $Tracks=$Cylinders * $TracksPerCylinder;
#  $Sectors=$Tracks * $SectorsPerTrack;
  $Sectors=($ucHiddenSects/$BytesPerSector)-1;

  # Goto starting sector
  &MySeekSector($StartSector);

  if (!$LastSectorCount)
    {
    # Print sector count for the first time
    $FileName=~/([a-zA-Z]:)/;
    print "Drive ",uc $1," has $Sectors sectors\n";
    }
  else
    {
    # Check that sector count is not changed
    if ($LastSectorCount!=$Sectors)
      {
      print "Sector count differs: $LastSectorCount != $Sectors\n";
      }
    }
  $LastSectorCount=$Sectors;
  }

# Create sector ID-string from sector number
sub MakeSectorId
  {
  # This is ugly way to do this!
  my $SectorNum=shift(@_);
  my ($Str,$Id);

  # Explode given number
  my $s=length($SectorNum);
  $Str.="h" for (1..$s);
  my @Tmp=unpack($Str,$SectorNum);
  # Add Zeros, until it has correct lenght
  unshift(@Tmp,0) for ($s..$CheckStringLength-1); 
  # Add some random variables
#  $Tmp[$_]|=$RandomID[$_] for(0..$CheckStringLength-1);
  $Tmp[$_]^=$RandomID[$_] for(0..$CheckStringLength-1);
  # Pack it to single string
  $Id.=pack("C",$_) foreach (@Tmp);
  return $Id;
  }

# Make random ID to prevent writing same data every run
sub GenerateRandomId
  {
  @RandomID=();  # Clear first
#  push(@RandomID,(rand(10)<<4)) for (0..$CheckStringLength-1);
  push(@RandomID,rand(255)) for (0..$CheckStringLength-1);
#  @RandomID=(0x60,0x50,0x50,0x10,0x00,0x00,0x70,0x40);
  }

# Read whole sector and return it's contents
sub MyRead
  {
  my $Buf;
  if (!$CompareOnly)
    {
    SetFilePointer($hIN,-$BytesPerSector,[],FILE_CURRENT()) or die "\nCan't seek backwards: $^E\n";
    }
  my $Ok=ReadFile($hIN,$Buf,$BytesPerSector,[],[]);
  if (!$Ok && !$ForceWrite)
    {
    die "\nCan't read: $^E\n"
    }
  else
    {
    for (0..$BytesPerSector)
      {
      $Buf.=pack("C",0);
      }
    }
  #return substr($Buf,0,$CheckStringLength);
  return $Buf;
  }

# Write whole sector with given number
sub MyWrite
  {
  return if ($CompareOnly);
  my $Id=shift(@_);
  my $Dat="";
  my $Size=$BytesPerSector/$CheckStringLength;
  $Dat.=$Id for (0..$Size);
  my $Ok=WriteFile($hIN,$Dat,$BytesPerSector,[],[]);
  die "\nCan't write: $^E\n" if (!$Ok && !$ForceWrite);
  }

# Goto to given sector
sub MySeekSector
  {
  my $Addr=$_[0]*$BytesPerSector;
  SetFilePointer($hIN,$Addr,[],FILE_BEGIN()) or die "\nCan't seek to $Addr: $^E\n";
  }