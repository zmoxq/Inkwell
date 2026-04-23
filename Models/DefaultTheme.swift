import SwiftUI

// MARK: - Theme Info

struct ThemeInfo: Identifiable, Hashable {
    let id: String           // unique key, e.g. "inkwell", "github"
    let name: String         // display name
    let bgColor: Color       // preview swatch: background
    let textColor: Color     // preview swatch: text
    let accentColor: Color   // preview swatch: accent
    let css: String          // full CSS
    let isBuiltIn: Bool
    
    init(id: String, name: String, bg: String, text: String, accent: String, css: String, isBuiltIn: Bool = true) {
        self.id = id
        self.name = name
        self.bgColor = Color(hex: bg)
        self.textColor = Color(hex: text)
        self.accentColor = Color(hex: accent)
        self.css = css
        self.isBuiltIn = isBuiltIn
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ThemeInfo, rhs: ThemeInfo) -> Bool { lhs.id == rhs.id }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        switch h.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Built-in Themes

struct BuiltInThemes {
    
    static let all: [ThemeInfo] = [inkwell, github, nord, dracula, solarizedLight, newsprint, zmzt]
    
    // ── 1. Inkwell (warm paper) ──
    static let inkwell = ThemeInfo(
        id: "inkwell", name: "Inkwell",
        bg: "FDFBF7", text: "2C2C2A", accent: "C4603C",
        css: baseCSS + """
        :root {
            --bg-primary: #FDFBF7;
            --bg-secondary: #F8F5EE;
            --bg-code: #F3F0E8;
            --text-primary: #2C2C2A;
            --text-secondary: #5A5A56;
            --text-muted: #8A8A84;
            --accent: #C4603C;
            --accent-light: #E8DDD4;
            --border: #E5E0D5;
            --link: #3B7EA1;
            --selection: rgba(196, 96, 60, 0.15);
            --font-body: 'Georgia', 'Palatino', serif;
            --font-heading: -apple-system, 'Helvetica Neue', sans-serif;
            --font-mono: 'SF Mono', 'Menlo', 'Consolas', monospace;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #1E1E1C;
                --bg-secondary: #262624;
                --bg-code: #2C2C28;
                --text-primary: #D8D4CC;
                --text-secondary: #A8A49C;
                --text-muted: #787470;
                --accent: #D4734F;
                --accent-light: #3A3228;
                --border: #3A3836;
                --link: #5BA4C4;
                --selection: rgba(212, 115, 79, 0.2);
            }
        }
        """
    )
    
    // ── 2. GitHub ──
    static let github = ThemeInfo(
        id: "github", name: "GitHub",
        bg: "FFFFFF", text: "1F2328", accent: "0969DA",
        css: baseCSS + """
        :root {
            --bg-primary: #FFFFFF;
            --bg-secondary: #F6F8FA;
            --bg-code: #EFF1F3;
            --text-primary: #1F2328;
            --text-secondary: #656D76;
            --text-muted: #8B949E;
            --accent: #0969DA;
            --accent-light: #DDF4FF;
            --border: #D1D9E0;
            --link: #0969DA;
            --selection: rgba(9, 105, 218, 0.15);
            --font-body: -apple-system, 'Helvetica Neue', 'Segoe UI', sans-serif;
            --font-heading: -apple-system, 'Helvetica Neue', 'Segoe UI', sans-serif;
            --font-mono: 'SF Mono', 'Menlo', 'Consolas', monospace;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #0D1117;
                --bg-secondary: #161B22;
                --bg-code: #1C2128;
                --text-primary: #E6EDF3;
                --text-secondary: #8B949E;
                --text-muted: #6E7681;
                --accent: #58A6FF;
                --accent-light: #1C3049;
                --border: #30363D;
                --link: #58A6FF;
                --selection: rgba(88, 166, 255, 0.15);
            }
        }
        """
    )
    
