using System.Reflection
using System.Reflection.Emit
using System.Reflection.Metadata
using System.Reflection.Metadata.Ecma335
using System.Reflection.PortableExecutable

namespace Alice.Playground
  # Decode the actual PE emitted by Roslyn; offsets, branches, tokens and exception regions are retained.
  module IlDisassembler
    def self.Print(image : Array(UInt8)) : String
      output = StringBuilder.new
      ops = Dictionary(Int32, OpCode).new
      for field in typeof(OpCodes).GetFields(BindingFlags::Public | BindingFlags::Static)
        op = field.GetValue(nil).not_nil!.as(OpCode)
        ops[op.Value.as(Int32) & 65535] = op
      end
      using stream = MemoryStream.new(image)
        using pe = PEReader.new(stream)
          md = PEReaderExtensions.GetMetadataReader(pe)
          for handle in md.MethodDefinitions
            method = md.GetMethodDefinition(handle)
            next if method.RelativeVirtualAddress == 0
            owner = md.GetTypeDefinition(method.GetDeclaringType())
            output.AppendLine(".method #{md.GetString(owner.Name)}::#{md.GetString(method.Name)}")
            body = pe.GetMethodBody(method.RelativeVirtualAddress)
            output.AppendLine("  .maxstack #{body.MaxStack}")
            bytes = body.GetILBytes().not_nil!
            offset = 0
            while offset < bytes.Length
              start = offset
              key = bytes[offset].as(Int32)
              offset += 1
              if key == 254
                key = 65024 | bytes[offset].as(Int32)
                offset += 1
              end
              op = ops[key]
              operand = ""
              case op.OperandType
              when OperandType::InlineNone
              when OperandType::ShortInlineI
                operand = bytes[offset].as(SByte).ToString
                offset += 1
              when OperandType::ShortInlineVar
                operand = bytes[offset].ToString()
                offset += 1
              when OperandType::InlineVar
                operand = BitConverter.ToUInt16(bytes, offset).ToString
                offset += 2
              when OperandType::InlineI
                operand = BitConverter.ToInt32(bytes, offset).ToString
                offset += 4
              when OperandType::InlineI8
                operand = BitConverter.ToInt64(bytes, offset).ToString
                offset += 8
              when OperandType::ShortInlineR
                operand = BitConverter.ToSingle(bytes, offset).ToString(System.Globalization.CultureInfo::InvariantCulture)
                offset += 4
              when OperandType::InlineR
                operand = BitConverter.ToDouble(bytes, offset).ToString(System.Globalization.CultureInfo::InvariantCulture)
                offset += 8
              when OperandType::ShortInlineBrTarget
                operand = "IL_" + (offset + 1 + bytes[offset].as(SByte)).ToString("X4")
                offset += 1
              when OperandType::InlineBrTarget
                operand = "IL_" + (offset + 4 + BitConverter.ToInt32(bytes, offset)).ToString("X4")
                offset += 4
              when OperandType::InlineSwitch
                count = BitConverter.ToInt32(bytes, offset)
                offset += 4
                target_base = offset + count * 4
                targets = List(String).new
                for i in 0...count
                  targets.Add("IL_" + (target_base + BitConverter.ToInt32(bytes, offset)).ToString("X4"))
                  offset += 4
                end
                operand = "(" + String.Join(", ", targets) + ")"
              else
                token = BitConverter.ToInt32(bytes, offset)
                operand = TokenName(md, token)
                offset += 4
              end
              output.AppendLine("  IL_#{start.ToString("X4")}: #{op.Name} #{operand}")
            end
            for region in body.ExceptionRegions
              output.AppendLine("  .#{region.Kind} try IL_#{region.TryOffset.ToString("X4")}..IL_#{(region.TryOffset + region.TryLength).ToString("X4")} handler IL_#{region.HandlerOffset.ToString("X4")}")
            end
            output.AppendLine
          end
        end
      end
      output.ToString
    end

    def self.TokenName(md : MetadataReader, token : Int32) : String
      if (token & -16777216) == 1879048192
        return System.Text.Json.JsonSerializer.Serialize<String>(md.GetUserString(MetadataTokens.UserStringHandle(token & 16777215)))
      end
      handle = MetadataTokens.EntityHandle(token)
      case handle.Kind
      when HandleKind::MethodDefinition
        method = md.GetMethodDefinition(handle.as(MethodDefinitionHandle))
        owner = md.GetTypeDefinition(method.GetDeclaringType())
        md.GetString(owner.Name) + "::" + md.GetString(method.Name)
      when HandleKind::MemberReference
        member = md.GetMemberReference(handle.as(MemberReferenceHandle))
        TokenName(md, MetadataTokens.GetToken(member.Parent)) + "::" + md.GetString(member.Name)
      when HandleKind::TypeReference
        type = md.GetTypeReference(handle.as(TypeReferenceHandle))
        md.GetString(type.Namespace) + "." + md.GetString(type.Name)
      when HandleKind::TypeDefinition
        definition = md.GetTypeDefinition(handle.as(TypeDefinitionHandle))
        md.GetString(definition.Namespace) + "." + md.GetString(definition.Name)
      when HandleKind::FieldDefinition
        md.GetString(md.GetFieldDefinition(handle.as(FieldDefinitionHandle)).Name)
      when HandleKind::MethodSpecification
        spec = md.GetMethodSpecification(handle.as(MethodSpecificationHandle))
        TokenName(md, MetadataTokens.GetToken(spec.Method)) + "<...>"
      else
        "0x" + token.ToString("X8")
      end
    end
  end
end
