import std.stdio;
import std.file;
import std.string;
import std.json;
import std.array;
import std.algorithm.searching;
import std.c.stdlib;
import BuildSystemConfigurable;
import std.uuid;
import std.conv;
import std.container;

/**
TODO:
   -build dll on windows with .def file
   -ability to specify functions to expose as dll
   -attribute system to replace static libraries & exported functions *MOAR DYNAMICALITY*
   -make all paths relative to the current script
*/

enum VersionType : string
{
   None = "None",
   Major = "Major",
   Minor = "Minor",
   Patch = "Patch"
}

struct VersionInformation
{
   int major;
   int minor;
   int patch;
   string appended;
   
   VersionType type;
   
   bool is_versioned;
}

struct PlatformInformation
{
   bool optimized;
   string arch;
   string OS;
}

struct BuildInformation
{
   PlatformInformation platform;
   bool can_build;
   string type;
   string language;
   string[] source_folders;
   string build_folder;
   string project_name;
   string[][string] attributes;
   
   string[] static_libraries;
   string[] exported_functions;
}

struct BuildRoutine
{  
   string directory;
   string path;
   string name;
}

void main(string[] args)
{
   if(args.length < 2)
   {
      writeln("Insufficient arguments!");
      writeln("Usage \'buildsystem [config file]\'");
      return;
   }
   
   string config_file_path = args[1];
   
   writeln("Global config file: ", GlobalConfigFilePath);
   
   if(args.length == 2)
   {
      string config_file_default_routine = GetDefaultRoutine(config_file_path); 
      RunRoutine(config_file_path, config_file_default_routine);
   }
   else if(args.length > 2)
   {
      VersionType version_type = VersionType.None; 
      bool function_called = false;
   
      for(int i = 2; args.length > i; ++i)
      {
         string argument = args[i];
         
         if(argument.startsWith("-"))
         {
            if(argument == "-major")
            {
               version_type = VersionType.Major;
            }
            else if(argument == "-minor")
            {
               version_type = VersionType.Minor;
            }
            else if(argument == "-patch")
            {
               version_type = VersionType.Patch;
            }
         }
         else
         {
            function_called = true;
            RunRoutine(config_file_path, argument, version_type);
         }
      }
      
      if(!function_called)
      {
         string config_file_default_routine = GetDefaultRoutine(config_file_path); 
         RunRoutine(config_file_path, config_file_default_routine, version_type);
      }
   }
}

string GetDefaultRoutine(string file_path)
{
   writeln("Finding default routine of ", file_path);

   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }

   JSONValue file_json = parseJSON(readText(file_path));
   
   try
   {
      if(file_json["default"].type() == JSON_TYPE.STRING)
      {
         return file_json["default"].str();
      }
   }
   catch
   {
      writeln("missing default routine");
      exit(-1);
   }
   
   return null;
}

