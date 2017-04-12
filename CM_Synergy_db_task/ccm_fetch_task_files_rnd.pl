################################################################################################
# Created by Tommi Paananen 01.09.2006
#			
#
# This script copies task object(S) from Synergy DB to local drive.
# The script also creates folder structure for objects if possible in case that folder structure exists or task objects are not in integrate state.
#
# Version history:
#	0.1 version 04.05.2006  - getting task-id content to disk, but not folder structure...
# 0.2 version 1.10.2006		- find out how to get task-id content plus folder structure to disk  
#	0.3 version 3.10.2006		- taskfolder handling added..
# 0.4 version 20.10.2006 	- Outputfolder option added and two bugs corrected: handle correct way files with same name, but different location.
# 0.5 version 30.10.2007  - corrections for handling task(s) which object(s) are in integrate state and lot of change for script structure
# 06. version 20.02.2008 - corrections for handlig cases when objects has not predecessor or successor version...
#
################################################################################################

use Cwd;
use strict;
use Getopt::Long;

my ($taskfolder_id,$task_id,$outputfolder,$dir,$base_dir, $taskfolder_on, $inputfile, $nopath) = "";
my ($owner,$status,$inst,$type,$version,$objectname,$release,$project) = "";
my $taskfile = "my_taskobjects.txt";
my $curr_dir = getcwd();
my $home_dir = getcwd();

#Check that all parameters are given...
&GetOptions ('taskfolder|f=s' => \$taskfolder_id, 'inputfile|i=s' => \$inputfile, 'task|t=s' => \$task_id, 'outputfolder|o=s' => \$outputfolder) || die "Wrong syntax !! \n";
unless ( $taskfolder_id or $task_id or $outputfolder)
	{
	usage();
	}

#Creates outputfolder and makes some cleaning...
#if (-e "$taskfolder_id"){system("rmdir /q /s ");}
#if (-e  "$task_id"){system("rmdir /q /s .");}

#Check what options have been given.
if ($outputfolder ne "")		#spesific folder name is given
{
	#system("rmdir /q /s $outputfolder");
	system("mkdir $outputfolder");
	chdir($outputfolder);
	$curr_dir = getcwd();
	$base_dir = getcwd();
		
	if ($taskfolder_id ne ""){
		system("ccm folder -show objects $taskfolder_id -u > $taskfile");
		$taskfolder_on = "tf";
		main();
	}
	elsif ($task_id ne ""){
		#system("ccm task -sh objects $task_id -u -f \"%fullname/%status/%owner/%release/%project\" > $taskfile");
		system("ccm task -sh objects $task_id -u > $taskfile");
		main();
	}
	elsif ($inputfile ne ""){
		#system("xcopy /Y $home_dir\\$inputfile $curr_dir\\$inputfile");
		open(TMP, "$home_dir\\$inputfile") || die "Cannot open $inputfile: $!";
		while (<TMP>){
			chomp;
			next if ($_ =~ /^$/);
			$task_id = $_;
			system("ccm task -sh objects $task_id -u > $taskfile");
			main();
		}
		close(TMP);
	}
	else {print "\ntask_id or task_folder_id is missing!\n";}
}
else 	#output folder name is not given
{
	if ($taskfolder_id ne ""){
		if (! -e "$taskfolder_id") {system("mkdir $taskfolder_id");}
		else {system("rmdir /q /s $taskfolder_id\\.");}
		chdir($taskfolder_id);
		$curr_dir = getcwd();
		$base_dir = getcwd();
		system("ccm folder -show objects $taskfolder_id -u > $taskfile");
		$taskfolder_on = "tf";
		main();
	}
	elsif ($task_id ne ""){
		#if (! -e "$task_id") {
			system("rmdir /q /s $task_id\\.");
			system("mkdir $task_id");
		#}
		#else {
			
		#}
		chdir($task_id);
		$curr_dir = getcwd();
		system("ccm task -sh objects $task_id -u > $taskfile");
		main();
	}
	else { print "\ntask_id or task_folder_id is missing!\n";}
}

##############################################################################################
#	MAIN FUNCTION: Finding out task objects 
##############################################################################################

