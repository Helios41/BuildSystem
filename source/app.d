import std.stdio;
import std.file;
import std.string;
import std.json;
import std.array;
import std.algorithm.searching;
import std.algorithm.comparison;
import std.c.stdlib;
import std.uuid;
import std.conv;
import std.container;

/**
TO DO:   
   -redesign field cross references (allow any value to use field cross references)
   -either build for host, all available or specified platforms (default host only)
   -specify platforms & host in the platform config on a per language basis? (If not move types out of "types" obj)
   -ability to download dependencies/sources (git or http)
   
   -Clean up code & comments
   -documentation
   -default platform configs
   
   -make the dll build script use /EXPORT instead of a .def & use delayed variable expansion
   
TO FIX:
   -Why is that folder created in the temporary directory?

NOTES:
   -CopyFile -> CopyItem (Item = both folders & files)
   -Is setting the platform to the host for the regular operations the right thing to do?
   -CopyFolderContents -> CopyMatchingItems (copy files in subfolders & keep the subfolders)
*/

const bool DEBUG_PRINTING = false;

static if(DEBUG_PRINTING)
{
   alias WriteMsg = writeln;
}
else
{
   alias WriteMsg = DontWriteMsg;
}

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
   
   string breakS = "_";
   VersionType type;
   
   bool is_versioned;
}

struct PlatformInformation
{
   bool optimized;
   string arch;
   string OS;
}

enum FileType : string
{
   Local = "local",
   Remote = "remote"
}

struct FileDescription
{
   string path;
   string begining = "";
   string ending = "";
   FileType type;
}

struct BuildInformation
{
   PlatformInformation platform;
   bool can_build;
   string type;
   string language;
   string build_folder;
   string project_name;
   string[][string] attributes;
   bool silent_build;
}

struct BuildRoutine
{  
   string directory;
   string path;
   string name;
   string platform_config_path;
}

struct ExternalVariable
{
   string declare;
   string value;
}

struct CommandInformation
{
   string command;
   string[] params;
}

const bool default_build_silent = false;

void LaunchConfig(string default_platform_config_path,
                  string config_file_path,
                  string[] args,
                  bool inhereted_build_silent = default_build_silent)
{
   if(exists(config_file_path ~ ".new"))
   {
      config_file_path = config_file_path ~ ".new";
   }

   bool function_called = false;
   
   VersionType version_type = VersionType.None; 
   string platform_config_path = default_platform_config_path;
   bool silent_build = default_build_silent;
   
   for(int i = 0; args.length > i; ++i)
   {
      string argument = args[i];
      
      if(argument.startsWith("-"))
      {
         switch(argument)
         {
            case "-major":
               version_type = VersionType.Major;
               break;
               
            case "-minor":
               version_type = VersionType.Minor;
               break;
               
            case "-patch":
               version_type = VersionType.Patch;
               break;
            
            case "-config":
            {
               if(args.length > (i + 1))
               {
                  platform_config_path = args[++i];
               }
               else
               {
                  writeln("Missing argument for option \"-config\"");
               }
            }
            break;
            
            case "-silent":
            {
               silent_build = true;
            }
            break;
            
            case "-pSilent":
            {
               silent_build = inhereted_build_silent;
            }
            break;
            
            default:
               writeln("Unknown option ", argument);
               break;
         }
      }
      else
      {
         function_called = true;
         RunRoutine(config_file_path, argument, platform_config_path, version_type, silent_build);
         
         version_type = VersionType.None; 
         platform_config_path = default_platform_config_path;
         silent_build = default_build_silent;
      }
   }
   
   if(!function_called)
   {
      RunRoutine(config_file_path, GetDefaultRoutine(config_file_path), platform_config_path, version_type, silent_build);
   }
}

void main(string[] args)
{
   if(args.length < 2)
   {
      writeln("Insufficient arguments!");
      writeln("Usage \'rebuild [config file]\'");
      return;
   }
   
   const string default_platform_config_path = "./platform_config.json";
   string config_file_path = args[1];
   
   if(!exists(default_platform_config_path))
   {
      writeln("Default platform config file missing! Generating empty json!");
      std.file.write(default_platform_config_path, "{\n}");
      return;
   }
      
   LaunchConfig(default_platform_config_path, config_file_path, args[2 .. $]);
}

string GetDefaultRoutine(string file_path)
{
   WriteMsg("Finding default routine of ", file_path);

   if((!exists(file_path)) || (!isFile(file_path)))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }

   JSONValue file_json = parseJSON(readText(file_path));
   
   if(HasJSON(file_json, "default"))
   {
      if(file_json["default"].type() == JSON_TYPE.STRING)
      {
         return file_json["default"].str();
      }
   }
   else
   {
      writeln("missing default routine");
      exit(-1);
   }
   
   return null;
}

