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
   -per build call operation
   -make stuff non case specific (e.g. architecture names)
   -"operations" & "peroperations" arrays
   -"Build" operation, if not called call build after operations are executed
   -build dll on windows (without delspec or .def file)
   -ability to specify functions to expose as dll
   -clean up code!
*/

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
      bool major_version = false;
      bool minor_version = false;
      bool patch_version = false; 
   
      bool function_called = false;
   
      for(int i = 2; args.length > i; ++i)
      {
         string argument = args[i];
         
         if(argument.startsWith("-"))
         {
            if(argument == "-major")
            {
               major_version = true;
            }
            else if(argument == "-minor")
            {
               minor_version = true;
            }
            else if(argument == "-patch")
            {
               patch_version = true;
            }
         }
         else
         {
            function_called = true;
            RunRoutine(config_file_path, argument, major_version, minor_version, patch_version);
         }
      }
      
      if(!function_called)
      {
         string config_file_default_routine = GetDefaultRoutine(config_file_path); 
         RunRoutine(config_file_path, config_file_default_routine, major_version, minor_version, patch_version);
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

void RunRoutine(string file_path, string routine_name, bool update_major_version = false, bool update_minor_version = false, bool update_patch_version = false)
{
   writeln("Executing routine ", routine_name, " in ", file_path);

   if(!isFile(file_path))
   {
      writeln(file_path ~ " not found!");
      exit(-1);
   }
   
   JSONValue file_json = parseJSON(readText(file_path));
   bool can_build = true;
   
   if(file_json[routine_name].type() == JSON_TYPE.OBJECT)
   {
      JSONValue routine_json = file_json[routine_name];
      
      string[] source_folders;
      string build_folder;
      string project_name;
      string language_name;
      string build_type;
      string static_libraries = "";
      bool optimized = true;
      
      int major_version = 0;
      int minor_version = 0;
      int patch_version = 0;
      string version_appended = "";
      
      try
      {
         if(routine_json["project"].type() == JSON_TYPE.STRING)
         {
            project_name = routine_json["project"].str();
         }   
      }      
      catch { can_build = false; }
      
      try
      {
         if(routine_json["language"].type() == JSON_TYPE.STRING)
         {
            language_name = routine_json["language"].str();
         } 
      }      
      catch { can_build = false; }
      
      try
      {
         if(routine_json["type"].type() == JSON_TYPE.STRING)
         {
            build_type = routine_json["type"].str();
         }
      }      
      catch { can_build = false; }
      
      try
      {
         if(routine_json["source"].type() == JSON_TYPE.STRING)
         {
            source_folders = new string[1];
            source_folders[0] = routine_json["source"].str();
         }
         else if(routine_json["source"].type() == JSON_TYPE.ARRAY)
         {
            source_folders = new string[routine_json["source"].array.length];
            int index = 0;
         
            foreach(JSONValue value; routine_json["source"].array)
            {
               if(value.type() == JSON_TYPE.STRING)
               {
                  source_folders[index] = value.str();
                  ++index;
               }
            }
         }
      }
      catch { can_build = false; }
      
      try
      {
         if(routine_json["build"].type() == JSON_TYPE.STRING)
         {
            build_folder = routine_json["build"].str();
         }
      }
      catch { can_build = false; }
      
      try
      {
         if(routine_json["version"].type() == JSON_TYPE.ARRAY)
         {
            JSONValue version_json = routine_json["version"];
            
            if(version_json.array.length >= 3)
            {
               if(version_json[0].type() == JSON_TYPE.INTEGER)
               {
                  major_version = to!int(version_json[0].integer);
               }
               
               if(version_json[1].type() == JSON_TYPE.INTEGER)
               {
                  minor_version = to!int(version_json[1].integer);
               }
               
               if(version_json[2].type() == JSON_TYPE.INTEGER)
               {
                  patch_version = to!int(version_json[2].integer);
               }
            }
            
            if(version_json.array.length == 4)
            {   
               if(version_json[3].type() == JSON_TYPE.STRING)
               {
                  version_appended = version_json[3].str();
               }
            }
         }
      }
      catch {}
      
      try
      {
         if(routine_json["optimized"].type() == JSON_TYPE.TRUE)
         {
            optimized = true;
         }
         else if(routine_json["optimized"].type() == JSON_TYPE.FALSE)
         {
            optimized = false;
         }
      }
      catch {}
      
      try
      {
         string arch_name = GetArchitectureNames(GlobalConfigFilePath)[0];
         string OS_name = GetOSName();
      
         if(routine_json["dependencies"].type() == JSON_TYPE.STRING)
         {
            string dependency = routine_json["dependencies"].str();
            
            if(IsProperPlatform(dependency, arch_name, OS_name, optimized))
            {
               static_libraries = static_libraries ~ " " ~ RemoveTags(dependency, arch_name, OS_name);
            }
         }
         else if(routine_json["dependencies"].type() == JSON_TYPE.ARRAY)
         {
            JSONValue dependencies_json = routine_json["dependencies"];
            
            foreach(JSONValue element_json; dependencies_json.array)
            {
               if(element_json.type == JSON_TYPE.STRING)
               {
                  string dependency = element_json.str();
                  
                  if(IsProperPlatform(dependency, arch_name, OS_name, optimized))
                  {
                     static_libraries = static_libraries ~ " " ~ RemoveTags(dependency, arch_name, OS_name);
                  }
               }
            }
         }
      }
      catch {}
      
      //writeln("Static Deps: ", static_libraries);
      
      try { ExecuteOperations(routine_json); } catch {}
      
      try { UpdateVersions(file_path, routine_name, update_major_version, update_minor_version, update_patch_version); } catch { writeln("version update failed!"); }
      
      if(can_build)
      {
         string OS_name = GetOSName();
         string[] arch_names = GetArchitectureNames(GlobalConfigFilePath);
         
         foreach(string arch_name; arch_names)
         {
            string output_directory = (build_folder.endsWith("/") ? build_folder[0 .. build_folder.lastIndexOf("/")] : build_folder) ~ "/" ~ OS_name ~ "_" ~ arch_name;
         
            Build(source_folders, output_directory, language_name, project_name, build_type, major_version, minor_version, patch_version, version_appended, static_libraries, arch_name, optimized, OS_name);
            
            try { CopyPerOperation(routine_json, output_directory); } catch {}
            try { DeletePerOperation(routine_json, output_directory); } catch {}
            try { MovePerOperation(routine_json, output_directory); } catch {}
            //try { CallPerOperation(routine_json, output_directory); } catch {}
         }
      }
      
      try { CopyOperation(routine_json); } catch {}
      try { DeleteOperation(routine_json); } catch {}
      try { MoveOperation(routine_json); } catch {}
      try { CallOperation(routine_json); } catch {}
   }
}

void ExecuteOperations(JSONValue routine_json)
{
   if(routine_json["operations"].type() == JSON_TYPE.ARRAY)
   {
      JSONValue operations_json = routine_json["operations"];
      
      foreach(JSONValue operation_json; operations_json.array)
      {
         if(operation_json.type() == JSON_TYPE.ARRAY)
         {
            
         }
         else if(operation_json.type() == JSON_TYPE.STRING)
         {
         
         }
      }
   }
}

void ExecutePerOperations(JSONValue routine_json, string output_dictionary)
{
   if(routine_json["peroperations"].type() == JSON_TYPE.ARRAY)
   {
      JSONValue operations_json = routine_json["peroperations"];
      
      foreach(JSONValue operation_json; operations_json.array)
      {
         if(operation_json.type() == JSON_TYPE.ARRAY)
         {
            
         }
         else if(operation_json.type() == JSON_TYPE.STRING)
         {
         
         }
      }
   }
}

void CopyPerOperation(JSONValue routine_json, string output_directory)
{
   if(routine_json["per"].type() == JSON_TYPE.OBJECT)
   {
      JSONValue per_operations_json = routine_json["per"];
      
      if(per_operations_json["copy"].type() == JSON_TYPE.ARRAY)
      {
         writeln("Executing copies:");
         
         foreach(JSONValue value; per_operations_json["copy"].array)
         {
            if(value.type() == JSON_TYPE.ARRAY)
            {
               if(value.array.length == 2)
               {
                  string copy_source = value[0].str().replace("[OUTPUT_DIRECTORY]", output_directory);
                  string copy_dest = value[1].str().replace("[OUTPUT_DIRECTORY]", output_directory);
               
                  writeln("\t", copy_source, " -> ", copy_dest);
                  CopyFile(copy_source, copy_dest);
               }
               
               if(value.array.length == 3)
               {
                  string copy_source = value[0].str().replace("[OUTPUT_DIRECTORY]", output_directory);
                  string copy_dest = value[1].str().replace("[OUTPUT_DIRECTORY]", output_directory);
               
                  writeln("\t", copy_source, " (", value[2].str(), ") -> ", copy_dest);
                  CopyFolder(copy_source, copy_dest, value[2].str());
               }
            }
         }
      }
   }
}

void CopyOperation(JSONValue routine_json)
{
   if(routine_json["copy"].type() == JSON_TYPE.ARRAY)
   {
      writeln("Executing copies:");
      
      foreach(JSONValue value; routine_json["copy"].array)
      {
         if(value.type() == JSON_TYPE.ARRAY)
         {
            if(value.array.length == 2)
            {
               writeln("\t", value[0].str(), " -> ", value[1].str());
               CopyFile(value[0].str(), value[1].str());
            }
            
            if(value.array.length == 3)
            {
               writeln("\t", value[0].str(), " (", value[2].str(), ") -> ", value[1].str());
               CopyFolder(value[0].str(), value[1].str(), value[2].str());
            }
         }
      }
   }
}

void DeletePerOperation(JSONValue routine_json, string output_directory)
{
   if(routine_json["per"].type() == JSON_TYPE.OBJECT)
   {
      JSONValue per_operations_json = routine_json["per"];
   
      if(per_operations_json["delete"].type() == JSON_TYPE.ARRAY)
      {
         writeln("Executing deletes:");
         
         foreach(JSONValue value; per_operations_json["delete"].array)
         {
            if(value.type() == JSON_TYPE.ARRAY)
            {
               string to_delete = value[0].str().replace("[OUTPUT_DIRECTORY]", output_directory);
            
               if(value.array.length == 2)
               {
                  writeln("\t", to_delete, " (", value[1].str(), ") -> /dev/null");
                  DeleteFolder(to_delete, value[1].str());
               }
            }
            else if(value.type() == JSON_TYPE.STRING)
            {
               string to_delete = value[0].str().replace("[OUTPUT_DIRECTORY]", output_directory);
            
               writeln("\t", to_delete, " -> /dev/null");
               DeleteFile(to_delete);
            }
         }
      }
   }
}

void DeleteOperation(JSONValue routine_json)
{
   if(routine_json["delete"].type() == JSON_TYPE.ARRAY)
   {
      writeln("Executing deletes:");
      
      foreach(JSONValue value; routine_json["delete"].array)
      {
         if(value.type() == JSON_TYPE.ARRAY)
         {
            if(value.array.length == 2)
            {
               writeln("\t", value[0].str(), " (", value[1].str(), ") -> /dev/null");
               DeleteFolder(value[0].str(), value[1].str());
            }
         }
         else if(value.type() == JSON_TYPE.STRING)
         {
            writeln("\t", value.str(), " -> /dev/null");
            DeleteFile(value.str());
         }
      }
   }
}

void MovePerOperation(JSONValue routine_json, string output_directory)
{
   if(routine_json["per"].type() == JSON_TYPE.OBJECT)
   {
      JSONValue per_operations_json = routine_json["per"];
      
      if(per_operations_json["move"].type() == JSON_TYPE.ARRAY)
      {
         writeln("Executing moves:");
         
         foreach(JSONValue value; per_operations_json["move"].array)
         {
            if(value.type() == JSON_TYPE.ARRAY)
            {
               if(value.array.length == 2)
               {
                  string move_source = value[0].str().replace("[OUTPUT_DIRECTORY]", output_directory);
                  string move_dest = value[1].str().replace("[OUTPUT_DIRECTORY]", output_directory);
               
                  writeln("\t", move_source, " -> ", move_dest);
                  CopyFile(move_source, move_dest);
                  DeleteFile(move_source);
               }
               
               if(value.array.length == 3)
               {
                  string move_source = value[0].str().replace("[OUTPUT_DIRECTORY]", output_directory);
                  string move_dest = value[1].str().replace("[OUTPUT_DIRECTORY]", output_directory);
               
                  writeln("\t", move_source, " (", value[2].str(), ") -> ", move_dest);
                  CopyFolder(move_source, move_dest, value[2].str());
                  DeleteFolder(move_source, value[2].str());
               }
            }
         }
      }
   }
}

void MoveOperation(JSONValue routine_json)
{
   if(routine_json["move"].type() == JSON_TYPE.ARRAY)
   {
      writeln("Executing moves:");
      
      foreach(JSONValue value; routine_json["move"].array)
      {
         if(value.type() == JSON_TYPE.ARRAY)
         {
            if(value.array.length == 2)
            {
               writeln("\t", value[0].str(), " -> ", value[1].str());
               CopyFile(value[0].str(), value[1].str());
               DeleteFile(value[0].str());
            }
            
            if(value.array.length == 3)
            {
               writeln("\t", value[0].str(), " (", value[2].str(), ") -> ", value[1].str());
               CopyFolder(value[0].str(), value[1].str(), value[2].str());
               DeleteFolder(value[0].str(), value[1].str());
            }
         }
      }
   }
}

void CallOperation(JSONValue routine_json)
{
   if(routine_json["call"].type() == JSON_TYPE.ARRAY)
   {
      writeln("Executing calls:");
      
      foreach(JSONValue value; routine_json["call"].array)
      {
         if(value.type() == JSON_TYPE.ARRAY)
         {
            if(value[0].type() == JSON_TYPE.STRING)
            {
               bool major_version = false;
               bool minor_version = false;
               bool patch_version = false; 
            
               bool function_called = false;
            
               for(int i = 1;  value.array.length > i; ++i)
               {
                  if(value[i].type() == JSON_TYPE.STRING)
                  {
                     string argument = value[i].str();
                     
                     if(argument.startsWith("-"))
                     {
                        if(argument == "-major")
                        {
                           major_version = true;
                        }
                        else if(argument == "-minor")
                        {
                           minor_version = true;
                        }
                        else if(argument == "-patch")
                        {
                           patch_version = true;
                        }
                     }
                     else
                     {
                        function_called = true;
                        RunRoutine(value[0].str(), argument, major_version, minor_version, patch_version);
                     }
                  }
               }
         
               if(!function_called)
               {
                  string config_file_default_routine = GetDefaultRoutine(value[0].str()); 
                  RunRoutine(value[0].str(), config_file_default_routine, major_version, minor_version, patch_version);
               }
            }
         }
         else if(value.type() == JSON_TYPE.STRING)
         {
            string call_default_routine = GetDefaultRoutine(value.str()); 
            RunRoutine(value.str(), call_default_routine);
         }
      }
   }
}

void UpdateVersions(string file_path, string routine_name, bool major_version, bool minor_version, bool patch_version)
{
   JSONValue file_json = parseJSON(readText(file_path));
   
   if(major_version || minor_version || patch_version)
   {
      if(file_json[routine_name].type() == JSON_TYPE.OBJECT)
      {  
         if(file_json[routine_name]["version"].type() == JSON_TYPE.ARRAY)
         {
            if(file_json[routine_name]["version"][0].type() == JSON_TYPE.INTEGER &&
               file_json[routine_name]["version"][1].type() == JSON_TYPE.INTEGER &&
               file_json[routine_name]["version"][2].type() == JSON_TYPE.INTEGER)
            {
               if(major_version)
               {
                  file_json[routine_name]["version"][0] = file_json[routine_name]["version"][0].integer + 1;
                  file_json[routine_name]["version"][1] = 0;
                  file_json[routine_name]["version"][2] = 0;
               }
               else if(minor_version)
               {
                  file_json[routine_name]["version"][1] = file_json[routine_name]["version"][1].integer + 1;
                  file_json[routine_name]["version"][2] = 0;
               }
               else if(patch_version)
               {
                  file_json[routine_name]["version"][2] = file_json[routine_name]["version"][2].integer + 1;
               }
            }
         }
      }
   }
   
   //writeln(file_path ~ ":\n" ~ file_json.toString() ~ "\n");
   //TODO: write to json file (make it look nice, add newlines)
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

bool IsProperPlatform(string tag, string arch_name, string OS_name, bool optimized)
{ 
   bool wrong_configuration = false;
   
   if(tag.startsWith("[ARCH: "))
   {
      if(!tag.startsWith("[ARCH: " ~ arch_name ~ "]"))
      {
         wrong_configuration = true;
      }
   }
   
   if(tag.startsWith("[OS: "))
   {
      if(!tag.startsWith("[OS: " ~ OS_name ~ "]"))
      {
         wrong_configuration = true;
      }
   }
   
   if(tag.startsWith("[OPT]") && !optimized)
   {
      wrong_configuration = true;
   }
   else if(tag.startsWith("[NOPT]") && optimized)
   {
      wrong_configuration = true;
   }
   
   return !wrong_configuration;
}

string RemoveTags(string tag, string arch_name, string OS_name)
{
   string new_tag = tag.replace("[ARCH: " ~ arch_name ~ "]", "")
                       .replace("[OS: " ~ OS_name ~ "]", "")
                       .replace("[OPT]", "")
                       .replace("[NOPT]", "");
                       
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

void Build(string[] sources, string dest, string language, string project_name, string build_type, int major_version, int minor_version, int patch_version, string appended, string static_libraries, string arch_name, bool optimized, string OS_name)
{
   string temp_dir = "./" ~ randomUUID().toString();
   string[] commands = GetLanguageCommands(GlobalConfigFilePath, language, build_type);
   string file_ending = GetLanguageFileEnding(GlobalConfigFilePath, language, build_type);
   string version_string = to!string(major_version) ~ "_" ~ to!string(minor_version) ~ "_" ~ to!string(patch_version) ~ "_" ~ appended;
   string output_file_name = project_name ~ "_" ~ version_string;
   
   mkdir(temp_dir);
   
   if(!exists(dest))
   {
      mkdir(dest);
   }
   
   foreach(string source; sources)
   {
      CopyFile(source, temp_dir ~ "/" ~ source);
      CopyFolder(source, temp_dir ~ "/");
   }

   writeln("Building " ~ project_name ~ " for " ~ arch_name ~ (optimized ? "(OPT)" : "(NOPT)"));

   string command_batch = "";
   
   foreach(string command_template; commands)
   {
      if(IsProperPlatform(command_template, arch_name, OS_name, optimized))
      {
         string command = RemoveTags(command_template, arch_name, OS_name)
                          .replace("[PROJECT_NAME]", project_name)
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
   
   //writeln(command_batch);
   system(toStringz(command_batch));
   
   CopyFile(temp_dir ~ "/" ~ project_name ~ file_ending, dest ~ "/" ~ output_file_name ~ file_ending);
   
   rmdirRecurse(temp_dir);
}