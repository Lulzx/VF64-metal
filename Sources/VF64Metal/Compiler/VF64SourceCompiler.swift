import Foundation

enum VF64CompilerError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

private enum VF64Token: Equatable {
    case identifier(String)
    case number(String)
    case symbol(Character)
    case arrow
    case eof
}

private indirect enum VF64Expression {
    case variable(String)
    case literal(Double)
    case binary(Character, VF64Expression, VF64Expression)
    case call(String, [VF64Expression])
    case negate(VF64Expression)
}

private enum VF64SourceType: String, Equatable, CustomStringConvertible {
    case double, bool, uint32, uint64, int32, int64, float, half

    var description: String { rawValue }

    static func parse(_ name: String) throws -> VF64SourceType {
        guard let type = VF64SourceType(rawValue: name) else {
            throw VF64CompilerError.invalid("unknown source type '\(name)'")
        }
        return type
    }
}

private struct VF64TypedRegister {
    let register: UInt32
    let type: VF64SourceType
}

private struct VF64SourceKernel {
    let name: String
    let parameters: [(String, VF64SourceType)]
    let bindings: [(String, VF64SourceType?, VF64Expression)]
    let returnType: VF64SourceType
    let result: VF64Expression
}

private func tokenizeVF64Source(_ source: String) throws -> [VF64Token] {
    let characters = Array(source)
    var tokens: [VF64Token] = []
    var index = 0
    while index < characters.count {
        let character = characters[index]
        if character.isWhitespace {
            index += 1
        } else if character == "/" && index + 1 < characters.count &&
                    characters[index + 1] == "/" {
            index += 2
            while index < characters.count && characters[index] != "\n" {
                index += 1
            }
        } else if character.isLetter || character == "_" {
            let start = index
            index += 1
            while index < characters.count &&
                    (characters[index].isLetter || characters[index].isNumber ||
                     characters[index] == "_") {
                index += 1
            }
            tokens.append(.identifier(String(characters[start..<index])))
        } else if character.isNumber || character == "." {
            let start = index
            index += 1
            while index < characters.count &&
                    (characters[index].isNumber || characters[index] == "." ||
                     characters[index] == "e" || characters[index] == "E" ||
                     characters[index] == "+" || characters[index] == "-") {
                if (characters[index] == "+" || characters[index] == "-") &&
                    characters[index - 1] != "e" && characters[index - 1] != "E" {
                    break
                }
                index += 1
            }
            tokens.append(.number(String(characters[start..<index])))
        } else if character == "-" && index + 1 < characters.count &&
                    characters[index + 1] == ">" {
            tokens.append(.arrow)
            index += 2
        } else if "(),{}:;=+-*/".contains(character) {
            tokens.append(.symbol(character))
            index += 1
        } else {
            throw VF64CompilerError.invalid("unexpected source character '\(character)'")
        }
    }
    tokens.append(.eof)
    return tokens
}

private struct VF64SourceParser {
    let tokens: [VF64Token]
    var index = 0

    mutating func take() -> VF64Token {
        defer { index += 1 }
        return tokens[index]
    }

    mutating func expectIdentifier(_ expected: String? = nil) throws -> String {
        guard case .identifier(let value) = take(), expected == nil || value == expected else {
            throw VF64CompilerError.invalid(
                expected.map { "expected '\($0)'" } ?? "expected identifier"
            )
        }
        return value
    }

    mutating func expect(_ expected: VF64Token) throws {
        guard take() == expected else {
            throw VF64CompilerError.invalid("expected \(expected)")
        }
    }

    mutating func parse() throws -> VF64SourceKernel {
        _ = try expectIdentifier("kernel")
        let name = try expectIdentifier()
        try expect(.symbol("("))
        var parameters: [(String, VF64SourceType)] = []
        if tokens[index] != .symbol(")") {
            while true {
                let type = try VF64SourceType.parse(expectIdentifier())
                parameters.append((try expectIdentifier(), type))
                if tokens[index] != .symbol(",") { break }
                _ = take()
            }
        }
        try expect(.symbol(")"))
        try expect(.arrow)
        let returnType = try VF64SourceType.parse(expectIdentifier())
        try expect(.symbol("{"))
        var bindings: [(String, VF64SourceType?, VF64Expression)] = []
        while tokens[index] == .identifier("let") {
            _ = take()
            let binding = try expectIdentifier()
            var declaredType: VF64SourceType?
            if tokens[index] == .symbol(":") {
                _ = take()
                declaredType = try VF64SourceType.parse(expectIdentifier())
            }
            try expect(.symbol("="))
            let expression = try parseExpression()
            try expect(.symbol(";"))
            bindings.append((binding, declaredType, expression))
        }
        _ = try expectIdentifier("return")
        let result = try parseExpression()
        try expect(.symbol(";"))
        try expect(.symbol("}"))
        try expect(.eof)
        guard Set(parameters.map(\.0)).count == parameters.count else {
            throw VF64CompilerError.invalid("duplicate kernel parameter")
        }
        return VF64SourceKernel(
            name: name, parameters: parameters, bindings: bindings,
            returnType: returnType, result: result
        )
    }

