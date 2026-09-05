nonisolated enum FormatSelection {
    static func resolve(optionHeld: Bool) -> OutputFormat {
        optionHeld ? .png : .jpeg
    }
}
