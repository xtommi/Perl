#!/bin/perl -w
use Win32API::File 0.08 qw( :ALL );

# Settings
$VerboseClusterChain=0;      # Wether or not script prints all cluster chains
$VerboseClusters=0;          # If cluster numbers are to be printed
#$SilentMode=0;               # If most of the prints are to be omitted
$ProcessBrokenDirectories=0; # If this is 1, then directories, which have broken cluster chain are processed
$ProcessDeletedFiles=0;      # If this is set to 1, then also deleted file's cluster chains are processed
$PreferredFAT=1;             # Which fat to use, 1 or 2
$PreferredPartition=-1;      # Which partition is to be used
$DoFileRecovery=0;           # If this is set to 1, then the script will try to save all files to a directory
$RecoveryPath="Recovery";    # This is the directory where recovered files are saved
$UseWin32ApiFileHandling=1;  # Set this to one if you want to use win32 file handling, it is slower, but allows read data directly from drive
@SkipTheseFiles=
  (
  # If some files/directories are listed here, then those are not processed.
  # This comparision is done against long filenames and DOS 8.3 filenames
  # Note that also spaces are included to filename
  #"documents","mg2",
  #"6e 20 74    ","4 64 75 .20 ","73   69 .6c ",
#"Videos"
  );

# Some variables
$BytesPerSector=0x200;
#$BootSectorSize=0x3E;  # This is the real boot sector size
$BootSectorSize=0x200;  # But this must be used
$PartitionStartAddr=0;  # Where partition starts
$ClusterChainErrors=0;
@ClusterChainErrorsTbl=();
$UnusedChains=0;
$CrossLinkedCount=0;
$FileSizeErrors=0;
@FileSizeErrorsTbl=();
$FatErrors=0;
$MissingDotEntries=0;
@MissingDotEntriesTbl=();
$FileCount=0;
$ShowFileCount=0;

#-------------------------------
# Code

# Read arguments
while (@ARGV)
  {
  # Read first argument
  $Arg=shift(@ARGV);

  # Check argument
  if ($Arg =~ /^-/)
    {
    $Arg=lc $Arg;  # Convert argument to lower case
    # Verbose
    $VerboseClusterChain=1 if ($Arg eq "-v");
    # Verbose cluster number
    $VerboseClusters=1 if ($Arg eq "-vc");
    # Change fat
    $PreferredFAT=shift(@ARGV) if ($Arg eq "-fat");
    # Change fat
    $PreferredPartition=shift(@ARGV) if ($Arg eq "-partition");
    # Do recovery process
    $DoFileRecovery=1 if ($Arg eq "-recovery");
    # Change recovery path
    $RecoveryPath=shift(@ARGV) if ($Arg eq "-path");
    # Do not use win32
    $UseWin32ApiFileHandling=0 if ($Arg eq "-nowin");
    # Calculate file count
    $ShowFileCount=1 if ($Arg eq "-filecount");
    }
  else
    {
    # Must be filename
    $FileName=$Arg;
    }
  }

# Read argument
#$FileName=$ARGV[0] if ($ARGV[0]);
die("Invalid filename!\n") if (!$FileName);
# Check if argument was a drive letter
$FileName="//./".$1.":" if ($FileName =~ /([a-zA-Z])\:$/);
$RecoveryPath.="/" if ($RecoveryPath !~ /\/$/);  # Add trailing slash if it is missing

# Start reading file
print "*** Image file ***\n";
print "$FileName\n\n";

if ($UseWin32ApiFileHandling)
  {
  print "Using Win32API file handling\n\n";
  our $hIN= CreateFile( $FileName, FILE_GENERIC_READ, FILE_SHARE_READ(), [], OPEN_EXISTING(), 0, [] ) or  die "Can't open \"$FileName\": $^E\n";

  # Resolve how many bytes are per sector - needed for disk read
  DeviceIoControl($hIN,IOCTL_DISK_GET_DRIVE_GEOMETRY(),[],[], $opOutBuf,[], [],[]);
  #( $ucCylsLow, $ivcCylsHigh, $uMediaType, $uTracksPerCyl, $uSectsPerTrack, $uBytesPerSect )= unpack( "L l I L L L", $opOutBuf );
  @OutBuf= unpack( "L l I L L L", $opOutBuf );
  $BytesPerSector=$OutBuf[5] if ($OutBuf[5]);
  $BootSectorSize=$OutBuf[5] if ($OutBuf[5] && $BootSectorSize<$OutBuf[5]);  # OutBuf[5] contains BytesPerSector data
  }
else
  {
  open(IN,$FileName) || die ("Can't open file \"$FileName\": $!");
  binmode(IN);
  }