    // ── 3. Nord ──
    static let nord = ThemeInfo(
        id: "nord", name: "Nord",
        bg: "ECEFF4", text: "2E3440", accent: "5E81AC",
        css: baseCSS + """
        :root {
            --bg-primary: #ECEFF4;
            --bg-secondary: #E5E9F0;
            --bg-code: #D8DEE9;
            --text-primary: #2E3440;
            --text-secondary: #4C566A;
            --text-muted: #7B8496;
            --accent: #5E81AC;
            --accent-light: #D8DEE9;
            --border: #D8DEE9;
            --link: #5E81AC;
            --selection: rgba(94, 129, 172, 0.2);
            --font-body: -apple-system, 'Helvetica Neue', sans-serif;
            --font-heading: -apple-system, 'Helvetica Neue', sans-serif;
            --font-mono: 'SF Mono', 'Menlo', monospace;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #2E3440;
                --bg-secondary: #3B4252;
                --bg-code: #434C5E;
                --text-primary: #ECEFF4;
                --text-secondary: #D8DEE9;
                --text-muted: #7B8496;
                --accent: #88C0D0;
                --accent-light: #3B4252;
                --border: #4C566A;
                --link: #88C0D0;
                --selection: rgba(136, 192, 208, 0.2);
            }
        }
        """
    )
    
    // ── 4. Dracula ──
    static let dracula = ThemeInfo(
        id: "dracula", name: "Dracula",
        bg: "282A36", text: "F8F8F2", accent: "BD93F9",
        css: baseCSS + """
        :root {
            --bg-primary: #282A36;
            --bg-secondary: #21222C;
            --bg-code: #1E1F29;
            --text-primary: #F8F8F2;
            --text-secondary: #BCC2CD;
            --text-muted: #6272A4;
            --accent: #BD93F9;
            --accent-light: #363848;
            --border: #44475A;
            --link: #8BE9FD;
            --selection: rgba(189, 147, 249, 0.2);
            --font-body: -apple-system, 'Helvetica Neue', sans-serif;
            --font-heading: -apple-system, 'Helvetica Neue', sans-serif;
            --font-mono: 'SF Mono', 'Fira Code', 'Menlo', monospace;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #282A36;
                --bg-secondary: #21222C;
                --bg-code: #1E1F29;
                --text-primary: #F8F8F2;
                --text-secondary: #BCC2CD;
                --text-muted: #6272A4;
                --accent: #BD93F9;
                --accent-light: #363848;
                --border: #44475A;
                --link: #8BE9FD;
                --selection: rgba(189, 147, 249, 0.2);
            }
        }
        """
    )
    
    // ── 5. Solarized Light ──
    static let solarizedLight = ThemeInfo(
        id: "solarized", name: "Solarized",
        bg: "FDF6E3", text: "657B83", accent: "268BD2",
        css: baseCSS + """
        :root {
            --bg-primary: #FDF6E3;
            --bg-secondary: #EEE8D5;
            --bg-code: #EEE8D5;
            --text-primary: #657B83;
            --text-secondary: #839496;
            --text-muted: #93A1A1;
            --accent: #268BD2;
            --accent-light: #EEE8D5;
            --border: #D6CBAE;
            --link: #268BD2;
            --selection: rgba(38, 139, 210, 0.15);
            --font-body: 'Georgia', 'Palatino', serif;
            --font-heading: -apple-system, 'Helvetica Neue', sans-serif;
            --font-mono: 'SF Mono', 'Menlo', monospace;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #002B36;
                --bg-secondary: #073642;
                --bg-code: #073642;
                --text-primary: #839496;
                --text-secondary: #657B83;
                --text-muted: #586E75;
                --accent: #268BD2;
                --accent-light: #0A3E4E;
                --border: #094656;
                --link: #2AA198;
                --selection: rgba(38, 139, 210, 0.2);
            }
        }
        """
    )
    
