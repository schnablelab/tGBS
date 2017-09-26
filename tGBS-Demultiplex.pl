#!/usr/bin/perl -w

# Description: tGBS barcodes demultiplexing script
#
# Schnable Laboratory (schadmin@iastate.edu)
# Iowa State University
# Copyright 2017 - All Rights Reserved
#

use strict;
use warnings;
use FileHandle;
use Getopt::Long;
use Time::Local;

use constant VERSION => "beta (June, 2017)";
use constant RE_FEATURE => "CATG";
use constant LIMIT => 1000;
use constant BUFFER => 1000000;		# Maximum number of debarcoded reads to keep in memory before writing output
use constant true => 1;
use constant false => 0;

# remove leading and trailing white space characters from string
sub trim {
    my $str = $_[0];
    
    if (defined($str)) {
        $str =~ s/^(\s+|\t+)//g;
        $str =~ s/(\s+|\t+)$//g;
    } # End of if statement

    return $str;
} # End of sub trim

# Formats the parametric number and adds commas every thousand, millions, etc
sub formatNumber {
    local($_) = shift;
    1 while s/^(-?\d+)(\d{3})/$1,$2/;

    return $_;  
} # End of sub formatNumber

# Given total seconds signifying the module run-time, format it in hh:mm:ss format
sub formatTime {
    my $totaltime = $_[0];
    my $str;

    $str = sprintf("%02d:", $totaltime / 3600);    # total hours
    $totaltime = $totaltime % 3600;
    $str .= sprintf("%02d:", $totaltime / 60);      # total minutes
    $totaltime = $totaltime % 60; 
    $str .= sprintf("%02d", $totaltime);            # total sconds

    return $str;
} # End of sub formatTime

# Format the progress string
sub printProgress {
    my ($old_progress, $new_progress) = @_; 
    my $end_of_line = false;

    if ($new_progress =~ m/\n$/) {
        $end_of_line = true;
        chomp($new_progress);
    } # End of if statement

    if (defined($old_progress)) {
        print STDERR sprintf("%s", "\b" x length($old_progress));
    } # End of if statemnet

    print STDERR sprintf("%s", $new_progress);

    # adjusting/padding text with white-space
    if (defined($old_progress) && length($new_progress) < length($old_progress)) {
        my $times = length($old_progress) - length($new_progress);
        if ($times > 0) {
            print STDERR sprintf("%s", " " x $times);
            print STDERR sprintf("%s", "\b" x $times);
        } # end of if statement
    } # End of if statement

    if ($end_of_line) {
        print STDERR sprintf("\n");
        $new_progress .= "\n";
    } # End of if statement

    return $new_progress;
} # end of sub printProgress

my ($barcodesFile, $fastqFile, $outDir);

my $result = &GetOptions("barcodes|b=s{1}" => \$barcodesFile,
                         "fastq|f=s{1}" => \$fastqFile,
						 "output|o=s{1}" => \$outDir);

unless ($result && defined($barcodesFile) && defined($fastqFile) && defined($outDir)) {
	print STDERR sprintf("\n");
	print STDERR sprintf("*** INCOMPLETE NUMBER OF ARGUMENTS ***\n");
	print STDERR sprintf("\n");
	print STDERR sprintf("perl %s --barcodes <barcodes file> --fastq <sequences file> -output <output dir>\n", $0);
	print STDERR sprintf("\n");
	print STDERR sprintf("WHERE:\n");
	print STDERR sprintf("   --barcodes|-b <barcodes file>      : Path to plain text file containing sample and barcode information\n");
	print STDERR sprintf("                                        separated by a tab character between columns. Column as\n");
	print STDERR sprintf("                                        follows:\n");
	print STDERR sprintf("                                           Col 1: Sample Name\n");
	print STDERR sprintf("                                           Col 2: Barcode Sequence\n");
	print STDERR sprintf("   --fastq|-f <sequences file>        : Path to FASTQ file containing sequence data\n");
	print STDERR sprintf("   --output|-o <output dir>           : Path to a directory where demultiplexed reads will be saved\n");
	print STDERR sprintf("\n");
	print STDERR sprintf("VERSION: %s\n", VERSION);
	print STDERR sprintf("\n");
	exit();
} # end of unless statement

