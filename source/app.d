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
   -prevent modification of output dir (eg. set output dir as file)?
   -prevent copy from wiping file permissions on *nix
   -error messages (missing language, missing build type, non-existant files or directories, cant build, etc...)
   -java pconfig still doesn't work
 
BUGS:
   -cant fread a file right after fwrite
	-
   
NOTES:
   -CopyFile -> CopyItem (Item = both folders & files)
   -Is setting the platform to the host for the regular operations the right thing to do?
   -CopyFolderContents -> CopyMatchingItems (copy files in subfolders & keep the subfolders)
   -["copy", "../example/Example.sol", "[OUTPUT_DIRECTORY]"] causes the output dir to become a file
   -The output directory is created in Build
   -copy creates dest folder if needed
*/

/**
Linux Testing:
NOTES:
	-Bash uses "{ " & ";}" instead of "(" & ")"
	-Linux binaries dont have a file ending
	-linux needs rpath for so's 
   -

TODO:
	-binaries dont have permissions (try to chmod?)
   -
*/

/**
Path Naming Standard:
   -directories end with a '/'
   -only use forward shashes, no backward slashes
   -do not support absolute paths or ~/ shell shortcut
   -
*/

const bool DEBUG_PRINTING = false;
const bool delete_temp_dir = true;

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

void Breakpoint(string text = "")
{
   try
   {
      throw new Exception("Breakpoint" ~ ((text != "") ? (": " ~ text) : ""));
   }
   catch(Exception e)
   {
      writeln(e.text);
   }
}

string SFileReadText(string path)
{
   try
   {
      return std.file.readText(path);
   }
   catch(Exception e)
   {
      writeln("Error On File Read:\n" ~ e.text);
      return "";
   }
}

void SFileWrite(string path, string contents)
{
   try
   {
      std.file.write(path, contents);
   }
   catch(Exception e)
   {
      writeln("Error On File Write:\n" ~ e.text);
   }
}

void SFileCopy(string source, string dest)
{
   try
   {
      std.file.copy(source, dest, std.file.PreserveAttributes.yes);
   }
   catch(Exception e)
   {
      writeln("Error On File Copy:\n" ~ e.text);
   }
}

void SFileDelete(string path)
{
   try
   {
      std.file.remove(path);
   }
   catch(Exception e)
   {
      writeln("Error On File Delete:\n" ~ e.text);
   }
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
   bool filtered;
   FileType type;
}