void RunRoutine(string file_path, string routine_name, VersionType version_type = VersionType.None)
{
   writeln("Executing routine ", routine_name, " in ", file_path);

   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   
   if(file_json[routine_name].type() == JSON_TYPE.OBJECT)
   {
      JSONValue routine_json = file_json[routine_name];
      
      BuildInformation build_info;
      
      build_info.language = "";
      build_info.type = "";
      build_info.can_build = true;
      build_info.source_folders = null;
      build_info.build_folder = "";
      build_info.project_name = "";
      build_info.platform.optimized = true;
      build_info.platform.arch = "";
      build_info.platform.OS = GetOSName();
      
      //TODO: remove in favour of attrib system
      build_info.static_libraries = null;
      build_info.exported_functions = null;
      
      VersionInformation version_info;
      
      version_info.type = version_type;
      version_info.major = 0;
      version_info.minor = 0;
      version_info.patch = 0;
      version_info.appended = "";
      version_info.is_versioned = true;
      
      BuildRoutine routine_info;
      
      routine_info.path = file_path;
      routine_info.name = routine_name;
      routine_info.directory = file_path[0 .. file_path.lastIndexOf("/")];
      
      try
      {
         if(routine_json["project"].type() == JSON_TYPE.STRING)
         {
            build_info.project_name = routine_json["project"].str();
         }   
      }      
      catch { build_info.can_build = false; }
      
      try
      {
         if(routine_json["language"].type() == JSON_TYPE.STRING)
         {
            build_info.language = routine_json["language"].str();
         } 
      }      
      catch { build_info.can_build = false; }
      
      try
      {
         if(routine_json["type"].type() == JSON_TYPE.STRING)
         {
            build_info.type = routine_json["type"].str();
         }
      }      
      catch { build_info.can_build = false; }
      
      try
      {
         if(routine_json["source"].type() == JSON_TYPE.STRING)
         {
            build_info.source_folders = new string[1];
            build_info.source_folders[0] = routine_json["source"].str();
         }
         else if(routine_json["source"].type() == JSON_TYPE.ARRAY)
         {
            build_info.source_folders = new string[routine_json["source"].array.length];
            int index = 0;
         
            foreach(JSONValue value; routine_json["source"].array)
            {
               if(value.type() == JSON_TYPE.STRING)
               {
                  build_info.source_folders[index] = value.str();
                  ++index;
               }
            }
         }
      }
      catch { build_info.can_build = false; }
      
      try
      {
         if(routine_json["build"].type() == JSON_TYPE.STRING)
         {
            build_info.build_folder = routine_json["build"].str();
         }
      }
      catch { build_info.can_build = false; }
      
      try
      {
         if(routine_json["version"].type() == JSON_TYPE.ARRAY)
         {
            JSONValue version_json = routine_json["version"];
            
            if(version_json.array.length >= 3)
            {
               if(version_json[0].type() == JSON_TYPE.INTEGER)
               {
                  version_info.major = to!int(version_json[0].integer);
               }
               
               if(version_json[1].type() == JSON_TYPE.INTEGER)
               {
                  version_info.minor = to!int(version_json[1].integer);
               }
               
               if(version_json[2].type() == JSON_TYPE.INTEGER)
               {
                  version_info.patch = to!int(version_json[2].integer);
               }
            }
            else
            {
               version_info.is_versioned = false;
            }
            
            if(version_json.array.length == 4)
            {   
               if(version_json[3].type() == JSON_TYPE.STRING)
               {
                  version_info.appended = version_json[3].str();
               }
            }
         }
      }
      catch { version_info.is_versioned = false; }
      
      try
      {
         if(routine_json["optimized"].type() == JSON_TYPE.TRUE)
         {
            build_info.platform.optimized = true;
         }
         else if(routine_json["optimized"].type() == JSON_TYPE.FALSE)
         {
            build_info.platform.optimized = false;
         }
      }
      catch {}
      
      try
      {
         //TODO: attrib system
         foreach(JSONValue attribute_json; routine_json.array)
         {
            writeln(routine_json.array.length);
         }
      } catch { writeln("Attrib system broke!"); }
      
      //PORT TO ATTRIB SYSTEM - BEGIN
      
      try
      {
         if(routine_json["dependencies"].type() == JSON_TYPE.STRING)
         {
            build_info.static_libraries = new string[1];
            build_info.static_libraries[0] = routine_json["dependencies"].str();
         }
         else if(routine_json["dependencies"].type() == JSON_TYPE.ARRAY)
         {
            JSONValue dependencies_json = routine_json["dependencies"];
            build_info.static_libraries = new string[dependencies_json.array.length];
            int index = 0;
            
            foreach(JSONValue element_json; dependencies_json.array)
            {
               if(element_json.type() == JSON_TYPE.STRING)
               {
                  build_info.static_libraries[index] = element_json.str();
                  ++index;
               }
            }
         }
      }
      catch {}
      
      try
      {
         if(routine_json["exports"].type() == JSON_TYPE.STRING)
         {
            build_info.exported_functions = new string[1];
            build_info.exported_functions[0] = routine_json["exports"].str();
         }
         else if(routine_json["exports"].type() == JSON_TYPE.ARRAY)
         {
            JSONValue dependencies_json = routine_json["exports"];
            build_info.static_libraries = new string[dependencies_json.array.length];
            int index = 0;
            
            foreach(JSONValue element_json; dependencies_json.array)
            {
               if(element_json.type() == JSON_TYPE.STRING)
               {
                  build_info.static_libraries[index] = element_json.str();
                  ++index;
               }
            }
         }
      }
      catch {}
      
      //PORT TO ATTRIB SYSTEM - END
      
      try { ExecuteOperations(routine_info, build_info, version_info); } catch {}
   }
}