# Start time of the execution of this script
my $startTime = timelocal(localtime(time));

my $logFH = new FileHandle();

# Checking for output directory
if (-d $outDir) {
	my $answer;

	do {
		print STDERR sprintf("\n");
		print STDERR sprintf("WARNING: output directory '%s' already exists.\n", $outDir);
		print STDERR sprintf("\n");
		print STDERR sprintf("Would you like to delete the contents of that directory\n");
		print STDERR sprintf("and continue executing? (Y/N): ");

		$answer = <>;
		$answer = &trim($answer);
	} while ($answer !~ m/^(Y|N|yes|no)$/i);

	if ($answer =~ m/^(Y|yes)$/i) {		# Delete contents
		$logFH = new FileHandle();
		open ($logFH, sprintf(">%s.log", $outDir)) or die("Cannot create log file\n");
		print $logFH sprintf("# %s\n", scalar(localtime(time)));
		print $logFH sprintf("\n");
		print $logFH sprintf("# Barcodes: %s\n", $barcodesFile);
		print $logFH sprintf("# Fastq: %s\n", $fastqFile);
		print $logFH sprintf("# Output Dir: %s\n", $outDir);
		print $logFH sprintf("\n");
		print STDERR sprintf("\n");
		print $logFH sprintf(" o Removing existing '%s' directory ... ", $outDir);
		print STDERR sprintf(" o Removing existing '%s' directory ... ", $outDir);

		my $command = sprintf("rm -rf %s", $outDir);
		system($command);

		if ($? == -1) {
			print $logFH sprintf("FAILED\n");
			print STDERR sprintf("FAILED\n");
			exit();
		} # end of if statement
		else {
			print $logFH sprintf("DONE\n");
			print STDERR sprintf("DONE\n");
		} # end of else statement
	} # end of if statement
	else {
		print STDERR sprintf("\n");
		exit();
	} # end of else statement
} # end of if statement
else {
	$logFH = new FileHandle();
	open ($logFH, sprintf(">%s.log", $outDir)) or die("Cannot create log file\n");
	print $logFH sprintf("# %s\n", scalar(localtime(time)));
	print $logFH sprintf("\n");
	print $logFH sprintf("# Barcodes: %s\n", $barcodesFile);
	print $logFH sprintf("# Fastq: %s\n", $fastqFile);
	print $logFH sprintf("# Output Dir: %s\n", $outDir);
	print $logFH sprintf("\n");
	print STDERR sprintf("\n");
} # end of else statement

print $logFH sprintf(" o Creating output directory '%s' ... ", $outDir);
print STDERR sprintf(" o Creating output directory '%s' ... ", $outDir);

if (-d $outDir || -e $outDir) {
	print $logFH sprintf("FAILED\n");
	print STDERR sprintf("FAILED\n");
	print $logFH sprintf("\n");
	print STDERR sprintf("\n");
	print $logFH sprintf("ERROR: It seems there is a directory or file named the same way as the specified output directory\n");
	print STDERR sprintf("ERROR: It seems there is a directory or file named the same way as the specified output directory\n");
	print $logFH sprintf("\n");
	print STDERR sprintf("\n");
	exit();
} # end of if statatmenet
else {	# Try to make directory
	# Create new output directory
	my $command = sprintf("mkdir -p \"%s\"", $outDir);
	system($command);

	if ($? == -1) {
		print $logFH sprintf("FAILED\n");
		print STDERR sprintf("FAILED\n");
		print $logFH sprintf("\n");
		print STDERR sprintf("\n");
		print $logFH sprintf("ERROR: Unable to create output directory\n");
		print STDERR sprintf("ERROR: Unable to create output directory\n");
		print $logFH sprintf("\n");
		print STDERR sprintf("\n");
		print $logFH sprintf("FAILED\n");
		print STDERR sprintf("FAILED\n");
		exit();
	} # end of if statement
	else {
		print $logFH sprintf("DONE\n");
		print STDERR sprintf("DONE\n");
	} # end of else statement
} # end of else statement

