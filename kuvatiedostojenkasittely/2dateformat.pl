#2dateformat.pl scirpt by Tommi Paananen 21.08.2012
#
#Script renames inmage and video files from IMG_* or MOV_* format 
#to year-month-day-flownumber.jpg or year-month-day-flownumber.mov format
#
#

use File::Find;
use File::Copy;
use File::Path;
use File::Basename;
use File::Find;
use File::stat;
use Time::localtime;

my $renamedfile;
my $untouchedfile;
my $totalfile;
my $totalfolder;

my @folders = "";
my $path = shift;

#this part reads directory and its subdirs to @found table
find(\&folderprocess, $path);

foreach my $foo (@folders){
	if (-f $foo){
		$totalfile++;
		renaming_file($foo);
	}
	if (-d $foo){
		$path = $foo;
		$totalfolder++;
		sleep 2;
		next;
	}	
}
print "Total amount of image and video files: $totalfile \n";
print "Total amount of folders: $totalfolder \n";
print "Total amount of untouched files: $untouchedfile \n";
print "Total amount of renamed files: $renamedfile";

#######sub##############sub##############sub##############sub##############sub##############sub#######


sub folderprocess {
	push(@folders, $File::Find::name);
}

sub renaming_file(){
	  my $full_file_name = $_[0];	
  	my $date_string = ctime(stat($full_file_name)->mtime);
  	print "file $full_file_name updated at $date_string\n";
  	my @date_array = split(/\s+/, $date_string);
  	#print "weekday: $date_array[0]\n";
  	#print "month: $date_array[1]\n"; 
  	#print "date: $date_array[2]\n";
  	#print "time: $date_array[3]\n";
  	#print "year: $date_array[4]\n";
		
		#this part changes month name to number
	 	my %mon2num = (
  		Jan => "01",
  		Feb => "02",
  		Mar => "03",
  		Apr => "04",
  		May => "05",
  		Jun => "06",
  		Jul => "07",
  		Aug => "08",
  		Sep => "09",
  		Oct	=> "10",
  		Nov => "11",
  		Dec => "12"
		);
		#this part changes one digit day format to double digit format
		my %date2num = (
			1 => "01",
			2 => "02",
			3 => "03",
			4 => "04",
			5 => "05",
			6 => "06",
			7 => "07",
			8 => "08",
			9 => "09"
		);
		#this checks date string format....
		my $new_file = "";
		if ($date_array[2] < 10) {
			#print "date array: $date_array[2]\n";
			my $new_date = $date2num{$date_array[2]};
			#print "new_date: $new_date\n ";
			$new_file = "$date_array[4]\-$mon2num{$date_array[1]}\-$new_date";
			#print "new_file: $new_file\n";
		}
		elsif ($date_array[2] >= 10) {
			#print "tuleeko tänne\n";
   		$new_file = "$date_array[4]\-$mon2num{$date_array[1]}\-$date_array[2]";
   		#print "new_file: $new_file\n";
   	}
   	#print "new_file: $new_file\n";
   	#sleep 2;
    my $file_name = fileparse($full_file_name);
    #print "full file_name: $full_file_name\n";
    #print "file_name: $file_name\n";
    #split file_name in two part
    (my $name_part, my $suffix) = split (/\./,$file_name);
    if ($suffix) {
    	#print "name_part: $name_part and suffix: $suffix\n";
    	if ($file_name =~ /(\d{4})(-)(\d+)(-)(\d+)(-)(\d+)(\.)($suffix)/){	#exclude yyyy-mm-dd-zzzz.jpg format
    		$untouchedfile++;
    		next;    
    	}
    	elsif ($name_part =~ /(\d{2})(\d{2})(\d{4})(\d+)/){ #image name: ddmmyyyyxxx.jpg 
			
    		my $new_name = "$new_file\-$4.$suffix";
    		print "new name: $new_name\n\n";
    		if (-e "$path\\$new_name"){
    		 	my $indexnum = counter($counter);
    		 	my $new_name = "$new_file\-$indexnum.$suffix";
    			print "renew name: $new_name\n\n";
    		}
    		$renamedfile++;
    		rename $full_file_name, "$path\\$new_name";
    	}
    	elsif ($name_part =~ /(IMG_)(\d+)/ || $name_part =~ /(DSC_)(\d+)/ || $name_part =~ /(CSC_)(\d+)/ || $name_part =~ /(Img_)(\d+)/ || $name_part =~ /(MVI_)(\d+)/ || $name_part =~ /(DSC_)(\d+)/ ) {  #image name: IMG_xxx.jpg or MVI_xxxx.jpg or Img_xxxx.jpg
     	
    		my $new_name = "$new_file\-$2.$suffix";
    		my $new_suffix = $2;
    		print "new name: $new_name\n\n";
    		if (-e "$path\\$new_name"){
    		 	my $indexnum = counter($counter);
    		 	my $new_name = "$new_file\_$indexnum.$suffix";
    			print "renew name: $new_name\n\n";
    		}
    		$renamedfile++;
    		rename $full_file_name, "$path\\$new_name";
    		
    	}
    	elsif ($file_name =~ /(\d+)(\.)(jpg)/ || $file_name =~ /(\d+)(\.)(JPG)/) {  #image name: xxxx.jpg or xxxx.JPG
     	
    		my $new_name = "$new_file\-$1.$suffix";
    		my $new_suffix = $2;
    		print "new name: $new_name\n\n";
    		if (-e "$path\\$new_name") {
    		 	my $indexnum = counter($counter);
    		 	my $new_name = "$new_file\_$indexnum.$suffix";
    			print "renew name: $new_name\n";
    		}
    		$renamedfile++;
    		rename $full_file_name, "$path\\$new_name";
    	}
    }
}
  
sub counter()
  {
  	my $scrollnumber = "";
  	$counter++;
  	if ($counter  < 10){
    			print "counter: $counter \n";
    			$scrollnumber = "00$counter";
    			print "scrollnumber: $scrollnumber\n";
    		}
    		elsif ($counter < 100) {
    			print "counter: $counter \n";
    			$scrollnumber = "0$counter";
    			print "scrollnumber: $scrollnumber\n";
    		}
    		else {
    			print "counter: $counter \n";
    			$scrollnumber = "$counter";
    			print "scrollnumber: $scrollnumber\n";
    		}
  	return $scrollnumber;
  }