void ExecuteOperations(BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   JSONValue routine_json = GetRoutineJSON(routine);

   if(routine_json["operations"].type() == JSON_TYPE.ARRAY)
   {
      JSONValue operations_json = routine_json["operations"];
      string last_operation_token = "";
      bool has_built = false;
      
      writeln("Executing Commands:");
      
      foreach(JSONValue operation_json; operations_json.array)
      {
         if(operation_json.type() == JSON_TYPE.ARRAY)
         {
            string operation_token = operation_json[0].str();
            if((operation_token !=  "=") && (operation_token !=  "||"))
            {
               last_operation_token = operation_token;
            }
            else
            {
               operation_token = last_operation_token;
            }
            
            if(IsProperPlatform(operation_token, build_info.platform))
            {
               operation_token = RemoveTags(operation_token, build_info.platform);
            }
            else
            {
               continue;
            }
            
            string[] operation_params = new string[operation_json.array.length - 1];
            for(int i = 1; i < operation_json.array.length; ++i)
            {
               if(operation_json[i].type() == JSON_TYPE.STRING)
               {
                  if(IsProperPlatform(operation_json[i].str(), build_info.platform))
                  {
                     operation_params[i - 1] = RemoveTags(operation_json[i].str(), build_info.platform);
                  }
               }
            }
            
            switch(operation_token)
            {
               case "move":
               {
                  try { MoveOperation(operation_params); } catch {}
               }
               break;
               
               case "delete":
               {
                  try { DeleteOperation(operation_params); } catch {}
               }
               break;
               
               case "copy":
               {
                  try { CopyOperation(operation_params); } catch {}
               }
               break;
               
               case "call":
               {
                  try { CallOperation(operation_params); } catch {}
               }
               break;
               
               case "print":
               {
                  string to_print = "";
                  foreach(string args; operation_params)
                  {
                     to_print = to_print ~ args;
                  }
                  writeln("[print] ", to_print);
               }
               break;
               
               default:
               {
                  writeln("Unknown Operation: ", operation_token);
               }
            }
         }
         else if(operation_json.type() == JSON_TYPE.STRING)
         {
            string operation_token = operation_json.str();
            if((operation_token !=  "=") && (operation_token !=  "||"))
            {
               last_operation_token = operation_token;
            }
            else
            {
               operation_token = last_operation_token;
            }
            
            switch(operation_token)
            {
               case "build":
               {
                  try { BuildOperation(routine, build_info, version_info); } catch {}
                  has_built = true;
               }
               break;
               
               case "clean":
               {
                  try { CleanOperation(routine, build_info, version_info); } catch {}
               }
               break;
               
               default:
               {
                  writeln("Unknown Operation: ", operation_token);
               }
            }
         }
      }
      
      if(!has_built)
      {
         try { BuildOperation(routine, build_info, version_info); } catch {}
      }
   }
}