# Read Boot Sector
#ReadFile($hIN,$Buf,$BootSectorSize,[],[]);
##read(IN,$Buf,$BootSectorSize);
$Buf=&MyRead($BootSectorSize);
&ReadBootSector($Buf);
#read(IN,$Buf,$BytesPerSector-$BootSectorSize);  # Read until full boot sector is readed
# Read until full boot sector is readed
#ReadFile($hIN,$Buf,$BytesPerSector-$BootSectorSize,[],[]) if ($BootSectorSize != $BytesPerSector);
&MyRead($BytesPerSector-$BootSectorSize) if ($BootSectorSize != $BytesPerSector);

# Skip reserved sectors
#read(IN,$Buf,$BytesPerSector) for (2..$ReservedSectors);
#ReadFile($hIN,$Buf,$BytesPerSector,[],[]) for (2..$ReservedSectors);
&MyRead($BytesPerSector) for (2..$ReservedSectors);

# Read FAT
print "\n*** FAT ***\n";
@Fat=&ReadFAT;
@FatFiles=();
@UseFat=();
print "FAT1 readed\n";

# Read rest of FAT:s and compare those to first fat
for $FatNum (2..$NumberOfFATs)
  {
  # Read FAT
  my @Tmp=&ReadFAT;
  my $Err=0;
  push(@UseFat,@Tmp) if ($FatNum==$PreferredFAT);

  # Compare FAT data
  foreach (@Fat)
    {
    $Err++ if ($_ != shift(@Tmp));
    }

  print "FAT$FatNum OK\n" if ($Err==0);
  print "FAT$FatNum Not OK!\n" if ($Err!=0);
  $FatErrors+=$Err;
  }

