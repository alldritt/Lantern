import Lantern

let interpreter = Interpreter()
let output = CapturedOutputHandler()
interpreter.outputHandler = output

print("Lantern REPL — Swift Interpreter")
print("Type Swift expressions or :quit to exit.\n")

while true {
    print("lantern> ", terminator: "")
    guard let line = readLine() else { break }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    if trimmed == ":quit" || trimmed == ":q" { break }

    output.clear()
    let result = interpreter.run(source: trimmed)

    // Show any captured print output
    for text in output.printOutput {
        print(text, terminator: "")
    }

    switch result {
    case .success(let value):
        if value != .void {
            print("= \(value.debugSummary)")
        }
    case .failure(let error):
        print("Error: \(error)")
    }
}