void RunRoutine(string file_path, string routine_name, string default_platform_config_path, VersionType version_type, bool silent_build)
{
   WriteMsg("Executing routine ", routine_name, " in ", file_path);

   if((!exists(file_path)) || (!isFile(file_path)))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   
   if(!HasJSON(file_json, routine_name))
      return;
   
   JSONValue routine_json = file_json[routine_name];
   
   if(routine_json.type() == JSON_TYPE.OBJECT)
   {
      BuildRoutine routine_info = MakeRoutine(file_path, routine_name, default_platform_config_path);
   
      if(HasJSON(routine_json, "platform config"))
      {
         JSONValue specified_platform_config_json = routine_json["platform config"];
         
         if(specified_platform_config_json.type() == JSON_TYPE.STRING)
         {
            routine_info = MakeRoutine(file_path, routine_name, specified_platform_config_json.str());
         }
      }
   
      BuildInformation build_info;
      build_info.language = "";
      build_info.type = "";
      build_info.can_build = true;
      build_info.build_folder = "";
      build_info.project_name = "";
      build_info.platform = GetHost(routine_info.platform_config_path);
      build_info.platform.optimized = true;
      build_info.silent_build = silent_build;
      
      VersionInformation version_info;
      version_info.type = version_type;
      version_info.major = 0;
      version_info.minor = 0;
      version_info.patch = 0;
      version_info.appended = "";
      version_info.is_versioned = true;
      
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
      
      if(HasJSON(routine_json, "type"))
      {
         if(routine_json["type"].type() == JSON_TYPE.STRING)
         {
            build_info.type = routine_json["type"].str();
         }
      }      
      else
      {
         build_info.can_build = false;
      }
      
      if(HasJSON(routine_json, "build"))
      {
         if(routine_json["build"].type() == JSON_TYPE.STRING)
         {
            build_info.build_folder = routine_json["build"].str();
         }
      }
      else
      {
         build_info.can_build = false;
      }
      
      if(HasJSON(routine_json, "version"))
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
      else
      {
         version_info.is_versioned = false;
      }
      
      if(HasJSON(routine_json, "version_break"))
      {
         JSONValue version_break_json = routine_json["version_break"];
         
         if(version_break_json.type() == JSON_TYPE.STRING)
         {
            version_info.breakS = version_break_json.str();
         }
      }
      
      if(HasJSON(routine_json, "optimized"))
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
      
      if(HasJSON(routine_json, "attributes"))
      {
         if(routine_json["attributes"].type() == JSON_TYPE.ARRAY)
         {
            JSONValue attributes_json = routine_json["attributes"];
            
            foreach(JSONValue attribute_name_json; attributes_json.array)
            {
               if(attribute_name_json.type() == JSON_TYPE.STRING)
               {
                  string attribute_name = attribute_name_json.str();
                  JSONValue attribute_json = routine_json[attribute_name];
                  
                  build_info.attributes[attribute_name] = new string[JSONArraySize(attribute_json)];
                  JSONMapString(attribute_json, (string attrib_str, int i)
                  {
                     build_info.attributes[attribute_name][i] = attrib_str;
                  });
               }
            }
         }
      }
      
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
   
   JSONValue operations_json = routine_json["operations"];
   
   if(operations_json.type() == JSON_TYPE.ARRAY)
   {
      string last_operation_token = "";
      bool has_built = false;
      CommandInformation[] commands = LoadCommandsFromTag(routine, build_info, version_info, operations_json);
      
      WriteMsg("Executing Commands:");
      
      foreach(CommandInformation command; commands)
      {
         string operation_token = command.command;
         string[] operation_params = command.params;
         
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
            case "move":
               MoveOperation(routine, operation_params);
               break;
            
            case "delete":
               DeleteOperation(routine, operation_params);
               break;
            
            case "copy":
               CopyOperation(routine, operation_params);
               break;
            
            case "call":
               CallOperation(routine, build_info, operation_params);
               break;
            
            case "cmd":
               CommandOperation(routine, operation_params);
               break;
            
            case "replace":
               ReplaceOperation(routine, operation_params);
               break;
            
            case "build":
            {
               BuildOperation(routine, build_info, version_info);
               has_built = true;
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
               writeln("Unknown Operation: ", operation_token);
         }
      }
      
      if(!has_built)
         BuildOperation(routine, build_info, version_info);
   }
}

void ExecutePerOperations(string output_directory, BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   JSONValue routine_json = GetRoutineJSON(routine);
   string version_string = GetVersionString(version_info);
   
   if(!HasJSON(routine_json, "per-operations"))
   {
      Build(output_directory, routine, build_info, version_info);
      return;
   }
   
   JSONValue operations_json = routine_json["per-operations"];
   
   if(operations_json.type() == JSON_TYPE.ARRAY)
   {
      bool specifies_build = false;
      bool has_built = false;
      
      string[string] replace_additions;
      replace_additions["[OUTPUT_DIRECTORY]"] = output_directory;
      WriteMsg(replace_additions["[OUTPUT_DIRECTORY]"]);
      
      CommandInformation[] commands = LoadCommandsFromTag(routine, build_info, version_info, operations_json, replace_additions);
      
      foreach(CommandInformation command; commands)
      {
         if(command.command == "build")
         {
            specifies_build = true;
         }
      }
      
      if(!specifies_build)
      {
         has_built = true;
         Build(output_directory, routine, build_info, version_info);
      }
   
      string last_operation_token = "";
   
      WriteMsg("Executing Per Build Commands:");
      
      foreach(CommandInformation command; commands)
      {
         string operation_token = command.command;
         string[] operation_params = command.params;
         
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
            case "move":
               MoveOperation(routine, operation_params);
               break;
            
            case "delete":
               DeleteOperation(routine, operation_params);
               break;
            
            case "copy":
               CopyOperation(routine, operation_params);
               break;
            
            case "call":
               CallOperation(routine, build_info, operation_params);
               break;
            
            case "cmd":
               CommandOperation(routine, operation_params);
               break;
            
            case "replace":
               ReplaceOperation(routine, operation_params);
               break;
            
            case "build":
            {
               if(!has_built)
               {
                  has_built = true;
                  WriteMsg("\tBuilding...");
                  Build(output_directory, routine, build_info, version_info);
               }
               else
               {
                  WriteMsg("Already built!");
               }
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
               writeln("Unknown Operation: ", operation_token);
         }
      }
   }
}

void BuildOperation(BuildRoutine routine, BuildInformation build_info, VersionInformation in_version_info)
{
   if(build_info.can_build)
   {
      VersionInformation version_info = in_version_info;
   
      if(version_info.is_versioned)
      {
         version_info = UpdateVersions(routine, version_info); 
      }
      
      JSONValue routine_json = GetRoutineJSON(routine);
      string[int][string] platforms = GetAvailablePlatforms(routine.platform_config_path);
      
      foreach(string OS, string[int] archs; platforms)
      {
         foreach(string arch; archs)
         {
            build_info.platform.arch = arch;
            build_info.platform.OS = OS;
            
            string output_directory_noslash = build_info.build_folder.endsWith("/") ? build_info.build_folder[0 .. build_info.build_folder.lastIndexOf("/")] : build_info.build_folder;
            string output_folder = output_directory_noslash ~ "/" ~ build_info.platform.OS ~ "_" ~ build_info.platform.arch;
            
            if(exists(PathF(output_folder, routine)))
            {
               rmdirRecurse(PathF(output_folder, routine));
            }
            
            ExecutePerOperations(output_folder, routine, build_info, version_info);
         }
      }
   }
}

void CopyOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      WriteMsg("\tCopy ", PathF(params[0], routine_info), " -> ", PathF(params[1], routine_info));
      CopyItem(PathF(params[0], routine_info), PathF(params[1], routine_info));
   }
   else if(params.length == 3)
   {
      WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
      CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2]);
   }
   else if(params.length == 4)
   {
      if(IsValidInt(params[3]))
      {
         WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2], to!int(params[3]));
      }
      else
      {
         WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
      }
   }
   else if(params.length == 5)
   {
      WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
      
      if(IsValidInt(params[4]))
      {
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3], to!int(params[4]));
      }
      else
      {
         writeln(params[4], " failed to convert from string to int!");
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
      }
   }
}