# Change fat table if needed
if ($PreferredFAT!=1 && $#UseFat!=-1)
  {
  print "Change to FAT$PreferredFAT\n";
  @Fat=();
  push(@Fat,@UseFat);
  @UseFat=();  # Empty this buffer
  }

#&MyClose;exit;

# Print recovery info
print "\nDo file recovery from $PreferredFAT to directory $RecoveryPath\n" if ($DoFileRecovery);

# Directories
print "\n*** Directory structure ***\n";
#read(IN,$Buf,$BytesPerSector);
#ReadFile($hIN,$Buf,$SectorsPerCluster*$BytesPerSector,[],[]);
&PrintClusterNumber(&MyTell);
$Buf=&MyRead($SectorsPerCluster*$BytesPerSector);
&ReadDirectory($Buf,0);

# Close file handle
&MyClose;


print "\n*** Cluster chain errors ***\n";
print "$_\n" foreach (@ClusterChainErrorsTbl);
print "None\n" if ($ClusterChainErrors==0);

print "\n*** Cross linked files ***\n";
for ($c=0; $c<$#FatFiles-1; $c++)
  {
  next if (!$FatFiles[$c]);
  $File=$FatFiles[$c];
  $File =~ s/\s+\*\*\s+$//;
  if ($File =~ /\*\* ./)
    {
    print "$c: $File\n";
    $CrossLinkedCount++;
    }
  }
print "None\n" if ($CrossLinkedCount==0);

print "\n*** File size errors ***\n";
print "$_\n" foreach (@FileSizeErrorsTbl);
print "None\n" if ($FileSizeErrors==0);

print "\n*** Missing \".\" or \"..\" directories ***\n";
print "$_\n" foreach (@MissingDotEntriesTbl);
print "None\n" if ($MissingDotEntries==0);

# Check unused chains (lost clusters)
#foreach (@Fat)
for (2..$FatSize)
  {
  my $c=$Fat[$_];
  if ($c>$RESERVED_CLUSTER)
    {
    #print "Lostcluster: $_ -> $c\n";
    $UnusedChains++;
    }
  }
$LostBytes=$UnusedChains*$SectorsPerCluster*$BytesPerSector;
$LostMbs=int($LostBytes*100/(1024*1024))/100;

# Print statistics
print "\n*** Statistics ***\n";
print "Differences between FATs: $FatErrors\n" if ($NumberOfFATs>1);
print "Cluster chain errors: $ClusterChainErrors\n";
print "Lost clusters: $UnusedChains = $LostBytes bytes = $LostMbs Mb\n";
print "Cross linked files: $CrossLinkedCount\n";
print "File size errors: $FileSizeErrors\n";
print "Missing \".\" or \"..\" directories: $MissingDotEntries\n";
print "\n",$#SkipTheseFiles+1," directories were skipped\n" if ($#SkipTheseFiles!=-1);
print "\nTotal directory entry count: $FileCount\n" if ($ShowFileCount);

# Count number of errors and print ok message if card was not corrupted
$ErrorCount=$FatErrors;				 								# Fat errors
$ErrorCount+=$ClusterChainErrors+$UnusedChains+$CrossLinkedCount;	# Cluster chain errors
$ErrorCount+=+$FileSizeErrors;										# File errors
$ErrorCount+=$MissingDotEntries;									# Directory errors
print "\nNo errors found\n" if ($ErrorCount==0);

#sub ReadBuf
#  {
#  my $Size=shift(@_);
#  my ($Buf,$Len);
#  read(IN,$Buf,$Size);
#  $s=length($Buf);
#  unpack("C$s",$Buf);
#  }

sub ClusterPos
  {
  my $Cluster=shift(@_);

  # Check errors
  #$Cluster&=$CLUSTER_MASK; # Mask excess bits
  return -1 if ($Cluster<0);
  return -2 if ($Cluster==$FREE_CLUSTER);
  return -3 if ($Cluster==$RESERVED_CLUSTER);
  return -3 if ($Cluster>=$RESERVED_START && $Cluster<=$RESERVED_END);
  return -4 if ($Cluster==$BAD_CLUSTER);
  return -5 if ($Cluster>$FatSize);
  return -9 if ($Cluster>=$LAST_CLUSTER); # Normal EOF

  # Calculate sector address from cluster number
  my $Addr=$ReservedSectors+$NumberOfFATs*$SectorsPerFAT; # Root dir
  $Addr+=($NumberOfRootDirEntries*32)/$BytesPerSector;    # Skip root dir entries
  $Addr+=($Cluster-2)*$SectorsPerCluster;                 # Cluster position. ($Cluster-2) because clusters 0&1 can't be used
  $Addr*=$BytesPerSector;                                 # How many bytes per sector
  $Addr+=$PartitionStartAddr;                             # Move to partition start address
  # Skip root dir entries
#  $Addr+=($NumberOfRootDirEntries*32) - $NumberOfHeads*$BytesPerSector;
  #$Addr+=($NumberOfRootDirEntries*32);

#  printf "ClusterPos::: %08X -> %08X\n",$Cluster,$Addr/$BytesPerSector;
#  printf "ClusterPos::: %08X -> %08X\n",$Cluster,$Addr;
#  print "ClusterPos:::: $Cluster->$Addr\n";
#exit;
  # Return address
  return $Addr;
  }

sub ReadDirectory
  {
  my ($Buffer,$DirCluster,$PrintOverhead)=(@_);
  $PrintOverhead="" if (!$PrintOverhead);
  my $LongFileName="";
  my $TempLongFileName="";
  my $Err;
  my $DotEntries=0;
  my $Cluster=0;
  
  if ($DoFileRecovery)
    {
    print STDERR "Make dir: $RecoveryPath$PrintOverhead\n";
    mkdir($RecoveryPath.$PrintOverhead,0777);
    }

  for(;;)
    {
    # Explode buffer to table
    my $s=length($Buffer);
    my @SectorBuf=unpack("C$s",$Buffer);
    my $SectorPos=0;
#    my $DirAddress=tell(IN);
#    my $DirAddress=SetFilePointer($hIN,0,[],FILE_CURRENT());
    my $DirAddress=&MyTell();

    # Check that all data was read
    if ($s != $SectorsPerCluster*$BytesPerSector)
      {
      print $PrintOverhead,"Read error in address ";
      printf "0x%08X!\n",$DirAddress;
      return;
      }

    # Continue until whole sector is readed
    while ($SectorPos<$SectorsPerCluster*$BytesPerSector)
      {
      $Buf[$_]=$SectorBuf[$SectorPos+$_] for (0..31);
      $SectorPos+=32;
      print "/".$PrintOverhead." ";

      my $FileName="";
      my $Attributes=0;

      # First byte has some special meanings
      $FirstByte=$Buf[0];
      if ($FirstByte == 0x00)  # If entry is empty, then directory ends
        {
        &EndOfDirectoryCheck($PrintOverhead,$DotEntries);
        return;
        }

      # If file is deleted
#      my $Deleted="   ";
#      $Deleted="Del" if ($FirstByte == 0xE5);
#      print $Deleted;

      #print "Dot entry:" if ($FirstByte == 0x2E); # If dir is . or ..
      $DotEntries++ if ($FirstByte == 0x2E); # If dir is . or ..
      $Buf[0]=0xE5 if ($FirstByte == 0x05); # If first letter is actually 0xE5


      # Check attributes
      $Attributes=$Buf[11];
      if ($Attributes == 0x0F)
        {
        # Long file name
        $Sequence=$Buf[0]&0x1F;
        for ($c=1; $c<11; $c+=2) { $FileName.=pack("U", $Buf[$c]+$Buf[$c+1]*0x100); }
        for ($c=14; $c<26; $c+=2) { $FileName.=pack("U", $Buf[$c]+$Buf[$c+1]*0x100); }
        for ($c=28; $c<32; $c+=2) { $FileName.=pack("U", $Buf[$c]+$Buf[$c+1]*0x100); }
        my $Nul=pack("C", 0+0*0x100);   # String is terminated with \0
        $FileName =~ s/$Nul.*$//g;      # Remove excess spaces
        my $Bell=pack("C", 7);          # Accidentally there might be bell in filename
        $FileName =~ s/$Bell//g;        # Remove bells

        $TempLongFileName=$FileName.$TempLongFileName;
        if ($Sequence==1)
          {
          $LongFileName=$TempLongFileName;
          $TempLongFileName="";
          }
        print "LFN \#$Sequence $FileName\n";
        next;
        }
      $TempLongFileName="";
      my @Attr=split(//,"------");
      $Attr[0]="r" if ($Attributes & 0x01);
      $Attr[1]="h" if ($Attributes & 0x02);
      $Attr[2]="s" if ($Attributes & 0x04);
      $Attr[3]="v" if ($Attributes & 0x08);
      $Attr[4]="d" if ($Attributes & 0x10);
      $Attr[5]="a" if ($Attributes & 0x20);
      print @Attr," ";

      # Read first cluster
      $Cluster=$Buf[26]+$Buf[27]*0x100;

      # Read filesize
      my $FileSize=$Buf[28]+$Buf[29]*0x100+$Buf[30]*0x10000+$Buf[31]*0x1000000;
      # Calculate size in clusters 
      my $FileClusters=int(($FileSize+$BytesPerSector-1)/$BytesPerSector);        # Bytes -> Sectors
      $FileClusters=int(($FileClusters+$SectorsPerCluster-1)/$SectorsPerCluster); # Sectors -> Clusters
      # Zero size is a special case
      #$FileClusters=1 if ($FileSize==0);  # ...or is it?
      

      # Read filename
      for (0..11)
        {
        $Buf[$_]=32 if ($Buf[$_]<=31);
#        $Buf[$_]=32 if ($Buf[$_]<=31 || $Buf[$_]>=127);
        }
      $FileName.=pack("C1",shift(@Buf)) for (1..8);
      $FileName=~ s/[\s]+$//;   # Remove excess spaces
      $FileName.=".";
      $FileName.=pack("C1",shift(@Buf)) for (1..3);
      $FileName=~ s/.   $/    /;
      $FileName=~ s/[\s]+$//;   # Remove excess spaces
      print "$FileName ";
#      print "$FileName " if (!$LongFileName);
#      print "$LongFileName " if ($LongFileName);
      #printf " Cluster: 0x%04X ",$Cluster;
      #print " $FileSize bytes ";

      # Check if this filename is to be skipped
      my $SkipFile=0;
      foreach (@SkipTheseFiles)
        {
        # Compare against dos filename and long filename (if exists)
        if ($_ eq $FileName || ($LongFileName && $_ eq $LongFileName))
          {
          print "** Skipped! **\n";
          $SkipFile=1;      # Can't use next here
          $LongFileName=""; # This must be cleared
          }
        }
      next if ($SkipFile);  # Jump to next if file was on list

      # Fix filename
      #$FileName =~ s/\s+//g;  # Remove excess spaces
      # Use long filename if available
      $FileName=$LongFileName if ($LongFileName);
      $LongFileName="";

      # Skip deleted files
      my $Deleted=0;
      if ($FirstByte == 0xE5)
        {
        print "(Del) ";
        print "\n" if (!$ProcessDeletedFiles);
        $FileName.=" (Del)";
        $Deleted=1;
        next if (!$ProcessDeletedFiles);
        }

      # Do not handle . and ..
      if ($FirstByte == 0x2E)
        {
        print "\n";
        next;
        }

      # Do not handle volume label
      if ($Attributes & 0x08)
        {
        print "\n";
        next;
        }

      # Check Cluster chain
      my $Ret=&CheckClusterChain($Cluster,$Deleted,$PrintOverhead.$FileName,$Attributes&0x18,$FileSize);
      $Err="cross linked" if ($Ret == -1);
      $Err="free clusters" if ($Ret == -2);
      $Err="reserved clusters" if ($Ret == -3);
      $Err="bad clusters" if ($Ret == -4);
      $Err="invalid address" if ($Ret == -5);
      next if ($Ret == -6);  # File writing failed
      if ($Ret<0)
        {
        $ClusterChainErrors++ if ($Ret<0);
        push (@ClusterChainErrorsTbl,"$PrintOverhead$FileName - $Err");
        print "Cluster chain is $Err!\n" if ($Ret==-1); 
        print "Cluster chain has $Err!\n" if ($Ret!=-1); 
        }

      if ($Ret >= 0) 
        {
        $FileClusters=$Ret if ($Attributes&0x10); # Directories filesize is ignored
        print "Cluster chain Ok, $Ret clusters";
        print "\n" if ($Ret == $FileClusters);
        if ($Ret != $FileClusters)
          {
          print ", FileSize error: $FileSize bytes = $FileClusters clusters\n";
          push(@FileSizeErrorsTbl,"$PrintOverhead$FileName: $Ret in chain, $FileClusters in dir entry");
          $FileSizeErrors++;
          }
       }
      #printf "\n";

      # Read directories recursively
#      if ($Attributes & 0x10 && $Ret>=0)
      my $Tmp=0;
      $Tmp=1 if ($Attributes & 0x10);
      $Tmp=0 if ($Ret<0 && !$ProcessBrokenDirectories);
      #$Tmp=0 if ($FileName eq "_PAlbTN");  # Skip thumbnails
      # $Tmp is 1 if this file is a directory
      if ($Tmp)
        {
        my @NewBuf;
        my $Addr=&ClusterPos($Cluster);
        if ($Addr <= 0)
          {
          &EndOfDirectoryCheck($PrintOverhead,$DotEntries);
          return;
          }
#        seek(IN,$Addr,0);
#        read(IN,$NewBuf,$BytesPerSector);
#		 SetFilePointer($hIN,$Addr,[],FILE_BEGIN());
#        ReadFile($hIN,$NewBuf,$SectorsPerCluster*$BytesPerSector,[],[]);
        &MySeek($Addr);
        &PrintClusterNumber($Addr);
        $NewBuf=&MyRead($SectorsPerCluster*$BytesPerSector);
        &ReadDirectory($NewBuf,$Cluster,$PrintOverhead.$FileName."/");
        }
      }

    # Continue reading
    my $Addr=$DirAddress; # Root directory entries are special
    $Cluster=0;
    if ($PrintOverhead ne "")
      {
      # Find next address from fat cluster chain
      $Cluster=abs($Fat[$DirCluster]);
      $Addr=&ClusterPos($Cluster);
      if ($Addr <= 0)
        {
        print "/".$PrintOverhead." ";
        &EndOfDirectoryCheck($PrintOverhead,$DotEntries);
        return;
        }
      #print "Read cluster: ";
      #printf "%08X\n",$Cluster;
      }
    else
      {
      # Display root dir sector
      my $Temp=$ReservedSectors+$NumberOfFATs*$SectorsPerFAT; # Root dir address
      $Temp=($Addr/$BytesPerSector)-$Temp;
      #print "Read root dir sector: $Temp\n";
      }
    #seek(IN,$Addr,0);
    #read(IN,$Buffer,$BytesPerSector);
    #SetFilePointer($hIN,$Addr,[],FILE_BEGIN());
    #ReadFile($hIN,$Buffer,$SectorsPerCluster*$BytesPerSector,[],[]);
    &MySeek($Addr);
    &PrintClusterNumber($Addr);
    $Buffer=&MyRead($SectorsPerCluster*$BytesPerSector);
    $DirCluster=$Cluster;
    }

  &EndOfDirectoryCheck($PrintOverhead,$DotEntries);
  }

sub PrintClusterNumber
  {
  my $Addr=$_[0];
  return if (!$VerboseClusters);  # Return if this is not needed

  # Calculate first cluster address
  my $FirstClusterAddr=&ClusterPos(2);

  if ($Addr < $FirstClusterAddr)
    {
    # Address was on root sector
    my $Temp=$ReservedSectors+$NumberOfFATs*$SectorsPerFAT; # Root dir address
    $Temp=($Addr/$BytesPerSector)-$Temp;
    print "Read root dir sector: $Temp\n";
    }
  else
    {
    # Print cluster number
    my $Cluster=$Addr-$FirstClusterAddr;
    $Cluster/=($SectorsPerCluster*$BytesPerSector);
    $Cluster+=2;  # First 2 clusters are invalid
    print "Read cluster: ";
    printf "%08X\n",$Cluster;
    }
  }

sub EndOfDirectoryCheck
  {
  my ($PrintOverhead,$DotEntries)=(@_);
  # Check dot entry count
  if ($DotEntries!=2 && $PrintOverhead)
    {
    print "Invalid count of dot entries: $DotEntries/2 found!\n" ;
    $MissingDotEntries++;
	push(@MissingDotEntriesTbl,$PrintOverhead);
    }
  print "End of directory\n\n";
  }

sub CheckClusterChain
  {
  my ($Cluster,$Del,$FileName,$Directory,$FileSize)=(@_);
  my $Count=0;

  # Calculate file count
  $FileCount++;

  # Skip if cluster is zero and size is zero
  return 0 if ($Cluster==0 && $FileSize==0);

  # Mask excess bits
  #$Cluster&=$CLUSTER_MASK;

  # File Recovery part
  if ($DoFileRecovery && !$Directory)
    {
    # Create destination file
    print STDERR "\nWrite $RecoveryPath$FileName\n";
    my $Name=$RecoveryPath.$FileName;
#    open(OUT,">>$RecoveryPath$FileName") || die "Can't write file \"$RecoveryPath$FileName\": $!\n";
    if (!open(OUT,">>$RecoveryPath$FileName"))
      {
      print "Can't write file \"$RecoveryPath$FileName\": $!\n";
      return -6;
      }
    binmode(OUT);
    }

  # Do printing
  print "\nFile \"/$FileName\" cluster chain:\n($Cluster)" if ($VerboseClusterChain);  

  for(;;)
    {
    # Mark which file is using the cluster
    $FatFiles[abs($Cluster)].=$FileName." ** "  if (abs($Cluster)>1 && abs($Cluster)<$RESERVED_START);
    

    # Check that address is valid 
    if (abs($Cluster)>$FatSize && abs($Cluster)<=$RESERVED_START)
      {
      print "(Invalid address)\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return -5;
      }

    # Check errors
    if ($Cluster<0 && abs($Cluster)<$RESERVED_START)
      {
      # Print filenames
      print "(Used by other file)\n" if ($VerboseClusterChain);
      print "** ",$FatFiles[abs($Cluster)];
      print "\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return -1;
      }
    if ($Cluster==0)
      {
      print "(Free)\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return -2;
      }
    if (abs($Cluster)==1)
      {
      print "(Reserved)\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return -3;
      }
    if (abs($Cluster)>=$RESERVED_START && $Cluster<=$RESERVED_END)
      {
      print "(Reserved)\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return -3;
      }
    if (abs($Cluster)==$BAD_CLUSTER)
      {
      print "(Bad)\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return -4;
      }

    # Normal End of file
    if (abs($Cluster)>=$LAST_CLUSTER)
      {
      print "(eof)\n" if ($VerboseClusterChain);
      close OUT if ($DoFileRecovery);
      return $Count;
      }

    # File recovery part
    if ($DoFileRecovery && !$Directory)
      {
      # Read sector and write it to file
      my $Addr=&ClusterPos(abs($Cluster));
      my $Buffer;
      #seek(IN,$Addr,0);
      #sysread(IN,$Buffer,$SectorsPerCluster*$BytesPerSector);
      #syswrite(OUT,$Buffer,$SectorsPerCluster*$BytesPerSector);
      #SetFilePointer($hIN,$Addr,[],FILE_BEGIN());
      #ReadFile($hIN,$Buffer,$SectorsPerCluster*$BytesPerSector,[],[]);
      &MySeek($Addr);
      $Buffer=&MyRead($SectorsPerCluster*$BytesPerSector);
      syswrite(OUT,$Buffer,$SectorsPerCluster*$BytesPerSector);
      }

    # Follow chain to next cluster
    my $NextCluster=$Fat[$Cluster];
    # Mark previous cluster as used
    $Fat[abs($Cluster)]=-abs($Fat[abs($Cluster)]) if (!$Del); 

    # Go to next cluster
    $Cluster=$NextCluster;
    # Mask excess bits
    #$Cluster&=$CLUSTER_MASK;
    print "->$Cluster" if ($VerboseClusterChain);
    $Count++;
    }
  }


# Read FAT (cluster chains)
sub ReadFAT
  {
  my $Buf;
  my @Fat;
  my @Tmp=();
  print "Read FAT from sector: ",&MyTell,"\n" if ($VerboseClusters);
  for (1..$SectorsPerFAT)
    {
    #read(IN,$Buf,$BytesPerSector);
    #ReadFile($hIN,$Buf,$BytesPerSector,[],[]);
    $Buf=&MyRead($BytesPerSector);
    my $s=length($Buf);
    if ($FATFileSystemType =~ /FAT12/)
      {
      # Explode data into 4 bit nybbles
      foreach (unpack("C$s",$Buf))
        {
        push(@Tmp,($_)&0xF);
        push(@Tmp,($_>>4)&0xF);
        }
      # Combine nybbles to 12 bit FAT values
      while($#Tmp>=3)
        {
        my $Addr=shift(@Tmp);
        $Addr+=shift(@Tmp)<<4;
        $Addr+=shift(@Tmp)<<8;
        push(@Fat,$Addr);
        }
      }
    if ($FATFileSystemType =~ /FAT16/)
      {
      # Just unpack data to 16 bit FAT values
      push (@Fat,unpack("S$s",$Buf));
      }
    }
  $FatSize=$#Fat;
  @Fat
  }

# Read boot sector
sub ReadBootSector
  {
  $Buffer=shift(@_);
  my $s=length($Buffer);
  @Buf=unpack("C$s",$Buffer);

  if (ReadPartitionTable(@Buf))
    {
    $Buffer=&MyRead($BootSectorSize);
    $s=length($Buffer);
    @Buf=unpack("C$s",$Buffer);
    }

  # Extract data
  $OEMName.=pack("C1",$Buf[3+$_]) for (0..7);
  $BytesPerSector=$Buf[11]+$Buf[12]*0x100;
  $SectorsPerCluster=$Buf[13];
  $ReservedSectors=$Buf[14]+$Buf[15]*0x100;
  $NumberOfFATs=$Buf[16];
  $NumberOfRootDirEntries=$Buf[17]+$Buf[18]*0x100;
  $TotalSectors=$Buf[19]+$Buf[20]*0x100;
#  $MediaDescriptor=$Buf[21];
  $SectorsPerFAT=$Buf[22]+$Buf[23]*0x100;
#  $SectorsPerTrack=$Buf[24]+$Buf[25]*0x100;
#  $NumberOfHeads=$Buf[26]+$Buf[27]*0x100;
  $HiddenSectors=$Buf[28]+$Buf[29]*0x100+$Buf[30]*0x10000+$Buf[31]*0x1000000;
  $BigSectors+=$Buf[32]+$Buf[33]*0x100+$Buf[34]*0x10000+$Buf[35]*0x1000000;
#  $PhysicalDriveNumber=$Buf[36];
#  $CurrentHead=$Buf[37];
#  $Signature=$Buf[38];
#  $ID=$Buf[39]+$Buf[40]*0x100+$Buf[41]*0x10000+$Buf[42]*0x1000000;
  $VolumeLabel.=pack("C1",$Buf[43+$_]) for (0..10);
  $FATFileSystemType.=pack("C1",$Buf[54+$_]) for (0..7);
  
  print "*** Boot Sector ***\n";
  print "OEM name: \"$OEMName\"\n";
  printf "Bytes Per Sector: 0x%X\n",$BytesPerSector;
  print "Sectors per cluster: $SectorsPerCluster\n";
  print "Reserved sectors: $ReservedSectors\n";
  print "Number of FATs: $NumberOfFATs\n";
  print "Number of root dir entries: $NumberOfRootDirEntries\n";
  printf "Total sectors: 0x%X%04X = %d Mb\n",$BigSectors,$TotalSectors,int($BigSectors*$BytesPerSector/1000000);
  print "Sectors per FAT: $SectorsPerFAT\n";
  print "Hidden sectors: $HiddenSectors\n";
  print "Volume label: \"$VolumeLabel\"\n";
  print "FAT file system type: \"$FATFileSystemType\"\n";

  # Check FAT type
  if ($FATFileSystemType =~ /FAT16/)
    {
    # FAT16 is supported
    #$CLUSTER_MASK=0xFFFF;
	$FREE_CLUSTER=0x0000;
	$RESERVED_CLUSTER=0x0001;
	$RESERVED_START=0xFFF0;
	$RESERVED_END=0xFFF6;
	$BAD_CLUSTER=0xFFF7;
	$LAST_CLUSTER=0xFFF8;
    }
  elsif ($FATFileSystemType =~ /FAT12/)
    {
    # Also FAT12 is supported
    #$CLUSTER_MASK=0xFFF;
	$FREE_CLUSTER=0x000;
	$RESERVED_CLUSTER=0x001;
	$RESERVED_START=0xFF0;
	$RESERVED_END=0xFF6;
	$BAD_CLUSTER=0xFF7;
	$LAST_CLUSTER=0xFF8;
    }
  else
    {
    # Unsupported FAT, do not process
    print "Unsupported FAT file system type!\n";
    &MyClose;
    exit;
    }
  }

sub ReadPartitionTable
  {
  my @Buf=@_;
  my ($Part,$Addr,$FoundPartitions,$FirstPartition);
  my ($BOOTABLE, $PARTITION_TYPE, $PARTITION_NAME, $START_CYLINDER, $START_HEAD, $START_SECTOR,
      $END_CYLINDER, $END_HEAD, $END_SECTOR, $REL_START_SECTOR, $TOTAL_SECTORS)=(0..10);

  # Check if this is a partition table
  return 0 if ($Buf[0x1FE]!=0x55 && $Buf[0x1FF]!=0xAA);

  # Read partition data
  $Addr=0x1BE;
  $FoundPartitions=0;
  $FirstPartition=-1;
  for $Part (1..4)
    {
    $Partition[$Part][$BOOTABLE]=$Buf[$Addr];
    $Partition[$Part][$PARTITION_TYPE]=$Buf[$Addr+4];

    $Partition[$Part][$START_HEAD]=$Buf[$Addr+1]; 
    $Partition[$Part][$START_SECTOR]=$Buf[$Addr+2]&0x3F;
    $Partition[$Part][$START_CYLINDER]=(($Buf[$Addr+2]&0xC0)<<2) + $Buf[$Addr+3]; 

    $Partition[$Part][$END_HEAD]=$Buf[$Addr+5]; 
    $Partition[$Part][$END_SECTOR]=$Buf[$Addr+6]&0x3F;
    $Partition[$Part][$END_CYLINDER]=(($Buf[$Addr+6]&0xC0)<<2) + $Buf[$Addr+7]; 
    
    $Partition[$Part][$REL_START_SECTOR]=$Buf[$Addr+8] + $Buf[$Addr+9]*0x100 + $Buf[$Addr+10]*0x10000 + $Buf[$Addr+11]*0x1000000;
    $Partition[$Part][$TOTAL_SECTORS]=$Buf[$Addr+12] + $Buf[$Addr+13]*0x100 + $Buf[$Addr+14]*0x10000 + $Buf[$Addr+15]*0x1000000;

    # Check partition type
    $Name="Unknown";
    $Name="FAT12" if ($Buf[$Addr+4]==0x01);
    $Name="FAT16" if ($Buf[$Addr+4]==0x04);
    $Name="FAT16-Ext" if ($Buf[$Addr+4]==0x05);
    $Name="FAT16-Huge" if ($Buf[$Addr+4]==0x06);
    $FoundPartitions++ if ($Name ne "Unknown");
    $Partition[$Part][$PARTITION_NAME]=$Name;

    # Mark first partition
    $FirstPartition=$Part if ($FoundPartitions==1 && $Name ne "Unknown");
    
    $Addr+=16;
    }
  # Return if no supported partitions were found
  return 0 if ($FoundPartitions==0);

  print "*** Partition table ***\n";
  for $Part (1..4)
    {
    print "Partition entry $Part\n";
    print "Bootable: $Partition[$Part][$BOOTABLE]\n";
    print "Partition type: $Partition[$Part][$PARTITION_TYPE] = $Partition[$Part][$PARTITION_NAME]\n";
    print "Start cylinder: $Partition[$Part][$START_CYLINDER]\n";
    print "Start head: $Partition[$Part][$START_HEAD]\n";
    print "Start sector: $Partition[$Part][$START_SECTOR]\n";
    print "Ending cylinder: $Partition[$Part][$END_CYLINDER]\n";
    print "Ending head: $Partition[$Part][$END_HEAD]\n";
    print "Ending sector: $Partition[$Part][$END_SECTOR]\n";
    print "Relative start sector: $Partition[$Part][$REL_START_SECTOR]\n";
    print "Total sectors: $Partition[$Part][$TOTAL_SECTORS]\n";
    print "\n";
    }

  # Change partition if required
  $FirstPartition=$PreferredPartition if ($PreferredPartition!=-1 && $Partition[$PreferredPartition][$PARTITION_NAME] ne "Unknown");

  # Skip if no partitions found
  return 0 if ($FirstPartition==-1);

  # Seek to partition boot record
  print "Reading partition $FirstPartition";
  print " at sector ",$Partition[$FirstPartition][$REL_START_SECTOR] if ($VerboseClusters);
  print "\n\n";
  $PartitionStartAddr=$Partition[$FirstPartition][$REL_START_SECTOR]*$BytesPerSector;
  &MySeek($PartitionStartAddr);
  return $FoundPartitions;
  }

# Filehandling abstractions
sub MyRead
  {
  my $Len=shift(@_);
  my $Buf;
  ReadFile($hIN,$Buf,$Len,[],[]) if ($UseWin32ApiFileHandling);
  read(IN,$Buf,$Len) if (!$UseWin32ApiFileHandling);
  return $Buf;
  }
sub MySeek
  {
  my $Addr=shift(@_);
  SetFilePointer($hIN,$Addr,[],FILE_BEGIN()) if ($UseWin32ApiFileHandling);
  seek(IN,$Addr,0) if (!$UseWin32ApiFileHandling);
  }
sub MyTell
  {
  my $Ret;
  $Ret=SetFilePointer($hIN,0,[],FILE_CURRENT()) if ($UseWin32ApiFileHandling);
  $Ret=tell(IN) if (!$UseWin32ApiFileHandling);
  return $Ret;
  }
sub MyClose
  {
  CloseHandle($hIN) if ($UseWin32ApiFileHandling);
  close(IN) if (!$UseWin32ApiFileHandling);
  }