    mutating func parseExpression(minimumPrecedence: Int = 0) throws -> VF64Expression {
        var left = try parsePrimary()
        while case .symbol(let operation) = tokens[index], "+-*/".contains(operation) {
            let precedence = operation == "+" || operation == "-" ? 1 : 2
            if precedence < minimumPrecedence { break }
            _ = take()
            let right = try parseExpression(minimumPrecedence: precedence + 1)
            left = .binary(operation, left, right)
        }
        return left
    }

    mutating func parsePrimary() throws -> VF64Expression {
        switch take() {
        case .number(let text):
            guard let value = Double(text) else {
                throw VF64CompilerError.invalid("invalid double literal '\(text)'")
            }
            return .literal(value)
        case .identifier(let name):
            guard tokens[index] == .symbol("(") else { return .variable(name) }
            _ = take()
            var arguments: [VF64Expression] = []
            if tokens[index] != .symbol(")") {
                while true {
                    arguments.append(try parseExpression())
                    if tokens[index] != .symbol(",") { break }
                    _ = take()
                }
            }
            try expect(.symbol(")"))
            return .call(name, arguments)
        case .symbol("-"):
            return .negate(try parsePrimary())
        case .symbol("("):
            let expression = try parseExpression()
            try expect(.symbol(")"))
            return expression
        default:
            throw VF64CompilerError.invalid("expected double expression")
        }
    }
}

struct VF64SourceCompiler {
    let mode: VF64PrecisionMode
    let laneCount: Int
    private(set) var instructions: [VF64Instruction] = []
    private var variables: [String: VF64TypedRegister] = [:]
    private var nextRegister: UInt32 = 0

    init(mode: VF64PrecisionMode, laneCount: Int) {
        self.mode = mode
        self.laneCount = laneCount
    }

    mutating func compile(_ source: String) throws -> VF64Program {
        guard laneCount > 0 else {
            throw VF64CompilerError.invalid("lane count must be positive")
        }
        var parser = VF64SourceParser(tokens: try tokenizeVF64Source(source))
        let kernel = try parser.parse()
        guard kernel.parameters.count <= VF64Program.maximumRegisters else {
            throw VF64CompilerError.invalid("too many kernel parameters")
        }
        for (slot, parameter) in kernel.parameters.enumerated() {
            let register = try allocateRegister()
            variables[parameter.0] = VF64TypedRegister(
                register: register, type: parameter.1
            )
            instructions.append(VF64Instruction(
                opcode: .load, destination: register, immediate: UInt64(slot)
            ))
        }
        for (name, declaredType, expression) in kernel.bindings {
            guard variables[name] == nil else {
                throw VF64CompilerError.invalid("duplicate binding '\(name)'")
            }
            let value = try lower(expression)
            if let declaredType, declaredType != value.type {
                throw VF64CompilerError.invalid(
                    "binding '\(name)' declares \(declaredType) but expression is \(value.type)"
                )
            }
            variables[name] = value
        }
        let result = try lower(kernel.result)
        guard result.type == kernel.returnType else {
            throw VF64CompilerError.invalid(
                "kernel returns \(kernel.returnType) but expression is \(result.type)"
            )
        }
        instructions.append(VF64Instruction(
            opcode: .store, source0: result.register, immediate: 0
        ))
        instructions.append(VF64Instruction(opcode: .halt))
        let allocated = try allocatePhysicalRegisters(instructions)
        let program = VF64Program(
            registerCount: allocated.registerCount,
            inputSlots: kernel.parameters.count, outputSlots: 1,
            laneCount: laneCount, instructions: allocated.instructions
        )
        try program.validate()
        return program
    }

    private mutating func allocateRegister() throws -> UInt32 {
        guard nextRegister < 4096 else {
            throw VF64CompilerError.invalid("kernel has too many virtual values")
        }
        defer { nextRegister += 1 }
        return nextRegister
    }

    private func sourceRegisters(_ instruction: VF64Instruction) -> [UInt32] {
        switch instruction.opcode {
        case .store, .move, .roundToInt,
             .ui32ToF64, .ui64ToF64, .i32ToF64, .i64ToF64,
             .f64ToUi32, .f64ToUi64, .f64ToI32, .f64ToI64,
             .f64ToF32, .f64ToF16, .f32ToF64, .f16ToF64:
            return [instruction.source0]
        case .select:
            return [instruction.source0, instruction.source1, instruction.source2]
        case .sqrt:
            return [instruction.source0]
        case .fma:
            return [instruction.source0, instruction.source1, instruction.source2]
        case .add, .sub, .mul, .div, .remainder,
             .eq, .le, .lt, .eqSignaling, .leQuiet, .ltQuiet:
            return [instruction.source0, instruction.source1]
        case .nop, .halt, .load, .constant, .flagsClear, .flagsGet, .laneU64:
            return []
        }
    }

