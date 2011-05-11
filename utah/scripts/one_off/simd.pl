#!/usr/bin/perl -w
use strict; 
use File::stat;

#######################################################################

my $MIN_PROGRAM_SIZE = 8000;
my $EXTRA_OPTIONS = "";
my $CSMITH_PATH = $ENV{"CSMITH_PATH"};
my $COMPILER = "icc -w";  

#######################################################################

my $HEADER = "-I${CSMITH_PATH}/runtime";

# find lines in a file that match a given pattern, return line# in the file
sub match_in_file($$\@) {
    my ($fn, $match, $matched) = @_;
    open INF, "<$fn" or die "Can't open $fn\n";
    my $cnt = 0;
    while (my $line = <INF>) {
        chomp $line; 
        if ($line =~ /$match/) {
            push @$matched, $line; 
        }     
        $cnt++;
    }
    close INF; 
    return $cnt;
}

# properly parse the return value from system()
sub runit ($$) {
    my ($cmd, $out) = @_;
    print "before running $cmd\n";
    my $res = system "$cmd";
    my $exit_value  = $? >> 8;
    $exit_value = $? & 127 if ($? & 127);
    return $exit_value;
}

sub yesno ($) {
    (my $opt) = @_;
    if (rand()<0.5) {
	return " --$opt ";
    } else {
	return " --no-$opt ";
    }
}

sub run_tests ($) {
    (my $n_tests) = @_;

    my $accum_percentage = 0;
    my $n_good = 0; 
    my $n_simd = 0;
    my $cfile = "test.c";
    my $ofile = "test.exe";
    while ($n_tests == -1 || $n_good < $n_tests) {
	    system "rm -f $cfile";

	    my $CSMITH_OPTIONS = "";
	    if (rand()<0.5) { $CSMITH_OPTIONS .= " --quiet "; }
	    #$CSMITH_OPTIONS .= yesno ("math64");
	    $CSMITH_OPTIONS .= yesno ("paranoid");
	    $CSMITH_OPTIONS .= yesno ("longlong");
	    $CSMITH_OPTIONS .= yesno ("pointers");
	    $CSMITH_OPTIONS .= yesno ("arrays");
	    $CSMITH_OPTIONS .= yesno ("jumps");
	    $CSMITH_OPTIONS .= yesno ("consts");
	    $CSMITH_OPTIONS .= yesno ("volatiles");
	    #$CSMITH_OPTIONS .= yesno ("volatile-pointers");
	    $CSMITH_OPTIONS .= yesno ("checksum");
	    $CSMITH_OPTIONS .= yesno ("divs");
	    $CSMITH_OPTIONS .= yesno ("muls");

	    my $cmd = "$CSMITH_PATH/src/csmith $CSMITH_OPTIONS $EXTRA_OPTIONS --output $cfile";
	    my $res = runit ($cmd, "csmith.out"); 
	    if ($res != 0 || !(-f $cfile) ) {
	        print "Failed to generate program: $cmd\n";
	        exit (-1);
	    } 
	    my $filesize = stat($cfile)->size;
	    if ($filesize < $MIN_PROGRAM_SIZE) {
		    next;
	    }
	    system "grep Seed $cfile";
	    system "ls -l $cfile";
	    system "rm -f $ofile";

        # these flags works for gcc and icc
	    my $cmd2 = "$COMPILER $cfile $HEADER -O3 -mssse3 -S -o $ofile";
	    $res = runit ($cmd2, "csmith.out"); 
	    if ($res!=0 || !(-f $ofile)) {
		    print "Failed to compile program generated by $cmd\n";
		    #exit (-1);
	    }	    
                   
        my @simd_instructions; 
        # look for simd instructions (integer operations only) such as padd[x], psub[x], etc, but not including pxor, 
        # which is commonly used to create a bunch of zeros. 
        # Also use line number as the approximation of the instruction number
        my $instr_cnt = match_in_file($ofile,  "^(\\s+p[a-s][a-z]+.*%xmm)", @simd_instructions);
        if (scalar @simd_instructions) {
            my $percentage = @simd_instructions / $instr_cnt * 100;
            print "found SIMD instruction: $simd_instructions[0], simd accounts for $percentage% of total instruction\n";
            $accum_percentage += $percentage;
            $n_simd++;
        }  
	    $n_good++;
	    print "test case $n_good\n";
    }
    my $avg_percentage = $accum_percentage / $n_good;
    print "average SIMD percentage: $avg_percentage ($n_simd out of $n_good programs)\n";
}

########################### main ##################################

if (!(-f "$CSMITH_PATH/runtime/csmith.h")) {
    print "Please point the environment variable CSMITH_PATH to the top-level\n";
    print "directory of your Csmith tree before running this script.";
    exit(-1);
}

my $cnt = $ARGV[0];
$cnt = -1 if (!defined($cnt));
$EXTRA_OPTIONS = $ARGV[1] if (@ARGV==2);
print "extra = $EXTRA_OPTIONS\n";
run_tests ($cnt);


##################################################################