void ExecutePerOperations(string output_directory, BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   JSONValue routine_json = GetRoutineJSON(routine);
   string version_string = to!string(version_info.major) ~ "_" ~ to!string(version_info.minor) ~ "_" ~ to!string(version_info.patch) ~ "_" ~ version_info.appended;
   
   if(routine_json["per-operations"].type() == JSON_TYPE.ARRAY)
   {
      JSONValue operations_json = routine_json["per-operations"];
      string last_operation_token = "";
      
      writeln("Executing Per Build Commands:");
      
      foreach(JSONValue operation_json; operations_json.array)
      {
         if(operation_json.type() == JSON_TYPE.ARRAY)
         {
            string operation_token = operation_json[0].str();
            if((operation_token !=  "=") && (operation_token !=  "||"))
            {
               last_operation_token = operation_token;
            }
            else
            {
               operation_token = last_operation_token;
            }
            
            if(IsProperPlatform(operation_token, build_info.platform))
            {
               operation_token = RemoveTags(operation_token, build_info.platform);
            }
            else
            {
               continue;
            }
            
            string[] operation_params = new string[operation_json.array.length - 1];
            for(int i = 1; i < operation_json.array.length; ++i)
            {
               if(operation_json[i].type() == JSON_TYPE.STRING)
               {
                  if(IsProperPlatform(operation_json[i].str(), build_info.platform))
                  {
                     operation_params[i - 1] = RemoveTags(operation_json[i].str(), build_info.platform)
                                               .replace("[OUTPUT_DIRECTORY]", output_directory)
                                               .replace("[ARCH_NAME]", build_info.platform.arch)
                                               .replace("[OS_NAME]", build_info.platform.OS)
                                               .replace("[PROJECT_NAME]", build_info.project_name);
                                               
                     if(version_info.is_versioned)
                     {
                        operation_params[i - 1] = operation_params[i - 1]
                                                      .replace("[MAJOR_VERSION]", to!string(version_info.major))
                                                      .replace("[MINOR_VERSION]", to!string(version_info.minor))
                                                      .replace("[PATCH_VERSION]", to!string(version_info.patch))
                                                      .replace("[APPENDED_VERSION]", version_info.appended)
                                                      .replace("[VERSION]", version_string);
                     }
                  }
               }
            }
            
            switch(operation_token)
            {
               case "move":
               {
                  try { MoveOperation(operation_params); } catch {}
               }
               break;
               
               case "delete":
               {
                  try { DeleteOperation(operation_params); } catch {}
               }
               break;
               
               case "copy":
               {
                  try { CopyOperation(operation_params); } catch {}
               }
               break;
               
               case "call":
               {
                  try { CallOperation(operation_params); } catch {}
               }
               break;
               
               case "print":
               {
                  string to_print = "";
                  foreach(string args; operation_params)
                  {
                     to_print = to_print ~ args;
                  }
                  writeln("[print] ", to_print);
               }
               break;
               
               default:
               {
                  writeln("Unknown Operation: ", operation_token);
               }
            }
         }
      }
   }
}

void BuildOperation(BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   if(build_info.can_build)
   {
      if(version_info.is_versioned)
      {
         try 
         { 
            UpdateVersions(routine, version_info.type); 
         } catch { writeln("version update failed!"); }
      }
      
      JSONValue routine_json = GetRoutineJSON(routine);
      string[] arch_names = GetArchitectureNames(GlobalConfigFilePath);
      //TODO: reload versions or allow UpdateVersions to update version info
      
      foreach(string arch_name; arch_names)
      {
         build_info.platform.arch = arch_name;
         string output_folder = (build_info.build_folder.endsWith("/") ? build_info.build_folder[0 .. build_info.build_folder.lastIndexOf("/")] : build_info.build_folder) ~ "/" ~ build_info.platform.OS ~ "_" ~ build_info.platform.arch;
         string static_libraries = "";
         
         foreach(string static_library; build_info.static_libraries)
         {
            if(IsProperPlatform(static_library, build_info.platform))
            {
               static_libraries = static_libraries ~ " " ~ RemoveTags(static_library, build_info.platform);
            }
         }
         
         if(exists(output_folder))
         {
            rmdirRecurse(output_folder);
         }
            
         Build(output_folder, static_libraries, build_info, version_info);
         
         try { ExecutePerOperations(output_folder, routine, build_info, version_info); } catch {}
      }
   }
}

