# Build-time browser adaptation of the pinned release DLL. No compiler source checkout is used.
using Mono.Cecil
using Mono.Cecil.Cil
using Alice.Compiler.Mir
using System.Runtime.CompilerServices

module PrepareCompiler
  def self.Normalize(type : TypeReference, scope : AssemblyNameReference)
    if type.is_a?(GenericInstanceType)
      generic = type.as(GenericInstanceType)
      Normalize(generic.ElementType, scope)
      for argument in generic.GenericArguments
        Normalize(argument, scope)
      end
    else
      type.Scope = scope if type.Scope.Name == "System.Private.CoreLib"
    end
  end

  def self.main(input : String, output : String)
    using assembly = AssemblyDefinition.ReadAssembly(input)
      mod = assembly.MainModule
      clr = mod.GetType("Alice.Compiler.Semantics.ClrTypes").not_nil!
      supported = mod.ImportReference(typeof(RuntimeFeature).GetProperty("IsDynamicCodeSupported").not_nil!.GetMethod.not_nil!)
      init = clr.Methods.First(->(m : MethodDefinition) { m.Name == ".cctor" })
      instructions = init.Body.Instructions
      first = instructions.First(->(i : Instruction) { i.OpCode == OpCodes::Ldstr && i.Operand.as(String) == "AliceTypeProxies" })
      last = instructions.First(->(i : Instruction) { i.OpCode == OpCodes::Stsfld && i.Operand.as(FieldReference).Name == "ProxyModule" })
      il = init.Body.GetILProcessor
      il.InsertBefore(first, Instruction.Create(OpCodes::Call, supported))
      il.InsertBefore(first, Instruction.Create(OpCodes::Brfalse, last.Next))
      proxy = clr.Methods.First(->(m : MethodDefinition) { m.Name == "Proxy" })
      first_proxy = proxy.Body.Instructions[0]
      proxy_il = proxy.Body.GetILProcessor
      type_field = mod.GetType("Alice.Compiler.Semantics.AType").not_nil!.Fields.First(->(f : FieldDefinition) { f.Name == "Clr" })
      proxy_il.InsertBefore(first_proxy, Instruction.Create(OpCodes::Call, supported))
      proxy_il.InsertBefore(first_proxy, Instruction.Create(OpCodes::Brtrue, first_proxy))
      proxy_il.InsertBefore(first_proxy, Instruction.Create(OpCodes::Ldarg_0))
      proxy_il.InsertBefore(first_proxy, Instruction.Create(OpCodes::Ldfld, type_field))
      proxy_il.InsertBefore(first_proxy, Instruction.Create(OpCodes::Ret))

      compiler = mod.GetType("Alice.Compiler.AliceCompiler").not_nil!
      emit = compiler.Methods.First(->(m : MethodDefinition) { m.Name == "Emit" })
      options_ctor = emit.Body.Instructions.First(->(i : Instruction) { i.OpCode == OpCodes::Newobj && i.Operand.as(MethodReference).DeclaringType.Name == "CSharpCompilationOptions" })
      concurrent = mod.ImportReference(typeof(Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions).GetMethod("WithConcurrentBuild", [typeof(Bool)]).not_nil!)
      emit_il = emit.Body.GetILProcessor
      flag = Instruction.Create(OpCodes::Ldc_I4_0)
      emit_il.InsertAfter(options_ctor, flag)
      emit_il.InsertAfter(flag, Instruction.Create(OpCodes::Callvirt, concurrent))
      load = compiler.Methods.First(->(m : MethodDefinition) { m.Name == "Load" })
      context_ctor = load.Body.Instructions.First(->(i : Instruction) { i.OpCode == OpCodes::Newobj && i.Operand.as(MethodReference).DeclaringType.Name == "AssemblyLoadContext" })
      context_ctor.Previous.OpCode = OpCodes::Ldc_I4_0

      # Observe the precise bodies consumed by the C# printer, including specializations.
      emitter = mod.GetType("Alice.Compiler.Backend.Emitter").not_nil!
      callback = FieldDefinition.new("ObserveMir", Mono.Cecil.FieldAttributes::Public, mod.ImportReference(typeof(Action(IReadOnlyList(MStmt)))))
      emitter.Fields.Add(callback)
      print_method = emitter.Methods.First(->(m : MethodDefinition) { m.Name == "Print" })
      first_print = print_method.Body.Instructions[0]
      print_il = print_method.Body.GetILProcessor
      invoke = mod.ImportReference(typeof(Action(IReadOnlyList(MStmt))).GetMethod("Invoke").not_nil!)
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Ldarg_0))
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Ldfld, callback))
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Brfalse, first_print))
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Ldarg_0))
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Ldfld, callback))
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Ldarg_1))
      print_il.InsertBefore(first_print, Instruction.Create(OpCodes::Callvirt, invoke))
      runtime_ref = mod.AssemblyReferences.First(->(r : AssemblyNameReference) { r.Name == "System.Runtime" })
      Normalize(callback.FieldType, runtime_ref)
      Normalize(invoke.DeclaringType, runtime_ref)
      Normalize(supported.DeclaringType, runtime_ref)
      for imported in mod.GetTypeReferences()
        imported.Scope = runtime_ref if imported.Scope.Name == "System.Private.CoreLib"
      end
      mod.Attributes = mod.Attributes | ModuleAttributes::ILOnly
      mod.Architecture = TargetArchitecture::I386
      assembly.Write(output)
    end
    puts "Prepared release compiler for browser execution"
  end
end
PrepareCompiler.main(ARGV[0], ARGV[1])