    private func hasDestination(_ opcode: VF64Opcode) -> Bool {
        ![VF64Opcode.nop, .halt, .store, .flagsClear].contains(opcode)
    }

    private func allocatePhysicalRegisters(
        _ virtual: [VF64Instruction]
    ) throws -> (instructions: [VF64Instruction], registerCount: Int) {
        var lastUse: [UInt32: Int] = [:]
        for (index, instruction) in virtual.enumerated() {
            for source in sourceRegisters(instruction) { lastUse[source] = index }
        }
        var mapping: [UInt32: UInt32] = [:]
        var free = Set((0..<VF64Program.maximumRegisters).map(UInt32.init))
        var maximumPhysical: UInt32 = 0
        var rewritten: [VF64Instruction] = []
        rewritten.reserveCapacity(virtual.count)

        for (index, original) in virtual.enumerated() {
            var instruction = original
            let sources = sourceRegisters(original)
            let physicalSources = try sources.map { source -> UInt32 in
                guard let physical = mapping[source] else {
                    throw VF64CompilerError.invalid(
                        "internal register allocator read undefined value \(source)"
                    )
                }
                return physical
            }
            switch original.opcode {
            case .store, .move, .roundToInt,
                 .ui32ToF64, .ui64ToF64, .i32ToF64, .i64ToF64,
                 .f64ToUi32, .f64ToUi64, .f64ToI32, .f64ToI64,
                 .f64ToF32, .f64ToF16, .f32ToF64, .f16ToF64, .sqrt:
                instruction.source0 = physicalSources[0]
            case .add, .sub, .mul, .div, .remainder,
                 .eq, .le, .lt, .eqSignaling, .leQuiet, .ltQuiet:
                instruction.source0 = physicalSources[0]
                instruction.source1 = physicalSources[1]
            case .fma, .select:
                instruction.source0 = physicalSources[0]
                instruction.source1 = physicalSources[1]
                instruction.source2 = physicalSources[2]
            case .nop, .halt, .load, .constant, .flagsClear, .flagsGet, .laneU64:
                break
            }
            for source in Set(sources) where lastUse[source] == index {
                if let physical = mapping.removeValue(forKey: source) {
                    free.insert(physical)
                }
            }
            if hasDestination(original.opcode) {
                guard let physical = free.min() else {
                    throw VF64CompilerError.invalid(
                        "kernel requires more than \(VF64Program.maximumRegisters) simultaneously live VF64 registers"
                    )
                }
                free.remove(physical)
                mapping[original.destination] = physical
                instruction.destination = physical
                maximumPhysical = max(maximumPhysical, physical)
                if lastUse[original.destination] == nil {
                    mapping.removeValue(forKey: original.destination)
                    free.insert(physical)
                }
            }
            rewritten.append(instruction)
        }
        return (rewritten, Int(maximumPhysical) + 1)
    }

    private mutating func lower(
        _ expression: VF64Expression
    ) throws -> VF64TypedRegister {
        switch expression {
        case .variable(let name):
            guard let value = variables[name] else {
                throw VF64CompilerError.invalid("unknown source value '\(name)'")
            }
            return value
        case .literal(let value):
            let destination = try allocateRegister()
            instructions.append(VF64Instruction(
                opcode: .constant, destination: destination,
                immediate: value.bitPattern
            ))
            return VF64TypedRegister(register: destination, type: .double)
        case .negate(let value):
            let operand = try lower(value)
            try require([operand], types: [.double], function: "unary minus")
            let zero = try lower(.literal(-0.0))
            return VF64TypedRegister(
                register: try emit(.sub, [zero.register, operand.register]),
                type: .double
            )
        case .binary(let operation, let left, let right):
            let lhs = try lower(left)
            let rhs = try lower(right)
            try require([lhs, rhs], types: [.double, .double], function: "\(operation)")
            let opcode: VF64Opcode
            switch operation {
            case "+": opcode = .add
            case "-": opcode = .sub
            case "*": opcode = .mul
            case "/": opcode = .div
            default: throw VF64CompilerError.invalid("unsupported binary operation")
            }
            return VF64TypedRegister(
                register: try emit(opcode, [lhs.register, rhs.register]),
                type: .double
            )
        case .call(let name, let arguments):
            let values = try arguments.map { try lower($0) }
            return try lowerCall(name, values)
        }
    }

