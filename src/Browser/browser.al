using System.Runtime.InteropServices.JavaScript
using System.Net.Http
using System.Text.Json
using Alice.Playground

namespace Alice.Playground
  module Browser
    @[JSExport]
    async def self.Initialize(base_url : String) : String
      begin
      # .NET's virtual filesystem supplies the exact runtime assemblies to Roslyn.
      using http = HttpClient.new
        names_json = await http.GetStringAsync(base_url + "references.json")
        names = JsonSerializer.Deserialize<Array(String)>(names_json).not_nil!
        Directory.CreateDirectory("/refs")
        tasks = List(Task(String)).new
        for name in names
          tasks.Add(Download(http, base_url, name))
        end
        paths = await Task.WhenAll(tasks)
        AppContext.SetData("TRUSTED_PLATFORM_ASSEMBLIES", String.Join(Path.PathSeparator.ToString(), paths))
      end
      "ready"
      rescue e : Exception
        e.ToString()
      end
    end

    async def self.Download(http : HttpClient, base_url : String, name : String) : String
      bytes = await http.GetByteArrayAsync(base_url + name)
      # Fingerprinted URLs carry the content identity; reflection needs the assembly's actual name.
      using stream = MemoryStream.new(bytes)
        using pe = System.Reflection.PortableExecutable.PEReader.new(stream)
          md = System.Reflection.Metadata.PEReaderExtensions.GetMetadataReader(pe)
          assembly_name = md.GetString(md.GetAssemblyDefinition().Name)
          path = "/refs/" + assembly_name + ".dll"
          File.WriteAllBytes(path, bytes)
          return path
        end
      end
    end

    @[JSExport]
    def self.Compile(source : String, run : Bool) : String
      JsonSerializer.Serialize<PlaygroundResult>(PlaygroundApp.Compile(source, run))
    end

    @[JSExport]
    def self.Shell() : String
      View.Page()
    end

    @[JSExport]
    def self.Example(name : String) : String
      View.Example(name)
    end

    @[JSExport]
    def self.Result(json : String, stage : String) : String
      result = JsonSerializer.Deserialize<PlaygroundResult>(json).not_nil!
      View.Result(result, stage)
    end
  end
end

# A synchronous Main is only needed to make a browser executable; exports drive the application.
Console.Write("")
