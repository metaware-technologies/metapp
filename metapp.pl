#!/usr/bin/perl
#
# metapp: a generic preprocessor for programs and text files
# Copyright 2010, 2011-2013, 2014 Metaware Technologies (www.metaware.fr).
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
my $_version = q$Revision: 1.52 $;
my $_usage = "usage: metapp [options] source
where:
 source = source file to preprocess
options (default):
 -e Expr: evaluate Perl expression Expr before doing anything else (none)
 -i Initfile: execute initialization file (none)
 -M Macrodirs: directories containing external macros, separated by ':' (.)
 -S Stubdirs: directories containing stubs, separated by ':' (.)
 -m lineMarker: format of line number markers (no line markers)
 -C Copyprefix: prefix for #copy marker lines (drop #copy lines)
 -B Beginmacro: format of begin macro markers (no begin markers)
 -E Endmacro: format of end macro markers (no end markers)
 -p Passregex: pass unchanged lines matching the regex (process all lines)
 -P PreproPrefix: prefix of all preprocessor lines (#)
 -V VarPrefix: prefix for macro variable references in text lines (\$)
 -6 ValueBegin: format of markers before variable values (no value markers)
 -9 ValueEnd: format of markers after variable values (no end value markers)
 -t: Trace each expression before evaluating it (don't)
 -x suffiX: add suffix to stub & macro file names ('')
 -L outlineLength: warn if any output line is longer (no limit)
 -l Leftmargin: ignore first N characters on each input line (don't)
 -r Rightmargin: truncate each input line at N characters (don't)
 -d: the Default value for any parameter \$x/\${x} is \"\$x\"/\"\${x}\" (undef)
 -v: print Version info and exit (don't)
";

use warnings;
use Getopt::Std;

## NB: All global variables must start with an underscore, to avoid
## interference with user macro-variables.

our %_opt; # vector with command-line options
die "$_usage" if !defined(getopts("e:i:S:M:m:B:E:C:p:P:V:6:9:tx:L:l:r:dv", \%_opt));
if($_opt{v}) { print STDERR "metapp $_version\n"; exit 0; }
if($#ARGV < 0 || $#ARGV > 1) { die "$_usage"; }
my ($_file) = @ARGV;

if(defined($_opt{e})) { 
    eval $_opt{e}; 
    die $@ if $@;
}
if(defined($_opt{i})) { require "$_opt{i}"; }
$_opt{S} ||= ".";
$_opt{M} ||= ".";
$_opt{B} ||= undef;
$_opt{m} ||= undef;
$_opt{E} ||= undef;
#$_opt{C} ||= undef; may be ""
$_opt{p} ||= undef;
$_opt{P} ||= "#";
$_opt{V} ||= '$';
$_opt{6} ||= '';
$_opt{9} ||= '';
$_opt{t} ||= 0;
$_opt{x} ||= "";
$_opt{L} ||= undef;
$_opt{l} ||= undef;
$_opt{r} ||= undef;
$_opt{d} ||= 0;

my $_nest = 0; # no of nested input files
my @_stack = (); # stack for macro arguments & #let variables
my @_calls = (); # stack of macro & stub calls (for debugging)
my @_repls = (); # stack of replacement commands for each line
my @_sdirs = split /:/, $_opt{S}; # list of stub directories
my @_mdirs = split /:/, $_opt{M}; # list of macro directories
my $_lblanks; # left margin is substituted with this
$_lblanks = " " x $_opt{l} if defined($_opt{l});
my %cache = (); # keeps the body of already seen macros

&prepro($_file); # preprocess the main file

die "corrupted stack" if $#_stack != -1;
### Program end.


### Subroutines

# Preprocess a given file (either the main file, a macro, or a stub)
# prepro(file [, args])
# where
# - file is the name of the file
# - args are the macro arguments, if the file is a macro
sub prepro {
    my $infile;
    $_[0] =~ s/^\.\///; # simplify curent directory paths
    my $fname = $_[0];
    if(!defined($cache{$fname})) {
	open $infile, $fname or die "$!: $fname";
	my @intbl = <$infile>;
	$cache{$fname} = \@intbl;
	close($infile);
    }
    prepro_tbl($cache{$fname}, @_); # add cached file as first arg
}

sub prepro_tbl {
    my $intbl = shift;
    my $fname = $_[0];
    # begin marker for the file (if required)
    my @args1 = @_; shift @args1;
    my $args1 = join ",", @args1;
    printf "$_opt{B}\n", $fname, $args1 if $_nest && defined($_opt{B}); 
    printf "$_opt{m}\n", 1, $fname if defined($_opt{m}); 
    $_nest++;

    my $lineno = 0; # line number in the current file
    my $block = 0; # true if current prepro line starts a new block
    # Stack of the current values of all pending if/loop conditions
    # (the current line is output if all the pending if/loop
    # conditions are true):
    my @cond=(1); 
    # Stack of the current if precondition.
    # Used for interpreting an if t1/elsif t2/.../else/fi as n exclusive ifs
    # if t1/fi; if !t1&t2/fi; if !t1&!t2&t3/fi; ...
    # with the precondition that none of the previous branches were taken.
    my @precond = ();
    # Stack for the current loop expression (in symbolic form):
    my @loopexpr = ();
#    my @looppos = (); # stack for the current loop start (as a file position)
    my @loopline = (); # stack for the current loop start (as a line number)
    my @locals =(); # names of the local variables of the current macro
    while($lineno <= $#$intbl) {
	$_ = $$intbl[$lineno++];
#	print "$lineno> $_";
	s/^.{$_opt{l}}/$_lblanks/o if defined($_opt{l}); # cut left margin
	s/^(.{$_opt{r}}).*$/$1/o if defined($_opt{r}); # cut right margin
	next if(/^\s*$_opt{P}\#/o); # skip preprocessor comments
	# Fuse continued preprocessor lines, starting with # ending with \
	# and continued with #...
 	while(/^\s*$_opt{P}/o && s/([^\\])\\ *$/$1/) {
 	    chomp;
 	    if($lineno > $#$intbl) { 
		die "$fname:$lineno: found eof, expected continuation line\n";
	    };
 	    my $line = $$intbl[$lineno++];
	    # cut left & right margins:
	    $line =~ s/^.{$_opt{l}}/$_lblanks/o if defined($_opt{l});
	    $line =~ s/^(.{$_opt{r}}).*$/$1/o if defined($_opt{r});
 	    if($line !~ s/^\s*$_opt{P}\.\.\.//o) { 
		die "$fname:$lineno: bad continuation line: $line\n";
	    };
	    $_ .= $line;
 	};
	# Various cases of preprocessor lines:
	if(s/^\s*$_opt{P}if *//o) {
	    if(&and(@cond)) {
		push @cond, (&myeval($_, $fname, $lineno)? 1: 0);
		$block = 1;
	    } else { # don't evaluate the condition, it may contain undef vars
		push @cond, 1; # random value
	    }
	    push @precond, 1; # initial precondition is true
	} elsif(s/^\s*$_opt{P}elsif *//o) {
	    my $lastcond = pop @cond;
	    if(&and(@cond)) {
		$precond[$#precond] &&= !$lastcond;
		push @cond, ($precond[$#precond] &&
			     (&myeval($_, $fname, $lineno)? 1: 0));
		$block = 1;
	    } else { # don't evaluate the condition, it may contain undef vars
		push @cond, 1; # random value
	    }
	} elsif(/^\s*$_opt{P}else */o) {
	    $precond[$#precond] &&= !$cond[$#cond];
	    $cond[$#cond] = $precond[$#precond];
	    $block = 1;
	} elsif(/^\s*$_opt{P}fi */o) {
	    die "$fname:$lineno: unexpected $_opt{P}fi\n" if $#cond < 1;
	    pop @cond;
	    pop @precond;
	    $block = 1;
	} elsif(s/^\s*$_opt{P}while *//o) {
	    my $expr = $_;
	    if(&and(@cond)) {
		push @cond, (&myeval($expr, $fname, $lineno)? 1: 0);
		$block = 1;
	    } else { # don't evaluate the condition, just push a random value
		push @cond, 1; 
	    }
	    push @loopexpr, $expr; # symbolic loop expr, for later re-eval
#	    push @looppos, tell $infile; # store beginning of the loop body
	    push @loopline, $lineno; # store beginning of the loop body
	} elsif(s/^\s*$_opt{P}end *//o) {
	    die "$fname:$lineno: unexpected $_opt{P}end\n" if $#cond < 1;
	    if(&and(@cond) and 
	       &myeval($loopexpr[$#loopexpr], $fname, $lineno)) {
#		seek $infile, $looppos[$#looppos], 0; # loop back
		$lineno = $loopline[$#loopline];
		$block = 1;
	    } else { # continue after the loop
		die "$fname:$lineno: unexpected $_opt{P}end\n" if $#loopexpr < 0;
		pop @loopexpr;
#		pop @looppos;
		pop @loopline;
		die "$fname:$lineno: too many $_opt{P}fi before this $_opt{P}end\n" 
		    if $#cond < 1;
		pop @cond;
		$block = 1;
	    }
	} elsif(&and(@cond)){
	    if(s/^\s*$_opt{P} +//o) { # the prepro line is a Perl statement
		&myeval($_, $fname, $lineno, @_);
		$block = 1;
	    } elsif(s/^\s*$_opt{P}let +//o) { #let $var=expr
		die "$fname:$lineno: invalid #let\n" 
		    if !s/(\$\w+) *= *(\S.*)$//;
		my $var = $1; # var name
		my $expr = $2; # expression
		push(@locals, $var); # recall var name for later restore
		# save current arg value, before assigning it
		&myeval("push(\@_stack, $var)", $fname, $lineno);
		&myeval("$var = $expr", $fname, $lineno);
		$block = 1;
	    } elsif(s/^\s*($_opt{P}copy *)//o) {
		print "$_opt{C}$1$_" if defined($_opt{C});
		#printf "$_opt{m}\n", $lineno, $fname if defined($_opt{m}) && $block; # mark the position of the call itself
		if(/^(\S+)(\(.*)$/) { #copy macro(...)
		    my $macro = &myeval('"'.$1.'"', $fname, $lineno);
		    my $list = $2;
		    my $f = "$macro$_opt{x}";
		    if(!defined($cache{$f})) {
			# search for the macro in the list of macro dirs
			my $found = 0;
			for my $dir (@_mdirs) {
			    $f = "$dir/$macro$_opt{x}";
			    if(-f $f) {
				$found = 1;
				last;
			    }
			}
			die "$fname:$lineno: macro $macro$_opt{x} not found\n"
			    if !$found;
		    }
		    # recursively preprocess the macro with its args
		    my @args = ($f, &myeval($list, $fname, $lineno));
		    push(@_calls, {file => $fname, line => $lineno,
				   name => $macro});
		    &prepro(@args);
		    pop(@_calls);
		} elsif(/^(\S+)(.*)$/)  { #copy stub
		    # search for the stub in the list of stub dirs
		    my $nm = $1;
		    my $repl = $2;
		    my $stub = &myeval('"'.$nm.'"', $fname, $lineno);
		    my $found = 0;
		    my $f;
		    for my $dir (@_sdirs) {
			$f = "$dir/$stub$_opt{x}";
			if(-f $f) {
			    $found = 1;
			    last;
			}
		    }
		    die "$fname:$lineno: stub $stub$_opt{x} not found\n"
			if !$found;
		    push(@_calls, {file => $fname, line => $lineno,
				   name => $stub});
		    push(@_repls, $repl);
		    # recursively preprocess the stub
		    &prepro($f);
		    pop(@_calls);
		    pop(@_repls);
		} else { die "$fname:$lineno: invalid macro/stub call: $_"; }
		$block = 1;
	    } elsif(s/^\s*$_opt{P}log *//o) {
		$block = 1;
		# protect double quotes and @s
		s/"/\\"/g; s/@/\\@/g;
		my $res = &myeval('"'.$_.'"', $fname, $lineno);
		print STDERR "$fname:$lineno: $res";
		&backtrace();
	    } elsif(s/^\s*$_opt{P}bind +//o) { #bind arg1 [=def1], ...
		$block = 1;
		# parse the list of arg names and optional default values
		my $i = 0;
		# a default value may be a number or a string (within simple
		# or double quotes):
		while(s/^(\$(?:\w+|{\w+}))(?:\s*=\s*([+-]?\d+|"(\\.|[^\\\"])*"|'(\\.|[^\\\'])*'))?\s*//) {
		    my $var = $1; # argument name
		    my $val = $2; # default value (possibly undef)
		    push(@locals, $var); # recall arg name for later restore
		    # save current arg value, before assigning it
    		    &myeval("push(\@_stack, $var)", $fname, $lineno);
		    if(defined($_[$i + 1])) { # there is an actual arg
			&myeval("$var = \$_[$i + 1]", $fname, $lineno, @_);
		    } elsif(defined($val)) { # there is a default val
			&myeval("$var = $val", $fname, $lineno, @_);
		    } elsif($_opt{d}) { # option -d giving default val
			&myeval("$var = \"\\$var\"", $fname, $lineno, @_);
		    } else {
			&myeval("$var = undef", $fname, $lineno, @_);
		    }
		    last if s/^\s*$//;
		    die "$fname:$lineno: comma expected: $_" unless s/^\s*,\s*//;
		    $i++;
		}
		die "$fname:$lineno: \$ or EOL expected: $_" unless /^$/;
	    } elsif(s/^\s*$_opt{P}exit *//o) {
		last; # stop preprocessing the current file/macro/stub
	    } elsif(s/^\s*$_opt{P}def +(\w+)//o) {
		chomp;
		my $name = $1;
		my @defbody = ();
		my @defs = ($name); # name of containing #def's
		if($lineno > $#$intbl) { 
		    die "$fname:$lineno: unterminated \#def $name";
		}
		$_ = $$intbl[$lineno++];
		while(!/^\s*$_opt{P}fed( +(\w+))? *$/ || $#defs > 0) {
		    push @defbody, $_;
		    if(/^\s*$_opt{P}def +(\w+)/) {
			push @defs, $1;
		    } elsif(/^\s*$_opt{P}fed( +(\w+))? *$/) { # => $#defs > 0
			my $tag = pop @defs; # now $#def > -1
			die "$fname:$lineno: mismatched \#fed: $tag...$1"
			    if /^\s*$_opt{P}fed +(\w+) *$/ && $tag ne $1;
		    }
		    if($lineno > $#$intbl) { 
			die "$fname:$lineno: unterminated \#def $name";
		    }
		    $_ = $$intbl[$lineno++];
		}
		# now -1 < $#defs <= 0 => $#defs == 0
		die "$fname:$lineno: mismatched \#fed: $name...$1"
		    if /^\s*$_opt{P}fed +(\w+) *$/ && $name ne $1;
		$cache{"$name$_opt{x}"} = \@defbody;
		# Also store an alias prefixed with the containing file name:
		$cache{"$fname:$name$_opt{x}"} = \@defbody;		
		if($_opt{t}) {
		    print "*** stored $name$_opt{x} with body:\n";
		    print "@defbody\n";
		    print "*** (alias: $fname:$name$_opt{x})\n";
		}
	    } elsif(s/^\s*$_opt{P}! *//o) { # shell command
		chomp;
		system $_;
	    } elsif(/^\s*$_opt{P}/o) {
		die "$fname:$lineno: Unknown prepro stmt: $_";
	    } elsif(defined($_opt{p}) && $_ =~ /$_opt{p}/o) {
		print; # don't preprocess these lines
	    } else { # non-preprocesor line: evaluate it as a string
		printf "$_opt{m}\n", $lineno, $fname if defined($_opt{m}) && $block;
		$block = 0;
		my $repl = $_repls[$#_repls];
		if(defined($repl) && $repl !~ /^\s*$/) { # perform replacements
		    &myeval($repl, $fname, $lineno); 
		}
		# protect double quotes and @s
		s/"/\\"/g; s/@/\\@/g;
		if($_opt{V} ne '$') {
		    s/\$/\\\$/g; # quote dollars
		    # replace macro vars with Perl vars & mark them:
		    my $line = '';
		    while(!/^$/) {
			if(s/^(\\.)//) {
			    $line .= $1;
			} elsif(s/^($_opt{V}(\w+|{\w+}))//o) {
			    my $var = $1;
			    $line .= sprintf $_opt{6}, $var;
			    $line .= '$' . $var;
			    $line .= sprintf $_opt{9}, $var;
			} else {
			    s/^(.)//;
			    $line .= "$1";
			}
		    }
		    $_ = "$line\n";
		} elsif($_opt{V} eq '$' && "$_opt{6}$_opt{9}" ne "") {
		    # mark Perl vars, dealing with tricky '$' in regex:
		    my $line = '';
		    while(!/^$/) {
			if(s/^(\\.)//) {
			    $line .= $1;
			} elsif(s/^(\$(\w+|{\w+}))//o) {
			    my $var = $1;
			    $line .= sprintf $_opt{6}, "\\$var";
			    $line .= $var;
			    $line .= sprintf $_opt{9}, "\\$var";
			} else {
			    s/^(.)//;
			    $line .= "$1";
			}
		    }
		    $_ = "$line\n";
		}
		my $res = &myeval('"'.$_.'"', $fname, $lineno);
		warn "$fname:$lineno: line too long:\n$res" 
		    if defined($_opt{L}) && length($res) > $_opt{L} + 1;
		print $res; 
	    }
	}
    }
    # restore formal args and local vars to their values before the bind/let
    for (my $i = $#locals; $i >= 0; $i--) {
        &myeval("$locals[$i] = pop(\@_stack)", $fname, $lineno);
    }
    $_nest--;
    # end marker for the file (if required)
    printf "$_opt{m}\n", $lineno, $fname if defined($_opt{m}); 
    printf "$_opt{E}\n", $fname, $args1 if $_nest && defined($_opt{E}); 
}

# Compute the and of N logical values.
# and(val1, val2, ...)
sub and {
    foreach my $i (@_) {
	if(!$i) { return 0; }
    }
    return 1;
}

# Eval a given expression, reporting the current file location in case of error
# myeval(expr, file, line [, args])
# where:
# - expr is the Perl expression to eval
# - file is the name of the current file
# - line is the line number in the current file
# - args are the arguments to the current macro (if needed by expr)
sub myeval {
    my $_expr = shift;
    my $_file = shift;
    my $_line = shift;
    chomp $_expr;
    print STDERR "> $_expr\n" if $_opt{t};
    my $res;
    my @res;
    if(wantarray) {
	@res = (eval $_expr);
    } else {
	$res = eval $_expr;
    }
    print STDERR "$_file:$_line: $@" if $@;
    $@ = "";
    return wantarray? @res: $res;
}

# prints the sequence of pending macro & stub calls, in reverse order
sub backtrace {
    for(my $i = $#_calls; $i >= 0; $i--) {
	my $call = $_calls[$i];
	print STDERR "called at $call->{file}:$call->{line}: $_opt{P}copy $call->{name}\n"
    }
}
