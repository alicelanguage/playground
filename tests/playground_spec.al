using Alice.Playground

module Specs
  def self.check(ok : Bool, label : String)
    raise "FAIL: " + label unless ok
    puts "PASS: " + label
  end

  def self.run
    result = PlaygroundApp.Compile("xs = [1, 2, 3]\nputs xs.map { |x| x * 2 }.sum", true)
    check(result.Success, "compile and run: " + result.Error)
    check(result.Output.strip == "12", "execute emitted IL")
    check(result.Hir.Contains("CallExpr") && result.Hir.Contains("int"), "typed HIR")
    check(result.Mir.Contains("MFor"), "actual lowered MIR")
    check(result.CSharp.Contains("public static void Main"), "generated C#")
    check(result.Il.Contains("IL_") && result.Il.Contains("call"), "decoded PE instructions")
    compile_only = PlaygroundApp.Compile("raise \"must not run\"", false)
    check(compile_only.Success && compile_only.Output == "", "compile without execution")
    bad = PlaygroundApp.Compile("val x = 1\nx = 2\nputs x", true)
    check(!bad.Success && bad.Diagnostics.Any(->(d : Alice.Compiler.Diagnostic) { d.Line == 2 }), "Alice safety diagnostics")
    failure = PlaygroundApp.Compile("puts \"before\"\nraise \"boom\"", true)
    check(!failure.Success && failure.Output.Contains("before") && failure.Error.Contains("boom") && failure.Il.Length > 0, "runtime errors retain output and stages")
    library = PlaygroundApp.Compile("def square(x : Int32) : Int32\n x * x\nend", false)
    check(library.Success && library.Il.Contains("square") && library.Mir.Contains("MReturn"), "inspect declarations without Main")
    loop_result = PlaygroundApp.Compile("sum = 0\nfor i in 0...5\n sum += i\nend\nputs sum", true)
    check(loop_result.Success && loop_result.Output.strip == "10" && loop_result.Il.Contains("IL_"), "decode loop branches")
    for example in ["pipeline", "fibonacci", "types", "patterns", "classes", "collections", "parallel", "performance"]
      sample = PlaygroundApp.Compile(View.Example(example), true)
      check(sample.Success && sample.Output.Length > 0, "example " + example + ": " + sample.Error)
    end
    escaped = PlaygroundApp.Compile("puts \"<script>alert(1)</script>\"", true)
    html = View.Result(escaped, "il")
    check(html.Contains("&lt;script&gt;") && !html.Contains("<script>alert"), "escape code and console HTML")
    check(View.Page().Contains("Alice source code"), "Alice renders the playground page")
    page = View.Page()
    check(View.Examples().All(->(e : String) { page.Contains("value=\"" + e.Split("|")[0] + "\"") }), "every example is in the menu")
    check(page.Contains("install.sh") && page.Contains("alice-mark.svg"), "site branding and install command")
    evaluation = PlaygroundApp.Compile("puts \"hello\"\n6 * 7", true)
    check(evaluation.Success, "evaluate a trailing expression: " + evaluation.Error)
    check(evaluation.Output.strip == "hello" && evaluation.HasValue && evaluation.Value == "42" && evaluation.ValueType == "Int32", "console output and expression result stay separate")
    value_only = PlaygroundApp.Compile("[1, 2, 3]", true)
    check(value_only.Success && value_only.Value == "[1, 2, 3]", "inspect a collection result")
    no_value = PlaygroundApp.Compile("puts 1", true)
    check(no_value.Success && !no_value.HasValue, "results reset between runs")
    overflow = PlaygroundApp.Compile("100000.times { puts \"xxxxxxxxxx\" }", true)
    check(!overflow.Success && overflow.Output.Length <= 65536 && overflow.Error.Contains("64 KiB"), "bounded console output")
  end
end
Specs.run