struct RoutineState
{
   BuildInfo build_info;
   VersionInfo version_info;
   RoutineInfo routine_info;
   Array!string *error_log;
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
   string[] outputs;
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

struct FileInput
{
   string decl;
   string value;
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

void LinkPlatformConfig(string config_to_link, string platform_config_path)
{
   const string default_platform_config_path = GetFileDirectory(thisExePath()) ~ "/platform_config.json";
   if(!exists(default_platform_config_path))
   {
      writeln("Default platform config file missing! Generating empty json!");
      SFileWrite(default_platform_config_path, "{\n}");
   }

   JSONValue platform_config_json = LoadJSONFile(platform_config_path);
   
   if(HasJSON(platform_config_json, "linked"))
   {
      writeln("Linking ", config_to_link, " to ", platform_config_path);
      JSONValue linked_json = platform_config_json["linked"];
      
      if(linked_json.type() == JSON_TYPE.ARRAY)
      {
         bool already_linked = false;
         
         foreach(JSONValue json_value; linked_json.array)
         {
            if(json_value.type() == JSON_TYPE.STRING)
            {
               if(json_value.str() == config_to_link)
                  already_linked = true;
            }
         }
         
         if(!already_linked)
         {
            linked_json.array ~= JSONValue(config_to_link);
         }
         else
         {
            writeln(config_to_link, " already linked");
         }
         
         platform_config_json["linked"] = linked_json;
         SFileWrite(platform_config_path, platform_config_json.toPrettyString());
      }
   }
   else
   {
      writeln("Linking ", config_to_link, " to ", platform_config_path);
      platform_config_json.object["linked"] = JSONValue([config_to_link]); 
      SFileWrite(platform_config_path, platform_config_json.toPrettyString());
   }
}

void LaunchConfig(string default_platform_config_path,
                  string config_file_path,
                  string[] args,
                  bool inhereted_build_silent = default_build_silent)
{
   bool can_version = true;

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
            {
               if(can_version)
                  version_type = VersionType.Major;
            }
            break;
               
            case "-minor":
            {
               if(can_version)
                  version_type = VersionType.Minor;
            }
            break;
               
            case "-patch":
            {
               if(can_version)
                  version_type = VersionType.Patch;
            }
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
            
            case "-pLink":
            {
               if(args.length > (i + 1))
               {
                  string config_to_link = args[++i];
                  LinkPlatformConfig(config_to_link, platform_config_path);
               }
               else
               {
                  writeln("Missing argument for option \"-pLink\"");
               }
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
   if(!delete_temp_dir)
      writeln("TEMPORARY DIRECTORY DELETION DISABLED!");
   
   if(args.length < 2)
   {
      writeln("Insufficient arguments!");
      writeln("Usage \'rebuild [config file]\'");
      return;
   }
   
   string exe_path = thisExePath();
   string exe_dir = GetFileDirectory(exe_path);
   
   const string default_platform_config_path = exe_dir ~ "/platform_config.json";
   string config_file_path = args[1];
  
   if(config_file_path == "-pLink")
   {
      if(args.length > 1)
      {
         string config_to_link = args[2];
         LinkPlatformConfig(config_to_link, default_platform_config_path);
      }
      else
      {
         writeln("Missing argument for option \"-pLink\"");
      }
      return;
   }
 
   if(!exists(default_platform_config_path))
   {
      writeln("Default platform config file missing! Generating empty json!");
      SFileWrite(default_platform_config_path, "{\n}");
      return;
   }
      
   LaunchConfig(default_platform_config_path, config_file_path, args[2 .. $]);
}

string GetDefaultRoutine(string file_path)
{
   WriteMsg("Finding default routine of ", file_path);

   if((!exists(file_path)) || (!isFile(file_path)))
   {
      ExitError(file_path ~ " not found!");
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
      ExitError("missing default routine");
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
      if(build_info.can_build && HasDefaultType(state.routine_info.platform_config_path, build_info.language))
      {
         build_info.type = GetDefaultType(state.routine_info.platform_config_path, build_info.language, state);
      }
      else
      {
         build_info.can_build = false;
      }
   }
   
   JSONString build;
   if(GetJSONDirectoryPath(state, "build", &build))
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
   
   JSONStringArray outputs;
   if(GetJSONStringArray(state, "outputs", &outputs))
   {
      build_info.outputs = outputs.get();
   }
   else
   {
      if(build_info.can_build)
      {
         build_info.outputs = GetLanguageFileEndings(state.routine_info.platform_config_path, build_info.language, build_info.type, state);
      }
      else
      {
         build_info.outputs = null;
      }
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
   
   JSONString version_break;
   if(GetJSONString(state, "version_break", &version_break))
   {
      version_info.breakS = version_break.get();
   }
   
   if(version_info.is_versioned)
   {
      *version_info = UpdateVersions(state.routine_info, *version_info); 
   }
   
   if(version_info.is_versioned && (state.routine_info.path.endsWith(".new")))
   {
      string regular_config_path = state.routine_info.path[0 .. $ - 4];
      string new_config_path = state.routine_info.path;
      
      WriteMsg("Syncing " ~ state.routine_info.name ~ " from \"" ~ regular_config_path ~ "\" to \"" ~ new_config_path ~ "\"");
      
      JSONValue regular_file_json = LoadJSONFile(regular_config_path);
      JSONValue new_file_json = LoadJSONFile(new_config_path);
      string routine_name = state.routine_info.name;
      
      new_file_json[routine_name] = regular_file_json[routine_name];
      
      new_file_json[routine_name]["version"][0] = version_info.major;
      new_file_json[routine_name]["version"][1] = version_info.minor;
      new_file_json[routine_name]["version"][2] = version_info.patch;
      
      if(version_info.appended != "")
      {
         new_file_json[routine_name]["version"][3] = version_info.appended;
      }
      
      SFileWrite(new_config_path, new_file_json.toPrettyString());
   }
   
   return *version_info;
}

void RunRoutine(string file_path, string routine_name, string default_platform_config_path, VersionType version_type, bool silent_build)
{
   WriteMsg("Executing routine ", routine_name, " in ", file_path);

   if((!exists(file_path)) || (!isFile(file_path)))
   {
      ExitError(file_path ~ " not found!");
   }
   
   JSONValue file_json = LoadJSONFile(file_path);
   
   if(!HasJSON(file_json, routine_name))
   {
      writeln("Routine \"" ~ routine_name ~ "\" in " ~ file_path ~ " not found!");
      return;
   }
   
   JSONValue routine_json = file_json[routine_name];
   
   if(routine_json.type() == JSON_TYPE.OBJECT)
   {
      Array!string error_log = Array!string();
      RoutineState state;
      
      state.error_log = &error_log;
      state.routine_info = MakeRoutine(file_path, routine_name, default_platform_config_path);
      state.build_info = GetBuildInfo(state, silent_build);
      state.version_info = GetVersionInfo(state, version_type);
      
      ExecuteOperations(state);
      
      foreach(string error; error_log)
      {
         writeln("[" ~ state.build_info.project_name ~ "] " ~ error);
      }
   }
}

void ExecuteOperation(string op_name, RoutineState state, string[] params, void delegate(RoutineState state)[string] extra_operations)
{
   switch(op_name)
   {
      case "move":
         MoveOperation(state.routine_info, params);
         break;
      
      case "delete":
         DeleteOperation(state.routine_info, params);
         break;
      
      case "copy":
         CopyOperation(state.routine_info, params);
         break;
      
      case "call":
         CallOperation(state.routine_info, state.build_info, params);
         break;
      
      case "cmd":
         CommandOperation(state.routine_info, params);
         break;
      
      case "replace":
         ReplaceOperation(state.routine_info, params);
         break;
      
      case "print":
         PrintOperation(params, state.routine_info.name);
         break;
      
      case "fwrite":
         FileWriteOperation(state.routine_info, params);
         break;
      
      default:
      {
         if(extra_operations.keys.canFind(op_name))
         {
            extra_operations[op_name](state);
         }
         else
         {
            writeln("Unknown Operation: ", op_name);
         }
      }
      break;
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
      
      void delegate(RoutineState state)[string] extra_operations;
      
      extra_operations["build"] = delegate(RoutineState state)
      {
         BuildOperation(state);
         has_built = true;
      };
      
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
      
         ExecuteOperation(operation_token, state, operation_params, extra_operations);
      }
      
      if(!has_built)
         BuildOperation(state);
   }
}

void ExecutePerOperations(string output_directory, RoutineState state)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   string version_string = GetVersionString(state.version_info);
   string output_file_name = state.build_info.project_name ~ 
                             (state.version_info.is_versioned ? (state.version_info.breakS ~ version_string) : ""); 
   
   string temp_dir = state.routine_info.directory ~ state.build_info.project_name ~ "_" ~ state.routine_info.name ~ "_" ~ randomUUID().toString();
   mkdirRecurse(temp_dir);
   
   if(!HasJSON(routine_json, "per-operations"))
   {
      Build(output_directory, temp_dir, state, output_file_name);
      static if(delete_temp_dir) { rmdirRecurse(temp_dir); }
      return;
   }
   
   JSONValue operations_json = routine_json["per-operations"];
   
   if(operations_json.type() == JSON_TYPE.ARRAY)
   {
      bool specifies_build = false;
      bool has_built = false;
      
      string[string] replace_additions;
      replace_additions["[OUTPUT_DIRECTORY]"] = output_directory;
      replace_additions["[OUTPUT_FILE_NAME]"] = output_file_name;
      replace_additions["[BUILD_DIRECTORY]"] = temp_dir;
      
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
         Build(output_directory, temp_dir, state, output_file_name);
      }
   
      string last_operation_token = "";
      
      void delegate(RoutineState state)[string] extra_operations;
      
      extra_operations["build"] = delegate(RoutineState state)
      {
         if(!has_built)
         {
            has_built = true;
            WriteMsg("\tBuilding...");
            Build(output_directory, temp_dir, state, output_file_name);
         }
         else
         {
            WriteMsg("Already built!");
         }
      };
      
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
         
         ExecuteOperation(operation_token, state, operation_params, extra_operations);
      }
   }
   
