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
   -build folder format
   -per build operations
   -optimized builds
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
      
      if(can_build)
      {
         Build(source_folders, build_folder, language_name, project_name, build_type, major_version, minor_version, patch_version, version_appended);
      }
      
      try { CopyOperation(routine_json); } catch {}
      try { DeleteOperation(routine_json); } catch {}
      try { MoveOperation(routine_json); } catch {}
      try { CallOperation(routine_json); } catch {}
      
      try { UpdateVersions(file_path, routine_name, update_major_version, update_minor_version, update_patch_version); } catch { writeln("version update failed!"); }
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
            //TODO: add type checking
            
            bool major_version = false;
            bool minor_version = false;
            bool patch_version = false; 
         
            bool function_called = false;
         
            for(int i = 1;  value.array.length > i; ++i)
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
      
            if(!function_called)
            {
               string config_file_default_routine = GetDefaultRoutine(value[0].str()); 
               RunRoutine(value[0].str(), config_file_default_routine, major_version, minor_version, patch_version);
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
         //TODO: add type checking
         
         if(file_json[routine_name]["version"].type() == JSON_TYPE.ARRAY)
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
   
   writeln(file_path ~ ":\n" ~ file_json.toString() ~ "\n");
   //TODO: write to json file (make it look nice, add newlines)
}

string[] GetLanguageCommands(string file_path, string language_name, string build_type)
{
   writeln("Loading language ", language_name, " (", build_type, ") from ", file_path);

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
   writeln("Loading language ", language_name, " (", build_type, ") from ", file_path);

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

void CopyFile(string source, string destination)
{
   try
   {
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
      if(isDir(source) && isDir(destination))
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

void Build(string[] sources, string dest, string language, string project_name, string build_type, int major_version, int minor_version, int patch_version, string appended)
{
   string temp_dir = "./" ~ randomUUID().toString();
   string[] commands = GetLanguageCommands(GlobalConfigFilePath, language, build_type);
   string file_ending = GetLanguageFileEnding(GlobalConfigFilePath, language, build_type);
   string version_string = to!string(major_version) ~ "_" ~ to!string(minor_version) ~ "_" ~ to!string(patch_version) ~ "_" ~ appended;
   string output_file_name = project_name ~ "_" ~ version_string;
   
   mkdir(temp_dir);
   
   foreach(string source; sources)
   {
      CopyFile(source, temp_dir ~ "/" ~ source);
      CopyFolder(source, temp_dir ~ "/");
   }

   writeln("Building " ~ project_name);

   string command_batch = "";
   
   foreach(string command_template; commands)
   {
      string command = command_template.replace("[PROJECT_NAME]", project_name)
                                       .replace("[BUILD_DIRECTORY]", temp_dir)
                                       .replace("[OUTPUT_FILE]", output_file_name);
      
      if(command_batch == "")
      {
         command_batch = command_batch ~ command;
      }
      else
      {
         command_batch = command_batch ~ " && " ~ command;
      }
   }
   
   system(toStringz(command_batch));
   
   CopyFile(temp_dir ~ "/" ~ project_name ~ file_ending, dest ~ "/" ~ output_file_name ~ file_ending);
   
   rmdirRecurse(temp_dir);
}