sub main ()
{
	#opens $taskfile and reads file line by line.
	open(TEMP1,"$taskfile") || die "Cannot open $taskfile: $!";    
	while (<TEMP1>){
		next if ($_ =~ /^$/);
		($objectname,$version,$type,$inst,$status,$owner,$nopath) = "";
		
		# if taskfolder option is given, do this if statement...
		if ($taskfolder_on eq "tf")
		{
			# wraps task folder id...
			$_ =~ /\ (\w+)(#)(\w+)/;
			$task_id = "$1$2$3";
			if ($outputfolder eq ""){
				chdir($base_dir);
				if (! -e "$task_id"){	system("mkdir $task_id");}
				chdir($task_id);
				$curr_dir = getcwd();
			}
		}
		(my $objetname_and_version, $type, my $rest_of_task_info)= split(/:/);
		($objectname, $version) = split(/-/,$objetname_and_version);
		split(/\s+/,$rest_of_task_info);
		$inst = $_[0];
		$status = $_[1];
		$owner = $_[2];
		if ($type eq "dir"){next;}
		else { ccm_finduse($objectname, $inst, $owner, $status, $version, $type);}
		next;
	}
	close(TEMP1);
}
system("del /q /f my_taskobjects.txt");
system("del /q /f ccm_finduse_results.txt");
system("del /q /f ccm_task_show.txt");
exit;

##############################################################################################
#	CCM FINDUSE starts here
##############################################################################################

sub ccm_finduse ()
{
	my $objectname = $_[0];
	my $inst = $_[1]; 
	my $owner = $_[2];
	my $status = $_[3]; 
	my $version = $_[4];
	my $type = $_[5];
	
	my $retu;
	$curr_dir = cwd();
	system("ccm finduse /n $objectname /i $inst /o $owner /v $version > ccm_finduse_results.txt");
	open(CFR1, "ccm_finduse_results.txt") || die "cannot open file: ccm_finduse_results.txt $!";
	while(<CFR1>){
		next if ($_ =~ /^$/);
		my $DLN = 2;
		my $line =  "";
		$. = 0;
		do { 
			$line = <CFR1> 
		}
		until $. == $DLN || eof;		
		if ($line =~ /Object is not used in scope/){
			my @table2 = &ccm_find_path($objectname, $inst, $owner, $status, $version, $type);
			foreach (@table2){
				#$_ =~ s/^\s+//;
				next if (/^$/);
				next if (/\s+(\w+)\s+(\w+)/);
				$line = $_;
			}
		}
		$dir = &processing_path($line);
		$retu = &ccm_cat($objectname, $inst, $dir);
		if ($retu eq "done") {
				last;
			}
		}
	close(CFR1);
}


########################################################################################
# CCM CAT starts here
########################################################################################
sub ccm_cat ()
{
	my $objectname = $_[0];
	my $inst = $_[1];
	my $dir = $_[2]; 
	my $cat_status = "";
	system("ccm task -sh objects $task_id -u -f %name-%version:%type:%instance > ccm_task_show.txt");
	open(TEMP3, "ccm_task_show.txt") || die "cannot open file: ccm_task_show.txt $!";
	while(<TEMP3>)
	{
		next if ($_ =~ /^$/);
		(my $s1, my $s2, my $s3)= split(/:/);
		(my $s4, my $s5) = split(/-/,$s1);
		(my $s6, my $s7) = split(/\s+/,$s3);
		chomp($s6);
		chomp($s4);
		if (($s4 eq $objectname) and ($inst eq $s6)){
			$_ =~ s/^\s+//;
			$_ =~ s/\s+$//;
			print "\n\n*******************************************************************************\n";
			print "objectname......: $objectname\n";
			print "longobjectname..: $_\n";
			print "TASK_ID.........: $task_id\n";
			if ($nopath eq 1){
				print "\nCould not found directory for $objectname \n";
				print "\nCopying file to: $dir\n";
				if ($objectname =~ /(\w+)( )(.*)(.)(\w+)/)
				{
					#system("ccm cat \"$_\" >> $dir\\\"$objectname-$version-$inst\" 2>&1");
					system("ccm cat \"$_\" >> $dir\\\"$objectname\" 2>&1");
					#system("ccm cat \"$_\" >> $dir\\\"$_\" 2>&1");
					$cat_status = "done";
					last;  
				} 
				#system("ccm cat $_ >> $dir\\$objectname-$version-$inst 2>&1");
				system("ccm cat $_ >> $dir\\$objectname 2>&1");
				$cat_status = "done";
				last;							
			} 
			else {
				print "Object directory: $dir\n";
				if (! -e "$dir"){
				 system("mkdir $dir");
				}
				if ($objectname =~ /(\w+)( )(.*)(.)(\w+)/){
					system("ccm cat \"$_\" >> $dir\\\"$objectname\" 2>&1");
					$cat_status = "done";
					last;
				}
				else { 
				system("ccm cat $_ >> $dir\\$objectname 2>&1");
				$cat_status = "done";
				last;
				}
			}	
		}
		next until ($_ =~ /^$/);
		last;
	}
	close(TEMP3);
	$cat_status = "done";
	return($cat_status);
}

####################################################################################################
#! DESCRIPTON : Creates folder structure information for task objects...
#! PARAMETER	: Value of ccm_finduse process
#! RETURN			: task object(s) path(s)  
####################################################################################################
sub processing_path(){
		my $temp_dir = "";
		(my $tsplit1, my $tsplit2) = split(/@/,$_[0]);
			
		split(/-/,$tsplit1);
		my $lastmatch = rindex($_[0],"\\");
		if ($lastmatch < 0){
			$temp_dir = "$curr_dir";
			$nopath = 1;
		}
		else {
			$temp_dir = substr($_[0],1,$lastmatch); # remove extra space from start and remov *.* end
		}
	return $temp_dir;
}

####################################################################################################
#! DESCRIPTON : finds path information for task object 
#! RETURN			: task object(s) path(s)  
####################################################################################################
sub ccm_find_path(){
	
	my $objectname = $_[0];
	my $inst = $_[1]; 
	my $owner = $_[2];
	my $status = $_[3]; 
	my $version = $_[4];
	my $type = $_[5];
	my @dupe_table;
	my $data;
	my $fpath;
	my $flast_predecessor;
	my @search_data;
	
	my ($fstatus,$fresult) = "";
	my $fsearch = "$objectname-$version:$type:$inst";
	$fresult = $fsearch;	
	my $query_result;
	
	#ccm query "is_predecessor_of('BMBubbleManager.cpp-ou1s60rt#161.1.10.1.1:c++:tr_calyp#1')" -f %objectname
	system("ccm query \"is_predecessor_of('$fsearch')\" -f %objectname > $query_result");
	#system("ccm finduse $query_result");
	exit;
	
	system("ccm history /f \"Object: %objectname:%task:%status\" $objectname-$version:$type:$inst > ccm_history.txt");
		
	while ($fstatus ne "released" or $fpath eq "No")	
	#for ($fsearch;$fstatus ne "released";$fsearch = "$_[0]")
	{
		#next if ($fresult eq "");
		$data = &read_file_to_string("ccm_history.txt");
		@search_data = &search($fsearch, $data);
		
		my $fstatus = shift(@search_data);
		my $fpredecessors = shift(@search_data);
		my $fsuccessors = shift(@search_data);
		
		
		# check if object is not in integrate state
		if ($fstatus ne "released"){
			#if only one version of object exist do this
			if ($fpredecessors eq "" and $fsuccessors eq ""){   
				$fpath = "No";
				last;
			}
			# check if object has not any predecessor object but successor object exists and save last predecessor point
			elsif ($fpredecessors eq "" and $fsuccessors ne ""){							
				#if several successors then split then and go successors trough one by one...
				split(/\s+/,$fsuccessors);
				foreach my $jemma (@_){
					if ($fresult eq $_){
					next;
					}
				$fsearch = $fsuccessors;
				$flast_predecessor = $fsuccessors;
				next;
				}	 
			}
			# check if object last_predecessor matched with current predecessor and next successor exists
			elsif ($flast_predecessor eq $fpredecessors and $fsuccessors ne ""){
				$fsearch = $fsuccessors;
				#if history tree ends to object which is integrated state then last
				unless ($fsuccessors eq "") {
					$fpath = "No";
					last;
				}  
				next;
			} 
			#do this if status is integrate and predecessors exist
			#save last predecessors to fresult 
			else {
				$fresult = $fpredecessors;   
				$fsearch = $fpredecessors;
				next;
			}
		}
		#if object state is released, do then this "else" statement
		else {
			split(/:/,$fsearch);
			my $finst = $_[2];
			my $ftype = $_[1];
			my $fname = $_[0];
			split(/-/,$fname);
			$fname = $_[0];
			my $fversion = $_[1];
			#finding task object "path" information...
			system ("ccm finduse /n $fname /v $fversion /t $ftype /i $finst > hubaa.txt");
			#reading hubaa.txt file content to array
			my @hubaa = &read_file_to_table("hubaa.txt");
			#prosessing table values to find out duplicate stuff... 
			@dupe_table = &remove_dupe(@hubaa);
			last;
		}
	}
	system("del /q /f ccm_history.txt");
	system("del /q /f hubaa.txt");
	return (@dupe_table);
	#return $line2;
}

#############################################################################################
#! DESCRIPTION : Get a value of a "successor" element.
#! PARAMETER   : Key (Name of the "Object" element)
#! PARAMETER   : Data (Data string)
#! RETURN      : Value of the corresponding "successors" element
############################################################################################# 
sub search(){
	
	my $ssearch = $_[0];
	my $sdata = $_[1];
	my @stable;
	$sdata =~ s/\n//g;			#removes line changes from data string
	$sdata =~ s/\*/\n/g;		#removes * marks from data string
	while (($sdata =~ /Object:\s+${ssearch}:(.*):(.*)\s+Predecessors:\s*(.*)\s+Successors:\s*(.*)/g) or ($sdata =~ /Object:\s+${ssearch}:(.*):(.*)\s+Predecessors:\s*(.*)\s+Successors:(.*)/g))  {
		my $sstatus = $2;
		my $spredecessors = $3;
		my $ssuccessors = $4;
		push(@stable, $sstatus,$spredecessors,$ssuccessors);
		return @stable;
	}		
}

#############################################################################################
#! DESCRIPTION : Read a file to a string.
#! PARAMETER   : File path.
#! RETURN      : Document string
#############################################################################################
sub read_file_to_string(){
	open( FH, "<$_[0]" );
	my $dataString = join ' ', <FH>;
	close( FH );
	return $dataString;
}

##############################################################################
#! DESCRIPTION : Read a file to a table
#! PARAMETER   : File path.
#! RETURN      : Document string as table value @_
##############################################################################
sub read_file_to_table(){
	open(FH, "<$_[0]" );
	my @table1 = <FH>;
	close( FH );
	return @table1;
}

##############################################################################
#! DESCRIPTION : Removes duplicates lines from hubaat.txt file
#! PARAMETER   : @hubaa array
#! RETURN      : Array of not duplicate lines
##############################################################################
sub remove_dupe(){
	my %seen = ();
	my @unig = ();
	my @dupe = @_;
	foreach my $item (@dupe){
		next if ($item =~ /(\w+)\s+(\w+)\s+/);  #next if line contains empty spaces 
		my $value1 = $item;
		split(/@/,$item);
		push(@unig, "$value1") unless $seen{$_[0]}++;
	}
	return @unig;
}

###############################################################################
#! DESCRIPTON : Instructions how to use this script...
#! PARAMETER	: none
#! RETURN			: exit
##############################################################################
sub usage () {
	
	print "\n\n**************************************************************\n\n";
	print "USAGE:\n\n";
	print "To get task files (objects):\n";
	print "\t\tperl ccm_fetch_tasks_files.pl -t <TASK_ID>\n\n";
	print "To get task files (objects) to spesific folder:\n";
	print "\t\tperl ccm_fetch_tasks_files.pl -t <TASK_ID> -o <OUTPUT_FOLDER_NAME>\n\n";
	print "To get task_folders files (objects):\n";
	print "\t\tperl ccm_fetch_tasks_files.pl -f <TASKFOLDER_ID>\n\n";
	print "To get task folders files (objects) to spesific folder:\n";
	print "\t\tperl ccm_fetch_tasks_files.pl -f <TASKFOLDER> -o <OUTPUT_FOLDER_NAME>\n\n";
	exit 1;
}