    private func require(
        _ values: [VF64TypedRegister], types: [VF64SourceType], function: String
    ) throws {
        guard values.count == types.count else {
            throw VF64CompilerError.invalid(
                "'\(function)' expects \(types.count) arguments"
            )
        }
        for (index, pair) in zip(values, types).enumerated() where pair.0.type != pair.1 {
            throw VF64CompilerError.invalid(
                "'\(function)' argument \(index + 1) must be \(pair.1), got \(pair.0.type)"
            )
        }
    }

    private mutating func lowerCall(
        _ name: String, _ values: [VF64TypedRegister]
    ) throws -> VF64TypedRegister {
        let doubleUnary: [String: VF64Opcode] = [
            "sqrt": .sqrt, "round": .roundToInt,
        ]
        let doubleBinary: [String: VF64Opcode] = ["remainder": .remainder]
        let comparisons: [String: VF64Opcode] = [
            "eq": .eq, "le": .le, "lt": .lt,
            "eq_signaling": .eqSignaling, "le_quiet": .leQuiet,
            "lt_quiet": .ltQuiet,
        ]
        let conversions: [String: (VF64Opcode, VF64SourceType, VF64SourceType)] = [
            "uint32_to_double": (.ui32ToF64, .uint32, .double),
            "uint64_to_double": (.ui64ToF64, .uint64, .double),
            "int32_to_double": (.i32ToF64, .int32, .double),
            "int64_to_double": (.i64ToF64, .int64, .double),
            "double_to_uint32": (.f64ToUi32, .double, .uint32),
            "double_to_uint64": (.f64ToUi64, .double, .uint64),
            "double_to_int32": (.f64ToI32, .double, .int32),
            "double_to_int64": (.f64ToI64, .double, .int64),
            "double_to_float": (.f64ToF32, .double, .float),
            "double_to_half": (.f64ToF16, .double, .half),
            "float_to_double": (.f32ToF64, .float, .double),
            "half_to_double": (.f16ToF64, .half, .double),
        ]
        if let opcode = doubleUnary[name] {
            try require(values, types: [.double], function: name)
            return VF64TypedRegister(
                register: try emit(opcode, values.map(\.register)), type: .double
            )
        }
        if let opcode = doubleBinary[name] {
            try require(values, types: [.double, .double], function: name)
            return VF64TypedRegister(
                register: try emit(opcode, values.map(\.register)), type: .double
            )
        }
        if name == "fma" {
            try require(values, types: [.double, .double, .double], function: name)
            return VF64TypedRegister(
                register: try emit(.fma, values.map(\.register)), type: .double
            )
        }
        if let opcode = comparisons[name] {
            try require(values, types: [.double, .double], function: name)
            return VF64TypedRegister(
                register: try emit(opcode, values.map(\.register)), type: .bool
            )
        }
        if name == "select" {
            guard values.count == 3 else {
                throw VF64CompilerError.invalid("'select' expects 3 arguments")
            }
            guard values[0].type == .bool else {
                throw VF64CompilerError.invalid("'select' condition must be bool")
            }
            guard values[1].type == values[2].type else {
                throw VF64CompilerError.invalid(
                    "'select' branches must have the same type"
                )
            }
            return VF64TypedRegister(
                register: try emit(.select, values.map(\.register)),
                type: values[1].type
            )
        }
        if let conversion = conversions[name] {
            try require(values, types: [conversion.1], function: name)
            return VF64TypedRegister(
                register: try emit(conversion.0, values.map(\.register)),
                type: conversion.2
            )
        }
        throw VF64CompilerError.invalid("unknown source function '\(name)'")
    }

    private mutating func emit(
        _ opcode: VF64Opcode, _ sources: [UInt32]
    ) throws -> UInt32 {
        let destination = try allocateRegister()
        let modeSpecific = [.add, .sub, .mul, .div, .sqrt, .fma].contains(opcode)
        instructions.append(VF64Instruction(
            opcode: opcode, destination: destination,
            source0: sources.indices.contains(0) ? sources[0] : 0,
            source1: sources.indices.contains(1) ? sources[1] : 0,
            source2: sources.indices.contains(2) ? sources[2] : 0,
            control: modeSpecific ? VF64Instruction.control(mode: mode) : 0
        ))
        return destination
    }
}

func compileVF64SourceFile(
    sourcePath: String, outputPath: String,
    mode: VF64PrecisionMode, laneCount: Int
) throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: sourcePath), encoding: .utf8
    )
    var compiler = VF64SourceCompiler(mode: mode, laneCount: laneCount)
    let program = try compiler.compile(source)
    try encodeLittleEndian(program.words).write(
        to: URL(fileURLWithPath: outputPath), options: .atomic
    )
}
