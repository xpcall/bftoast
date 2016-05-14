# bftoast
Brainf*ck Toast Compiler project

The goal of bftoast is to have a high level statically typed language that compiles to size optimized brainfuck.

Stack managment:
  Every object used in bftoast gets pushed to a stack and later popped off that stack
  There are two types of objects on the stack:
    Static objects:
      These objects either have a known size at compile time or are finalized
      For example ints
    Dynamic objects:
      These objects can dynamically grow on the stack to the right
      For example strings
  Issues happen when multiple dynamic objects need to exist at the same time since obviously you cant have two strings expanding infinitely in the same place
  To allow multiple dynamic objects at once, multiple stacks are multiplexed together as one dynamic object on the end of the parent stack
  As a result, any operations on the child stacks have their < and > commands doubled
