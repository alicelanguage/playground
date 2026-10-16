using Alice.Compiler
using Alice.Compiler.Syntax
using Alice.Compiler.Semantics
using Alice.Compiler.Backend
using Alice.Compiler.Mir
using Microsoft.CodeAnalysis
using System.Reflection

namespace Alice.Playground
  class PlaygroundResult
    property Success : Bool = false
    property Hir : String = ""
    property Mir : String = ""
    property CSharp : String = ""
    property Il : String = ""
    property Output : String = ""
    property Error : String = ""
    property HasValue : Bool = false
    property Value : String = ""
    property ValueType : String = ""
    property Diagnostics : List(Alice.Compiler.Diagnostic) = List(Alice.Compiler.Diagnostic).new
  end

  # This is the application, not a wrapper around a second implementation.
  module PlaygroundApp
    def self.Compile(source : String, run : Bool) : PlaygroundResult
      result = PlaygroundResult.new
      begin
        raise "Source is limited to 100,000 characters." if source.Length > 100000
        file = Parser.ParseFile(source, "main.al")
        files = List(FileNode).new
        files.Add(file)
        binder = Alice.Compiler.Semantics.Binder.new(files, ClrTypes.new)
        binder.Bind
        result.Hir = TreeDump.Print(file)
        if PlaygroundApp.CaptureTail(file)
          binder = Alice.Compiler.Semantics.Binder.new(files, ClrTypes.new)
          binder.Bind
        end
        mir = StringBuilder.new
        emitter = Emitter.new(binder)
        emitter.ObserveMir = ->(body : IReadOnlyList(MStmt)) { mir.AppendLine(TreeDump.Print(body)) }
        result.CSharp = emitter.EmitFile(file)
        result.Mir = mir.ToString
        units = List(String).new
        units.Add(result.CSharp)
        executable = file.Items.Any(->(item : Item) { item.is_a?(StmtItem) })
        image = AliceCompiler.Emit(units, "Playground_" + Guid.NewGuid().ToString("N"), executable)
        result.Il = IlDisassembler.Print(image)
        if run && executable
          old_out = Console.Out
          old_err = Console.Error
          old_in : TextReader = TextReader.Null
          old_in = Console.In unless OperatingSystem.IsBrowser()
          output = BoundedOutput.new
          Console.SetOut(output)
          Console.SetError(output)
          Console.SetIn(StringReader.new(""))
          ExecutionCapture.Reset()
          begin
            assembly = AliceCompiler.Load(image)
            assembly.EntryPoint.not_nil!.Invoke(nil, [Array(String).new(0).as(Object)])
          ensure
            result.Output = output.ToString
            result.HasValue = ExecutionCapture.HasValue
            result.Value = ExecutionCapture.Value
            result.ValueType = ExecutionCapture.ValueType
            Console.SetOut(old_out)
            Console.SetError(old_err)
            Console.SetIn(old_in)
          end
        end
        result.Success = true
      rescue e : CompileException
        result.Error = e.Message
        for diagnostic in e.Diagnostics
          result.Diagnostics.Add(diagnostic)
        end
      rescue e : Exception
        error = e
        while error.is_a?(TargetInvocationException) && !error.InnerException.nil?
          error = error.InnerException.not_nil!
        end
        result.Error = error.ToString()
      end
      result
    end

    # Retain the original HIR for inspection, and lower a typed capture call for a value-producing tail.
    def self.CaptureTail(file : FileNode) : Bool
      return false if file.Items.Count == 0
      last = file.Items[file.Items.Count - 1]
      return false unless last.is_a?(StmtItem)
      statement = last.as(StmtItem).Stmt
      return false unless statement.is_a?(ExprStmt)
      expression = statement.as(ExprStmt).Expr
      return false if expression.Type.IsVoid
      template = Parser.ParseFile("Alice.Playground.ExecutionCapture.Record(nil)", "main.al")
      call = template.Items[0].as(StmtItem).Stmt.as(ExprStmt).Expr.as(CallExpr)
      call.Args[0].Value = expression
      call.Line = statement.Line
      call.Col = statement.Col
      statement.as(ExprStmt).Expr = call
      true
    end
  end

  module ExecutionCapture
    property HasValue : Bool = false
    property Value : String = ""
    property ValueType : String = ""

    def self.Reset() : Nil
      ExecutionCapture.HasValue = false
      ExecutionCapture.Value = ""
      ExecutionCapture.ValueType = ""
    end

    def self.Record(value : Object?) : Nil
      text = Alice.Runtime.Prelude.inspect(value)
      ExecutionCapture.Value = text.Length > 8192 ? text.Substring(0, 8192) + "…" : text
      ExecutionCapture.ValueType = value.nil? ? "Nil" : value.not_nil!.GetType().Name
      ExecutionCapture.HasValue = true
    end
  end

  # Keep a runaway puts loop bounded even before the worker deadline fires.
  class BoundedOutput < StringWriter
    def Write(value : Char) : Nil
      raise "Output exceeded 64 KiB." if self.GetStringBuilder().Length >= 65536
      super(value)
    end
    def Write(value : String?) : Nil
      raise "Output exceeded 64 KiB." if self.GetStringBuilder().Length + (value.nil? ? 0 : value.not_nil!.Length) > 65536
      super(value)
    end
    def WriteLine(value : String?) : Nil
      self.Write(value)
      self.Write("\n")
    end
  end
end