void DeleteOperation(BuildRoutine routine_info, string[] params)
{  
   if(params.length == 1)
   {
      WriteMsg("\tDelete ", PathF(params[0], routine_info), " -> /dev/null");
      DeleteItem(PathF(params[0], routine_info));
   }
   else if(params.length == 2)
   {
      WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], ") -> /dev/null");
      DeleteFolderContents(PathF(params[0], routine_info), "", params[1]);
   }
   else if(params.length == 3)
   {
      if(IsValidInt(params[2]))
      {
         WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], ") -> /dev/null");
         DeleteFolderContents(PathF(params[0], routine_info), "", params[1], to!int(params[2]));
      }
      else
      {
         WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], " ", params[2], ") -> /dev/null");
         DeleteFolderContents(PathF(params[0], routine_info), params[1], params[2]);
      }
   }
   else if(params.length == 4)
   {
      if(IsValidInt(params[3]))
      {
         WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], " ", params[2], ") -> /dev/null");
         DeleteFolderContents(PathF(params[0], routine_info), params[1], params[2], to!int(params[3]));
      }
      else
      {
         writeln(params[3], " failed to convert from string to int!");
         DeleteFolderContents(PathF(params[0], routine_info), params[1], params[2]);
      }
   }
}

void MoveOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      WriteMsg("\tMove ", PathF(params[0], routine_info), " -> ", PathF(params[1], routine_info));
      CopyItem(PathF(params[0], routine_info), PathF(params[1], routine_info));
      DeleteItem(PathF(params[0], routine_info));
   }
   else if(params.length == 3)
   {
      WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
      CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2]);
      DeleteFolderContents(PathF(params[0], routine_info), "", params[2]);
   }
   else if(params.length == 4)
   {
      if(IsValidInt(params[3]))
      {
         WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2], to!int(params[3]));
         DeleteFolderContents(PathF(params[0], routine_info), "", params[2], to!int(params[3]));
      }
      else
      {
         WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
         DeleteFolderContents(PathF(params[0], routine_info), params[2], params[3]);
      }
   }
   else if(params.length == 5)
   {
      WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
   
      if(IsValidInt(params[4]))
      {
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3], to!int(params[4]));
         DeleteFolderContents(PathF(params[0], routine_info), params[2], params[3], to!int(params[4]));
      }
      else
      {
         writeln(params[4], " failed to convert from string to int!");
         CopyFolderContents(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
         DeleteFolderContents(PathF(params[0], routine_info), params[2], params[3]);
      }
   }
}

void CallOperation(BuildRoutine routine_info, BuildInformation build_info, string[] params)
{
   WriteMsg("Executing calls:");
   
   if(params.length >= 1)
   {
      const string default_platform_config_path = routine_info.platform_config_path; 
      string config_file_path = PathF(params[0], routine_info);
   
      if((params[0] == "=") || (params[0] == "||"))
      {
         config_file_path = routine_info.path;
      }
      
      LaunchConfig(default_platform_config_path,
                   config_file_path,
                   params[1 .. $],
                   build_info.silent_build);
   }
}

void CommandOperation(BuildRoutine routine_info, string[] params)
{
   foreach(string command; params)
   {
      system(toStringz(command));
   }
}

void ReplaceOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length > 2)
   {
      foreach(string file_name; params[2 .. $])
      {
         string file_path = PathF(file_name, routine_info);
         string file_contents = readText(file_path);
         file_contents = file_contents.replace(params[0], params[1]);
         std.file.write(file_path, file_contents);
      }
   }
}

string GetVersionString(VersionInformation version_info)
{
   string version_string = to!string(version_info.major) ~ version_info.breakS
                           ~ to!string(version_info.minor) ~ version_info.breakS
                           ~ to!string(version_info.patch)
                           ~ ((version_info.appended != "") ? (version_info.breakS ~ version_info.appended) : "");
   
   return version_string;
}