void CleanOperation(BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   if(build_info.can_build)
   {
      string[] arch_names = GetArchitectureNames(GlobalConfigFilePath);
      
      foreach(string arch_name; arch_names)
      {
         build_info.platform.arch = arch_name;
         string output_folder = (build_info.build_folder.endsWith("/") ? build_info.build_folder[0 .. build_info.build_folder.lastIndexOf("/")] : build_info.build_folder) ~ "/" ~ build_info.platform.OS ~ "_" ~ build_info.platform.arch;
         
         if(exists(output_folder))
         {
            rmdirRecurse(output_folder);
         }
      }
   }
}

void CopyOperation(string[] params)
{
   if(params.length == 2)
   {
      writeln("\tCopy ", params[0], " -> ", params[1]);
      CopyFile(params[0], params[1]);
   }
   else if(params.length == 3)
   {
      writeln("\tCopy ", params[0], " (", params[2], ") -> ", params[1]);
      CopyFolder(params[0], params[1], params[2]);
   }
}

void DeleteOperation(string[] params)
{
   if(params.length == 2)
   {
      writeln("\tDelete ", params[0], " (", params[1], ") -> /dev/null");
      DeleteFolder(params[0], params[1]);
   }
   else if(params.length == 1)
   {
      writeln("\tDelete ", params[0], " -> /dev/null");
      DeleteFile(params[0]);
   }
}

void MoveOperation(string[] params)
{
   if(params.length == 2)
   {
      writeln("\tMove ", params[0], " -> ", params[1]);
      CopyFile(params[0], params[1]);
      DeleteFile(params[0]);
   }
   else if(params.length == 3)
   {
      writeln("\tMove ", params[0], " (", params[2], ") -> ", params[1]);
      CopyFolder(params[0], params[1], params[2]);
      DeleteFolder(params[0], params[1]);
   }
}

void CallOperation(string[] params)
{
   writeln("Executing calls:");
   
   if(params.length > 1)
   {
      VersionType version_type = VersionType.None;
      bool function_called = false;
      
      foreach(string call_arg; params[1 .. $])
      {
         if(call_arg.startsWith("-"))
         {
            if(call_arg == "-major")
            {
               version_type = VersionType.Major;
            }
            else if(call_arg == "-minor")
            {
               version_type = VersionType.Minor;
            }
            else if(call_arg == "-patch")
            {
               version_type = VersionType.Patch;
            }
         }
         else
         {
            function_called = true;
            RunRoutine(params[0], call_arg, version_type);
         }
      }
   
      if(!function_called)
      {
         RunRoutine(params[0], GetDefaultRoutine(params[0]), version_type);
      }
   }
   else if(params.length == 1)
   {
      RunRoutine(params[0], GetDefaultRoutine(params[0]));
   }
}

void UpdateVersions(BuildRoutine routine, VersionType type)
{
   JSONValue file_json = parseJSON(readText(routine.path));
   
   if(type != VersionType.None)
   {
      if(file_json[routine.name].type() == JSON_TYPE.OBJECT)
      {  
         if(file_json[routine.name]["version"].type() == JSON_TYPE.ARRAY)
         {
            if(file_json[routine.name]["version"][0].type() == JSON_TYPE.INTEGER &&
               file_json[routine.name]["version"][1].type() == JSON_TYPE.INTEGER &&
               file_json[routine.name]["version"][2].type() == JSON_TYPE.INTEGER)
            {
               if(type == VersionType.Major)
               {
                  file_json[routine.name]["version"][0] = file_json[routine.name]["version"][0].integer + 1;
                  file_json[routine.name]["version"][1] = 0;
                  file_json[routine.name]["version"][2] = 0;
               }
               else if(type == VersionType.Minor)
               {
                  file_json[routine.name]["version"][1] = file_json[routine.name]["version"][1].integer + 1;
                  file_json[routine.name]["version"][2] = 0;
               }
               else if(type == VersionType.Patch)
               {
                  file_json[routine.name]["version"][2] = file_json[routine.name]["version"][2].integer + 1;
               }
            }
         }
      }
   }
   
   //TODO: writeln(routine.path ~ ":\n" ~ file_json.toPrettyString() ~ "\n");
   //TODO: enable this std.file.write(routine.path ~ ".new", file_json.toPrettyString());
}

