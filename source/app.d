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

/**
TODO:
   -Clean up code & comments
   -documentation
   -dependencies using file ending
*/

/**
        Field Cross Reference format
[FIELD_REF: _field_name_<-_file_:_routine_optional_]
*/

const string GlobalConfigFilePath = "./global_config.json";

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

struct FileDescription
{
   string path;
   string begining = "";
   string ending = "";
}

struct BuildInformation
{
   PlatformInformation platform;
   bool can_build;
   string type;
   string language;
   FileDescription[] source_folders;
   string build_folder;
   string project_name;
   string[][string] attributes;
   FileDescription[] dependencies;
}

struct BuildRoutine
{  
   string directory;
   string path;
   string name;
}

struct FieldCrossReference
{
   string field;
   string tag;
   BuildRoutine routine;
}

void main(string[] args)
{
   if(args.length < 2)
   {
      writeln("Insufficient arguments!");
      writeln("Usage \'rebuild [config file]\'");
      return;
   }
   
   string config_file_path = args[1];
   
   writeln("Global config file: ", GlobalConfigFilePath);
   
   if(exists(config_file_path ~ ".new"))
   {
      config_file_path = config_file_path ~ ".new";
   }
   
   if(args.length == 2)
   {
      RunRoutine(config_file_path, GetDefaultRoutine(config_file_path));
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
                  
               default:
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
         RunRoutine(config_file_path, GetDefaultRoutine(config_file_path), version_type);
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
   
   JSONValue routine_json = file_json[routine_name];
   
   if(routine_json.type() == JSON_TYPE.OBJECT)
   {
      BuildRoutine routine_info = MakeRoutine(file_path, routine_name);
   
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
      build_info.dependencies = null;
      
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
      
      if(HasJSON(routine_json, "source"))
      {
         JSONValue source_json = routine_json["source"];
         build_info.source_folders = new FileDescription[JSONArraySize(source_json)];
         
         if(source_json.type() == JSON_TYPE.STRING)
         {
            build_info.source_folders[0].path = routine_json["source"].str();
         }
         else if(source_json.type() == JSON_TYPE.ARRAY)
         {
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
      
      if(HasJSON(routine_json, "dependencies"))
      {
         JSONValue dependencies_json = routine_json["dependencies"];
         
         //TODO: file endings
         build_info.dependencies = new FileDescription[JSONArraySize(dependencies_json)];
         JSONMapString(dependencies_json, (string dep_str_in, int i) 
         {
            if(AreTagsValid(dep_str_in, build_info))
            {
               string dep_str = ProcessTags(dep_str_in , build_info, routine_info);
               
               if(dep_str.canFind("/"))
                  dep_str = PathF(dep_str, routine_info);
               
               build_info.dependencies[i].path = dep_str;  
            }
         });
      }
      else
      {
         build_info.dependencies = new FileDescription[1];
         build_info.dependencies[0].path = "";
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
            
            if(AreTagsValid(operation_token, build_info))
            {
               operation_token = ProcessTags(operation_token, build_info, routine);
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
                  if(AreTagsValid(operation_json[i].str(), build_info))
                     operation_params[i - 1] = ProcessTags(operation_json[i].str(), build_info, routine);
               }
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
                  CallOperation(routine, operation_params);
                  break;
               
               case "cmd":
                  CommandOperation(routine, operation_params);
                  break;
               
               case "replace":
                  ReplaceOperation(routine, operation_params);
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
            
            if(AreTagsValid(operation_token, build_info))
            {
               operation_token = ProcessTags(operation_token, build_info, routine);
            }
            else
            {
               continue;
            }
            
            switch(operation_token)
            {
               case "build":
                  BuildOperation(routine, build_info, version_info);
                  has_built = true;
                  break;
               
               default:
                  writeln("Unknown Operation: ", operation_token);
            }
         }
      }
      
      if(!has_built)
         BuildOperation(routine, build_info, version_info);
   }
}

void ExecutePerOperations(string output_directory, BuildRoutine routine, BuildInformation build_info, VersionInformation version_info)
{
   JSONValue routine_json = GetRoutineJSON(routine);
   string version_string = to!string(version_info.major) ~ "_" ~ to!string(version_info.minor) ~ "_" ~ to!string(version_info.patch) ~ "_" ~ version_info.appended;
   
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
      
      foreach(JSONValue operation_json; operations_json.array)
      {
         if(operation_json.type() == JSON_TYPE.STRING)
         {
            if(operation_json.str() == "build")
            {
               specifies_build = true;
            }
         }
      }
      
      if(!specifies_build)
      {
         has_built = true;
         Build(output_directory, routine, build_info, version_info);
      }
   
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
            
            if(AreTagsValid(operation_token, build_info))
            {
               operation_token = ProcessTags(operation_token, build_info, routine);
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
                  if(AreTagsValid(operation_json[i].str(), build_info))
                  {
                     operation_params[i - 1] = ProcessTags(operation_json[i].str(), build_info, routine)
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
                  MoveOperation(routine, operation_params);
                  break;
               
               case "delete":
                  DeleteOperation(routine, operation_params);
                  break;
               
               case "copy":
                  CopyOperation(routine, operation_params);
                  break;
               
               case "call":
                  CallOperation(routine, operation_params);
                  break;
               
               case "cmd":
                  CommandOperation(routine, operation_params);
                  break;
               
               case "replace":
                  ReplaceOperation(routine, operation_params);
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
                  
            if(AreTagsValid(operation_token, build_info))
            {
               operation_token = ProcessTags(operation_token, build_info, routine);
            }
            else
            {
               continue;
            }
                  
            switch(operation_token)
            {
               case "build":
               {
                  if(!has_built)
                  {
                     has_built = true;
                     writeln("\tBuilding...");
                     Build(output_directory, routine, build_info, version_info);
                  }
                  else
                  {
                     writeln("Already built!");
                  }
               }
               break;
               
               default:
                  writeln("Unknown Operation: ", operation_token);
            }
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
      string[] arch_names = GetArchitectureNames(GlobalConfigFilePath);
      
      foreach(string arch_name; arch_names)
      {
         build_info.platform.arch = arch_name;
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

void CopyOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      writeln("\tCopy ", PathF(params[0], routine_info), " -> ", PathF(params[1], routine_info));
      CopyFile(PathF(params[0], routine_info), PathF(params[1], routine_info));
   }
   else if(params.length == 3)
   {
      writeln("\tCopy ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
      CopyFolder(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2]);
   }
}

void DeleteOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      writeln("\tDelete ", PathF(params[0], routine_info), " (", params[1], ") -> /dev/null");
      DeleteFolder(PathF(params[0], routine_info), params[1]);
   }
   else if(params.length == 1)
   {
      writeln("\tDelete ", PathF(params[0], routine_info), " -> /dev/null");
      DeleteFile(PathF(params[0], routine_info));
   }
}

void MoveOperation(BuildRoutine routine_info, string[] params)
{
   if(params.length == 2)
   {
      writeln("\tMove ", PathF(params[0], routine_info), " -> ", PathF(params[1], routine_info));
      CopyFile(PathF(params[0], routine_info), PathF(params[1], routine_info));
      DeleteFile(PathF(params[0], routine_info));
   }
   else if(params.length == 3)
   {
      writeln("\tMove ", PathF(params[0], routine_info), " (", params[2], ") -> ", PathF(params[1], routine_info));
      CopyFolder(PathF(params[0], routine_info), PathF(params[1], routine_info), params[2]);
      DeleteFolder(PathF(params[0], routine_info), PathF(params[1], routine_info));
   }
}

void CallOperation(BuildRoutine routine_info, string[] params)
{
   writeln("Executing calls:");
   
   if(params.length > 1)
   {
      if((params[0] == "=") || (params[0] == "||"))
      {
         params[0] = routine_info.path;
      }
      
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
            RunRoutine(PathF(params[0], routine_info), call_arg, version_type);
         }
      }
   
      if(!function_called)
      {
         RunRoutine(PathF(params[0], routine_info), GetDefaultRoutine(PathF(params[0], routine_info)), version_type);
      }
   }
   else if(params.length == 1)
   {
      RunRoutine(PathF(params[0], routine_info), GetDefaultRoutine(PathF(params[0], routine_info)));
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
   else
   {
      writeln("Language config missing commands for language ", language_name, "(", build_type, ")");
      exit(-1);
   }
   
   return output;
}

string[] GetLanguageOptionalAttribs(string file_path, string language_name, string build_type)
{
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

bool IsAttribOptional(string file_path, string language_name, string build_type, string attrib_name)
{
   return GetLanguageOptionalAttribs(file_path, language_name, build_type).canFind(attrib_name);
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
   
   if(HasJSON(file_json, "architectures"))
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
   else 
   {
      writeln("No available architectures!");
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
      new_tag = new_tag[letter_index .. $];
                       
   return new_tag;
}

string ProcessTags(string tag, BuildInformation build_info, BuildRoutine routine_info)
{
   string new_tag = RemoveTags(tag, build_info.platform);
   
   foreach(string attrib_name, string[] attrib_array; build_info.attributes)
   {
      string attrib_string = "";
   
      foreach(string attrib_element; attrib_array)
      {
         if(IsProperPlatform(attrib_element, build_info.platform))
            attrib_string = attrib_string ~ " " ~ RemoveTags(attrib_element, build_info.platform)
                                                  .replace("[ARCH_NAME]", build_info.platform.arch)
                                                  .replace("[OS_NAME]", build_info.platform.OS)
                                                  .replace("[PROJECT_NAME]", build_info.project_name);
      }
      
      new_tag = new_tag.replace("[ATTRIB: " ~ attrib_name ~ "]", attrib_string);
   }
   
   foreach(string optional_attrib_name; GetLanguageOptionalAttribs(GlobalConfigFilePath, build_info.language, build_info.type))
   {
      new_tag = new_tag.replace("[ATTRIB: " ~ optional_attrib_name ~ "]", ""); 
   }
   
   if(IsFieldCrossReference(new_tag))
   {
      FieldCrossReference fcr = GetFieldCrossReference(routine_info, new_tag);
      
      BuildRoutine fcr_routine = fcr.routine;
      fcr_routine.path = PathF(fcr.routine.path, routine_info);
      fcr_routine.directory = PathF(fcr.routine.directory, routine_info);
      
      string field_string = GetFieldStringFromRoutine(fcr_routine, fcr.field);
      new_tag = new_tag.replace(fcr.tag, field_string);
   }
   
   return new_tag;
}

bool AreTagsValid(string tag, BuildInformation build_info)
{
   bool tags_valid = true;
   string copy_tag = tag;
   
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
            
            bool is_optional = IsAttribOptional(GlobalConfigFilePath, build_info.language, build_info.type, attrib_name);
            auto is_available = (attrib_name in build_info.attributes);
            if(!is_available && !is_optional)
            {
               writeln("------------------------------------------------------");
               writeln("Attribute \"", attrib_name, "\" not available! \nReferenced in tag\n\"", tag , "\"");
               writeln("------------------------------------------------------");
               
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

string[] GetFieldFromRoutine(BuildRoutine routine, string field_name)
{
   JSONValue routine_json = GetRoutineJSON(routine);
   string[] field_array = null;
   
   if(HasJSON(routine_json, field_name))
   {
      JSONValue field_json = routine_json[field_name];
      
      field_array = new string[JSONArraySize(field_json)];
      JSONMapString(field_json, (string field_str, int i)
      {
         field_array[i] = field_str;
      });
   }
   
   return field_array;
}

string GetFieldStringFromRoutine(BuildRoutine routine, string attrib_name)
{
   string[] attrib_array = GetFieldFromRoutine(routine, attrib_name);
   string attrib_string = "";
   
   foreach(string attrib_element; attrib_array)
   {
      attrib_string = attrib_string ~ " " ~ attrib_element;
   }
   
   return attrib_string;
}

bool IsFieldCrossReference(string attrib_tag)
{
   if(attrib_tag.canFind("[FIELD_REF: ") && 
      attrib_tag.canFind("<-") && 
      attrib_tag.canFind("]"))
   {
      return true;
   }
   
   return false;
}

FieldCrossReference GetFieldCrossReference(BuildRoutine routine_info, string in_field_tag)
{
   string field_tag = in_field_tag[in_field_tag.indexOf("[FIELD_REF: ") + "[FIELD_REF: ".length .. $];
   
   string field_name = field_tag[0 .. field_tag.indexOf("<-")];
   field_tag = field_tag[field_tag.indexOf("<-") + 2 .. $];
   
   int end_of_file_path = field_tag.indexOf(":") >= 0 ? field_tag.indexOf(":") : field_tag.indexOf("]");
   string file_path = field_tag[0 .. end_of_file_path];
   
   FieldCrossReference fcr;
   fcr.field = field_name;
   fcr.tag = in_field_tag[in_field_tag.indexOf("[FIELD_REF: ") .. in_field_tag.indexOf("]") + 1];
   
   if(field_tag.canFind(":"))
   {
      string routine_name = field_tag[field_tag.indexOf(":") + 1 .. field_tag.indexOf("]")];
      fcr.routine = MakeRoutine(file_path, routine_name);
   }
   else
   {
      fcr.routine = MakeRoutine(file_path, GetDefaultRoutine(PathF(file_path, routine_info)));
   }
   
   return fcr;
}

BuildRoutine MakeRoutine(string file_path, string routine_name)
{
   BuildRoutine routine_info;
   
   routine_info.path = file_path;
   routine_info.name = routine_name;
   routine_info.directory = file_path[0 .. file_path.lastIndexOf("/") + 1];
   
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

void JSONMapString(JSONValue json, void delegate(string str, int i) map_func)
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

void CopyFile(string source, string destination)
{
   try
   {
      string dest_directory = destination[0 .. destination.lastIndexOf("/")];
      if(!exists(dest_directory))
         mkdirRecurse(dest_directory);
   
      if(isFile(source))
         copy(source, destination, PreserveAttributes.no);
         
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
               CopyFile(e.name(), destination ~ e.name().replace(source, ""));
               
         }
      }
   } catch {}
}

void DeleteFile(string path)
{
   try
   {
      if(isFile(path))
         remove(path);

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
               DeleteFile(e.name());
               
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
   
   if(!exists(PathF(output_folder, routine_info)))
   {
      mkdirRecurse(PathF(output_folder, routine_info));
   }
   
   foreach(FileDescription source_in; build_info.source_folders)
   {
      if(AreTagsValid(source_in.path, build_info))
      {
         FileDescription source = source_in;
         source.path = ProcessTags(source_in.path, build_info, routine_info)
                       .replace("[ARCH_NAME]", build_info.platform.arch)
                       .replace("[OS_NAME]", build_info.platform.OS)
                       .replace("[PROJECT_NAME]", build_info.project_name);
         
         CopyFile(PathF(source.path, routine_info), temp_dir ~ "/" ~ source.path[source.path.indexOf("/") + 1 .. $]);
         CopyFolder(PathF(source.path, routine_info), temp_dir ~ "/", source.ending);
      }
   }

   string dependencies = "";
   foreach(FileDescription dep; build_info.dependencies)
   {
      //TODO: file endings
      dependencies = dependencies ~ " " ~ dep.path;
   }
   
   writeln("Building " ~ build_info.project_name ~ " for " ~ build_info.platform.arch ~ (build_info.platform.optimized ? "(OPT)" : "(NOPT)"));

   string command_batch = "";
   
   foreach(string command_template; commands)
   {
      if(AreTagsValid(command_template, build_info))
      {
         string command = ProcessTags(command_template, build_info, routine_info)
                          .replace("[ARCH_NAME]", build_info.platform.arch)
                          .replace("[OS_NAME]", build_info.platform.OS)
                          .replace("[PROJECT_NAME]", build_info.project_name)
                          .replace("[BUILD_DIRECTORY]", temp_dir)
                          .replace("[OUTPUT_FILE]", output_file_name)
                          .replace("[DEPENDENCIES]", dependencies);
     
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
   
   CopyFile(temp_dir ~ "/" ~ build_info.project_name ~ file_ending, PathF(output_folder, routine_info) ~ "/" ~ output_file_name ~ file_ending);
   
   rmdirRecurse(temp_dir);
}