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
import std.datetime;

/**
TO DO:   
   -warning if target is not supported
   
   -Clean up code & comments
   -documentation
   -default platform configs
   
   -update .json.new file by checking file date of original
   
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
   void DontWriteMsg(T...)(T args) {}
}

void ExitError(string msg)
{
   writeln("ERROR! stopping!");
   writeln(msg);
   exit(-1);
}

enum VersionType : string
{
   None = "None",
   Major = "Major",
   Minor = "Minor",
   Patch = "Patch"
}

struct VersionInfo
{
   int major;
   int minor;
   int patch;
   string appended;
   
   string breakS = "_";
   VersionType type;
   
   bool is_versioned;
}

struct PlatformInfo
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

struct RoutineState
{
   BuildInfo build_info;
   VersionInfo version_info;
   RoutineInfo routine_info;
}

struct BuildTarget
{
   string OS;
   string[] archs;
}

struct BuildInfo
{
   PlatformInfo platform;
   bool can_build;
   string type;
   string language;
   string build_folder;
   string project_name;
   bool silent_build;
   BuildTarget[] targets;
}

struct RoutineInfo
{  
   string directory;
   string path;
   string name;
   string platform_config_path;
}

struct Variable
{
   int location;
   int length;
   string declare;
   string[] value;
}

struct CommandInformation
{
   string command;
   string[] params;
}

enum TagType
{
   String,
   StringArray
}

struct ProcessedTag
{
   string str;
   string[] array;
}

const bool default_build_silent = false;

void LaunchConfig(string default_platform_config_path,
                  string config_file_path,
                  string[] args,
                  bool inhereted_build_silent = default_build_silent)
{
   if(exists(config_file_path ~ ".new"))
   {
      string regular_config_path = config_file_path;
      config_file_path = config_file_path ~ ".new";
      
      SysTime null_time;
      
      SysTime regular_config;
      getTimes(regular_config_path, null_time, regular_config);
      
      SysTime new_config;
      getTimes(config_file_path, null_time, new_config);
      
      if(regular_config.stdTime() > new_config.stdTime())
      {
         //TODO: update .json.new
         writeln("The config file has been updated without the .new file");
      }
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

   JSONValue file_json = LoadJSONFile(file_path);
   
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

BuildInfo GetBuildInfo(RoutineState state, bool silent_build)
{
   BuildInfo *build_info = &state.build_info;
   
   build_info.language = "";
   build_info.type = "";
   build_info.can_build = true;
   build_info.build_folder = "";
   build_info.project_name = "";
   build_info.silent_build = silent_build;
   
   JSONString project;
   if(GetJSONString(state, "project", &project))
   {
      build_info.project_name = project.get();
   }
   else
   {
      build_info.can_build = false;
   }
   
   JSONString language;
   if(GetJSONString(state, "language", &language))
   {
      build_info.language = language.get();
   }
   else
   {
      build_info.can_build = false;
   }
   
   if(build_info.can_build)
   {
      build_info.platform = GetHostInfo(state.routine_info.platform_config_path, build_info.language);
      build_info.platform.optimized = true;
   }
   
   JSONString type;
   if(GetJSONString(state, "type", &type))
   {
      build_info.type = type.get();
   }
   else
   {
      build_info.can_build = false;
   }
   
   JSONString build;
   if(GetJSONString(state, "build", &build))
   {
      build_info.build_folder = build.get();
   }
   else
   {
      build_info.can_build = false;
   }
   
   JSONBool optimized;
   if(GetJSONBool(state, "optimized", &optimized))
   {
      build_info.platform.optimized = optimized.get();
   }
   
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(build_info.can_build && HasJSON(routine_json, "target"))
   {
      BuildTarget[] build_targets = LoadBuildTargetsFromTag(state, routine_json["target"]);
      build_info.targets = build_targets;
      
      if(build_targets == null)
      {
         build_info.can_build = false;
      }
   }
   else
   {
      build_info.can_build = false;
   }
   
   if(!build_info.can_build)
   {
      WriteMsg("CANT BUILD");
   }
   
   return *build_info;
}

VersionInfo GetVersionInfo(RoutineState state, VersionType version_type)
{
   VersionInfo *version_info = &state.version_info;
   
   version_info.type = version_type;
   version_info.major = 0;
   version_info.minor = 0;
   version_info.patch = 0;
   version_info.appended = "";
   version_info.is_versioned = true;
   
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(HasJSON(routine_json, "version"))
   {
      if(routine_json["version"].type() == JSON_TYPE.ARRAY)
      {
         JSONValue version_json = routine_json["version"];
         
         if(version_json.array.length >= 3)
         {
            if(version_json[0].type() == JSON_TYPE.INTEGER)
            {
               state.version_info.major = to!int(version_json[0].integer);
            }
            
            if(version_json[1].type() == JSON_TYPE.INTEGER)
            {
               state.version_info.minor = to!int(version_json[1].integer);
            }
            
            if(version_json[2].type() == JSON_TYPE.INTEGER)
            {
               state.version_info.patch = to!int(version_json[2].integer);
            }
         }
         else
         {
            state.version_info.is_versioned = false;
         }
         
         if(version_json.array.length == 4)
         {   
            if(version_json[3].type() == JSON_TYPE.STRING)
            {
               state.version_info.appended = version_json[3].str();
            }
         }
      }
   }
   else
   {
      state.version_info.is_versioned = false;
   }
   
   JSONString version_break;
   if(GetJSONString(state, "version_break", &version_break))
   {
      version_info.breakS = version_break.get();
   }
   
   return *version_info;
}

void RunRoutine(string file_path, string routine_name, string default_platform_config_path, VersionType version_type, bool silent_build)
{
   WriteMsg("Executing routine ", routine_name, " in ", file_path);

   if((!exists(file_path)) || (!isFile(file_path)))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = LoadJSONFile(file_path);
   
   if(!HasJSON(file_json, routine_name))
      return;
   
   JSONValue routine_json = file_json[routine_name];
   
   if(routine_json.type() == JSON_TYPE.OBJECT)
   {
      RoutineState state;
   
      state.routine_info = MakeRoutine(file_path, routine_name, default_platform_config_path);
      state.build_info = GetBuildInfo(state, silent_build);
      state.version_info = GetVersionInfo(state, version_type);
      
      ExecuteOperations(state);
   }
}

void ExecuteOperations(RoutineState state)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);

   if(!HasJSON(routine_json, "operations"))
   {
      BuildOperation(state);
      return;
   }
   
   JSONValue operations_json = routine_json["operations"];
   
   if(operations_json.type() == JSON_TYPE.ARRAY)
   {
      string last_operation_token = "";
      bool has_built = false;
      CommandInformation[] commands = LoadCommandsFromTag(state, operations_json);
      
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
               MoveOperation(state.routine_info, operation_params);
               break;
            
            case "delete":
               DeleteOperation(state.routine_info, operation_params);
               break;
            
            case "copy":
               CopyOperation(state.routine_info, operation_params);
               break;
            
            case "call":
               CallOperation(state.routine_info, state.build_info, operation_params);
               break;
            
            case "cmd":
               CommandOperation(state.routine_info, operation_params);
               break;
            
            case "replace":
               ReplaceOperation(state.routine_info, operation_params);
               break;
            
            case "build":
            {
               BuildOperation(state);
               has_built = true;
            }
            break;
            
            case "print":
            {
               PrintOperation(operation_params);
            }
            break;
            
            default:
               writeln("Unknown Operation: ", operation_token);
         }
      }
      
      if(!has_built)
         BuildOperation(state);
   }
}

void ExecutePerOperations(string output_directory, RoutineState state)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   string version_string = GetVersionString(state.version_info);
   
   if(!HasJSON(routine_json, "per-operations"))
   {
      Build(output_directory, state);
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
      
      CommandInformation[] commands = LoadCommandsFromTag(state, operations_json, replace_additions);
      
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
         Build(output_directory, state);
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
               MoveOperation(state.routine_info, operation_params);
               break;
            
            case "delete":
               DeleteOperation(state.routine_info, operation_params);
               break;
            
            case "copy":
               CopyOperation(state.routine_info, operation_params);
               break;
            
            case "call":
               CallOperation(state.routine_info, state.build_info, operation_params);
               break;
            
            case "cmd":
               CommandOperation(state.routine_info, operation_params);
               break;
            
            case "replace":
               ReplaceOperation(state.routine_info, operation_params);
               break;
            
            case "build":
            {
               if(!has_built)
               {
                  has_built = true;
                  WriteMsg("\tBuilding...");
                  Build(output_directory, state);
               }
               else
               {
                  WriteMsg("Already built!");
               }
            }
            break;
            
            case "print":
            {
               PrintOperation(operation_params);
            }
            break;
            
            default:
               writeln("Unknown Operation: ", operation_token);
         }
      }
   }
}

void BuildOperation(RoutineState state)
{
   if(state.build_info.can_build)
   {
      VersionInfo version_info = state.version_info;
   
      if(version_info.is_versioned)
      {
         version_info = UpdateVersions(state.routine_info, state.version_info); 
      }
      
      //TODO: fix version not being used
      
      foreach(BuildTarget target; state.build_info.targets)
      {
         foreach(string arch; target.archs)
         {
            RoutineState per_platform_state = state;
            
            per_platform_state.build_info.platform.arch = arch;
            per_platform_state.build_info.platform.OS = target.OS;
            per_platform_state.version_info = version_info;
            
            string output_directory_noslash = per_platform_state.build_info.build_folder.endsWith("/") ? per_platform_state.build_info.build_folder[0 .. per_platform_state.build_info.build_folder.lastIndexOf("/")] : per_platform_state.build_info.build_folder;
            string output_folder = output_directory_noslash ~ "/" ~ per_platform_state.build_info.platform.OS ~ "_" ~ per_platform_state.build_info.platform.arch;
            
            if(exists(PathF(output_folder, per_platform_state.routine_info)))
            {
               rmdirRecurse(PathF(output_folder, per_platform_state.routine_info));
            }
            
            ExecutePerOperations(output_folder, per_platform_state);
         }
      }
   }
}

void CopyOperation(RoutineInfo routine_info, string[] params)
{
   if(params.length == 2)
   {
      WriteMsg("\tCopy ", PathF(params[0], routine_info), " -> ", PathF(params[1], routine_info));
      CopyItem(PathF(params[0], routine_info), PathF(params[1], routine_info));
   }
   else if(params.length == 3)
   {
      WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
      CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2]);
   }
   else if(params.length == 4)
   {
      if(IsValid!int(params[3]))
      {
         WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2], to!int(params[3]));
      }
      else
      {
         WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
      }
   }
   else if(params.length == 5)
   {
      WriteMsg("\tCopy ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
      
      if(IsValid!int(params[4]))
      {
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3], to!int(params[4]));
      }
      else
      {
         writeln(params[4], " failed to convert from string to int!");
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
      }
   }
}

void DeleteOperation(RoutineInfo routine_info, string[] params)
{  
   if(params.length == 1)
   {
      WriteMsg("\tDelete ", PathF(params[0], routine_info), " -> /dev/null");
      DeleteItem(PathF(params[0], routine_info));
   }
   else if(params.length == 2)
   {
      WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], ") -> /dev/null");
      DeleteMatchingItems(PathF(params[0], routine_info), "", params[1]);
   }
   else if(params.length == 3)
   {
      if(IsValid!int(params[2]))
      {
         WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], ") -> /dev/null");
         DeleteMatchingItems(PathF(params[0], routine_info), "", params[1], to!int(params[2]));
      }
      else
      {
         WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], " ", params[2], ") -> /dev/null");
         DeleteMatchingItems(PathF(params[0], routine_info), params[1], params[2]);
      }
   }
   else if(params.length == 4)
   {
      if(IsValid!int(params[3]))
      {
         WriteMsg("\tDelete ", PathF(params[0], routine_info), " (", params[1], " ", params[2], ") -> /dev/null");
         DeleteMatchingItems(PathF(params[0], routine_info), params[1], params[2], to!int(params[3]));
      }
      else
      {
         writeln(params[3], " failed to convert from string to int!");
         DeleteMatchingItems(PathF(params[0], routine_info), params[1], params[2]);
      }
   }
}

void MoveOperation(RoutineInfo routine_info, string[] params)
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
      CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2]);
      DeleteMatchingItems(PathF(params[0], routine_info), "", params[2]);
   }
   else if(params.length == 4)
   {
      if(IsValid!int(params[3]))
      {
         WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), "", params[2], to!int(params[3]));
         DeleteMatchingItems(PathF(params[0], routine_info), "", params[2], to!int(params[3]));
      }
      else
      {
         WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
         DeleteMatchingItems(PathF(params[0], routine_info), params[2], params[3]);
      }
   }
   else if(params.length == 5)
   {
      WriteMsg("\tMove ", PathF(params[0], routine_info), " (", params[2], " ", params[3], ") -> ", PathF(params[1], routine_info));
   
      if(IsValid!int(params[4]))
      {
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3], to!int(params[4]));
         DeleteMatchingItems(PathF(params[0], routine_info), params[2], params[3], to!int(params[4]));
      }
      else
      {
         writeln(params[4], " failed to convert from string to int!");
         CopyMatchingItems(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2], params[3]);
         DeleteMatchingItems(PathF(params[0], routine_info), params[2], params[3]);
      }
   }
}

void CallOperation(RoutineInfo routine_info, BuildInfo build_info, string[] params)
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

void CommandOperation(RoutineInfo routine_info, string[] params)
{
   foreach(string command; params)
   {
      system(toStringz(command));
   }
}

void ReplaceOperation(RoutineInfo routine_info, string[] params)
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

void PrintOperation(string[] params)
{
   string to_print = "";
   string separator = "";
   
   for(int i = 0; params.length > i; ++i)
   {
      string arg = params[i];
      
      if(arg.startsWith("-"))
      {
         switch(arg)
         {
            case "-separator":
            {
               if(params.length > (i + 1))
               {
                  if(separator == "")
                  {
                     separator = params[++i];
                  }
                  else
                  {
                     writeln("[print error] Separator can only be set once");
                  }
               }
               else
               {
                  writeln("[print error] Missing argument for option \"-separator\"");
               }
            }
            break;
            
            default:
         }
      }
      else
      {
         to_print = to_print ~ separator ~ arg;
      }
   }
   
   if(to_print.startsWith(separator))
   {
      to_print = to_print[separator.length .. $];
   }
   
   writeln("[print] ", to_print);
}

string GetVersionString(VersionInfo version_info)
{
   string version_string = to!string(version_info.major) ~ version_info.breakS
                           ~ to!string(version_info.minor) ~ version_info.breakS
                           ~ to!string(version_info.patch)
                           ~ ((version_info.appended != "") ? (version_info.breakS ~ version_info.appended) : "");
   
   return version_string;
}

VersionInfo UpdateVersions(RoutineInfo routine, VersionInfo version_info)
{
   JSONValue file_json = LoadJSONFile(routine.path);
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

JSONValue LoadJSONFile(string path)
{
   try
   {
      string json_text = readText(path);
      JSONValue json_value = parseJSON(json_text);
      return json_value;
   }
   catch(JSONException e)
   {
      writeln(e);
      exit(-1);
      return JSONValue.init;
   }
}

JSONValue GetRoutineJSON(RoutineInfo routine)
{
   JSONValue file_json = LoadJSONFile(routine.path);
   
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
   
   JSONValue file_json = LoadJSONFile(file_path);
   
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

PlatformInfo GetHostInfo(string file_path, string language)
{
   WriteMsg("Get Host");
   
   JSONValue file_json = LoadJSONFile(file_path);
   
   if(HasJSON(file_json, "languages"))
   {
      JSONValue languages_json = file_json["languages"];
      
      if(HasJSON(languages_json, language))
      {
         JSONValue language_json = languages_json[language];
         
         if(HasJSON(language_json, "host"))
         {
            JSONValue host_json = language_json["host"];
            
            if(host_json.type() == JSON_TYPE.ARRAY)
            {
               if(host_json.array.length == 2)
               {
                  if((host_json[0].type() == JSON_TYPE.STRING) &&
                     (host_json[1].type() == JSON_TYPE.STRING))
                  {
                     PlatformInfo info;
                     info.OS = host_json[0].str();
                     info.arch = host_json[1].str();
                     return info;
                  }
               }
            }
         }
      }
   }
   
   writeln("Platform config missing host");
   exit(-1);

   return PlatformInfo.init;
}

BuildTarget GetHost(string file_path, string language)
{
   WriteMsg("Get Host");
   
   JSONValue file_json = LoadJSONFile(file_path);
   
   if(HasJSON(file_json, "languages"))
   {
      JSONValue languages_json = file_json["languages"];
      
      if(HasJSON(languages_json, language))
      {
         JSONValue language_json = languages_json[language];
         
         if(HasJSON(language_json, "host"))
         {
            JSONValue host_json = language_json["host"];
            
            if(host_json.type() == JSON_TYPE.ARRAY)
            {
               if(host_json.array.length == 2)
               {
                  if((host_json[0].type() == JSON_TYPE.STRING) &&
                     (host_json[1].type() == JSON_TYPE.STRING))
                  {
                     BuildTarget target;
                     target.OS = host_json[0].str();
                     target.archs = new string[1];
                     target.archs[0] = host_json[1].str();
                     return target;
                  }
               }
            }
         }
      }
   }
   
   writeln("Platform config missing host");
   exit(-1);

   return BuildTarget.init;
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

string[] GetLanguageFileEndings(string file_path, string language_name, string build_type, RoutineState state)
{
   WriteMsg("Loading language ", language_name, " ending (", build_type, ") from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   
   if(HasJSON(language_json, "types"))
   {
      JSONValue types_json = language_json["types"];
      
      if(HasJSON(types_json, build_type))
      {
         JSONValue build_type_json = types_json[build_type];
         
         if(HasJSON(build_type_json, "endings"))
         {
            JSONValue endings_json = build_type_json["endings"];
            string[] file_endings = LoadStringArrayFromTag(state, endings_json, TagType.StringArray);
            return file_endings;
         }
      }
   }

   return null;
}

string[int][string] GetAvailablePlatforms(string file_path, string language)
{
   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = LoadJSONFile(file_path);
   
   string[int][string] platforms;
   
   if(HasJSON(file_json, "languages"))
   {
      JSONValue languages_json = file_json["languages"];
      
      if(HasJSON(languages_json, language))
      {
         JSONValue language_json = languages_json[language];
         
         if(HasJSON(language_json, "platforms"))
         {
            JSONValue platforms_json = language_json["platforms"];
            
            if(platforms_json.type() == JSON_TYPE.ARRAY)
            {
               string current_platform = "";
               
               foreach(JSONValue platform_json; platforms_json.array)
               {
                  if(platform_json.type() == JSON_TYPE.STRING)
                  {
                     current_platform = platform_json.str();
                  }
                  else if(platform_json.type() == JSON_TYPE.ARRAY)
                  {
                     int index = 0;
                     
                     foreach(JSONValue arch_json; platform_json.array)
                     {
                        if(arch_json.type() == JSON_TYPE.STRING)
                           platforms[current_platform][index++] = arch_json.str();
                     }
                     
                     current_platform = "";
                  }
               }
            }
         }
      }
   }
   
   return platforms;
}

const string var_decl_begin = "[VAR ";
const string var_decl_end = "]";

Variable[] GetVariables(RoutineState state,
                        string tag_str)
{
   int var_count = min(tag_str.count(var_decl_begin),
                       tag_str.count(var_decl_end));
   
   Variable[] vars = new Variable[var_count];
   int str_index = 0;
   
   for(int i = 0; i < var_count; ++i)
   {
      int var_index = tag_str.indexOf(var_decl_begin, str_index);
      int var_end_index = tag_str.indexOf(var_decl_end, var_index);
      string var_decl = tag_str[var_index .. var_end_index + 1];
      
      string file_path;
      string routine_name;
      string var_name;
      
      if(var_decl.count(">") == 2)
      {
         string path = var_decl[var_decl_begin.length .. var_decl.indexOf(">")];
         
         if(path == "THIS")
         {
            file_path = state.routine_info.path;
         }
         else
         {
            file_path = path;
            file_path = PathF(file_path, state.routine_info);
         }
         
         routine_name = var_decl[var_decl.indexOf(">") + 1 .. var_decl.lastIndexOf(">")];
         var_name = var_decl[var_decl.lastIndexOf(">") + 1 .. $ - 1];
      }
      else if(var_decl.count(">") == 1)
      {
         string path = var_decl[var_decl_begin.length .. var_decl.indexOf(">")];
         
         if(path == "THIS")
         {
            file_path = state.routine_info.path;
         }
         else
         {
            file_path = path;
            file_path = PathF(file_path, state.routine_info);
         }
         
         routine_name = GetDefaultRoutine(file_path);
         var_name = var_decl[var_decl.lastIndexOf(">") + 1 .. $ - 1];
      }
      else if(var_decl.count(">") == 0)
      {
         file_path = state.routine_info.path;
         routine_name = state.routine_info.name;
         var_name = var_decl[var_decl_begin.length .. $ - 1];
      }
      else
      {
         writeln("Invalid variable declaration: ", var_decl);
         exit(-1);
      }
      
      RoutineState access_state;
      access_state.routine_info = MakeRoutine(file_path, routine_name, state.routine_info.platform_config_path);
      access_state.build_info = GetBuildInfo(access_state, state.build_info.silent_build);
      access_state.version_info = GetVersionInfo(access_state, VersionType.None);
      
      JSONValue access_json = GetRoutineJSON(access_state.routine_info);
      
      Variable var;
      var.declare = var_decl;
      var.value = null;
      var.location = var_index;
      var.length = var_decl.length;
      
      if(HasJSON(access_json, var_name))
      {
         string[] var_value_raw = LoadStringArrayFromTag(access_state,
                                                         access_json[var_name],
                                                         TagType.StringArray);
         
         var.value = var_value_raw;     
      }
      
      vars[i] = var;
      
      str_index = var_end_index;
   }
   
   return vars;
}

string CombindStrings(string[] strings)
{
   string result = "";

   foreach(string str; strings)
   {
      result = result ~ " " ~ str;
   }
   
   if(result.length > 1)
      return result[1 .. $];
      
   return result;
}

RoutineInfo MakeRoutine(string file_path,
                         string routine_name,
                         string default_platform_config_path,
                         bool can_specify_platform_config = true)
{
   RoutineInfo routine_info;
   
   routine_info.path = file_path;
   routine_info.name = routine_name;
   routine_info.directory = file_path[0 .. file_path.lastIndexOf("/") + 1];
   routine_info.platform_config_path = default_platform_config_path;
   
   if(can_specify_platform_config)
   {
      JSONValue file_json = LoadJSONFile(file_path);
      
      if(HasJSON(file_json, routine_name))
      {
         JSONValue routine_json = file_json[routine_name];
         
         if(HasJSON(routine_json, "platform config"))
         {
            JSONValue specified_platform_config_json = routine_json["platform config"];
            
            if(specified_platform_config_json.type() == JSON_TYPE.STRING)
            {
               routine_info.platform_config_path = PathF(specified_platform_config_json.str(), routine_info);
            }
         }
      }
   }
   
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

bool IsJSONBool(JSONValue json)
{
   return (json.type() == JSON_TYPE.TRUE) || (json.type() == JSON_TYPE.FALSE);
}

string PathF(string str, RoutineInfo routine)
{
   string new_str = str;
   
   if(new_str.startsWith("./"))
      new_str = new_str[2 .. $];

   return routine.directory ~ new_str;
}

bool JSONMapString(JSONValue json, void delegate(string str, int i) map_func)
{
   if(json.type() == JSON_TYPE.ARRAY)
   {
      int i = 0;
   
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
      map_func(json.str(), 0);
   }
   else
   {
      return false;
   }
   
   return true;
}

bool HandleConditional(RoutineState state,
                       string condit_str)
{
   string conditional = condit_str[0 .. condit_str.indexOf("=") + 1];
   string value = condit_str[condit_str.indexOf("=") + 1 .. $];
   
   switch(conditional)
   {
      case "OS=":
      {
         return (value == state.build_info.platform.OS);
      }
      
      case "ARCH=":
      {
         return (value == state.build_info.platform.arch);
      }
      
      case "OPT=":
      {
         return (value == to!string(state.build_info.platform.optimized));
      }
      
      case "SILENT=":
      {
         return (value == to!string(state.build_info.silent_build));
      }
      
      case "HASVAR=":
      {
         JSONValue routine_json = GetRoutineJSON(state.routine_info);
         if(HasJSON(routine_json, value))
         {
            JSONValue value_json = routine_json[value];
            
            if((value_json.type() == JSON_TYPE.STRING) ||   
               (value_json.type() == JSON_TYPE.ARRAY))
            {
               return true;
            }
         }
         return false;
      }
      
      default:
   }
   
   return false;
}

ProcessedTag ProcessTag(RoutineState state,
                        string str,
                        string[string] replace_additions,
                        TagType tag_type)
{ 
   string new_str = str.replace("[ARCH_NAME]", state.build_info.platform.arch)
                       .replace("[OS_NAME]", state.build_info.platform.OS)
                       .replace("[PROJECT_NAME]", state.build_info.project_name)
                       .replace("[MAJOR_VERSION]", to!string(state.version_info.major))
                       .replace("[MINOR_VERSION]", to!string(state.version_info.minor))
                       .replace("[PATCH_VERSION]", to!string(state.version_info.patch))
                       .replace("[VERSION_TYPE]", state.version_info.appended)
                       .replace("[VERSION]", GetVersionString(state.version_info));
  
   if(replace_additions != null)
   {
      foreach(string orig_str, string repl_str; replace_additions)
      {
         new_str = new_str.replace(orig_str, repl_str);
      }
   }
   
   Array!string tag_list = Array!string();
   int str_index = 0;
   
   foreach(Variable var; GetVariables(state, new_str))
   {
      tag_list.insert(new_str[0 .. var.location]);
      str_index = var.location + var.length;
      
      foreach(string var_value; var.value)
      {
         tag_list.insert(var_value);
      }
   }
   
   if((str_index != new_str.length) && (tag_list.length > 0))
   {
      tag_list.insert(new_str[str_index .. $]);
   }
   
   ProcessedTag result;
   
   if(tag_list.length > 0)
   {
      result.array = new string[tag_list.length];
      int index = 0;
      
      foreach(string tag_str; tag_list)
      {
         result.array[index++] = tag_str;
      }
   }
   else
   {
      result.array = new string[1];
      result.array[0] = new_str;
   }
   
   if(tag_type == TagType.String)
   {
      result.str = CombindStrings(result.array);
   }
   
   return result;
}

string LoadStringFromTag(RoutineState state,
                         JSONValue json,
                         string[string] replace_additions = null)
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
            bool condit_state = true;
            
            JSONMapString(if_json, (string condit_str, int i)
            {
               condit_state = condit_state && HandleConditional(state, condit_str);
            });
            
            if(condit_state)
            {
               return ProcessTag(state, then_json.str(), replace_additions, TagType.String).str;
            }
            else if(HasJSON(json, "else"))
            {
               JSONValue else_json = json["else"];
               
               if(else_json.type() == JSON_TYPE.STRING)
               {
                  return ProcessTag(state, else_json.str(), replace_additions, TagType.String).str;
               }
            }
         }
      }
   }
   else if(json.type() == JSON_TYPE.STRING)
   {
      return json.str();
   }
   
   ExitError("Couldn't load string from tag!");
   return null;
}

bool LoadBoolFromTag(RoutineState state,
                     JSONValue json)
{
   if(json.type() == JSON_TYPE.OBJECT)
   {
      if(HasJSON(json, "if") && HasJSON(json, "then"))
      {
         JSONValue if_json = json["if"];
         JSONValue then_json = json["then"];
         
         if(((if_json.type() == JSON_TYPE.STRING) || (if_json.type() == JSON_TYPE.ARRAY)) &&
            IsJSONBool(then_json))
         {
            bool condit_state = true;
            
            JSONMapString(if_json, (string condit_str, int i)
            {
               condit_state = condit_state && HandleConditional(state, condit_str);
            });
            
            if(condit_state)
            {
               return (then_json.type() == JSON_TYPE.TRUE);
            }
            else if(HasJSON(json, "else"))
            {
               JSONValue else_json = json["else"];
               
               if(IsJSONBool(else_json))
               {
                  return (else_json.type() == JSON_TYPE.TRUE); 
               }
            }
         }
      }
   }
   else if(IsJSONBool(json))
   {
      return (json.type() == JSON_TYPE.TRUE);
   }
   
   ExitError("Couldn't load bool from tag!");
   return false;
}

void InsertProcessedTags(Array!string *sarray, 
                         RoutineState state,
                         string str,
                         string[string] replace_additions,
                         TagType type)
{
   if(type == TagType.String)
   {
      sarray.insert(ProcessTag(state, str, replace_additions, TagType.String).str);
   }
   else if(type == TagType.StringArray)
   {
      foreach(string tag_str; ProcessTag(state, str, replace_additions, TagType.StringArray).array)
      {
         sarray.insert(tag_str);
      }
   }
}

void LoadStringArrayFromTag_internal(RoutineState state,
                                     JSONValue json,
                                     Array!string *sarray,
                                     string[string] replace_additions,
                                     TagType type)
{
   if(HasJSON(json, "if") && HasJSON(json, "then"))
   {
      JSONValue if_json = json["if"];
      JSONValue then_json = json["then"];
      
      if(((if_json.type() == JSON_TYPE.STRING) || (if_json.type() == JSON_TYPE.ARRAY)) &&
         ((then_json.type() == JSON_TYPE.STRING) || (then_json.type() == JSON_TYPE.ARRAY)))
      {
         bool condit_state = true;
         
         JSONMapString(if_json, (string condit_str, int i)
         {
            condit_state = condit_state && HandleConditional(state, condit_str);
         });
         
         if(condit_state)
         {
            JSONMapString(then_json, (string str, int i)
            {
               InsertProcessedTags(sarray, state, str, replace_additions, type);
            });
         }
         else if(HasJSON(json, "else"))
         {
            JSONValue else_json = json["else"];
            
            JSONMapString(else_json, (string str, int i)
            {
               InsertProcessedTags(sarray, state, str, replace_additions, type);
            }); 
         }
      }
   }
}

string[] LoadStringArrayFromTag(RoutineState state,
                                JSONValue json,
                                TagType type,
                                string[string] replace_additions = null)
{
   Array!string sarray = Array!string();
   
   if(json.type() == JSON_TYPE.ARRAY)
   {
      foreach(JSONValue json_value; json.array)
      {
         if(json_value.type() == JSON_TYPE.OBJECT)
         {
            LoadStringArrayFromTag_internal(state, json_value, &sarray, replace_additions, type);
         }
         else if(json_value.type() == JSON_TYPE.STRING)
         {
            InsertProcessedTags(&sarray, state, json_value.str(), replace_additions, type);
         }
      }
   }
   else if(json.type() == JSON_TYPE.OBJECT)
   {
      LoadStringArrayFromTag_internal(state, json, &sarray, replace_additions, type);
   }
   else if(json.type() == JSON_TYPE.STRING)
   {
      InsertProcessedTags(&sarray, state, json.str(), replace_additions, type);
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

CommandInformation[] LoadCommandsFromTag(RoutineState state,
                                         JSONValue json,
                                         string[string] replace_additions = null)
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
            string[] strings = LoadStringArrayFromTag(state, json_value, TagType.StringArray, replace_additions);
            
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

FileDescription[] LoadFileDescriptionsFromTag(RoutineState state,
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
            string[] strings = LoadStringArrayFromTag(state, json_value, TagType.String);
            
            if(strings == null)
               continue;
            
            fdesc.path = strings[0];
            
            if(strings.length == 2)
            {
               if(IsValid!FileType(strings[0]))
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

BuildTarget[] LoadBuildTargetsFromTag(RoutineState state,
                                      JSONValue json)
{
   Array!BuildTarget target_list = Array!BuildTarget();
   
   if(json.type() == JSON_TYPE.STRING)
   {
      if(json.str() == "host")
      {
         target_list.insert(GetHost(state.routine_info.platform_config_path, state.build_info.language));
      }
      else if(json.str() == "all")
      {
         string[int][string] platforms = GetAvailablePlatforms(state.routine_info.platform_config_path,
                                                               state.build_info.language);
         foreach(string OS, string[int] archs; platforms)
         {
            BuildTarget target;
            target.OS = OS;
            target.archs = new string[archs.length];
            
            int index = 0;
            
            foreach(string arch; archs)
            {   
               target.archs[index++] = arch;
            }
            
            target_list.insert(target);
         }
      }
   }
   else if(json.type() == JSON_TYPE.ARRAY)
   {
      Array!BuildTarget specified_target_list = Array!BuildTarget();
      bool OS_set = false;
      BuildTarget current_target;
      
      foreach(JSONValue json_value; json.array)
      {
         if(json_value.type() == JSON_TYPE.STRING)
         {
            OS_set = true;
            current_target = BuildTarget.init;
            
            current_target.OS = json_value.str();
         }
         else if(json_value.type() == JSON_TYPE.ARRAY)
         {
            if(OS_set)
            {
               current_target.archs = new string[json_value.array.length];
               int index = 0;
               
               foreach(JSONValue arch_json; json_value.array)
               {
                  current_target.archs[index++] = arch_json.str();
               }
               
               specified_target_list.insert(current_target);
            }
         }
      }
      
      Array!BuildTarget available_target_list = Array!BuildTarget();
      
      string[int][string] platforms = GetAvailablePlatforms(state.routine_info.platform_config_path,
                                                            state.build_info.language);
      foreach(string OS, string[int] archs; platforms)
      {
         BuildTarget target;
         target.OS = OS;
         target.archs = new string[archs.length];
         
         int index = 0;
         
         foreach(string arch; archs)
         {   
            target.archs[index++] = arch;
         }
         
         available_target_list.insert(target);
      }
      
      foreach(BuildTarget wanted_target; specified_target_list)
      {
         foreach(BuildTarget supported_target; available_target_list)
         {
            if(wanted_target.OS == supported_target.OS)
            {
               BuildTarget target;
               target.OS = wanted_target.OS;
               target.archs = new string[wanted_target.archs.length];
               int index = 0;
               
               foreach(string arch_name; wanted_target.archs)
               {
                  if(supported_target.archs.canFind(arch_name))
                  {
                     target.archs[index++] = arch_name;
                  }
               }
               
               target.archs = target.archs[0 .. index];
               target_list.insert(target);
            }
         }
      }
   }
   
   if(target_list.length > 0)
   {
      BuildTarget[] output = new BuildTarget[target_list.length];
      int index = 0;
      
      foreach(BuildTarget target; target_list)
      {
         output[index++] = target;
      }
      
      return output;
   }
   
   return null;
}

struct JSONString
{
   string _val;
   
   string get()
   {
      return _val;
   }
   
   string getPath(RoutineInfo routine)
   {
      return PathF(_val, routine);
   }
}

bool GetJSONString(RoutineState state, string var_name, JSONString *result)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(HasJSON(routine_json, var_name))
   {
      JSONValue var_json = routine_json[var_name];
      
      result._val = LoadStringFromTag(state,
                                      var_json);
      return true;
   }
   
   return false;
}

struct JSONBool
{
   bool _val;
   
   bool get()
   {
      return _val;
   }
}

bool GetJSONBool(RoutineState state, string var_name, JSONBool *result)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(HasJSON(routine_json, var_name))
   {
      JSONValue var_json = routine_json[var_name];
      
      result._val = LoadBoolFromTag(state,
                                    var_json);
      return true;
   }
   
   return false;
}

struct JSONStringArray
{
   string[] _val;
   
   string[] get()
   {
      return _val;
   }
}

bool GetJSONStringArray(RoutineState state, string var_name, JSONStringArray *result)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(HasJSON(routine_json, var_name))
   {
      JSONValue var_json = routine_json[var_name];
      
      result._val = LoadStringArrayFromTag(state,
                                           var_json,
                                           TagType.StringArray);
      return true;
   }
   
   return false;
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

void CopyMatchingItems(string source, string destination, string begining = "", string ending = "", int depth = 0)
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

void DeleteMatchingItems(string path, string begining = "", string ending = "", int depth = 0)
{
   try
   {
      DeleteMatchingItems_internal(path, begining, ending, depth);
   } catch {}
}

string pipeToNUL(string str)
{
   version(Windows)
   {
      return "(" ~ str ~ ") 1> nul 2> nul";
   }
   else
   {
      return "(" ~ str ~ ") 2>&1 > /dev/null";
   }
}

void DownloadFile(string source, string dest)
{
   string curl_download_command = ("(curl \"" ~ source ~ "\" -o \"" ~ dest ~ "\")");
   curl_download_command = pipeToNUL(curl_download_command);
   system(toStringz(curl_download_command));
}

bool IsValid(T)(string str)
{
   try
   {
      T var = to!T(str);
      return true;
   } catch(ConvException e) { return false; }
}

void Build(string output_folder, RoutineState state)
{
   string temp_dir = state.routine_info.directory ~ state.build_info.project_name ~ "_" ~ state.routine_info.name ~ "_" ~ randomUUID().toString();
   string version_string = GetVersionString(state.version_info);
                           
   string output_file_name = state.build_info.project_name ~ 
                             (state.version_info.is_versioned ? (state.version_info.breakS ~ version_string) : "");
   
   mkdirRecurse(temp_dir);
   
   if(!exists(PathF(output_folder, state.routine_info)))
   {
      mkdirRecurse(PathF(output_folder, state.routine_info));
   }
   
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   string dependencies = "";
   
   if(HasJSON(routine_json, "source"))
   {
      FileDescription[] source_folders = LoadFileDescriptionsFromTag(state, routine_json["source"]);
      
      foreach(FileDescription source; source_folders)
      {
         WriteMsg("Src " ~ PathF(source.path, state.routine_info) ~ "|" ~ source.begining ~ "|" ~ source.ending);
         
         if(source.type == FileType.Local)
         {
            if((source.begining != "") || (source.ending != ""))
            {
               CopyMatchingItems(PathF(source.path, state.routine_info), temp_dir ~ "/", source.begining, source.ending);
            }
            else
            {
               CopyItem(PathF(source.path, state.routine_info), temp_dir ~ "/" ~ source.path[source.path.lastIndexOf("/") + 1 .. $]);
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
      FileDescription[] dependency_items = LoadFileDescriptionsFromTag(state, routine_json["dependencies"]);
      
      foreach(FileDescription dep; dependency_items)
      {
         if(dep.type == FileType.Local)
         {
            if(exists(PathF(dep.path, state.routine_info)))
            {
               WriteMsg("FDep " ~ PathF(dep.path, state.routine_info) ~ "|" ~ dep.begining ~ "|" ~ dep.ending);
               
               if((dep.begining != "") || (dep.ending != ""))
               {
                  CopyMatchingItems(PathF(dep.path, state.routine_info), temp_dir ~ "/", dep.begining, dep.ending);
               }
               else
               {
                  CopyItem(PathF(dep.path, state.routine_info), temp_dir ~ "/" ~ dep.path[dep.path.lastIndexOf("/") + 1 .. $]);
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
   
   writeln("Building " ~ state.build_info.project_name ~ " for " ~ state.build_info.platform.arch ~ (state.build_info.platform.optimized ? "(OPT)" : "(NOPT)"));
   
   string command_batch = "";
   
   string[] command_templates = LoadStringArrayFromTag(state,
                                                       GetLanguageCommandTag(state.routine_info.platform_config_path, state.build_info.language, state.build_info.type),
                                                       TagType.String);
   
   foreach(string command_template; command_templates)
   {
      string command = command_template.replace("[BUILD_DIRECTORY]", temp_dir)
                                       .replace("[DEPENDENCIES]", dependencies);
   
      command_batch = command_batch ~ " && ( " ~ command ~ " )";
   }
   
   command_batch = "(" ~ command_batch[4 .. $] ~ ")";
   
   if(state.build_info.silent_build)
   {
      command_batch = pipeToNUL(command_batch);
   }
   
   system(toStringz(command_batch));
   
   foreach(string file_ending; GetLanguageFileEndings(state.routine_info.platform_config_path, state.build_info.language, state.build_info.type, state))
   {
      CopyItem(temp_dir ~ "/" ~ state.build_info.project_name ~ file_ending, PathF(output_folder, state.routine_info) ~ "/" ~ output_file_name ~ file_ending);
   }
   
   rmdirRecurse(temp_dir);
}