   static if(delete_temp_dir) { rmdirRecurse(temp_dir); }
}

void BuildOperation(RoutineState state)
{
   if(state.build_info.can_build)
   {
      VersionInfo version_info = state.version_info;
      
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
   if(params.length < 2)
      return;

   string src = RelativePath(FormatPath(params[0]), routine_info);
   string dest = RelativePath(FormatPath(params[1]), routine_info);
      
   if(params.length == 2)
   {
      WriteMsg("\tCopy ", src, " -> ", dest);
      CopyItem(src, dest);
   }
   else if(params.length == 3)
   {
      WriteMsg("\tCopy ", src, " (", params[2], ") -> ", dest);
      CopyMatchingItems(src, dest, "", params[2]);
   }
   else if(params.length == 4)
   {
      if(IsValid!int(params[3]))
      {
         WriteMsg("\tCopy ", src, " (", params[2], ") -> ", dest);
         CopyMatchingItems(src, dest, "", params[2], to!int(params[3]));
      }
      else
      {
         WriteMsg("\tCopy ", src, " (", params[2], " ", params[3], ") -> ", dest);
         CopyMatchingItems(src, dest, params[2], params[3]);
      }
   }
   else if(params.length == 5)
   {
      WriteMsg("\tCopy ", src, " (", params[2], " ", params[3], ") -> ", dest);
      
      if(IsValid!int(params[4]))
      {
         CopyMatchingItems(src, dest, params[2], params[3], to!int(params[4]));
      }
      else
      {
         writeln(params[4], " failed to convert from string to int!");
         CopyMatchingItems(src, dest, params[2], params[3]);
      }
   }
}

void DeleteOperation(RoutineInfo routine_info, string[] params)
{  
   if(params.length < 1)
      return;

   string path = RelativePath(FormatPath(params[0]), routine_info);
      
   if(params.length == 1)
   {
      WriteMsg("\tDelete ", path, " -> /dev/null");
      DeleteItem(path);
   }
   else if(params.length == 2)
   {
      WriteMsg("\tDelete ", path, " (", params[1], ") -> /dev/null");
      DeleteMatchingItems(path, "", params[1]);
   }
   else if(params.length == 3)
   {
      if(IsValid!int(params[2]))
      {
         WriteMsg("\tDelete ", path, " (", params[1], ") -> /dev/null");
         DeleteMatchingItems(path, "", params[1], to!int(params[2]));
      }
      else
      {
         WriteMsg("\tDelete ", path, " (", params[1], " ", params[2], ") -> /dev/null");
         DeleteMatchingItems(path, params[1], params[2]);
      }
   }
   else if(params.length == 4)
   {
      if(IsValid!int(params[3]))
      {
         WriteMsg("\tDelete ", path, " (", params[1], " ", params[2], ") -> /dev/null");
         DeleteMatchingItems(path, params[1], params[2], to!int(params[3]));
      }
      else
      {
         writeln(params[3], " failed to convert from string to int!");
         DeleteMatchingItems(path, params[1], params[2]);
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
   
      if(!IsFilePath(config_file_path))
      {
         writeln("\"" ~ config_file_path ~ "\" Is not a valid file path");
         return;
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
         string file_contents = SFileReadText(file_path);
         file_contents = file_contents.replace(params[0], params[1]);
         SFileWrite(file_path, file_contents);
      }
   }
}

void PrintOperation(string[] params, string routine_name)
{
   string to_print = "";
   string separator = "";
   const string default_prefix = "[print: " ~ routine_name ~ "] ";
   string prefix = default_prefix;
   
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
            
            case "-prefix":
            {
               if(params.length > (i + 1))
               {
                  if(prefix == default_prefix)
                  {
                     prefix = params[++i];
                  }
                  else
                  {
                     writeln("[print error] Prefix can only be set once");
                  }
               }
               else
               {
                  writeln("[print error] Missing argument for option \"-prefix\"");
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
   
   writeln(prefix, to_print);
}

void FileWriteOperation(RoutineInfo routine_info, string[] params)
{
   if(params.length > 1)
   {
      string file_path = PathF(params[0], routine_info);
      bool append = false;
      string to_write = "";
      
      foreach(string param; params[1 .. $])
      {
         if(param.startsWith("-"))
         {
            switch(param)
            {
               case "-append":
                  append = true;
                  break;
               
               case "-overwrite":
                  append = false;
                  break;
                  
               default:
                  to_write = to_write ~ param;
            }
         }
         else
         {
            to_write = to_write ~ param;
         }
      }
      
      if(append && exists(file_path))
      {
         WriteMsg("Append To " ~ file_path);
         string file_contents = SFileReadText(file_path);
         SFileWrite(file_path, file_contents ~ to_write);
      }
      else
      {
         WriteMsg("Write To " ~ file_path);
         SFileWrite(file_path, to_write);
      }
   }
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
         SFileWrite(routine.path, file_json.toPrettyString());
      }
      else
      {
         SFileWrite(routine.path ~ ".new", file_json.toPrettyString());
      }
   }
   
   return version_info;
}

JSONValue LoadJSONFile(string path)
{
   try
   {
      string json_text = SFileReadText(path);
      JSONValue json_value = parseJSON(json_text);
      return json_value;
   }
   catch(JSONException e)
   {
      ExitError(e.text);
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

JSONValue[string] language_json_cache; 

bool InLangCache(string key)
{
   JSONValue *p = (key in language_json_cache);
   
   if(p == null)
      return false;
   
   return true;
}

JSONValue GetLanguageJSON(string file_path, string language_name)
{
   string key = file_path ~ "?" ~ language_name;
   
   if(InLangCache(key))
   {
      return JSONValue(language_json_cache[key]);
   }
   else
   {
      if(!isFile(file_path))
      {
         ExitError(file_path ~ " not found!");
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
      
      if(HasJSON(file_json, "linked"))
      {
         JSONValue links_json = file_json["linked"];
         
         string exe_path = thisExePath();
         string exe_dir = GetFileDirectory(exe_path);
         
         if(links_json.type() == JSON_TYPE.ARRAY)
         {
            Array!string linked_configs = Array!string();
            
            foreach(JSONValue json_value; links_json.array)
            {
               if(json_value.type() == JSON_TYPE.STRING)
               {
                  linked_configs.insert(json_value.str());
               }
            }
            
            foreach(string linked_config; linked_configs)
            {
               linked_config = linked_config.replace("\\", "/");
            
               if(linked_config.startsWith("./"))
               {
                  linked_config = linked_config[2 .. $];
               }
               else if(linked_config.startsWith("/"))
               {
                  linked_config = linked_config[1 .. $];
               }
               
               if(exists(exe_dir ~ "/" ~ linked_config))
               {
                  JSONValue linked_config_json = LoadJSONFile(exe_dir ~ "/" ~ linked_config);
                  
                  if(HasJSON(linked_config_json, "languages"))
                  {
                     JSONValue languages_json = linked_config_json["languages"];
               
                     if(HasJSON(languages_json, language_name))
                     {
                        JSONValue language_json = languages_json[language_name];
                        language_json_cache[key] = language_json;
                        return language_json;
                     }
                  }
               }
               else
               {
                  writeln("Invalid link \"" ~ exe_dir ~ "/" ~ linked_config ~ "\"");
               }
            }
         }
      }
      
      ExitError("Platform config missing for language \"" ~ language_name ~ "\"");
      
      return JSONValue.init; 
   }
}

PlatformInfo GetHostInfo(string file_path, string language)
{
   WriteMsg("Get Host");
   
   JSONValue language_json = GetLanguageJSON(file_path, language);
         
   if(HasJSON(language_json, "host"))
   {
      JSONValue host_json = language_json["host"];
      
      if(host_json.type() == JSON_TYPE.ARRAY)
      {
         if(host_json.array.length == 1)
         {
            if(host_json[0].type() == JSON_TYPE.STRING)
               
            {
               PlatformInfo info;
               info.OS = host_json[0].str();
               info.arch = host_json[0].str();
               return info;
            }
         }
         else if(host_json.array.length == 2)
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
      else if(host_json.type() == JSON_TYPE.STRING)
      {
         PlatformInfo info;
         info.OS = host_json.str();
         info.arch = host_json.str();
         return info;
      }
   }
   
   ExitError("Platform config missing host");

   return PlatformInfo.init;
}

BuildTarget GetHost(string file_path, string language)
{
   WriteMsg("Get Host");
   
   PlatformInfo host_info = GetHostInfo(file_path, language);
   
   BuildTarget host_target;
   host_target.OS = host_info.OS;
   host_target.archs = new string[1];
   host_target.archs[0] = host_info.arch;
   return host_target;
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
   
   ExitError("Platform config missing commands for language " ~ language_name ~ "(" ~ build_type ~ ")");
   
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
         ExitError("Platform config missing commands for language " ~ language_name ~ "(" ~ build_type ~ ")");
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

string[] GetLanguageSourceFileEndings(string file_path, string language_name, RoutineState state)
{
   WriteMsg("Loading language ", language_name, " source file ending from ", file_path);
   
   JSONValue language_json = GetLanguageJSON(file_path, language_name);
   
   if(HasJSON(language_json, "sources"))
   {
      JSONValue sources_json = language_json["sources"];
      
      string[] source_endings = LoadStringArrayFromTag(state, sources_json, TagType.StringArray);
      return source_endings;
   }

   return null;
}

string[int][string] GetAvailablePlatforms(string file_path, string language)
{
   if(!isFile(file_path))
   {
      ExitError(file_path ~ " not found!");
   }
   
   JSONValue language_json = GetLanguageJSON(file_path, language);
   string[int][string] platforms;
   
   if(HasJSON(language_json, "platforms"))
   {
      JSONValue platforms_json = language_json["platforms"];
      
      if(platforms_json.type() == JSON_TYPE.ARRAY)
      {
         if(platforms_json.array.length == 1)
         {
            if(platforms_json[0].type == JSON_TYPE.STRING)
            {
               platforms[platforms_json[0].str()][0] = platforms_json[0].str();
            }
         }
      
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
      else if(platforms_json.type() == JSON_TYPE.STRING)
      {
         platforms[platforms_json.str()][0] = platforms_json.str();
      }
   }
   
   return platforms;
}

bool HasDefaultType(string file_path, string language)
{
   JSONValue language_json = GetLanguageJSON(file_path, language);
   
   return HasJSON(language_json, "default_type");
}

string GetDefaultType(string file_path, string language, RoutineState state)
{
   JSONValue language_json = GetLanguageJSON(file_path, language);
   
   if(HasDefaultType(file_path, language))
   {
      return LoadStringFromTag(state, language_json["default_type"]);
   }
   
   return null;
}

const string var_decl_begin = "[VAR ";
const string var_decl_end = "]";

Variable[] GetVariables(RoutineState state,
                        string tag_str)
{
   int var_count = cast(int) min(tag_str.count(var_decl_begin),
                       	     tag_str.count(var_decl_end));
   
   Variable[] vars = new Variable[var_count];
   int str_index = 0;
   
   for(int i = 0; i < var_count; ++i)
   {
      int var_index = cast(int) tag_str.indexOf(var_decl_begin, str_index);
      int var_end_index = cast(int) tag_str.indexOf(var_decl_end, var_index);
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
         ExitError("Invalid variable declaration: " ~ var_decl);
      }
      
      Array!string error_log = Array!string();
      
      RoutineState access_state;
      access_state.error_log = &error_log;
      access_state.routine_info = MakeRoutine(file_path, routine_name, state.routine_info.platform_config_path);
      access_state.build_info = GetBuildInfo(access_state, state.build_info.silent_build);
      access_state.version_info = GetVersionInfo(access_state, VersionType.None);
      
      JSONValue access_json = GetRoutineJSON(access_state.routine_info);
      
      Variable var;
      var.declare = var_decl;
      var.value = null;
      var.location = var_index;
      var.length = cast(int) var_decl.length;
      
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

const string ending_decl_begin = "[ENDING ";
const string ending_decl_end = "]";

Variable[] GetEndings(RoutineState state,
                      string tag_str)
{
   int var_count = cast(int) min(tag_str.count(ending_decl_begin),
                       	     tag_str.count(ending_decl_end));
   
   Variable[] endings = new Variable[var_count];
   int str_index = 0;
   
   for(int i = 0; i < var_count; ++i)
   {
      int var_index = cast(int) tag_str.indexOf(ending_decl_begin, str_index);
      int var_end_index = cast(int) tag_str.indexOf(ending_decl_end, var_index);
      string var_decl = tag_str[(var_index + ending_decl_begin.length) .. (var_end_index - ending_decl_end.length + 1)];
      string full_decl = tag_str[var_index .. var_end_index + 1];
      
      if(var_decl.count(" ") != 1)
      {
         writeln("------------------");
         writeln("Invalid ENDING tag");
         writeln(var_decl);
         writeln("------------------");
         return new Variable[0];
      }
      
      string language_name = var_decl[0 .. var_decl.indexOf(" ")];
      string build_type = var_decl[var_decl.indexOf(" ") + 1 .. $];
      
      string[] lang_endings = GetLanguageFileEndings(state.routine_info.platform_config_path, language_name, build_type, state);
      
      Variable ending;
      ending.declare = full_decl;
      ending.value = lang_endings;
      ending.location = var_index;
      ending.length = cast(int) full_decl.length;
      
      str_index = var_end_index;
      endings[i] = ending;
   }
   
   return endings;
}

const string fread_decl_begin = "[fread ";
const string fread_decl_end = "]";

//TODO: multiple freads in one line cause error
FileInput[] GetFileInputs(RoutineState state, string tag_str)
{
   int fread_count = cast(int) min(tag_str.count(fread_decl_begin),
                                   tag_str.count(fread_decl_end));
                         
   FileInput[] freads = new FileInput[fread_count];
   int str_index = 0;
   
   for(int i = 0; i < fread_count; ++i)
   {
      int fread_index = cast(int) tag_str.indexOf(fread_decl_begin, str_index);
      int fread_end_index = cast(int) tag_str.indexOf(fread_decl_end, fread_index);
      string fread_decl = tag_str[fread_index .. fread_end_index + 1];
      
      string fread_param = fread_decl[fread_decl_begin.length .. $ - fread_decl_end.length];
      string file_path = PathF(fread_param, state.routine_info);
      
      freads[i].decl = fread_decl;
      
      if(exists(file_path))
      {
         if(isFile(file_path))
         {
            freads[i].value = SFileReadText(file_path);
            continue;
         }
      }
      
      state.error_log.insert("File \"" ~ fread_param ~ "\" not found");
      freads[i].value = "";
   }
   
   return freads;
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
   
   if(routine_info.directory.length == 0)
   {
      routine_info.directory = "./";
   }
   
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

//TODO: replace PathF with RelativePath
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
   string conditional = "";
   string value = "";
   
   if(condit_str.canFind("="))
   {
      conditional = condit_str[0 .. condit_str.indexOf("=") + 1];
      value = condit_str[condit_str.indexOf("=") + 1 .. $];
   }
   else if(condit_str.canFind("(") && condit_str.canFind(")"))
   {
      conditional = condit_str[0 .. condit_str.indexOf("(") + 1];
      value = condit_str[condit_str.indexOf("(") + 1 .. $ - 1];
   }
   else
   {
      ExitError("Invalid conditional");
   }
   
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
      
      case "MAJORVERSION=":
      {
         return (to!string(state.version_info.type == VersionType.Major) == value);
      }
      
      case "MINORVERSION=":
      {
         return (to!string(state.version_info.type == VersionType.Minor) == value);
      }
      
      case "PATCHVERSION=":
      {
         return (to!string(state.version_info.type == VersionType.Patch) == value);
      }
      
      case "HASVAR(":
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
      
      case "ISFILE(":
      {
         string file_path = PathF(value, state.routine_info);
         if(exists(file_path))
         {
            return isFile(file_path);
         }
         return false;
      }
      
      case "ISDIR(":
      {
         string file_path = PathF(value, state.routine_info);
         if(exists(file_path))
         {
            return isDir(file_path);
         }
         return false;
      }
      
      default:
   }
   
   return false;
}

string CombindStrings(string[] strings, string splitter)
{
   string result = "";

   foreach(string str; strings)
   {
      result = result ~ splitter ~ str;
   }
   
   if(strings.length > 0)
      return result[splitter.length .. $];
    
   return "";
}

string RelativePath(string path, RoutineInfo routine)
{
   string new_path = path;
   
   if(new_path.startsWith("./"))
      new_path = new_path[2 .. $];
      
   if(!IsDirPath(routine.directory))
   {
      writeln(routine.directory);
      assert(false);
   }
   
   new_path = routine.directory ~ new_path;
      
   return new_path;
}

string FormatPath(string path)
{
   string new_path = path.replace("\\", "/");
   
   if(new_path.startsWith("~/"))
   {
      writeln("does not support user dir shortcut");
      new_path = new_path[2 .. $];
   }
   
   if(new_path.startsWith("/"))
   {
      writeln("does not support absolute paths");
      new_path = new_path[1 .. $];
   }
   
   return new_path;
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
   
   foreach(FileInput fread; GetFileInputs(state, new_str))
   {
      new_str = new_str.replace(fread.decl, fread.value);
   }
   
   Array!string tag_list = Array!string();
   int str_index = 0;
   
   foreach(Variable ending; GetEndings(state, new_str))
   {
      string pre_value = new_str[0 .. ending.location];
      str_index = ending.location + ending.length;
      
      if(pre_value.length > 0)
         tag_list.insert(pre_value);
      
      foreach(string var_value; ending.value)
      {
         tag_list.insert(var_value);
      }
      
      writeln(tag_list[0 .. $]);
   }
   
   foreach(Variable var; GetVariables(state, new_str))
   {
      string pre_value = new_str[0 .. var.location];
      str_index = var.location + var.length;
      
      if(pre_value.length > 0)
         tag_list.insert(pre_value);
      
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
      //TODO: does this always want to be ""
      result.str = CombindStrings(result.array, "");
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
         
         if(((if_json.type() == JSON_TYPE.STRING) || (if_json.type() == JSON_TYPE.ARRAY)))
         {
            bool condit_state = true;
            
            JSONMapString(if_json, (string condit_str, int i)
            {
               condit_state = condit_state && HandleConditional(state, ProcessTag(state, condit_str, replace_additions, TagType.String).str);
            });
            
            if(condit_state)
            {
					if((then_json.type() == JSON_TYPE.STRING) ||
						(then_json.type() == JSON_TYPE.ARRAY))
					{
						string result = "";
						
						JSONMapString(then_json, (string value_str, int i)
						{
							result = result ~ ProcessTag(state, value_str, replace_additions, TagType.String).str;
						});

						return result;
					}
					else if(then_json.type() == JSON_TYPE.OBJECT)
					{
						return LoadStringFromTag(state, then_json, replace_additions);
					}
            }
            else if(HasJSON(json, "else"))
            {
               JSONValue else_json = json["else"];
               
               if((else_json.type() == JSON_TYPE.STRING) ||
						(else_json.type() == JSON_TYPE.ARRAY))
               {
						string result = "";
						
						JSONMapString(else_json, (string value_str, int i)
						{
							result = result ~ ProcessTag(state, value_str, replace_additions, TagType.String).str;	
						});					

                  return result;
               }
					else if(else_json.type() == JSON_TYPE.OBJECT)
					{
						return LoadStringFromTag(state, else_json, replace_additions);
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

//TODO: improve LoadBoolFromTag to match LoadStringFromTag functionallity
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

string GetFileDirectory(string file_path)
{
   return file_path[0 .. max(file_path.lastIndexOf("/"), file_path.lastIndexOf("\\"))];
}

string GetFileName(string file_path)
{
   return file_path[max(file_path.lastIndexOf("/"), file_path.lastIndexOf("\\")) + 1 .. $];
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
      
      if(((if_json.type() == JSON_TYPE.STRING) || (if_json.type() == JSON_TYPE.ARRAY)))
      {
         bool condit_state = true;
         
         JSONMapString(if_json, (string condit_str, int i)
         {
            condit_state = condit_state && HandleConditional(state, ProcessTag(state, condit_str, replace_additions, TagType.String).str);
         });
         
         if(condit_state)
         {
            if(then_json.type() == JSON_TYPE.ARRAY)
            {
               foreach(JSONValue array_element; then_json.array)
               {
                  if(array_element.type == JSON_TYPE.OBJECT)
                  {
                     LoadStringArrayFromTag_internal(state, array_element, sarray, replace_additions, type);
                  }
                  else if(array_element.type == JSON_TYPE.STRING)
                  {
                     InsertProcessedTags(sarray, state, array_element.str(), replace_additions, type);
                  }
               }
            }
				else if(then_json.type() == JSON_TYPE.STRING)
				{
               InsertProcessedTags(sarray, state, then_json.str(), replace_additions, type);
				}
				else if(then_json.type() == JSON_TYPE.OBJECT)
				{
					LoadStringArrayFromTag_internal(state, then_json, sarray, replace_additions, type);
				}
         }
         else if(HasJSON(json, "else"))
         {
            JSONValue else_json = json["else"];
           
				if((else_json.type() == JSON_TYPE.STRING) ||
					(else_json.type() == JSON_TYPE.ARRAY))
				{ 
            	JSONMapString(else_json, (string str, int i)
            	{
               	InsertProcessedTags(sarray, state, str, replace_additions, type);
            	});
				}
				else if(else_json.type() == JSON_TYPE.OBJECT)
				{
					LoadStringArrayFromTag_internal(state, else_json, sarray, replace_additions, type);
				} 
         }
      }
   }
   
   //writeln((*sarray)[]);
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
   
   //writeln(sarray[]);
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
            //TODO: Process tag!
            fdesc.path = json_value.str();
            fdesc.filtered = false;
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
                  fdesc.filtered = false;
               }
               else
               {
                  fdesc.ending = strings[1];
                  fdesc.filtered = true;
               }
            }  
            else if(strings.length == 3)
            {
               fdesc.begining = strings[1];
               fdesc.ending = strings[2];
               fdesc.filtered = true;
            }
         }
         
         file_list.insert(fdesc);
      }
   }
   else if(json.type() == JSON_TYPE.STRING)
   {
      FileDescription fdesc;
      fdesc.path = json.str();
      fdesc.filtered = false;
      
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
                  else
                  {
                     state.error_log.insert(arch_name ~ " on " ~ target.OS ~ " not supported");
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

bool IsDirPath(string path)
{
   if(path.endsWith("/"))
   {
      return true;
   }
   
   return false;
}

bool IsFilePath(string path)
{
   if(!path.endsWith("/"))
   {
      return true;
   }
   
   return false;
}

bool GetJSONDirectoryPath(RoutineState state, string var_name, JSONString *result)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(HasJSON(routine_json, var_name))
   {
      JSONValue var_json = routine_json[var_name];
      string dir_path = FormatPath(LoadStringFromTag(state, var_json));
      
      if(IsDirPath(dir_path))
      {
         result._val = dir_path;
         return true;
      }
      else
      {
         writeln("\"" ~ dir_path ~ "\" not a valid directory path!");
      }
   }
   
   return false;
}

bool GetJSONFilePath(RoutineState state, string var_name, JSONString *result)
{
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   
   if(HasJSON(routine_json, var_name))
   {
      JSONValue var_json = routine_json[var_name];
      string dir_path = FormatPath(LoadStringFromTag(state, var_json));
      
      if(IsFilePath(dir_path))
      {
         result._val = dir_path;
         return true;
      }
      else
      {
         writeln("\"" ~ dir_path ~ "\" not a valid file path!");
      }
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

void CopyMatchingItems_internal(string source, string destination, string begining, string ending, int depth, Array!string *result)
{
   source = source.replace("\\", "/");
   destination = destination.replace("\\", "/");

   if(isDir(source))
   {
      if(!destination.endsWith("/"))
      {
         destination = destination ~ "/";
      }
   
      foreach(DirEntry e; dirEntries(source, SpanMode.shallow))
      {
         string entry_path = e.name().replace(source, "");
         
         if(entry_path.startsWith("\\") || entry_path.startsWith("/"))
            entry_path = entry_path[1 .. $];
         
         if(e.isDir() && ((depth - 1) >= 0))
         {
            CopyMatchingItems_internal(e.name().replace("\\", "/"), destination ~ e.name().replace("\\", "/").replace(source, ""), begining, ending, depth - 1, result);
         }
         
         if(e.isFile() && entry_path.startsWith(begining) && entry_path.endsWith(ending))
         {
            if(!exists(destination))
               mkdirRecurse(destination);
         
            string rsource = source ~ (source.endsWith("/") ? "" : "/");
            SFileCopy(e.name().replace("\\", "/"), destination ~ e.name().replace("\\", "/").replace(rsource, ""));
            result.insert(destination ~ e.name().replace("\\", "/").replace(rsource, ""));
         }
      }
   }
   else if(isFile(source))
   {
      string dest_folder = destination[0 .. destination.lastIndexOf("/")];
      if(!exists(dest_folder))
         mkdirRecurse(dest_folder);
      
      SFileCopy(source, destination);
   }
}

string[] CopyMatchingItems(string source, string destination, string begining = "", string ending = "", int depth = 0)
{
   Array!string result_list = Array!string();
   
   try
   {
      CopyMatchingItems_internal(source, destination, begining, ending, depth, &result_list);
   } catch {}
   
   string[] result = new string[result_list.length];
   int i = 0;
   
   foreach(string str; result_list)
      result[i++] = str;
   
   return result;
}

string[] CopyItem(string source, string dest)
{
   return CopyMatchingItems(source, dest, "", "", int.max);
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
            SFileDelete(e.name());
      }
   }
   else if(isFile(path))
   {
      SFileDelete(path);
   }
}

void DeleteMatchingItems(string path, string begining = "", string ending = "", int depth = 0)
{
   try
   {
      DeleteMatchingItems_internal(path, begining, ending, depth);
   } catch {}
}

void DeleteItem(string path)
{
   DeleteMatchingItems(path, "", "", int.max);
}

string pipeToNUL(string str)
{
   version(Windows)
   {
      return "(" ~ str ~ ") 1> nul 2> nul";
   }
   else
   {
      return "(" ~ str ~ ") >/dev/null 2>&1";
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

void Build(string output_folder, string build_dir, RoutineState state, string output_file_name)
{
   string version_string = GetVersionString(state.version_info);
  
   if(!exists(PathF(output_folder, state.routine_info)))
   {
      mkdirRecurse(PathF(output_folder, state.routine_info));
   }
   
   JSONValue routine_json = GetRoutineJSON(state.routine_info);
   string[] source_file_endings = GetLanguageSourceFileEndings(state.routine_info.platform_config_path, state.build_info.language, state);
   string sources = "";
   string dependencies = "";
   
   if(HasJSON(routine_json, "source"))
   {
      FileDescription[] source_folders = LoadFileDescriptionsFromTag(state, routine_json["source"]);
      writeln(source_folders);
      
      foreach(FileDescription source; source_folders)
      {
         writeln("Src " ~ PathF(source.path, state.routine_info) ~ "|" ~ source.begining ~ "|" ~ source.ending);
         
         if(source.type == FileType.Local)
         {
            string[] src_files = null;
            
            if(source.filtered)
            {
               src_files = CopyMatchingItems(PathF(source.path, state.routine_info), build_dir ~ "/", source.begining, source.ending, int.max);               
            }
            else
            {
               string source_path = PathF(source.path, state.routine_info);
               
               if(exists(source_path))
               {
                  if(isFile(source_path))
                  {
                     src_files = CopyItem(source_path, build_dir ~ "/" ~ source.path[max(source.path.lastIndexOf("/"), source.path.lastIndexOf("\\")) + 1 .. $]);
                  }
                  else if(isDir(source_path))
                  {
                     src_files = CopyItem(source_path, build_dir ~ "/");
                  }
               }
            }
            
            if(src_files != null)
            {
               foreach(string src; src_files)
               {
                  string source_path = src.replace(build_dir ~ "/", "");
               
                  foreach(string ending; source_file_endings)
                  {
                     if(source_path.endsWith(ending))
                     {
                        sources = sources ~ " " ~ source_path;
                        break;
                     }
                  }
               }
            }
         }
         else if(source.type == FileType.Remote)
         {
            string dest_path = build_dir ~ "/" ~ source.path[source.path.lastIndexOf("/") + 1 .. $];
            DownloadFile(source.path, dest_path);
            
            string source_path = dest_path.replace(build_dir ~ "/", "");
            
            foreach(string ending; source_file_endings)
            {
               if(source_path.endsWith(ending))
               {
                  sources = sources ~ " " ~ source_path;
                  break;
               }
            }
         }
      }
   }
   
   if(HasJSON(routine_json, "dependencies"))
   {
      FileDescription[] dependency_items = LoadFileDescriptionsFromTag(state, routine_json["dependencies"]);
      //writeln(dependency_items);
      
      foreach(FileDescription dep; dependency_items)
      {
         if(dep.type == FileType.Local)
         {
            string dep_path = PathF(dep.path, state.routine_info);
            
            if(exists(dep_path))
            {
               WriteMsg("FDep " ~ PathF(dep.path, state.routine_info) ~ "|" ~ dep.begining ~ "|" ~ dep.ending);
               string[] dep_files = null;
             
               if(dep.filtered)
               {
                  dep_files = CopyMatchingItems(PathF(dep.path, state.routine_info), build_dir ~ "/", dep.begining, dep.ending);
               }
               else
               {
                  if(isFile(dep_path))
                  {
                     dep_files = CopyItem(dep_path, build_dir ~ "/" ~ dep.path[max(dep.path.lastIndexOf("/"), dep.path.lastIndexOf("\\")) + 1 .. $]);
                  }
                  else if(isDir(dep_path))
                  {
                     dep_files = CopyItem(dep_path, build_dir ~ "/");
                  }
               }
              
               WriteMsg(dep_files);
 
               if(dep_files != null)
               {
                  foreach(string dep_file; dep_files)
                     dependencies = dependencies ~ " " ~ dep_file.replace(build_dir ~ "/", "");
               }
            }
            else
            {
               WriteMsg("LDep " ~ dep.path);
               
               if(!dependencies.canFind(" " ~ dep.path))
               {
                  dependencies = dependencies ~ " " ~ dep.path;
                  
                  if((dep.ending != "") && dep.filtered)
                  {
                     /**
                        Ok, so this is a total hack and i intend on someday fixing it,
                        which may entail totally changing the syntax of the file descriptions,
                        but this is a bug fix for the fact that ["User32.lib", "Gdi32.lib"] is
                        treaded as if "User32.lib" is the path and "Gdi32.lib" is the ending filter
                     */
                     dependencies = dependencies ~ " " ~ dep.ending;
                  }
               }
            }
         }
         else if(dep.type == FileType.Remote)
         {
            string dest_path = build_dir ~ "/" ~ dep.path[dep.path.lastIndexOf("/") + 1 .. $];
            DownloadFile(dep.path, dest_path);
            
            dependencies = dependencies ~ " " ~ dest_path.replace(build_dir ~ "/", "");
         }
      }
   }
   
   writeln("Building " ~ state.build_info.project_name ~ " for " ~ state.build_info.platform.arch ~ (state.build_info.platform.optimized ? "(OPT)" : "(NOPT)"));
   
   string command_batch = "";
   
   {
      int first_letter = 0;
      
      for(int i = 0; i < sources.length; ++i)
      {
         if(sources[i] == ' ')
         {
            first_letter++;
         }
         else
         {
            break;
         }
      }
      
      sources = sources[first_letter .. $];
   }
   
   {
      int first_letter = 0;
      
      for(int i = 0; i < dependencies.length; ++i)
      {
         if(dependencies[i] == ' ')
         {
            first_letter++;
         }
         else
         {
            break;
         }
      }
      
      dependencies = dependencies[first_letter .. $];
   }
   
   WriteMsg("S|", sources, "|");
   WriteMsg("D|", dependencies, "|");
   
   string[string] replace_additions;
   replace_additions["[BUILD_DIRECTORY]"] = build_dir;
   replace_additions["[SOURCES]"] = sources;
   replace_additions["[DEPENDENCIES]"] = dependencies;
   replace_additions["[OUTPUT_FILE_NAME]"] = output_file_name;  
   
   string[] commands = LoadStringArrayFromTag(state,
                                              GetLanguageCommandTag(state.routine_info.platform_config_path, state.build_info.language, state.build_info.type),
                                              TagType.String,
                                              replace_additions);
  
	version(Windows)
	{
		const string begin_bracket = "( ";
		const string end_bracket = " )";
		const string command_and = " && ";
	}
	else
	{
		const string begin_bracket = "{ ";
		const string end_bracket = ";}";
		const string command_and = " && ";
	}
 
   foreach(string command; commands)
   {                                   
      command_batch = command_batch ~ command_and ~ begin_bracket ~ command ~ end_bracket;
   }
   
   if(command_batch.length > command_and.length)
   {
      command_batch = begin_bracket ~ command_batch[command_and.length .. $] ~ end_bracket;
   }
   
   if(state.build_info.silent_build)
   {
      command_batch = pipeToNUL(command_batch);
   }
   
	WriteMsg(command_batch); 
   system(toStringz(command_batch));
   
   foreach(string file_ending; GetLanguageFileEndings(state.routine_info.platform_config_path, state.build_info.language, state.build_info.type, state))
   {
      if(state.build_info.outputs.canFind(file_ending))
      {
         CopyItem(build_dir ~ "/" ~ state.build_info.project_name ~ file_ending, PathF(output_folder, state.routine_info) ~ "/" ~ output_file_name ~ file_ending);
      }
   }
}
