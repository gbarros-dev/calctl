import Foundation

let cli = CLI(arguments: Array(CommandLine.arguments.dropFirst()))
await cli.run()