VersionInformation UpdateVersions(BuildRoutine routine, VersionInformation version_info)
{
   JSONValue file_json = parseJSON(readText(routine.path));
   bool update_versions = true;
   
   if(version_info.type != VersionType.None)
   {
      if(HasJSON(file_json, routine.name) &&
         HasJSON(file_json[routine.name], "version"))
      {
         JSONValue version_json = file_json[routine.name]["version"];
         
         if(version_json.type() != JSON_TYPE.ARRAY)
         {
            update_versions = false;
         }
         else
         {
            if(version_json.array.length < 3)
               update_versions = false;
         }
      }
      else
      {
         update_versions = false;
      }
   
      if(update_versions)
      {  
         if(file_json[routine.name]["version"][0].type() == JSON_TYPE.INTEGER &&
            file_json[routine.name]["version"][1].type() == JSON_TYPE.INTEGER &&
            file_json[routine.name]["version"][2].type() == JSON_TYPE.INTEGER)
         {
            if(version_info.type == VersionType.Major)
            {
               file_json[routine.name]["version"][0] = file_json[routine.name]["version"][0].integer + 1;
               file_json[routine.name]["version"][1] = 0;
               file_json[routine.name]["version"][2] = 0;
               
               version_info.major++;
               version_info.minor = 0;
               version_info.patch = 0;
            }
            else if(version_info.type == VersionType.Minor)
            {
               file_json[routine.name]["version"][1] = file_json[routine.name]["version"][1].integer + 1;
               file_json[routine.name]["version"][2] = 0;
               
               version_info.minor++;
               version_info.patch = 0;
            }
            else if(version_info.type == VersionType.Patch)
            {
               file_json[routine.name]["version"][2] = file_json[routine.name]["version"][2].integer + 1;
               
               version_info.patch++;
            }
         }
      }
      
      if(routine.path.endsWith(".new"))
      {
         std.file.write(routine.path, file_json.toPrettyString());
      }
      else
      {
         std.file.write(routine.path ~ ".new", file_json.toPrettyString());
      }
   }
   
   return version_info;
}

JSONValue GetRoutineJSON(BuildRoutine routine)
{
   JSONValue file_json = parseJSON(readText(routine.path));
   
   if(HasJSON(file_json, routine.name))
   {
      if(file_json[routine.name].type() == JSON_TYPE.OBJECT)
      {
         return file_json[routine.name];
      }
   }
   else
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
   }
   
   writeln("Platform config missing for language \"", language_name, "\"");
   exit(-1);
   
   return JSONValue.init; 
}

PlatformInformation GetHost(string file_path)
{
   WriteMsg("Get Host");
   
   JSONValue file_json = parseJSON(readText(file_path));
   
   if(HasJSON(file_json, "host"))
   {
      JSONValue host_json = file_json["host"];
      
      if(host_json.type() == JSON_TYPE.ARRAY)
      {
         if(host_json.array.length == 2)
         {
            if((host_json.array[0].type() == JSON_TYPE.STRING) &&
               (host_json.array[1].type() == JSON_TYPE.STRING))
            {
               PlatformInformation info;
               info.OS = host_json[0].str();
               info.arch = host_json[1].str();
               return info;
            } 
         }
      }
   }
   
   writeln("Platform config missing host");
   exit(-1);

   return PlatformInformation.init;
}