    // ── 6. Newsprint ──
    static let newsprint = ThemeInfo(
        id: "newsprint", name: "Newsprint",
        bg: "F5F0EB", text: "1A1A1A", accent: "8B0000",
        css: baseCSS + """
        :root {
            --bg-primary: #F5F0EB;
            --bg-secondary: #EDE7E0;
            --bg-code: #E8E1D8;
            --text-primary: #1A1A1A;
            --text-secondary: #4A4A4A;
            --text-muted: #7A7A7A;
            --accent: #8B0000;
            --accent-light: #F0E0D8;
            --border: #D5CEC4;
            --link: #5B3A29;
            --selection: rgba(139, 0, 0, 0.12);
            --font-body: 'Georgia', 'Times New Roman', serif;
            --font-heading: 'Georgia', 'Times New Roman', serif;
            --font-mono: 'Courier New', 'Courier', monospace;
        }
        .ProseMirror h1 {
            font-variant: small-caps;
            letter-spacing: 0.05em;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #1C1A18;
                --bg-secondary: #242220;
                --bg-code: #2A2826;
                --text-primary: #D4CFC8;
                --text-secondary: #A09A92;
                --text-muted: #6E6A64;
                --accent: #CC4444;
                --accent-light: #332828;
                --border: #3A3632;
                --link: #C4956E;
                --selection: rgba(204, 68, 68, 0.15);
            }
        }
        """
    )
    
