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

private struct VF64SourceKernel {
    let name: String
    let parameters: [String]
    let bindings: [(String, VF64Expression)]
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
        var parameters: [String] = []
        if tokens[index] != .symbol(")") {
            while true {
                _ = try expectIdentifier("double")
                parameters.append(try expectIdentifier())
                if tokens[index] != .symbol(",") { break }
                _ = take()
            }
        }
        try expect(.symbol(")"))
        try expect(.arrow)
        _ = try expectIdentifier("double")
        try expect(.symbol("{"))
        var bindings: [(String, VF64Expression)] = []
        while tokens[index] == .identifier("let") {
            _ = take()
            let binding = try expectIdentifier()
            if tokens[index] == .symbol(":") {
                _ = take()
                _ = try expectIdentifier("double")
            }
            try expect(.symbol("="))
            let expression = try parseExpression()
            try expect(.symbol(";"))
            bindings.append((binding, expression))
        }
        _ = try expectIdentifier("return")
        let result = try parseExpression()
        try expect(.symbol(";"))
        try expect(.symbol("}"))
        try expect(.eof)
        guard Set(parameters).count == parameters.count else {
            throw VF64CompilerError.invalid("duplicate kernel parameter")
        }
        return VF64SourceKernel(
            name: name, parameters: parameters, bindings: bindings,
            result: result
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
    private var variables: [String: UInt32] = [:]
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
        for (slot, name) in kernel.parameters.enumerated() {
            let register = try allocateRegister()
            variables[name] = register
            instructions.append(VF64Instruction(
                opcode: .load, destination: register, immediate: UInt64(slot)
            ))
        }
        for (name, expression) in kernel.bindings {
            guard variables[name] == nil else {
                throw VF64CompilerError.invalid("duplicate binding '\(name)'")
            }
            variables[name] = try lower(expression)
        }
        let result = try lower(kernel.result)
        instructions.append(VF64Instruction(
            opcode: .store, source0: result, immediate: 0
        ))
        instructions.append(VF64Instruction(opcode: .halt))
        let program = VF64Program(
            registerCount: Int(nextRegister), inputSlots: kernel.parameters.count,
            outputSlots: 1, laneCount: laneCount, instructions: instructions
        )
        try program.validate()
        return program
    }

    private mutating func allocateRegister() throws -> UInt32 {
        guard nextRegister < VF64Program.maximumRegisters else {
            throw VF64CompilerError.invalid("kernel requires more than 32 VF64 registers")
        }
        defer { nextRegister += 1 }
        return nextRegister
    }

    private mutating func lower(_ expression: VF64Expression) throws -> UInt32 {
        switch expression {
        case .variable(let name):
            guard let register = variables[name] else {
                throw VF64CompilerError.invalid("unknown double value '\(name)'")
            }
            return register
        case .literal(let value):
            let destination = try allocateRegister()
            instructions.append(VF64Instruction(
                opcode: .constant, destination: destination,
                immediate: value.bitPattern
            ))
            return destination
        case .negate(let value):
            let zero = try lower(.literal(-0.0))
            let operand = try lower(value)
            return try emit(.sub, [zero, operand])
        case .binary(let operation, let left, let right):
            let lhs = try lower(left)
            let rhs = try lower(right)
            let opcode: VF64Opcode
            switch operation {
            case "+": opcode = .add
            case "-": opcode = .sub
            case "*": opcode = .mul
            case "/": opcode = .div
            default: throw VF64CompilerError.invalid("unsupported binary operation")
            }
            return try emit(opcode, [lhs, rhs])
        case .call(let name, let arguments):
            let registers = try arguments.map { try lower($0) }
            let opcode: VF64Opcode
            let arity: Int
            switch name {
            case "sqrt": opcode = .sqrt; arity = 1
            case "fma": opcode = .fma; arity = 3
            case "remainder": opcode = .remainder; arity = 2
            case "round": opcode = .roundToInt; arity = 1
            case "eq": opcode = .eq; arity = 2
            case "le": opcode = .le; arity = 2
            case "lt": opcode = .lt; arity = 2
            case "eq_signaling": opcode = .eqSignaling; arity = 2
            case "le_quiet": opcode = .leQuiet; arity = 2
            case "lt_quiet": opcode = .ltQuiet; arity = 2
            case "select": opcode = .select; arity = 3
            default: throw VF64CompilerError.invalid("unknown double function '\(name)'")
            }
            guard registers.count == arity else {
                throw VF64CompilerError.invalid("'\(name)' expects \(arity) arguments")
            }
            return try emit(opcode, registers)
        }
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
