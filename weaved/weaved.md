#About the program
This program reads a certain description of an undirected graph and
determines the number of connected components of it.
##About the description of the graph
The graph shall be read from a file. The file describes
the graph by way of specifying the number of nodes, the
number of edges and a description of what nodes
each edge connects.
###Syntax
The input file consists only of a series of arbitrarily space-
separated integer constants written in plain ASCII, and
consequently, also readable as an UTF-8 plain text file.

The first two integers shall be the number of nodes (n), and the
number of edges (m), respectively.

Given this, the set of nodes is assumed to be {1, 2, ... n}, and
each node will be referred simply by its number.

Then comes "m" pairs of integers "u" and "v" each giving the
existence of a bidirectional edge between nodes "u" and "v".
##The command line interface
As a binary, our program shall receive one and only one command line argument, and this will
be interpreted as the file name for the input file described in #/about/interface/syntax.

If the input file doesn't comply with the #/about/interface/syntax our program will fail silently.
#The program
As this program will be considerably small, it will consist of a single source file
in which we will put all of our code.
##Source file "source/app.d"
The one and only sourcefile. Will contain everything.
The structure of this file will be typical.
##< source/app.d > += 
	> Import declarations
	> Global variable definitions
	> Function definitions
##< Import declarations > = 
In this fragment will be included the import declarations that we see
fit.
##< Global variable definitions > = 
In this fragment we will be creating and initializing global variables
as we require them.
##< Function definitions > = 
In this fragment we will be inserting our function definitions.

As per the rules of the D programming language, the order in which we insert new fragments
into the three previous fragments won't affect the final result.
##The main function
The main function will be the entry point to our program. This is the starting point of execution.
The structure of this function will be typical of a D program.
###< Function definitions > += 
	void main(string[] args)
	{
	  > Local variables definitions
	  > Main process
	}
###< Local variables definitions > = 
In this fragment we will be inserting the local variables we require.
###< Main process > = 
In this fragment we will input how our main function does its processing.

Where `args` is an array of strings that contains the arguments we received from the user. The first argument is always the name of the binary,
the rest are given by the user.
###The process
####< Main process > += 
	> Commandline arguments validation
	> Read the input
	> Compute the answer
	> Write the answer
####< Commandline arguments validation > = 
As it is normal in a program with command-line interface, our
first job shall be to validate the arguments that we are given.
####< Read the input > = 
Given that we have a valid argument giving us the input file name.
We will try to open the given file and get it's data (ala Succ).
This fragment's job will imply verifying the existence and syntax of
the given file.
####< Compute the answer > = 
With the information about the graph we will now be ready to compute the
number of connected components of it.
####< Write the answer > = 
Given the answer obtained in the previous fragment. We will present it to
the user through stdout.
\paragraph{Commandline arguments validation}
To do this, it is enough to verify that we have been given one and only one user-defined commandline argument.
The first given argument in "args" is always the name of the binary, so we need to verify that the args array
is of size 2 exactly.
####< Commandline arguments validation > += 
	if (args.length != 2)
	{
	  import std.stdio: stderr;
	  stderr.writeln("Expected an only argument giving an input file");
	  return;
	}
Before reading the input we must know how
