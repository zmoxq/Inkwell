// Add these new cases to the existing FormatCommand enum in DataModels.swift:
//
// enum FormatCommand: String {
//     case bold, italic, strikethrough
//     case inlineCode          // ← NEW
//     case heading1, heading2, heading3, heading4  // ← heading4 NEW
//     case paragraph           // ← NEW
//     case bulletList, orderedList, taskList
//     case codeBlock, blockquote
//     case horizontalRule
//     case link, image
//     case table               // ← NEW
//     case increaseIndent, decreaseIndent  // ← NEW
// }
//
// Note: The EditorCoordinator now uses String instead of FormatCommand.rawValue
// for flexibility, so this enum is mainly for reference. The JS editor accepts
// any of these command strings via execFormat().