    // ── 7. ZMZT (读营) ──
    static let zmzt = ThemeInfo(
        id: "zmzt", name: "ZMZT",
        bg: "FFFFFF", text: "000000", accent: "00C4B6",
        css: baseCSS + """
        :root {
            --bg-primary: #FFFFFF;
            --bg-secondary: #FAFAFA;
            --bg-code: #f8f5ec;
            --text-primary: #000000;
            --text-secondary: #3f3f3f;
            --text-muted: #999999;
            --accent: #00c4b6;
            --accent-light: #e0f8f8;
            --border: #c5c5c5;
            --link: #000000;
            --selection: rgba(129, 207, 246, 0.5);
            --font-body: 'Source Sans Pro', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif;
            --font-heading: 'Source Sans Pro', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            --font-mono: 'JetBrains Mono', 'SF Mono', 'Fira Code', Menlo, monospace;
        }

        /* ── Heading auto-numbering ── */
        /* H1: no number, resets h2 counter */
        /* H2: "1. ", H3: "1.1 ", H4: "1.1.1 ", etc. */
        .ProseMirror {
            counter-reset: h2counter;
        }
        .ProseMirror h1 {
            counter-reset: h2counter;
        }
        .ProseMirror h2 {
            counter-reset: h3counter;
        }
        .ProseMirror h3 {
            counter-reset: h4counter;
        }
        .ProseMirror h4 {
            counter-reset: h5counter;
        }
        .ProseMirror h5 {
            counter-reset: h6counter;
        }
        .ProseMirror h2::before {
            counter-increment: h2counter;
            content: counter(h2counter) ". ";
            font-weight: bold;
        }
        .ProseMirror h3::before {
            counter-increment: h3counter;
            content: counter(h2counter) "." counter(h3counter) " ";
            font-weight: bold;
        }
        .ProseMirror h4::before {
            counter-increment: h4counter;
            content: counter(h2counter) "." counter(h3counter) "." counter(h4counter) " ";
            font-weight: bold;
        }
        .ProseMirror h5::before {
            counter-increment: h5counter;
            content: counter(h2counter) "." counter(h3counter) "." counter(h4counter) "." counter(h5counter) " ";
            font-weight: bold;
        }
        .ProseMirror h6::before {
            counter-increment: h6counter;
            content: counter(h2counter) "." counter(h3counter) "." counter(h4counter) "." counter(h5counter) "." counter(h6counter) " ";
            font-weight: bold;
        }

        /* ── Link style: orange underline, pointer cursor, hover fill ── */
        .ProseMirror a {
            border-bottom: 2px solid #ff6600 !important;
            padding: 0 4px;
            color: #000000 !important;
            text-decoration: none !important;
            transition: 0.3s;
            cursor: pointer !important;
        }
        .ProseMirror a:hover {
            border-radius: 6px;
            border-bottom: 2px solid transparent !important;
            background-color: #ff6600;
            color: #ffffffe6 !important;
            cursor: pointer !important;
        }

        /* ── Inline code: red text on cream bg ── */
        .ProseMirror code {
            color: #ff3502 !important;
            background-color: #f8f5ec !important;
            border: none !important;
            border-radius: 2px !important;
            padding: 2px 4px !important;
            font-size: 0.9em !important;
        }

        /* ── Code block: One Dark style ── */
        .ProseMirror pre {
            background: #282c34 !important;
            border: none !important;
            border-radius: 6px !important;
            padding: 12px 16px !important;
        }
        .ProseMirror pre code {
            color: #abb2bf !important;
            background: transparent !important;
            font-size: 0.92em !important;
        }

        /* ── Blockquote: blue left bar + light blue bg ── */
        .ProseMirror blockquote {
            border-left: 5px solid #5fa7e4 !important;
            background-color: #f4fcff !important;
            padding: 10px 15px !important;
            color: #3f3f3f;
            font-style: normal !important;
            border-radius: 3px !important;
        }

        /* ── Heading styles ── */
        .ProseMirror h1 {
            text-align: center;
            font-size: 2.2em;
            margin: 2.4em auto 1.2em !important;
            border-bottom: none !important;
        }
        .ProseMirror h2 {
            font-size: 1.8em;
            margin: 1.8em auto 1.2em !important;
            border-bottom: 2px solid var(--accent) !important;
            padding-bottom: 0.2em !important;
        }
        .ProseMirror h3 {
            font-size: 1.4em;
            line-height: 1.43;
        }
        .ProseMirror h4 {
            font-size: 1.2em;
            padding-left: 6px;
            padding-right: 6px;
        }

        /* ── Horizontal rule: diagonal stripe pattern ── */
        .ProseMirror hr {
            background-image: repeating-linear-gradient(
                -45deg,
                #00c4b6,
                #00c4b6 4px,
                transparent 4px,
                transparent 8px
            ) !important;
            border: none !important;
            border-top: none !important;
            height: 3px !important;
            background-color: transparent !important;
        }

        /* ── Table ── */
        .ProseMirror th {
            background-color: #b9c2c6 !important;
            border: 1px solid #c5c5c5 !important;
            font-weight: bold;
        }
        .ProseMirror td {
            border: 1px solid #c5c5c5 !important;
        }
        .ProseMirror tr:nth-child(2n) {
            background-color: rgb(238, 240, 244);
        }
        .ProseMirror tr:hover {
            background-color: #e0f8f8;
        }

        /* ── Lists: teal markers ── */
        .ProseMirror ul { list-style-type: disc; }
        .ProseMirror li::marker { color: #0abaae; }

        /* ── Task list ── */
        .ProseMirror ul[data-type="taskList"] li input[type="checkbox"] {
            accent-color: #00c4b6;
        }

        /* ── Strong ── */
        .ProseMirror strong {
            color: #333;
        }

        /* ── Dark mode ── */
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #1a1a1a;
                --bg-secondary: #222222;
                --bg-code: #2a2520;
                --text-primary: #e0e0e0;
                --text-secondary: #b0b0b0;
                --text-muted: #666666;
                --accent: #00c4b6;
                --accent-light: #1a3030;
                --border: #444444;
                --link: #e0e0e0;
                --selection: rgba(129, 207, 246, 0.3);
            }
            .ProseMirror a {
                color: #e0e0e0 !important;
            }
            .ProseMirror blockquote {
                background-color: #1a2a30 !important;
                color: #b0b0b0;
            }
            .ProseMirror th {
                background-color: #3a4246 !important;
            }
            .ProseMirror tr:nth-child(2n) {
                background-color: #252525;
            }
            .ProseMirror tr:hover {
                background-color: #1a3030;
            }
            .ProseMirror strong {
                color: #f0f0f0;
            }
            .ProseMirror code {
                color: #ff6b4f !important;
                background-color: #2a2520 !important;
            }
        }
        """
    )
    
    // ── Shared base CSS (layout, typography, elements) ──
    
