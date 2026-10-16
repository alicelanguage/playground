using System.Collections
using System.Reflection
using System.Text.Json
using Alice.Compiler.Syntax
using Alice.Compiler.Semantics
using Alice.Compiler.Mir

namespace Alice.Playground
  module TreeDump
    def self.Print(root : Object) : String
      output = StringBuilder.new
      Visit(root, "", 0, output)
      output.ToString
    end

    def self.Visit(value : Object?, label : String, depth : Int32, output : StringBuilder)
      return if output.Length > 524288 || depth > 80
      output.Append("  " * depth).Append(label)
      if value.nil?
        output.AppendLine("nil")
        return
      end
      item = value.not_nil!
      if item.is_a?(AType)
        output.AppendLine(item.as(AType).Cs)
        return
      end
      if item.is_a?(LocalSym)
        local = item.as(LocalSym)
        output.AppendLine("local #{local.Name} : #{local.Type.Cs}")
        return
      end
      if item.is_a?(MethodSym)
        method = item.as(MethodSym)
        output.AppendLine("method #{method.Owner.Name}.#{method.Name} : #{method.Ret.Cs}")
        return
      end
      if item.is_a?(TypeSym)
        output.AppendLine("type " + item.as(TypeSym).Name)
        return
      end
      if item.is_a?(FieldSym)
        symbol_field = item.as(FieldSym)
        output.AppendLine("field #{symbol_field.Name} : #{symbol_field.Type.Cs}")
        return
      end
      if item.is_a?(String)
        output.AppendLine(JsonSerializer.Serialize<String>(item.as(String)))
        return
      end
      if item.is_a?(IEnumerable)
        output.AppendLine("[")
        for child in item.as(IEnumerable)
          Visit(child, "", depth + 1, output)
        end
        output.Append("  " * depth).AppendLine("]")
        return
      end
      type = item.GetType
      if type.IsPrimitive || type.IsEnum || item.is_a?(Decimal)
        output.AppendLine(item.ToString)
        return
      end
      output.Append(type.Name)
      if item.is_a?(Expr)
        expr = item.as(Expr)
        output.Append(" : #{expr.Type.Cs} [#{expr.Res}]")
      end
      if item.is_a?(Node)
        node = item.as(Node)
        output.Append(" @#{node.Line}:#{node.Col}")
      end
      if item.is_a?(MStmt)
        output.Append(" @#{item.as(MStmt).Line}")
      end
      output.AppendLine
      for field in type.GetFields(BindingFlags::Instance | BindingFlags::Public).OrderBy(->(f : FieldInfo) { f.Name })
        next if ["Type", "Line", "Col", "Res", "SourceText", "Hoisted"].includes?(field.Name)
        child = field.GetValue(item)
        next if child.nil?
        next if child.is_a?(String) && child.as(String).Length == 0
        next if child.is_a?(ICollection) && child.as(ICollection).Count == 0
        Visit(child, field.Name + ": ", depth + 1, output)
      end
    end
  end
end
