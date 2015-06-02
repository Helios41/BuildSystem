import std.stdio;
import std.file;
import std.json;
import std.array;
import std.algorithm.searching;

void main(string[] args)
{
   if(args.length < 2)
   {
      writeln("Insufficient arguments!");
      writeln("Usage \'buildsystem [make directory]\'");
      return;
   }
   
   string config_path = args[1] ~ "make.json";
   writeln("Loading configs from ", config_path);
   
   if(!isFile(config_path))
   {
      writeln(config_path ~ " not found!");
      return;
   }
   
   string config_contents = readText(config_path); 
   JSONValue config_json = parseJSON(config_contents);
   
   string[] source_folders;
   
   try
   {
      if(config_json["project"].type() == JSON_TYPE.STRING)
      {
         writeln("Building " ~ config_json["project"].str());
      }   
      
      if(config_json["source"].type() == JSON_TYPE.STRING)
      {
         source_folders = new string[1];
         source_folders[0] = config_json["source"].str();
      }
      else if(config_json["source"].type() == JSON_TYPE.ARRAY)
      {
         source_folders = new string[config_json["source"].array.length];
         int index = 0;
      
         foreach (JSONValue value; config_json["copy"].array)
         {
            if(value.type() == JSON_TYPE.STRING)
            {
               source_folders[index] = value.str();
               ++index;
            }
         }
      }
      
      if(config_json["build"].type() == JSON_TYPE.STRING)
      {
      
      }
      
      Build(source_folders, null);
      
      if(config_json["copy"].type() == JSON_TYPE.ARRAY)
      {
         writeln("Executing copies:");
         
         foreach (JSONValue value; config_json["copy"].array)
         {
            if(value.type() == JSON_TYPE.ARRAY)
            {
               if(value.array.length == 2)
               {
                  writeln("\t" ~ value[0].str() ~ " -> " ~ value[1].str());
                  CopyFile(value[0].str(), value[1].str());
               }
            }
         }
      }
   }
   catch
   {
      writeln("Missing JSON element(s)!");
   } 
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

void Build(string[] sources, string dest)
{
   mkdir("./build_dir_temp");
   
   //TODO: only copy source with certain ending
   
   foreach(string source; sources)
   {
      CopyFile(source, "./build_dir_temp/" ~ source);
      CopyFolder(source, "./build_dir_temp/");
   }
   
   rmdirRecurse("./build_dir_temp");
}