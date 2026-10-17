using System.Runtime.InteropServices.JavaScript
using System.Text.Json
using Alice.Playground

namespace Alice.Playground
  module Browser
    @[JSExport]
    def self.Initialize(base_url : String) : String
      begin
      # The bootstrap reuses its verified runtime downloads in /refs; no second fetch.
      paths = Directory.GetFiles("/refs", "*.dll")
      AppContext.SetData("TRUSTED_PLATFORM_ASSEMBLIES", String.Join(Path.PathSeparator.ToString(), paths))
      "ready"
      rescue e : Exception
        e.ToString()
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