# Reading indexes file
my %indexes;
my $indexesCount = 0;

print $logFH sprintf(" o Reading indexes file '%s' ... ", $barcodesFile);
print STDERR sprintf(" o Reading indexes file '%s' ... ", $barcodesFile);
my $fh = new FileHandle();
open ($fh, $barcodesFile) or die("Cannot open indexes file\n");
while (<$fh>) {
	chomp;
	my ($sample, $index) = split(/\t/, $_);

	# Remove leading and trailing white space characters
	$sample = &trim($sample);
	$index = uc(&trim($index));

	my $bcLength = length($index);

	# Saving
	if (!exists $indexes{$bcLength}->{$index}) {
		$indexes{$bcLength}->{$index}->{"sample"} = $sample;
		$indexes{$bcLength}->{$index}->{"barcode"} = $index;
		$indexes{$bcLength}->{$index}->{"poolID"} = sprintf("%s.%s", $sample, $index);
		$indexesCount++;
	} # end of if statement
	else {
		print $logFH sprintf("ERROR\n");
		print $logFH sprintf("\n");
		print $logFH sprintf("ERROR: Duplicate barcode '%s' was found\n", $index);
		print $logFH sprintf("\n");
		close ($logFH);

		print STDERR sprintf("ERROR\n");
		print STDERR sprintf("\n");
		print STDERR sprintf("ERROR: Duplicate barcode '%s' was found\n", $index);
		print STDERR sprintf("\n");
		exit();
	} # End of else statement
} # end of while loop
close ($fh);

print $logFH sprintf("DONE [ %s indexes ]\n", &formatNumber($indexesCount));
print STDERR sprintf("DONE [ %s indexes ]\n", &formatNumber($indexesCount));

my @diffLengths = sort {$b <=> $a} keys %indexes;
my $dummy = length($diffLengths[0]);
foreach my $l (@diffLengths) {
	my $subtotal = scalar(keys %{ $indexes{$l} });
	print $logFH sprintf("     + Length %\Q$dummy\Es bp indexes = %s / %s = %2.1f%%\n",
	                     &formatNumber($l), &formatNumber($subtotal), &formatNumber($indexesCount),
						 $indexesCount != 0 ? ($subtotal / $indexesCount) * 100 : 0);
	print STDERR sprintf("     + Length %\Q$dummy\Es bp indexes = %s / %s = %2.1f%%\n",
	                     &formatNumber($l), &formatNumber($subtotal), &formatNumber($indexesCount),
						 $indexesCount != 0 ? ($subtotal / $indexesCount) * 100 : 0);
} # end of foreach statement

# Check whether program was able to read barcodes from the specified index file
if ($indexesCount == 0) {
	print $logFH sprintf("\n");
	print $logFH sprintf("ERROR: Program cannot continue because no barcodes were found in the specified index file\n");
	print $logFH sprintf("\n");
	close ($logFH);

	print STDERR sprintf("\n");
	print STDERR sprintf("ERROR: Program cannot continue because no barcodes were found in the specified index file\n");
	print STDERR sprintf("\n");
	exit();
} # end of if statement

# Reading sequences and searching for barcodes
my $progress = "Please Wait";

print $logFH sprintf(" o Searching indexes ... ");
print STDERR sprintf(" o Searching indexes ... %s", $progress);

my %pool;		# Pool of reads per barcode
my $poolID;
my $poolCount = 0;
my $sequencesCount = 0;
my $demultiplexedCount = 0;
my ($seq_desc, $seq, $qual_desc, $qual);
my $found = false;
my @barcodes;
my $search;

$fh = new FileHandle();
open ($fh, $fastqFile) or die("Cannot open fastq file\n");