JSONValue GetRoutineJSON(BuildRoutine routine)
{
   JSONValue file_json = parseJSON(readText(routine.path));
   
   try
   {
      if(file_json[routine.name].type() == JSON_TYPE.OBJECT)
      {
         return file_json[routine.name];
      }
   }
   catch
   {
      writeln("Routine " ~ routine.name ~ " not found in file " ~ routine.path ~ "!");
   }
   
   return JSONValue.init;
}

string[] GetLanguageCommands(string file_path, string language_name, string build_type)
{
   writeln("Loading language ", language_name, " commands (", build_type, ") from ", file_path);

   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   string[] output = null;
   
   try
   {
      if(file_json[language_name].type() == JSON_TYPE.OBJECT)
      {
         JSONValue language_json = file_json[language_name];
         
         if(language_json[build_type].type() == JSON_TYPE.OBJECT)
         {
            JSONValue build_type_json = language_json[build_type];
            
            if(build_type_json["commands"].type() == JSON_TYPE.ARRAY)
            {
               JSONValue commands_json = build_type_json["commands"];
               
               output = new string[commands_json.array.length];
               int index = 0;
            
               foreach(JSONValue value; commands_json.array)
               {
                  if(value.type() == JSON_TYPE.STRING)
                  {
                     output[index] = value.str();
                     ++index;
                  }
               }
            }
         }
      }
   }
   catch
   {
      writeln("Language config missing JSON element(s)!");
      exit(-1);
   }

   return output;
}

string GetLanguageFileEnding(string file_path, string language_name, string build_type)
{
   writeln("Loading language ", language_name, " ending (", build_type, ") from ", file_path);

   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   
   try
   {
      if(file_json[language_name].type() == JSON_TYPE.OBJECT)
      {
         JSONValue language_json = file_json[language_name];
         
         if(language_json[build_type].type() == JSON_TYPE.OBJECT)
         {
            JSONValue build_type_json = language_json[build_type];
            
            if(build_type_json["ending"].type() == JSON_TYPE.STRING)
            {
               return build_type_json["ending"].str();
            }
         }
      }
   }
   catch
   {
      writeln("Language config missing JSON element(s)!");
      exit(-1);
   }

   return null;
}

string[] GetArchitectureNames(string file_path)
{
   writeln("Loading available architectures from ", file_path);

   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   string[] arch_names = null;
   
   try
   {
      if(file_json["architectures"].type() == JSON_TYPE.ARRAY)
      {
         JSONValue arch_array_json = file_json["architectures"];
         arch_names = new string[arch_array_json.array.length];
         int index = 0;
         
         foreach(JSONValue element_json; arch_array_json.array)
         {
            if(element_json.type() == JSON_TYPE.STRING)
            {
               arch_names[index++] = element_json.str();
            }
         }
      }
   }
   catch 
   {
      writeln("No available architectures present!");
      exit(-1);
   }
   
   return arch_names;
}

bool IsProperPlatform(string tag, PlatformInformation platform)
{ 
   bool wrong_configuration = false;
   
   if(tag.startsWith("[ARCH: "))
   {
      if(!tag.startsWith("[ARCH: " ~ platform.arch ~ "]"))
      {
         wrong_configuration = true;
      }
   }
   
   if(tag.startsWith("[OS: "))
   {
      if(!tag.startsWith("[OS: " ~ platform.OS ~ "]"))
      {
         wrong_configuration = true;
      }
   }
   
   if(tag.startsWith("[OPT]") && !platform.optimized)
   {
      wrong_configuration = true;
   }
   else if(tag.startsWith("[NOPT]") && platform.optimized)
   {
      wrong_configuration = true;
   }
   
   return !wrong_configuration;
}

