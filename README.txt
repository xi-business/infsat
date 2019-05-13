InfSat version 0.1 (c) 2019 by Jan Wroblewski

License
--------
InfSat is released under the terms of the GPL version 3.0.
See the file COPYING for license terms.
InfSat is based on HorSat2 version 0.96 by Naoki Kobayashi and Taku Terao. HorSat2 is also
licensed under the GPL version 3.0.

How to install
--------------
First install and configure opam (docs on https://opam.ocaml.org/doc/Install.html), then
install OCaml 4.07.1 (docs on http://www.ocaml.org/docs/install.html#OPAM), e.g., using
opam switch create 4.07.1
and finally install opam package dependencies using
make install-dependencies

Run "make infsat" to make the final executable. Run "make run-test" to compile and run all
tests.

TODO update readme later

Usage
------
Basic usage:
./infsat path/to/file.inf
Skip the file path for input from stdin.

To learn advanced usage, run
./infsat -help

TODO incomplete

infsat [options] <input file name>
  horsat2 [option] <input file name>

 option: 
    -merge  alternative mode (which may be faster/slower than the default mode,
            depending on the input)
    -noce   suppress printing of a counterexample when a given property is not satisfied
 
    -cert   print the types of constants and non-terminals when a given property is satisfied

    -o <filename>
          Output the result to <filename>.
          The output is either:
             SATISFIED
                  if the property is satisfied; or
             VIOLATED
             ... (counterexample)
                  if the property is not satisfied.
          The format of an error trace depends on the automaton given is deterministic or
          alternating.
          If the automaton is deterministic, the counterexample is a path of the tree,
          written in the form:
              (a_1,d_1)(a_2,d_2)....(a_n,d_n).
          where a_i is a terminal symbol, and
                d_i is a non-negative integer representing the direction of the branch.

          If the automaton is alternating, the counterexample is a finite subtree that
          violates the property.

Format of Input File
--------------------
TODO

The input file should consist of a grammar section, followed by a description of
a tree automaton.

The grammar section should be of the form:
%BEGING
<rewriting rule 1>
 ....
<rewriting rule n>
%ENDG
where each rule should be of the form "F x1 ... xn -> t."
The non-terminal symbol defined by the first rule is interpreted as the start symbol.

The syntax of terms is:

  t ::= x   (variable)
        c   (terminal symbol)
        F   (non-terminal)
        t1 t2

See examples in the directory "examples".

The automaton part should specify either a trivial deterministic tree automaton
(a deterministic Buchi tree automaton with a trivial acceptance condition), or
a trivial alternating tree automaton (a topdown alternating tree automaton 
with a trivial acceptance condition).

The description of a trivial deterministic automaton should consist of the following
one section.

%BEGINA
<transition rule 1>
...
<transition rule m>
%ENDA

Each transition rule should be of the form "q a -> q1 ... qk".
Here, q,q1,...,qk are states of the automaton, and a is a tree constructor of
arity k. It should be read "when the automaton reads node a in state q,
the automaton should proceed to read the i-th child with state qi".
The state on the lefthand side of the first rule is interpreted as the initial
state of the automaton.

The description of a trivial alternating tree automaton should consist of the
following two sections.

%BEGINR
<arity declaration 1>
...
<arity declaration k>
%ENDR

%BEGINATA
<alternating transition rule 1>
...
<alternating transition rule m>
%ENDATA

The first section declares the arity of each tree constructor.
Each declaration should be of the form "a -> <non-negative number>".
For example, "a->3" means that a has arity 3.

The second section declares the transition rules of the alternating tree automaton.
Each line should be of the form:

   q a -> <form>.

where the syntax of <form> is:

<form> ::= true
         | false
         |  (i, q)
         | <form> /\ <form>
         | <form> \/ <form>

(i,q) means "read the i-th child with state q".
For example, the rule
  q a -> (1,q0) \/ ((1,q1) /\ (2,q2)) 
means: "upon reading a at state q,
either read the first child with state q0, or
read the first and second children with states q1 and q2 respectively".

Here is a sample input.
%BEGING
S -> F c.
F x -> br x (a (F (b x))).
%ENDG

%BEGINR
br -> 2.
a -> 1.
b -> 1.
c -> 0.
%ENDR

%BEGINATA
q0 br -> (1,q0) /\ (2,q1).
q1 br -> (1,q1) \/ (2,q1).
q0 a -> (1,q0).
q1 a -> false.
q0 b -> (1,q1).
q1 b -> (1,q1).
q0 c -> true.
q1 c -> true.
%ENDATA

TODO
----
* 3 versions of pretty printing of types:
  (pr -> np) -> np -> pr
  (pr, (np, (pr, o) -> o) -> (np, o) -> o)
  (pr, (np, pr -> o) -> np -> o) where sort o is shortened (f, o) to f
* external app to color matching parens to pipe infsat output through it
* indexing different used typings of same variable or nonterminal, e.g.,
  f#1: pr -> np
  f#2: np /\ pr -> pr
  X: np /\ pr
  a: pr -> pr
  |- f#1 (a (f#2 X)) : pr
* add info about used typings of terminals, also indexed when needed, same example
* ascii art with arrows showing the graph
