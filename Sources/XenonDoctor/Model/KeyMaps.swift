import Foundation

/// What each control on the pad does in each game, for the Controller map tab. One entry
/// per control, in the order the map lists them; a nil action draws faded, so the grid
/// stays complete and a control that does nothing is visibly nothing.
enum KeyMaps {
    /// The pad's controls, by the ids the tester and the HID parser use.
    static let controls: [String] = [
        "L2", "L1", "up", "down", "left", "right", "leftStick", "L3", "share", "touchpad",
        "R2", "R1", "triangle", "circle", "cross", "square", "rightStick", "R3", "options", "ps",
    ]

    static func name(_ control: String) -> String {
        switch control {
        case "up", "down", "left", "right": return "D-pad " + control
        case "leftStick": return "Left stick"
        case "rightStick": return "Right stick"
        case "share": return "Share"
        case "options": return "Options"
        case "touchpad": return "Touchpad"
        case "ps": return "PS"
        case "cross", "circle", "square", "triangle": return control.prefix(1).uppercased() + control.dropFirst()
        default: return control
        }
    }

    /// The controls on the left half of the pad; the rest sit on the right.
    static func isLeft(_ control: String) -> Bool {
        ["L2", "L1", "up", "down", "left", "right", "leftStick", "L3", "share", "touchpad"].contains(control)
    }

    static func actions(for game: Game) -> [String: String] {
        switch game.link {
        case .game: return stardew
        case .factorio: return factorio
        case .undertale: return undertale
        default: return [:]
        }
    }

    /// Chords that need two or three controls at once; listed under the map.
    static func chords(for game: Game) -> [(String, String)] {
        switch game.link {
        case .factorio:
            return [
                ("R2 + Cross", "place a ghost"), ("R2 + Square", "copy entity settings"), ("R2 + Options", "pause"),
                ("L2 + R2 + left", "copy"), ("L2 + R2 + right", "paste"), ("L2 + Options", "search"),
                ("L2 + R2 + Options", "blueprint library"), ("L2 + R2 + Triangle", "undo"), ("L2 + R2 + Square", "redo"),
                ("R2 + D-pad up or down", "zoom"), ("L2 + D-pad up or down", "cycle blueprints"),
            ]
        default: return []
        }
    }

    /// Stardew's own gamepad layout (Xbox letters translated to this pad).
    static let stardew: [String: String] = [
        "leftStick": "walk, push to run", "up": "walk", "down": "walk", "left": "walk", "right": "walk",
        "rightStick": "move the cursor", "R3": "chat (click), emotes (hold)",
        "cross": "check, do action", "square": "use tool", "circle": "open menu, back", "triangle": "crafting menu",
        "L1": "shift toolbar left", "R1": "shift toolbar right", "L2": "previous item", "R2": "next item",
        "options": "open menu", "share": "journal",
    ]

    /// Factorio's stock controller layout plus the chords Xenon Doctor adds.
    static let factorio: [String: String] = [
        "leftStick": "move", "rightStick": "aim the cursor", "R3": "free cursor on and off",
        "up": "show info, rail layer", "down": "pick up items", "left": "rotate back", "right": "rotate",
        "cross": "build, open, confirm", "square": "mine, use item", "circle": "clear cursor, pipette, close", "triangle": "character screen",
        "L1": "quick panel", "R1": "shoot", "L2": "held: chords below", "R2": "held: alternate action",
        "options": "menu", "share": "map",
    ]

    /// The keys Xenon Doctor presses for Undertale.
    static let undertale: [String: String] = [
        "leftStick": "move (arrows)", "up": "move", "down": "move", "left": "move", "right": "move",
        "cross": "confirm (Z)", "circle": "cancel, hold to skip text (X)", "square": "cancel (X)", "triangle": "menu (C)",
        "touchpad": "menu (C)", "options": "Enter", "share": "fullscreen (F4)", "R2": "hold to skip text (X)",
    ]
}
