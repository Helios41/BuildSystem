Custom Build System:
   -multi programming language
   -easy (to a degree)
   -multi-platform & multi-architecture

Feature complete build is available... sometimes...
Still being actively developed, use at your own risk.

Documentation:
   Configuration files are in JSON format.
   
   In the root object declare an object with any name except "default", this 
   object will become a routine, an executable section of the file. 
   
   In the root object declare a string named "default" with 
   the value of a name of the routine you wish to be executed by default.
   
   Within the routine declare a string named "language" with the value of
   the name of the language you are compiling for(ex. "language": "C").
   
   Within the routine declare a string named "type" with the value of the
   type of file you are compiling(ex. executable, dynamic, static, etc...).
   
   Within the routine declare a string named "build" with the value of a
   path to a directory relative to the configuration file, this will be
   where the build file ends up.
   
   [Work In Progress]