string RemoveTags(string tag, PlatformInformation platform)
{
   string new_tag = tag.replace("[ARCH: " ~ platform.arch ~ "]", "")
                       .replace("[OS: " ~ platform.OS ~ "]", "")
                       .replace("[OPT]", "")
                       .replace("[NOPT]", "");
                       
   int letter_index = 0;              
   foreach(char c; new_tag)
   {
      if(c != ' ')
         break;
         
      ++letter_index;
   }
   
   if(letter_index != 0)
   {
      //writeln(letter_index, " : |", new_tag);
      new_tag = new_tag[letter_index .. $];
      //writeln("|", new_tag);
   }
                       
   return new_tag;
}

void CopyFile(string source, string destination)
{
   try
   {
      string dest_directory = destination[0 .. destination.lastIndexOf("/")];
      if(!exists(dest_directory))
      {
         mkdir(dest_directory);
      }
   
      if(isFile(source))
      {
         copy(source, destination, PreserveAttributes.no);
      }
   } catch {} 
}

void CopyFolder(string source, string destination, string ending = "")
{
   try
   {
      if(isDir(source))
      {
         foreach(DirEntry e; dirEntries(source, SpanMode.shallow))
         {
            if(e.isFile() && e.name().endsWith(ending))
            {
               CopyFile(e.name(), destination ~ e.name().replace(source, ""));
            }
         }
      }
   } catch {}
}

void DeleteFile(string path)
{
   try
   {
      if(isFile(path))
      {
         remove(path);
      }
   } catch {} 
}

void DeleteFolder(string path, string ending = "")
{
   try
   {
      if(isDir(path))
      {
         foreach(DirEntry e; dirEntries(path, SpanMode.shallow))
         {
            if(e.isFile() && e.name().endsWith(ending))
            {
               DeleteFile(e.name());
            }
         }
      }
   } catch {}
}

void Build(string output_folder, string static_libraries, BuildInformation build_info, VersionInformation version_info)
{
   string temp_dir = "./" ~ randomUUID().toString();
   string[] commands = GetLanguageCommands(GlobalConfigFilePath, build_info.language, build_info.type);
   string file_ending = GetLanguageFileEnding(GlobalConfigFilePath, build_info.language, build_info.type);
   string version_string = to!string(version_info.major) ~ "_" ~ to!string(version_info.minor) ~ "_" ~ to!string(version_info.patch) ~ "_" ~ version_info.appended;
   string output_file_name = build_info.project_name ~ "_" ~ version_string;
   
   mkdir(temp_dir);
   
   if(!exists(output_folder))
   {
      mkdir(output_folder);
   }
   
   foreach(string source; build_info.source_folders)
   {
      CopyFile(source, temp_dir ~ "/" ~ source);
      CopyFolder(source, temp_dir ~ "/");
   }

   writeln("Building " ~ build_info.project_name ~ " for " ~ build_info.platform.arch ~ (build_info.platform.optimized ? "(OPT)" : "(NOPT)"));

   string command_batch = "";
   
   foreach(string command_template; commands)
   {
      if(IsProperPlatform(command_template, build_info.platform))
      {
         string command = RemoveTags(command_template, build_info.platform)
                          .replace("[PROJECT_NAME]", build_info.project_name)
                          .replace("[BUILD_DIRECTORY]", temp_dir)
                          .replace("[OUTPUT_FILE]", output_file_name)
                          .replace("[STATIC_LIBRARIES]", static_libraries);
         
         if(command_batch == "")
         {
            command_batch = command_batch ~ " ( " ~ command ~ " )";
         }
         else
         {
            command_batch = command_batch ~ " && ( " ~ command ~ " )";
         }
      }
   }
   
   system(toStringz(command_batch));
   
   CopyFile(temp_dir ~ "/" ~ build_info.project_name ~ file_ending, output_folder ~ "/" ~ output_file_name ~ file_ending);
   
   rmdirRecurse(temp_dir);
}