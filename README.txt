Custom Build System:
   -multi programming language
   -easy (to a degree)
   -multi-platform & multi-architecture

Still being actively developed, use at your own risk.
Things will change and break!
Complete build coming soon

Requires CURL

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
   
   [Documentation Still Work In Progress]
   
   Command Line Options:
      "-major" -> this is a major build
      "-minor" -> this is a minor build
      "-patch" -> this is a patch build
      "-config" -> sets the platform configuration file path, overridden if the make 
                   configuration file specifies its own path for a platform
                   configuration file
      "-silent" -> silences the build process
      "-pSilent" -> silences the build process if the parent process was silences,
                    if no parent process then it is not silenced
   
{
   "default": "Default function name",
   "function name":
   {
      "language": "a programming language",
      "project": "project name",
      "type": "executable, static or dynamic",
      "build": "path/to/output/directory/",
      "source": 
      [
         "path/to/source",
         ["Remote", "http://www.some.url.file"],
         "[EXTERN _file_>_routine_is_optional_>_var_]"
      ]
   },
   "another function name":
   {
   
   }
}
