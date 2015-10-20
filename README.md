# Metapp (v1.52)

* * *

## Introduction

Metapp is a general-purpose text preprocessor featuring a minimalistic macro language. Its primary purpose is to add macros to programming languages not allowing macros, such as Cobol or Java, but it can be used in a wider spectrum of text processing applications.

Metapp is implemented in Perl and provides access to a significant part of Perl within the macro language.

When used in conjunction with a programming language, macros are a powerful mechanism for code refactoring. The metapp implementation of macros is considerably more powerful than both C macros and Cobol's COPY REPLACING.

* * *

## Downloads

Metapp consists of only one Perl file: [metapp](http://www.metaware.fr/metapp/metapp), licensed under [GNU GPL v3](http://www.gnu.org/copyleft/gpl.html).

There is a research paper describing Metapp and its application to program refactoring:

#### Nic Volanschi |  [Safe Clone-Based Refactoring through Stereotype Identification and Iso-Generation](http://www.metaware.fr/metapp/Metaware_Opensource_metapp_isogen_iwsc12.pdf).

presented at the IWSC'12 (6th International Workshop On Software Clones) Zurich, Switzerland, June 4th, 2012.

* * *

## Syntax

#### The syntax of a source file to be preprocessed is very simple:

*   Each line starting with a '#' (after any whitespace) is considered to be a line in the macro language interpreted by metapp, also called a preprocessor line. (However, see option -P for changing the prefix of preprocessor lines.)
*   Any other line (also called a text line) is reproduced by metapp in the output, after substituting any Perl interpolated variable ($name or ${name}) with its current value. (However, see option -p to inhibit substitutions on some text lines, and see option -V for changing the prefix of variables.)

#### Metapp lines (starting with '#') can be of the following types:

*   ## text
    *   This line is simply skipped by metapp. It can serve to place comments that will not appear in the preprocessed file. Note that there is no space between the two '#' characters.
*   # perl-command
    *   Evaluate the given Perl command. Note the mandatory space after the '#'. The most common use of this command is for assigning a macro-variable. Another common use is for calling an external code generator written in Perl.
    *   As in Perl, if a variable assigned this way was not previously declared (see #let below), it is a global variable. A global variable assigned in some file can be retrieved afterwards both in files included by the current file and in files including the current file.
*   #!shell-command
    *   Evaluate the given shell command, incorporating its standard output into the output file at this point. The command may include any needed arguments, as on a command line. This allows calling external code generators written in any language.
*   #copy macro-name( [arg, ...] )
    *   This line is substituted by the result of preprocessing the named macro. A macro may be either an external macro, that is, a file called macro-name, searched in the list of macro directories (see option -M), or an internal macro, defined using the #def construct below. Preprocessing of the macro takes place after evaluation the arguments, if any, as Perl expressions. See option -x for specifying a file extension to be appended automatically to external macro names. Arguments can be defined in the macro body using the command #bind below.
    *   The macro name itself may contain variables.
*   #copy stub-name [perl-command]
    *   This line is substituted by the result of preprocessing the file called stub-name, searched in the list of stub directories (see option -S). See option -x for specifying a file extension to be appended automatically to stub names. Thus, a stub is just a simplified form of external macro that is not parameterized (i.e. cannot take arguments), and lives in a distinct namespace (i.e. is searched in a distinct list of directories). However, the perl-command, if given, is applied on each line of the stub before printing it. The typical use of perl-command is to perform a series of Perl substitutions on each line.
    *   The stub name itself may contain variables.
*   #bind $arg1[=defval1], ...
    *   Bind the formal arguments $arg1 ... to the actual arguments passed to the current macro. If an actual argument is absent or undefined (i.e. has the Perl value undef), the corresponding formal argument is bound to the optionally specified default value. If both the actual argument and the default value are missing, the formal is undefined. The #bind statement is usually the first statement in a macro taking arguments. In a macro without arguments or in a stub, this statement is useless.
    *   Formal arguments are dynamically scoped, i.e. they exist until exiting the current file; in particular, these variable are also visible in files included by the current one (unless the variables are redefined). If some variable with the same name existed before the current statement, its old definition is shaded until exiting the current file.
*   #let $var=expr
    *   Define a local variable $var and assign to it the result of evaluating the Perl expression expr.
    *   Local variables are also dynamically scoped (see #bind).
*   #if condition ... {#elsif condition ...} [#else ...] #fi
    *   The first condition is evaluated as a Perl expression. If the result is true (in Perl), the lines between the #if line and the first #elsif, #else, or #fi line are preprocessed and the remaining lines are skipped. If the result is false, the former lines are skipped, and processing similarly continues with the following #elsif condition (if any); if all #elsif conditions are false, the lines between the #else and the #fi, if any, are preprocessed.
*   #while condition ... #end
    *   The condition is evaluated as a Perl expression. If the result is true, the lines between the #while line and the #end line are preprocessed, after which the #while line is preprocessed again in the same way. If the result is false, the lines between the #while line and the #end line, as well as the #end line itself, are skipped.
*   #def macro-name ... #fed [macro-name]
    *   This sequence does not generate any output. It defines a macro with the given name. The #fed line can optionally contain the same macro name as the #def line. Arguments, if any, can be defined within the macro body using #bind commands. Any control construct within the body is interpreted only when the macro is invoked. A macro "m" defined in file "f" can be called as "m.f" after including file "f". This is useful when redefining a macro, for calling the old definition within the new one.
    *   Macro definitions can be nested, allowing a macro to define other macros.
*   #exit
    *   This line does not generate any output. It only ends the preprocessing of the current (macro or stub) file, and continues preprocessing right after the calling #copy line, if any.
*   #log message
    *   The message is evaluated as a Perl interpolated string and the result is printed on the standard error output.


#### Any line can be continued on the following line by:

*   appending a "\" at the end of the line (which may followed only by some trailing spaces),
*   and starting the following line with "#..." (which may be preceded by any number of spaces).


The #if, #while, and #def constructs may be nested.

* * *

## Invocation

#### Synopsis:

*   metapp [options] source-file

#### Arguments:

*   source-file: the source file to be pre-processed

#### Options:

*   -e Expr: evaluate Perl expression Expr before doing anything else
    *   default: no expression is evaluated
    *   This expression can serve for example to perform a simple initialization.
*   -i Initfile: execute initialization file
    *   default: no initialization file
    *   This file can serve to perform various initializations. It is executed with the Perl "require" command, which means that the last command in the file has to return a value equivalent to "true" (e.g. 1).
*   -M Macrodirs: directories containing external macros, separated by ':'
    *   default: "." (the current directory)
    *   Directories in the list are separated by a colon (":"). When a macro is called using #copy macro(...), this list of directories is searched, in order, until a macro of the given name is found.
*   -S Stubdirs: directories containing stubs, separated by ':'
    *   default: "." (the current directory)
    *   Directories in the list are separated by a colon (":"). When a stub is called using #copy stub, this list of directories is searched, in order, until a stub of the given name is found.
*   -m lineMarker: format of line number markers
    *   default: no line number markers
    *   If this option is present, the preprocessor outputs a line number marker each time the current line does not directly follow the previous line in the original file currently being processed. The marker is built by calling printf with the supplied format, the current line number, and the current file name.
    *   This option is useful to trace the precise source line for every output line, allowing for instance source-level debuggers to work on the preprocessed code. For example, the format '#line %d "%s"' would be suitable for many standard tools.
*   -C Copyprefix: prefix for #copy marker lines
    *   default: drop #copy lines
    *   If provided, keep each original #copy line, prefixed with this string.
*   -B Beginmacro: format of begin macro markers
    *   default: no begin macro markers
    *   If provided, mark the beginning of each expanded macro. The marker is built by calling printf with the supplied format, the name of the macro, and a list of its actual argument values. For example, "// %s(%s)" might be a suitable format when processing C/C++ code.
*   -E Endmacro: format of end macro markers
    *   default: no end macro markers
    *   If provided, mark the end of each expanded macro. The marker is built by calling printf with the supplied format, the name of the macro, and a list of its actual argument values. For example, "// %s EOF" might be a suitable format when processing C/C++ code. Note that it is legal to drop the list of arguments by not including a second "%s" in the format.
*   -p Passregex: pass unchanged text lines matching the regex
    *   default: process all lines
    *   Text lines matching this regex are not substituted for embedded variables or arrays, but rather output as is. This may be used for instance to inhibit the substitution of macro variables within comments.
*   -P PreproPrefix: prefix of all preprocessor lines
    *   default: "#" (after any whitespace)
    *   Changing the prefix identifying preprocesor lines is one means for embedding metapp in various host languages.
*   -V VarPrefix: prefix for macro variable references in text lines
    *   default: "$"
    *   Changing the prefix identifying preprocesor variables is another means for embedding metapp in various host languages.
*   -6 ValueBegin: format of markers before variable values
    *   default: no begin value markers
    *   Precede each expanded variable value by a marker. The marker is built by calling printf with the supplied format and the original variable reference (e.g. $x or ${x}). For example, when preprocessing C/C++ code, an appropriate format might be "/*#<%s*/".
*   -9 ValueEnd: format of markers after variable values
    *   default: no end value markers
    *   Follow each expanded variable value by a marker. The marker is built by calling printf with the supplied format and the original variable reference (e.g. $x or ${x}). For example, when preprocessing C/C++ code, an appropriate format might be "/*#>*/". Note that it is legal to drop the original variable syntax by not including any "%s" in the marker format.
*   -t: Trace each expression before evaluating it
    *   default: don't trace
    *   Prints on standard error output each expression before handing it to Perl for evaluation.
*   -x suffiX: add suffix to stub & external macro file names
    *   default: "" (the empty suffix)
    *   This option is useful if all stubs and macros share a common filename extension (such as .cpy). In that case, the order #copy _stub_ will look for the file _stub_.cpy.
*   -L outlineLength: warn if any output line is longer than the given limit
    *   default: no limit
    *   This option is useful when the output program must not exceed a certain line length.
*   -l Leftmargin: ignore the first N characters in each input line
    *   default: no left margin
    *   This option is useful when the input program is in fixed format with a left margin (e.g. left numbering).
*   -r Rightmargin: truncate each input line at N characters
    *   default: don't truncate
    *   This option is useful when the input program is in fixed format with a right margin (e.g. right numbering).
*   -d: the Default value for any parameter $x/${x} is "$x"/"${x}"
    *   default: the parameter is undefined
    *   This option is provided for compatibility with some old code generators, but should be avoided as it may mask errors related to uninitialized macro parameters.
*   -v: print Version info and exit
    *   default: don't print version but do real work
    *   This option is useful e.g. for scripts requiring a minimum version of the tool.


* * *

## Examples

### 1 Cobol entry points

The following file, called "entrypts.cpy", is a macro file generating a COPY REPLACING statement with _n_ WHEN clauses, where each clause represents a Cobol Entry point:


<div class="code">

<pre>#bind $n
#<span class="java-keyword">if</span> $n <= 0
 #log <span class="java-quote">"n must be positive!"</span>
 #exit
#fi
           COPY ENTRYPTS REPLACING ==(SET)== BY ==                      
# $i=0
#<span class="java-keyword">while</span> ++$i <= $n
             WHEN <span class="java-quote">"$i"</span>                                                 
               SET ENTRY--PTR TO ENTRY <span class="java-quote">"$i"</span>                            
#end
             == .                                                       
           CONTINUE.</pre>

</div>


#### In this macro:

*   the #bind statement binds the first (and only) argument of the macro to the local variable $n
*   the #if statement checks that the argument is negative; if so, it prints an error message and stops processing the macro (but goes on processing the rest of the program)
*   the assignment sets the global macro-variable $i to 0
*   the #while loop generates $n WHEN clauses, and in each clause substitutes $i with the loop index

The following Cobol program, called "BCVDC05M.cbl" uses the above macro.

<div class="code">

<pre># $n=4; $pgmid='BCVDC05M'
 PROCEDURE DIVISION.
 PROGRAM-ID. $pgmid.
 BEGIN--MAIN SECTION.
#copy entrypts.cpy(3);
 BEGIN--PROGRAM SECTION.
#<span class="java-keyword">if</span>($n > 3)
     MOVE '$pgmid' TO L--RAV16FL-QUESTION-AMT-CODE
#<span class="java-keyword">else</span>
     CONTINUE
#fi
 END PROGRAM $pgmid.</pre>

</div>


#### In the above program:

*   the first assignment sets global variables $n and $pgmid
*   the global $pgmid is to be substituted in the header and footer of the program (lines PROGRAM-ID and END PROGRAM)
*   the #copy statement invokes the previous entrypts macro passing it an argument of 3
*   the #if generates either a MOVE or a CONTINUE, depending on the value of the global $n (which is different from the local $n in the entrypts macro)

The Cobol file can be preprocessed by metapp using the following command:

<div class="code">

<pre>metapp -B "*** File %s(%s)" -E "*** EOF %s" BCVDC05M.cbl</pre>

</div>

The resulting file looks as follows:

<div class="code">

<pre> PROCEDURE DIVISION.
 PROGRAM-ID. BCVDC05M.
 BEGIN--MAIN SECTION.
*** File entrypts.cpy(3)
           COPY ENTRYPTS REPLACING ==(SET)== BY ==                      
             WHEN "1"                                                 
               SET ENTRY--PTR TO ENTRY "1"                            
             WHEN "2"                                                 
               SET ENTRY--PTR TO ENTRY "2"                            
             WHEN "3"                                                 
               SET ENTRY--PTR TO ENTRY "3"                            
             == .                                                       
           CONTINUE.
*** EOF entrypts.cpy
 BEGIN--PROGRAM SECTION.
     MOVE 'BCVDC05M' TO L--RAV16FL-QUESTION-AMT-CODE
 END PROGRAM BCVDC05M.
</pre>

</div>

Note that options -B and -E can be omitted if the markers are not needed.

### <span id="HRecursivemacro">2 Recursive macro</span>

The following file, called "fact.txt", is a macro taking a positive number as argument _n_ and generating a single line containing _n!_, the factorial of _n_.

<div class="code">

<pre>#bind $n, $accu=1
#<span class="java-keyword">if</span> $n == 0 or $n == 1
$accu
#<span class="java-keyword">else</span>
 #copy fact.txt($n - 1, $n * $accu)
#fi</pre>

</div>

In this macro:

*   the #bind statement declares two arguments, the second one having a default value of 1
*   when argument $n is zero or 1, the result accumulated in $accu is directly output; otherwise, the macro is invoked recursively

The following file is using macro fact.txt to compute the factorial of 5:

<div class="code">

<pre>The factorial of 5 is:
#copy fact.txt(5)
Right?</pre>

</div>


The preprocessed file will look as follows (assuming the same options -B and -E as above):


<div class="code">

<pre>The factorial of 5 is:
*** File fact.txt(5)
*** File fact.txt(4,5)
*** File fact.txt(3,20)
*** File fact.txt(2,60)
*** File fact.txt(1,120)
120
*** EOF fact.txt
*** EOF fact.txt
*** EOF fact.txt
*** EOF fact.txt
*** EOF fact.txt
Right?</pre>

</div>


Alternatively, the macro "fact" can be defined locally as follows:


<div class="code">

<pre>#def fact
 #bind $n, $accu=1
 #if $n == 0 or $n == 1
$accu
 #else
  #copy fact($n - 1, $n * $accu)
 #fi
#fed
###
The factorial of 5 is:
#copy fact(5)
Right?</pre>

</div>

