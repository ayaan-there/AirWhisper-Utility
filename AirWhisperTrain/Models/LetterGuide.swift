import Foundation

enum LetterGuide {
    static let alphabet: [String] = (65...90).map { String(UnicodeScalar($0)) }

    static func instruction(for letter: String) -> String {
        instructions[letter] ?? "Trace the capital letter \"\(letter)\" in one smooth motion."
    }

    private static let instructions: [String: String] = [
        "A": "Draw two angled lines meeting at the top, then a horizontal crossbar.",
        "B": "Draw a vertical line down, then two rounded bumps on the right.",
        "C": "Open a rounded curve to the right.",
        "D": "Vertical line down, then a large rounded belly on the right.",
        "E": "Vertical line down, then three horizontal arms to the right.",
        "F": "Vertical line down, then two horizontal arms to the right.",
        "G": "Open curve to the right, then a small horizontal bar into the middle.",
        "H": "Two vertical lines, then a horizontal bar joining them in the middle.",
        "I": "A straight vertical line, with small top and bottom bars.",
        "J": "Vertical line that curves into a hook at the bottom, with a top bar.",
        "K": "Vertical line, then two diagonal strokes meeting it in the middle.",
        "L": "Vertical line down, then a horizontal foot to the right.",
        "M": "Two vertical sides joined by two diagonals meeting at the top.",
        "N": "Two vertical sides joined by a diagonal from top-left to bottom-right.",
        "O": "A smooth, complete oval or circle.",
        "P": "Vertical line down, then a rounded bump at the top on the right.",
        "Q": "An oval, then a small tail stroke out the bottom-right.",
        "R": "Vertical line, rounded bump at the top right, then a slanted leg.",
        "S": "A single curved 'S' shape from top-right to bottom-left.",
        "T": "Horizontal bar across the top, then a vertical line down the middle.",
        "U": "A rounded cup shape open at the top.",
        "V": "Two straight lines meeting in a point at the bottom.",
        "W": "Four angled strokes forming two touching points.",
        "X": "Two diagonal lines crossing in the middle.",
        "Y": "Two diagonals meeting at the center, then a short vertical tail.",
        "Z": "Top horizontal bar, diagonal down to the left, then bottom horizontal bar."
    ]
}