JSONValue GetLanguageCommandTag(string file_path, string language_name, string build_type)
{
   WriteMsg("Loading language ", language_name, " commands (", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   
   if(HasJSON(language_json, "types"))
   {
      JSONValue types_json = language_json["types"];
   
      if(HasJSON(types_json, build_type))
      {
         JSONValue build_type_json = types_json[build_type];
         
         if(HasJSON(build_type_json, "commands"))
            return build_type_json["commands"];
      }
   }
   
   writeln("Platform config missing commands for language ", language_name, "(", build_type, ")");
   exit(-1);
   
   return JSONValue.init;
}

string[] GetLanguageCommands(string file_path, string language_name, string build_type)
{
   WriteMsg("Loading language ", language_name, " commands (", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   string[] output = null;
   
   if(HasJSON(language_json, "types"))
   {
      JSONValue types_json = language_json["types"];
   
      if(HasJSON(types_json, build_type))
      {
         JSONValue build_type_json = types_json[build_type];
         
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
      else
      {
         writeln("Platform config missing commands for language ", language_name, "(", build_type, ")");
         exit(-1);
      }
   }
   
   return output;
}

string[] GetLanguageOptionalAttribs(string file_path, string language_name, string build_type)
{
   WriteMsg("Get Language Optional Attribs");

   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   string[] output = null;
   
   if(HasJSON(language_json, "types"))
   {
      JSONValue types_json = language_json["types"];
   
      if(HasJSON(types_json, build_type))
      {
         JSONValue build_type_json = types_json[build_type];
         
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
   }

   return output;
}

string GetLanguageFileEnding(string file_path, string language_name, string build_type)
{
   WriteMsg("Loading language ", language_name, " ending (", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   
   if(HasJSON(language_json, "types"))
   {
      JSONValue types_json = language_json["types"];
      
      if(HasJSON(types_json, build_type))
      {
         JSONValue build_type_json = types_json[build_type];
         
         if(HasJSON(build_type_json, "ending"))
         {
            JSONValue ending_json = build_type_json["ending"];
            
            if(ending_json.type() == JSON_TYPE.STRING)
            {
               return ending_json.str();
            }
         }
      }
   }

   return null;
}

string[int][string] GetAvailablePlatforms(string file_path)
{
   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   
   string[int][string] platforms;
   
   if(HasJSON(file_json, "platforms"))
   {
      JSONValue platforms_json = file_json["platforms"];
      
      if(platforms_json.type() == JSON_TYPE.ARRAY)
      {
         string current_platform = "";
      
         foreach(JSONValue platform_value; platforms_json.array)
         {
            if(platform_value.type() == JSON_TYPE.STRING)
            {
               current_platform = platform_value.str();
            }
            else if(platform_value.type() == JSON_TYPE.ARRAY)
            {
               if(current_platform != "")
               {
                  int index = 0;
                  
                  foreach(JSONValue arch_json; platform_value.array)
                  {
                     if(arch_json.type() == JSON_TYPE.STRING)
                     {
                        platforms[current_platform][index++] = arch_json.str();
                     }
                  }
                  
                  current_platform = "";
               }
            }
         }
      }
   }
   
   return platforms;
}

/*
   [EXTERN _file_>_routine_opt_>_var_]
*/

const string extern_decl_begin = "[EXTERN ";
const string extern_decl_end = "]";

ExternalVariable[] GetExternalVariables(BuildRoutine routine_info, 
                                        BuildInformation build_info,
                                        VersionInformation version_info,
                                        string tag_str)
{
   int extern_var_count = min(tag_str.count(extern_decl_begin),
                              tag_str.count(extern_decl_end));
   
   ExternalVariable[] extern_vars = new ExternalVariable[extern_var_count];
   int str_index = 0;
   
   for(int i = 0; i < extern_var_count; ++i)
   {
      int extern_index = tag_str.indexOf(extern_decl_begin, str_index);
      int extern_end_index = tag_str.indexOf(extern_decl_end, extern_index);
      string extern_decl = tag_str[extern_index .. extern_end_index + 1];
      
      string file_path = extern_decl[extern_decl_begin.length .. extern_decl.indexOf(">")];
      string routine_name;
      string var_name;
      
      file_path = PathF(file_path, routine_info);
      
      if(extern_decl.count(">") == 2)
      {
         routine_name = extern_decl[extern_decl.indexOf(">") + 1 .. extern_decl.lastIndexOf(">")];
         var_name = extern_decl[extern_decl.lastIndexOf(">") + 1 .. $ - 1];
      }
      else if(extern_decl.count(">") == 1)
      {
         routine_name = GetDefaultRoutine(file_path);
         var_name = extern_decl[extern_decl.lastIndexOf(">") + 1 .. $ - 1];
      }
      else
      {
         writeln("Invalid external variable: ", extern_decl);
         assert(false);
      }
      
      BuildRoutine extern_routine = MakeRoutine(file_path, routine_name, routine_info.platform_config_path);
      JSONValue extern_json = GetRoutineJSON(extern_routine);
      
      ExternalVariable extern_var;
      extern_var.declare = extern_decl;
      extern_var.value = "";
      
      if(HasJSON(extern_json, var_name))
      {
         string[] extern_var_value_raw = LoadStringArrayFromTag(routine_info,
                                                                build_info,
                                                                version_info,
                                                                extern_json[var_name]);
         
         if(extern_var_value_raw != null)
         {
            string extern_var_value = "";
         
            foreach(string str; extern_var_value_raw)
            {
               extern_var_value = extern_var_value ~ " " ~ str;
            }
            
            extern_var_value = extern_var_value[1 .. $];
            extern_var.value = extern_var_value;
         }                                        
      }
      
      extern_vars[i] = extern_var;
      
      str_index = extern_end_index;
   }
   
   return extern_vars;
}

BuildRoutine MakeRoutine(string file_path, string routine_name, string platform_config_path)
{
   BuildRoutine routine_info;
   
   routine_info.path = file_path;
   routine_info.name = routine_name;
   routine_info.directory = file_path[0 .. file_path.lastIndexOf("/") + 1];
   routine_info.platform_config_path = platform_config_path;
   
   return routine_info;
}

bool HasJSON(JSONValue json, string ID)
{
   try
   {
      if(json.type() != JSON_TYPE.OBJECT)
         return false;
         
      json[ID];
      return true;
   }
   catch(JSONException exc)
   {
      return false;
   }
}

string PathF(string str, BuildRoutine routine)
{
   string new_str = str;
   
   if(new_str.startsWith("./"))
      new_str = new_str[2 .. $];

   return routine.directory ~ new_str;
}

bool JSONMapString(JSONValue json, int starting_index, void delegate(string str, int i) map_func)
{
   if(json.type() == JSON_TYPE.ARRAY)
   {
      int i = starting_index;
   
      foreach(JSONValue element_json; json.array)
      {
         if(element_json.type() == JSON_TYPE.STRING)
         {
            map_func(element_json.str(), i);
            ++i;
         }
      }
   }
   else if(json.type() == JSON_TYPE.STRING)
   {
      map_func(json.str(), starting_index);
   }
   else
   {
      return false;
   }
   
   return true;
}

bool JSONMapString(JSONValue json, void delegate(string str, int i) map_func)
{
   return JSONMapString(json, 0, map_func);
}

int JSONArraySize(JSONValue json)
{
   if(json.type() == JSON_TYPE.STRING)
   {
      return 1;
   }
   else if(json.type() == JSON_TYPE.ARRAY)
   {
      return json.array.length;
   }
   
   return 0;
}

string GetAttribString(BuildRoutine routine_info, 
                       BuildInformation build_info,
                       VersionInformation version_info,
                       string attrib_name)
{
   WriteMsg("Loading ", attrib_name, " from ", routine_info.path);
   string attrib_value = "";

   JSONValue routine_json = GetRoutineJSON(routine_info);
   
   if(HasJSON(routine_json, attrib_name))
   {
      JSONValue attrib_json = routine_json[attrib_name];
      
      string[] attribs = LoadStringArrayFromTag(routine_info, build_info, version_info, attrib_json, null, attrib_name);
      
      foreach(string str; attribs)
      {
         attrib_value = attrib_value ~ " " ~ str;
      }
   }
   
   if(attrib_value.length > 0)
      return attrib_value[1 .. $];
      
   return "";
}

bool HandleConditional(BuildRoutine routine_info, 
                       BuildInformation build_info,
                       VersionInformation version_info,
                       string condit_str)
{
   string conditional = condit_str[0 .. condit_str.indexOf("=") + 1];
   string value = condit_str[condit_str.indexOf("=") + 1 .. $];
   
   switch(conditional)
   {
      case "OS=":
      {
         return (value == build_info.platform.OS);
      }
      
      case "ARCH=":
      {
         return (value == build_info.platform.arch);
      }
      
      case "OPT=":
      {
         return (value == to!string(build_info.platform.optimized));
      }
      
      case "SILENT=":
      {
         return (value == to!string(build_info.silent_build));
      }
      
      default:
   }
   
   return false;
}

string ProcessTag(BuildRoutine routine_info, 
                  BuildInformation build_info,
                  VersionInformation version_info,
                  string str,
                  string[string] replace_additions,
                  string str_attrib_group)
{ 
   string new_str = str.replace("[ARCH_NAME]", build_info.platform.arch)
                       .replace("[OS_NAME]", build_info.platform.OS)
                       .replace("[PROJECT_NAME]", build_info.project_name)
                       .replace("[MAJOR_VERSION]", to!string(version_info.major))
                       .replace("[MINOR_VERSION]", to!string(version_info.minor))
                       .replace("[PATCH_VERSION]", to!string(version_info.patch))
                       .replace("[VERSION_TYPE]", version_info.appended)
                       .replace("[VERSION]", GetVersionString(version_info));
                       
   if(replace_additions != null)
   {
      foreach(string orig_str, string repl_str; replace_additions)
      {
         new_str = new_str.replace(orig_str, repl_str);
      }
   }
   
   foreach(string attrib_name, string[] attrib_array; build_info.attributes)
   {
      if(attrib_name != str_attrib_group)
      {
         new_str = new_str.replace("[ATTRIB: " ~ attrib_name ~ "]",
                                   GetAttribString(routine_info, build_info, version_info, attrib_name));
      }
   }
   
   //TODO: fix this properly, this is temporary
   if(build_info.can_build)
   {
      foreach(string optional_attrib_name; GetLanguageOptionalAttribs(routine_info.platform_config_path, build_info.language, build_info.type))
      {
         new_str = new_str.replace("[ATTRIB: " ~ optional_attrib_name ~ "]", ""); 
      }
   }
      
   foreach(ExternalVariable extern_var; GetExternalVariables(routine_info, build_info, version_info, new_str))
   {
      new_str = new_str.replace(extern_var.declare, extern_var.value);
   }
   
   return new_str;
}

string LoadStringFromTag(BuildRoutine routine_info, 
                         BuildInformation build_info,
                         VersionInformation version_info,
                         JSONValue json,
                         string[string] replace_additions = null,
                         string str_attrib_group = "")
{
   if(json.type() == JSON_TYPE.OBJECT)
   {
      if(HasJSON(json, "if") && HasJSON(json, "then"))
      {
         JSONValue if_json = json["if"];
         JSONValue then_json = json["then"];
         
         if(((if_json.type() == JSON_TYPE.STRING) || (if_json.type() == JSON_TYPE.ARRAY)) &&
            (then_json.type() == JSON_TYPE.STRING))
         {
            bool state = true;
            
            JSONMapString(if_json, (string condit_str, int i)
            {
               state = state && HandleConditional(routine_info, build_info, version_info, condit_str);
            });
            
            if(state)
            {
               return ProcessTag(routine_info, build_info, version_info, then_json.str(), replace_additions, str_attrib_group);
            }
            else if(HasJSON(json, "else"))
            {
               JSONValue else_json = json["else"];
               
               if(else_json.type() == JSON_TYPE.STRING)
               {
                  return ProcessTag(routine_info, build_info, version_info, else_json.str(), replace_additions, str_attrib_group);
               }
            }
         }
      }
   }
   else if(json.type() == JSON_TYPE.STRING)
   {
      return json.str();
   }
   
   writeln("ERROR! stopping!");
   writeln("Could load string from tag");
   exit(-1);
   
   return null;
}

void LoadStringArrayFromTag_internal(BuildRoutine routine_info, 
                                     BuildInformation build_info,
                                     VersionInformation version_info,
                                     JSONValue json,
                                     Array!string *sarray,
                                     string[string] replace_additions = null,
                                     string str_attrib_group = "")
{
   if(HasJSON(json, "if") && HasJSON(json, "then"))
   {
      JSONValue if_json = json["if"];
      JSONValue then_json = json["then"];
      
      if(((if_json.type() == JSON_TYPE.STRING) || (if_json.type() == JSON_TYPE.ARRAY)) &&
         ((then_json.type() == JSON_TYPE.STRING) || (then_json.type() == JSON_TYPE.ARRAY)))
      {
         bool state = true;
         
         JSONMapString(if_json, (string condit_str, int i)
         {
            state = state && HandleConditional(routine_info, build_info, version_info, condit_str);
         });
         
         if(state)
         {
            JSONMapString(then_json, (string str, int i)
            {
               sarray.insert(ProcessTag(routine_info, build_info, version_info, str, replace_additions, str_attrib_group));
            });
         }
         else if(HasJSON(json, "else"))
         {
            JSONValue else_json = json["else"];
            
            JSONMapString(else_json, (string str, int i)
            {
               sarray.insert(ProcessTag(routine_info, build_info, version_info, str, replace_additions, str_attrib_group));
            }); 
         }
      }
   }
}

string[] LoadStringArrayFromTag(BuildRoutine routine_info, 
                                BuildInformation build_info,
                                VersionInformation version_info,
                                JSONValue json,
                                string[string] replace_additions = null,
                                string str_attrib_group = "")
{
   Array!string sarray = Array!string();
   
   if(json.type() == JSON_TYPE.ARRAY)
   {
      foreach(JSONValue json_value; json.array)
      {
         if(json_value.type() == JSON_TYPE.OBJECT)
         {
            LoadStringArrayFromTag_internal(routine_info, build_info, version_info, json_value, &sarray, replace_additions, str_attrib_group);
         }
         else if(json_value.type() == JSON_TYPE.STRING)
         {
            JSONMapString(json_value, (string str, int i)
            {
               sarray.insert(ProcessTag(routine_info, build_info, version_info, str, replace_additions, str_attrib_group));
            }); 
         }
      }
   }
   else if(json.type() == JSON_TYPE.OBJECT)
   {
      LoadStringArrayFromTag_internal(routine_info, build_info, version_info, json, &sarray, replace_additions, str_attrib_group);
   }

   if(sarray.length > 0)
   {
      string[] output = new string[sarray.length];
      int index = 0;
      
      foreach(string str; sarray)
      {
         output[index++] = str;
      }
      
      return output;
   }
   
   return null;
}

CommandInformation[] LoadCommandsFromTag(BuildRoutine routine_info, 
                                         BuildInformation build_info,
                                         VersionInformation version_info,
                                         JSONValue json,
                                         string[string] replace_additions = null,
                                         string str_attrib_group = "")
{
   Array!CommandInformation command_list = Array!CommandInformation();

   if(json.type() == JSON_TYPE.ARRAY)
   {
      foreach(JSONValue json_value; json.array)
      {
         CommandInformation command;
      
         if(json_value.type() == JSON_TYPE.STRING)
         {
            command.command = json_value.str();
         }
         else
         {
            string[] strings = LoadStringArrayFromTag(routine_info, build_info, version_info, json_value, replace_additions, str_attrib_group);
            
            if(strings == null)
               continue;
            
            command.command = strings[0];
            command.params = strings[1 .. $];
         }
         
         command_list.insert(command);
      }
   }

   if(command_list.length > 0)
   {
      CommandInformation[] output = new CommandInformation[command_list.length];
      int index = 0;
      
      foreach(CommandInformation cmd; command_list)
      {
         output[index++] = cmd;
      }
      
      return output;
   }
   
   return null;
}

FileDescription[] LoadFileDescriptionsFromTag(BuildRoutine routine_info, 
                                              BuildInformation build_info,
                                              VersionInformation version_info,
                                              JSONValue json)
{
   Array!FileDescription file_list = Array!FileDescription();
   
   if(json.type() == JSON_TYPE.ARRAY)
   {
      foreach(JSONValue json_value; json.array)
      {
         FileDescription fdesc;
         fdesc.type = FileType.Local; 
      
         if(json_value.type() == JSON_TYPE.STRING)
         {
            fdesc.path = json_value.str();
         }
         else
         {
            string[] strings = LoadStringArrayFromTag(routine_info, build_info, version_info, json_value);
            
            if(strings == null)
               continue;
            
            fdesc.path = strings[0];
            
            if(strings.length == 2)
            {
               if(IsValidFileType(strings[0]))
               {
                  fdesc.path = strings[1];
                  fdesc.type = to!FileType(strings[0]);
               }
               else
               {
                  fdesc.ending = strings[1];
               }
            }  
            else if(strings.length == 3)
            {
               fdesc.begining = strings[1];
               fdesc.ending = strings[2];
            }
         }
         
         file_list.insert(fdesc);
      }
   }
   else if(json.type() == JSON_TYPE.STRING)
   {
      FileDescription fdesc;
      fdesc.path = json.str();
      
      file_list.insert(fdesc);
   }
   
   if(file_list.length > 0)
   {
      FileDescription[] output = new FileDescription[file_list.length];
      int index = 0;
      
      foreach(FileDescription fdesc; file_list)
      {
         output[index++] = fdesc;
      }
      
      return output;
   }
   
   return null;
}

void CopyItem(string source, string destination)
{
   try
   {
      string dest_directory = destination[0 .. destination.lastIndexOf("/")];
      
      if(!exists(dest_directory))
         mkdirRecurse(dest_directory);
   
      if(exists(source))
         copy(source, destination, PreserveAttributes.no);
         
   } catch {} 
}

void CopyMatchingItems_internal(string source, string destination, string begining, string ending, int depth)
{
   if(isDir(source))
   {
      foreach(DirEntry e; dirEntries(source, SpanMode.shallow))
      {
         string entry_path = e.name().replace(source, "");
         
         if(entry_path.startsWith("\\") || entry_path.startsWith("/"))
            entry_path = entry_path[1 .. $];
         
         if(e.isDir() && ((depth - 1) >= 0))
         {
            CopyMatchingItems_internal(e.name(), destination ~ e.name().replace(source, ""), begining, ending, depth - 1);
         }
         
         if(e.isFile() && entry_path.startsWith(begining) && entry_path.endsWith(ending))
         {
            if(!exists(destination))
               mkdirRecurse(destination);
               
            CopyItem(e.name(), destination ~ e.name().replace(source, ""));
         }
      }
   }
}

void CopyFolderContents(string source, string destination, string begining = "", string ending = "", int depth = 0)
{
   try
   {
      CopyMatchingItems_internal(source, destination, begining, ending, depth);
   } catch {}
}

void DeleteItem(string path)
{
   try
   {
      if(exists(path))
         remove(path);

   } catch {} 
}

void DeleteMatchingItems_internal(string path, string begining, string ending, int depth)
{
   if(isDir(path))
   {
      foreach(DirEntry e; dirEntries(path, SpanMode.shallow))
      {
         string entry_path = e.name().replace(path, "");
         
         if(entry_path.startsWith("\\") || entry_path.startsWith("/"))
            entry_path = entry_path[1 .. $];
         
         if(e.isDir() && ((depth - 1) >= 0))
         {
            DeleteMatchingItems_internal(e.name(), begining, ending, depth - 1);
         }
         
         if(e.isFile() && entry_path.startsWith(begining) && entry_path.endsWith(ending))
            DeleteItem(e.name());
      }
   }
}

void DeleteFolderContents(string path, string begining = "", string ending = "", int depth = 0)
{
   try
   {
      DeleteMatchingItems_internal(path, begining, ending, depth);
   } catch {}
}

void DontWriteMsg(T...)(T args)
{
   static if(DEBUG_PRINTING)
   {
      writeln(T);
   }
}

void DownloadFile(string source, string dest)
{
   string curl_download_command = ("curl \"" ~ source ~ "\" -o \"" ~ dest ~ "\" 1> nul 2> nul");
   writeln(curl_download_command);
   //system(toStringz(curl_download_command));
}

bool IsValidInt(string str)
{
   try
   {
      int i = to!int(str);
      
      return true;
   }
   catch(ConvException e)
   {
      return false;
   }
}

bool IsValidFileType(string str)
{
   try
   {
      FileType t = to!FileType(str);
      
      return true;
   }
   catch(ConvException e)
   {
      return false;
   }
}

void Build(string output_folder, BuildRoutine routine_info, BuildInformation build_info, VersionInformation version_info)
{
   string temp_dir = routine_info.directory ~ build_info.project_name ~ "_" ~ routine_info.name ~ "_" ~ randomUUID().toString();
   string file_ending = GetLanguageFileEnding(routine_info.platform_config_path, build_info.language, build_info.type);
   string version_string = GetVersionString(version_info);
                           
   string output_file_name = build_info.project_name ~ 
                             (version_info.is_versioned ? (version_info.breakS ~ version_string) : "");
   
   mkdirRecurse(temp_dir);
   
   if(!exists(PathF(output_folder, routine_info)))
   {
      mkdirRecurse(PathF(output_folder, routine_info));
   }
   
   JSONValue routine_json = GetRoutineJSON(routine_info);
   string dependencies = "";
   
   if(HasJSON(routine_json, "source"))
   {
      FileDescription[] source_folders = LoadFileDescriptionsFromTag(routine_info, build_info, version_info, routine_json["source"]);
      
      foreach(FileDescription source; source_folders)
      {
         WriteMsg("Src " ~ PathF(source.path, routine_info) ~ "|" ~ source.begining ~ "|" ~ source.ending);
         
         if(source.type == FileType.Local)
         {
            if((source.begining != "") || (source.ending != ""))
            {
               CopyFolderContents(PathF(source.path, routine_info), temp_dir ~ "/", source.begining, source.ending);
            }
            else
            {
               CopyItem(PathF(source.path, routine_info), temp_dir ~ "/" ~ source.path[source.path.lastIndexOf("/") + 1 .. $]);
            }
         }
         else if(source.type == FileType.Remote)
         {
            string dest_path = temp_dir ~ "/" ~ source.path[source.path.lastIndexOf("/") + 1 .. $];
            DownloadFile(source.path, dest_path);
         }
      }
   }
   
   if(HasJSON(routine_json, "dependencies"))
   {
      FileDescription[] dependency_items = LoadFileDescriptionsFromTag(routine_info, build_info, version_info, routine_json["dependencies"]);
      
      foreach(FileDescription dep; dependency_items)
      {
         if(dep.type == FileType.Local)
         {
            if(exists(PathF(dep.path, routine_info)))
            {
               WriteMsg("FDep " ~ PathF(dep.path, routine_info) ~ "|" ~ dep.begining ~ "|" ~ dep.ending);
               
               if((dep.begining != "") || (dep.ending != ""))
               {
                  CopyFolderContents(PathF(dep.path, routine_info), temp_dir ~ "/", dep.begining, dep.ending);
               }
               else
               {
                  CopyItem(PathF(dep.path, routine_info), temp_dir ~ "/" ~ dep.path[dep.path.lastIndexOf("/") + 1 .. $]);
               }
            }
            else
            {
               WriteMsg("LDep " ~ dep.path);
               
               if(!dependencies.canFind(" " ~ dep.path))
                  dependencies = dependencies ~ " " ~ dep.path;
            }
         }
         else if(dep.type == FileType.Remote)
         {
            string dest_path = temp_dir ~ "/" ~ dep.path[dep.path.lastIndexOf("/") + 1 .. $];
            DownloadFile(dep.path, dest_path);
         }
      }
   }
   
   writeln("Building " ~ build_info.project_name ~ " for " ~ build_info.platform.arch ~ (build_info.platform.optimized ? "(OPT)" : "(NOPT)"));
   
   string command_batch = "";
   
   string[] command_templates = LoadStringArrayFromTag(routine_info,
                                                       build_info,
                                                       version_info,
                                                       GetLanguageCommandTag(routine_info.platform_config_path, build_info.language, build_info.type));
   
   foreach(string command_template; command_templates)
   {
      string command = command_template.replace("[BUILD_DIRECTORY]", temp_dir)
                                       .replace("[DEPENDENCIES]", dependencies);
   
      command_batch = command_batch ~ " && ( " ~ command ~ " )";
   }
   
   command_batch = "(" ~ command_batch[4 .. $] ~ ")";
   
   if(build_info.silent_build)
   {
      version(Windows)
      {
         command_batch = command_batch ~ " 1> nul 2> nul";
      }
      else
      {
         command_batch = command_batch ~ " 2>&1 > /dev/null";
      }
   }
   
   system(toStringz(command_batch));
   
   CopyItem(temp_dir ~ "/" ~ build_info.project_name ~ file_ending, PathF(output_folder, routine_info) ~ "/" ~ output_file_name ~ file_ending);
   
   rmdirRecurse(temp_dir);
}