while (!eof($fh)) {
	$seq_desc = <$fh>;		chomp($seq_desc);
	$seq = <$fh>;			chomp($seq);
	$qual_desc = <$fh>;		chomp($qual_desc);
	$qual = <$fh>;			chomp($qual);
	$sequencesCount++;

	$seq = uc($seq);		# Convert sequences to uppercase

	$found = false;
	for (my $i=0; $i < scalar(@diffLengths) && !$found; $i++) {
		$search = substr($seq, 0, $diffLengths[$i]);
	
		if (exists $indexes{$diffLengths[$i]}->{$search}) {	# Found barcode
			$found = true;

			# Remove barcode 
			$seq = substr($seq, $diffLengths[$i]);
			$qual = substr($qual, $diffLengths[$i]);

			# Check feature
			if (substr($seq, 0, length(RE_FEATURE)) eq RE_FEATURE) {		# Match RE feature, save in pool
				$poolID = $indexes{$diffLengths[$i]}->{$search}->{"poolID"};
				
				if (exists $pool{$poolID}) {
					$pool{$poolID} .= sprintf("\n%s\n%s\n%s\n%s", $seq_desc, $seq, $qual_desc, $qual);
				} # end of if statement
				else {
					$pool{$poolID} = sprintf("%s\n%s\n%s\n%s", $seq_desc, $seq, $qual_desc, $qual);
				} # end of if statemnt

				$poolCount++;
				$demultiplexedCount++;
			} # end of if statement
		} # end of if statement
	} # End of for loop

	if ($poolCount >= BUFFER) {	# dump output
		foreach my $p (keys %pool) {
			my $ofh = new FileHandle();
			my $outFile = sprintf("%s/%s.fastq", $outDir, $p);

			if (-e $outFile) {	# File already exists, need to apped
				open ($ofh, sprintf(">>%s", $outFile)) or die("Cannot open output file in append mode\n");
			} # end of if statement
			else {
				open ($ofh, sprintf(">%s", $outFile)) or die("Cannot open output file\n");
			} # end of else statement

			print $ofh sprintf("%s\n", $pool{$p});
			close ($ofh);

			delete $pool{$p};
		} # end of for each statement
		
		$poolCount = 0;
	} # end of if statement

	if ($sequencesCount % LIMIT == 0) {
		$progress = &printProgress($progress, sprintf("%s reads processed so far",
		                                              &formatNumber($sequencesCount)));
	} # end of if statement
} # end of while loop
close ($fh);
	
# The very last batch
foreach my $p (keys %pool) {
	my $ofh = new FileHandle();
	my $outFile = sprintf("%s/%s.fastq", $outDir, $p);

	if (-e $outFile) {	# File already exists, need to apped
		open ($ofh, sprintf(">>%s", $outFile)) or die("Cannot open output file in append mode\n");
	} # end of if statement
	else {
		open ($ofh, sprintf(">%s", $outFile)) or die("Cannot open output file\n");
	} # end of else statement

	print $ofh sprintf("%s\n", $pool{$p});
	close ($ofh);

	delete $pool{$p};
} # end of for each statement

$progress = &printProgress($progress, sprintf("DONE [ %s / %s = %2.1f%% demultiplexed ]\n",
                                              &formatNumber($demultiplexedCount),
											  &formatNumber($sequencesCount),
											  $sequencesCount != 0 ? ($demultiplexedCount / $sequencesCount) * 100 : 0));
print $logFH sprintf("DONE [ %s / %s = %2.1f%% demultiplexed ]\n",
                     &formatNumber($demultiplexedCount),
					 &formatNumber($sequencesCount),
					 $sequencesCount != 0 ? ($demultiplexedCount / $sequencesCount) * 100 : 0);

my $endTime = timelocal(localtime(time));

print STDERR sprintf(" o Total Run-Time: %s\n", &formatTime($endTime - $startTime));
print $logFH sprintf(" o Total Run-Time: %s\n", &formatTime($endTime - $startTime));


print STDERR sprintf("\n");
print $logFH sprintf("\n");
close ($logFH);