    static let baseCSS = """
    * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
    }

    html, body {
        background: var(--bg-primary);
        color: var(--text-primary);
        font-family: var(--font-body);
        font-size: 17px;
        line-height: 1.75;
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
    }

    .ProseMirror {
        width: 100%;
        padding: 40px 48px 120px;
        outline: none;
        min-height: 100vh;
        caret-color: var(--accent);
    }

    .ProseMirror ::selection {
        background: var(--selection);
    }

    .ProseMirror h1,
    .ProseMirror h2,
    .ProseMirror h3,
    .ProseMirror h4,
    .ProseMirror h5,
    .ProseMirror h6 {
        font-family: var(--font-heading);
        color: var(--text-primary);
        font-weight: 600;
        line-height: 1.3;
        margin-top: 1.6em;
        margin-bottom: 0.4em;
    }

    .ProseMirror h1 {
        font-size: 2em;
        letter-spacing: -0.02em;
        border-bottom: 1px solid var(--border);
        padding-bottom: 0.3em;
    }

    .ProseMirror h2 {
        font-size: 1.5em;
        letter-spacing: -0.01em;
    }

    .ProseMirror h3 { font-size: 1.25em; }
    .ProseMirror h4 { font-size: 1.1em; }
    .ProseMirror h5 { font-size: 1em; }
    .ProseMirror h6 { font-size: 0.9em; color: var(--text-secondary); }

    .ProseMirror p { margin-bottom: 0.8em; }

    .ProseMirror a {
        color: var(--link);
        text-decoration: none;
        border-bottom: 1px solid transparent;
        transition: border-color 0.15s ease;
    }
    .ProseMirror a:hover { border-bottom-color: var(--link); }

    .ProseMirror code {
        font-family: var(--font-mono);
        font-size: 0.88em;
        background: var(--bg-code);
        border: 1px solid var(--border);
        border-radius: 4px;
        padding: 1px 5px;
    }

    .ProseMirror pre {
        background: var(--bg-code);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 16px 20px;
        margin: 1em 0;
        overflow-x: auto;
        line-height: 1.5;
    }

    .ProseMirror pre code {
        font-family: var(--font-mono);
        font-size: 0.88em;
        background: none;
        border: none;
        padding: 0;
        border-radius: 0;
        color: var(--text-primary);
    }

    .ProseMirror blockquote {
        border-left: 3px solid var(--accent);
        padding-left: 20px;
        margin: 1em 0;
        color: var(--text-secondary);
        font-style: italic;
    }
    .ProseMirror blockquote p { margin-bottom: 0.5em; }

    .ProseMirror ul,
    .ProseMirror ol {
        padding-left: 1.5em;
        margin-bottom: 0.8em;
    }
    .ProseMirror li { margin-bottom: 0.3em; }
    .ProseMirror li > p { margin-bottom: 0.3em; }

    .ProseMirror ul[data-type="taskList"] {
        list-style: none;
        padding-left: 0;
    }
    .ProseMirror ul[data-type="taskList"] li {
        display: flex;
        align-items: flex-start;
        gap: 8px;
    }
    .ProseMirror ul[data-type="taskList"] li input[type="checkbox"] {
        margin-top: 5px;
        accent-color: var(--accent);
        width: 16px;
        height: 16px;
    }

    .ProseMirror hr {
        border: none;
        border-top: 1px solid var(--border);
        margin: 2em 0;
    }

    .ProseMirror img {
        max-width: 100%;
        height: auto;
        border-radius: 6px;
        margin: 1em 0;
    }

    .ProseMirror table {
        border-collapse: collapse;
        width: 100%;
        margin: 1em 0;
    }
    .ProseMirror th,
    .ProseMirror td {
        border: 1px solid var(--border);
        padding: 8px 12px;
        text-align: left;
    }
    .ProseMirror th {
        background: var(--bg-secondary);
        font-weight: 600;
    }

    .ProseMirror strong { font-weight: 700; }
    .ProseMirror em { font-style: italic; }
    .ProseMirror s { text-decoration: line-through; color: var(--text-muted); }

    .ProseMirror mark {
        background-color: #FFFF00;
        color: red;
        padding: 1px 2px;
        border-radius: 2px;
    }

    .ProseMirror ol {
        list-style-type: decimal;
    }

    .ProseMirror p.is-editor-empty:first-child::before {
        content: 'Start writing...';
        color: var(--text-muted);
        pointer-events: none;
        float: left;
        height: 0;
    }

    .ProseMirror-focused { outline: none; }

    """
}
