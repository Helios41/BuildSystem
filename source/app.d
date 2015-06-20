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
   -Clean up code & comments
   -Remove "./" from beginning of paths
   -Clean up relative paths
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

struct SourceDescription
{
   string path;
   string ending = "";
}

struct BuildInformation
{
   PlatformInformation platform;
   bool can_build;
   string type;
   string language;
   SourceDescription[] source_folders;
   string build_folder;
   string project_name;
   string[][string] attributes;
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
   
   if(!HasJSON(file_json, routine_name))
      return;
   
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
      routine_info.directory = file_path[0 .. file_path.lastIndexOf("/") + 1];
      
      if(HasJSON(routine_json, "project"))
      {
         if(routine_json["project"].type() == JSON_TYPE.STRING)
         {
            build_info.project_name = routine_json["project"].str();
         }   
      }      
      else
      {
         build_info.can_build = false;
      }
      
      if(HasJSON(routine_json, "language"))
      {
         if(routine_json["language"].type() == JSON_TYPE.STRING)
         {
            build_info.language = routine_json["language"].str();
         } 
      }      
      else
      {
         build_info.can_build = false;
      }
      
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
            build_info.source_folders = new SourceDescription[1];
            build_info.source_folders[0].path = routine_json["source"].str();
         }
         else if(routine_json["source"].type() == JSON_TYPE.ARRAY)
         {
            build_info.source_folders = new SourceDescription[routine_json["source"].array.length];
            int index = 0;
         
            foreach(JSONValue value; routine_json["source"].array)
            {
               if(value.type() == JSON_TYPE.STRING)
               {
                  build_info.source_folders[index].path = value.str();
                  ++index;
               }
               else if(value.type() == JSON_TYPE.ARRAY)
               {
                  if(value.array.length == 2)
                  {
                     if((value[0].type() == JSON_TYPE.STRING) && (value[1].type() == JSON_TYPE.STRING))
                     {
                        build_info.source_folders[index].path = value[0].str();
                        build_info.source_folders[index].ending = value[1].str();
                        ++index;
                     }
                  }
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
         if(HasJSON(routine_json, "attributes"))
         {
            if(routine_json["attributes"].type() == JSON_TYPE.ARRAY)
            {
               JSONValue attributes_json = routine_json["attributes"];
               
               foreach(JSONValue attribute_json; attributes_json.array)
               {
                  if(attribute_json.type() == JSON_TYPE.STRING)
                  {
                     string attribute_name = attribute_json.str();
                     
                     if(routine_json[attribute_name].type() == JSON_TYPE.STRING)
                     {
                        build_info.attributes[attribute_name] = new string[1];
                        build_info.attributes[attribute_name][0] = routine_json[attribute_name].str();
                     }
                     else if(routine_json[attribute_name].type() == JSON_TYPE.ARRAY)
                     {
                        JSONValue attribute_content_json = routine_json[attribute_name];
                        build_info.attributes[attribute_name] = new string[attribute_content_json.array.length];
                        int index = 0;
                        
                        foreach(JSONValue element_json; attribute_content_json.array)
                        {
                           if(element_json.type() == JSON_TYPE.STRING)
                           {
                              build_info.attributes[attribute_name][index] = element_json.str();
                              ++index;
                           }
                        }
                     }
                  }
               }
            }
         }
      } catch { writeln("Attribute system broke!"); }
      
      ExecuteOperations(routine_info, build_info, version_info);
   }
}

void ExecuteOperations(BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   JSONValue routine_json = GetRoutineJSON(routine);

   if(!HasJSON(routine_json, "operations"))
   {
      BuildOperation(routine, build_info, version_info);
      return;
   }
   
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
                  try { MoveOperation(routine, operation_params); } catch {}
               }
               break;
               
               case "delete":
               {
                  try { DeleteOperation(routine, operation_params); } catch {}
               }
               break;
               
               case "copy":
               {
                  try { CopyOperation(routine, operation_params); } catch {}
               }
               break;
               
               case "call":
               {
                  try { CallOperation(routine, operation_params); } catch {}
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
                  BuildOperation(routine, build_info, version_info);
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
   
   if(!HasJSON(routine_json, "per-operations"))
      return;
   
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
                  try { MoveOperation(routine, operation_params); } catch {}
               }
               break;
               
               case "delete":
               {
                  try { DeleteOperation(routine, operation_params); } catch {}
               }
               break;
               
               case "copy":
               {
                  try { CopyOperation(routine, operation_params); } catch {}
               }
               break;
               
               case "call":
               {
                  try { CallOperation(routine, operation_params); } catch {}
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
         
         if(exists(output_folder))
         {
            rmdirRecurse(output_folder);
         }
            
         Build(output_folder, routine, build_info, version_info);
         
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

void CopyOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      writeln("\tCopy ", routine_info.directory ~ RemoveLocal(params[0]), " -> ", routine_info.directory ~ RemoveLocal(params[1]));
      CopyFile(routine_info.directory ~ RemoveLocal(params[0]), routine_info.directory ~ RemoveLocal(params[1]));
   }
   else if(params.length == 3)
   {
      writeln("\tCopy ", routine_info.directory ~ RemoveLocal(params[0]), " (", params[2], ") -> ", routine_info.directory ~ RemoveLocal(params[1]));
      CopyFolder(routine_info.directory ~ RemoveLocal(params[0]), routine_info.directory ~ RemoveLocal(params[1]), params[2]);
   }
}

void DeleteOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      writeln("\tDelete ", routine_info.directory ~ params[0], " (", params[1], ") -> /dev/null");
      DeleteFolder(routine_info.directory ~ params[0], params[1]);
   }
   else if(params.length == 1)
   {
      writeln("\tDelete ", routine_info.directory ~ params[0], " -> /dev/null");
      DeleteFile(routine_info.directory ~ params[0]);
   }
}

void MoveOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      writeln("\tMove ", routine_info.directory ~ params[0], " -> ", routine_info.directory ~ params[1]);
      CopyFile(routine_info.directory ~ params[0], routine_info.directory ~ params[1]);
      DeleteFile(routine_info.directory ~ params[0]);
   }
   else if(params.length == 3)
   {
      writeln("\tMove ", routine_info.directory ~ params[0], " (", params[2], ") -> ", routine_info.directory ~ params[1]);
      CopyFolder(routine_info.directory ~ params[0], routine_info.directory ~ params[1], params[2]);
      DeleteFolder(routine_info.directory ~ params[0], routine_info.directory ~ params[1]);
   }
}

void CallOperation(BuildRoutine routine_info, string[] params)
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
            RunRoutine(routine_info.directory ~ params[0], call_arg, version_type);
         }
      }
   
      if(!function_called)
      {
         RunRoutine(routine_info.directory ~ params[0], GetDefaultRoutine(routine_info.directory ~ params[0]), version_type);
      }
   }
   else if(params.length == 1)
   {
      RunRoutine(routine_info.directory ~ params[0], GetDefaultRoutine(routine_info.directory ~ params[0]));
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

JSONValue GetLanguageJSON(string file_path, string language_name)
{
   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   
   if(HasJSON(file_json, "languages"))
   {
      JSONValue languages_json = file_json["languages"];
      if(HasJSON(languages_json, language_name))
      {
         JSONValue language_json = languages_json[language_name];
         return language_json;
      }
      else
      {
         writeln("Language config missing  for language \"", language_name, "\"");
         exit(-1);
      }
   }
   else
   {
      writeln("Language config missing \"language\" segment");
      exit(-1);
   }
   
   return JSONValue.init; 
}

string[] GetLanguageCommands(string file_path, string language_name, string build_type)
{
   writeln("Loading language ", language_name, " commands (", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   string[] output = null;
   
   if(HasJSON(language_json, build_type))
   {
      JSONValue build_type_json = language_json[build_type];
      
      if(HasJSON(build_type_json, "commands"))
      {
         JSONValue commands_json = build_type_json["commands"];
         
         if(commands_json.type() == JSON_TYPE.ARRAY)
         {
            output = new string[commands_json.array.length];
            int index = 0;
            
            foreach(JSONValue command_json; commands_json.array)
            {
               if(command_json.type() == JSON_TYPE.STRING)
                  output[index++] = command_json.str();
            }
         }
      }
   }

   return output;
}

string[] GetLanguageOptionalAttribs(string file_path, string language_name, string build_type)
{
   //writeln("Loading optional attributes for ", language_name, "(", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   string[] output = null;
   
   if(HasJSON(language_json, build_type))
   {
      JSONValue build_type_json = language_json[build_type];
      
      if(HasJSON(build_type_json, "optional"))
      {
         JSONValue optional_attribs_json = build_type_json["optional"];
         
         if(optional_attribs_json.type() == JSON_TYPE.ARRAY)
         {
            output = new string[optional_attribs_json.array.length];
            int index = 0;
            
            foreach(JSONValue attrib_json; optional_attribs_json.array)
            {
               if(attrib_json.type() == JSON_TYPE.STRING)
                  output[index++] = attrib_json.str();
            }
         }
      }
   }

   return output;
}

string GetLanguageFileEnding(string file_path, string language_name, string build_type)
{
   writeln("Loading language ", language_name, " ending (", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   
   if(HasJSON(language_json, build_type))
   {
      JSONValue build_type_json = language_json[build_type];
      
      if(HasJSON(build_type_json, "ending"))
      {
         JSONValue ending_json = build_type_json["ending"];
         
         if(ending_json.type() == JSON_TYPE.STRING)
         {
            return ending_json.str();
         }
      }
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

string ProcessTags(string tag, BuildInformation build_info)
{
   string new_tag = RemoveTags(tag, build_info.platform);
   
   foreach(string attrib_name, string[] attrib_array; build_info.attributes)
   {
      string attrib_string = "";
   
      foreach(string attrib_element; attrib_array)
      {
         if(IsProperPlatform(attrib_element, build_info.platform))
         {
            attrib_string = attrib_string ~ " " ~ RemoveTags(attrib_element, build_info.platform);
         }
      }
      
      new_tag = new_tag.replace("[ATTRIB: " ~ attrib_name ~ "]", attrib_string);
   }
   
   foreach(string optional_attrib_name; GetLanguageOptionalAttribs(GlobalConfigFilePath, build_info.language, build_info.type))
   {
      new_tag = new_tag.replace("[ATTRIB: " ~ optional_attrib_name ~ "]", ""); 
   }
   
   return new_tag;
}

bool AreTagsValid(string tag, BuildInformation build_info, bool extra_information = true)
{
   bool tags_valid = true;
   string copy_tag = RemoveTags(tag, build_info.platform);
   
   if(IsProperPlatform(tag, build_info.platform))
   {
      while(tags_valid)
      {
         int index_of = copy_tag.indexOf("[ATTRIB: ");
         
         if(index_of >= 0)
         {
            copy_tag = copy_tag[(index_of + "[ATTRIB: ".length) .. $];
            string attrib_name = copy_tag[0 .. copy_tag.indexOf("]")];
            copy_tag = copy_tag[copy_tag.indexOf("]") + 1 .. $];
            
            bool is_optional = GetLanguageOptionalAttribs(GlobalConfigFilePath, build_info.language, build_info.type).canFind(attrib_name);
            auto is_available = (attrib_name in build_info.attributes);
            if(!is_available && !is_optional)
            {
               if(extra_information)
               {
                  writeln("------------------------------------------------------");
                  writeln("Attribute \"", attrib_name, "\" not available! \nReferenced in tag\n\"", tag , "\"");
                  writeln("------------------------------------------------------");
               }
               tags_valid = false;
               break;
            }
         }
         else
         {
            break;
         }
      }
   }
   else
   {
      tags_valid = false;
   }
   
   return tags_valid;
}

bool HasJSON(JSONValue json, string ID)
{
   try
   {
      if(json.type() != JSON_TYPE.OBJECT)
      {
         return false;
      }
      json[ID];
      return true;
   }
   catch(JSONException exc)
   {
      return false;
   }
}

string RemoveLocal(string str)
{
   if(str.startsWith("./"))
   {
      return str[2 .. $];
   }
   
   return str;
}

void CopyFile(string source, string destination)
{
   try
   {
      string dest_directory = destination[0 .. destination.lastIndexOf("/")];
      if(!exists(dest_directory))
      {
         mkdirRecurse(dest_directory);
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

void Build(string output_folder, BuildRoutine routine_info, BuildInformation build_info, VersionInformation version_info)
{
   string temp_dir = routine_info.directory ~ build_info.project_name ~ "_" ~ routine_info.name ~ "_" ~ randomUUID().toString();
   string[] commands = GetLanguageCommands(GlobalConfigFilePath, build_info.language, build_info.type);
   string file_ending = GetLanguageFileEnding(GlobalConfigFilePath, build_info.language, build_info.type);
   string version_string = to!string(version_info.major) ~ "_" ~ to!string(version_info.minor) ~ "_" ~ to!string(version_info.patch) ~ "_" ~ version_info.appended;
   string output_file_name = build_info.project_name ~ (version_info.is_versioned ? " " ~ version_string : "");
   
   mkdirRecurse(temp_dir);
   
   if(!exists(routine_info.directory ~ output_folder))
   {
      mkdirRecurse(routine_info.directory ~ output_folder);
   }
   
   foreach(SourceDescription source; build_info.source_folders)
   {
      //writeln(temp_dir ~ "/" ~ source.path[source.path.indexOf("/") + 1 .. $]);
      CopyFile(routine_info.directory ~ source.path, temp_dir ~ "/" ~ source.path[source.path.indexOf("/") + 1 .. $]);
      CopyFolder(routine_info.directory ~ source.path, temp_dir ~ "/", source.ending);
   }

   writeln("Building " ~ build_info.project_name ~ " for " ~ build_info.platform.arch ~ (build_info.platform.optimized ? "(OPT)" : "(NOPT)"));

   string command_batch = "";
   
   foreach(string command_template; commands)
   {
      if(AreTagsValid(command_template, build_info))
      {
         string command = ProcessTags(command_template, build_info)
                          .replace("[PROJECT_NAME]", build_info.project_name)
                          .replace("[BUILD_DIRECTORY]", temp_dir)
                          .replace("[OUTPUT_FILE]", output_file_name);
     
         //writeln(command);
     
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
   
   CopyFile(temp_dir ~ "/" ~ build_info.project_name ~ file_ending, routine_info.directory ~ output_folder ~ "/" ~ output_file_name ~ file_ending);
   
   rmdirRecurse(temp_dir);
}