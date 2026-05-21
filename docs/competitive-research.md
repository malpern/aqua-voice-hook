# Competitive Research: Voice Dictation Automation Tools

*Research date: 2026-05-20*

## Landscape Summary

| Tool | Price | Philosophy | Post-transcription model |
|------|-------|-----------|------------------------|
| **Aqua Voice** | $8/mo | "Perfect text insertion" | AI rewrite + tone adapt + edit mode. No hooks/automation. |
| **Wispr Flow** | $15/mo | "AI handles it invisibly" | Auto-cleanup + tone per app. Command Mode rewrites. No shell/custom actions. |
| **SuperWhisper** | $250 lifetime | "Modes are everything" | Mode = model + LLM prompt + app rules. Shell triggers. Community tool (Macrowhisper) adds actions. |
| **VoiceInk** | $25-49 one-time | "Power Mode per app" | Per-app/URL modes + AI prompts + auto-send keystrokes. Open source (GPL v3). |
| **Talon Voice** | Free | "Voice IS the computer" | Commands map to Python/shell. Deepest automation, steepest curve. |
| **DictaFlow** | $7/mo | "Get it right first time" | In-voice correction. Minimal post-processing. |
| **Willow Voice** | YC-backed | "Speed + accuracy" | ~200ms latency. Format on first pass. No automation. |

---

## Aqua Voice (aquavoice.ai) -- What It Already Does

### Core Features
- Floating text box overlay, hotkey-triggered (Ctrl+Space default)
- Auto-pastes into focused text field on completion
- Streaming mode (real-time display) or Instant mode (~450ms)
- 49-language auto-detection

### AI Features (don't replicate)
- **Fluid Rewrite**: Rephrases and cleans spoken text while preserving tone
- **Filler removal**: Strips "um", "uh", false starts automatically
- **Fill in the blank**: Context-aware gap filling for forgotten words/numbers
- **Style adaptation**: Professional for email, casual for Slack, structured for tickets
- **Custom Instructions**: Persistent per-app rules ("use UK spelling", "lowercase in iMessage")
- **Context awareness**: Reads screen via accessibility APIs for code terms, variable names
- **Edit Mode**: Voice-based post-transcription refinement ("make this more concise")
- **File tagging**: Speak filenames in Cursor/Windsurf to create `@file.ts` references
- **Technical vocabulary**: Trained on programming corpora (JSON, kubectl, PyTorch, etc.)

### What Aqua Voice Does NOT Do
- No auto-submit (never presses Enter)
- No scripting, hooks, or callbacks
- No shell command triggers
- No plugin/extension system
- No webhook integrations
- No macOS Shortcuts actions
- No way to programmatically consume output (paste only)
- No offline mode (100% cloud)
- No Linux support

### Pricing
| Tier | Price |
|------|-------|
| Starter | Free (1,000 words one-time) |
| Pro | $8/mo web, $13/mo App Store |
| Team | $12/mo per user |
| Enterprise | Custom |
| Avalon API | $0.39/hr audio (transcription only) |

---

## Wispr Flow (wisprflow.ai)

### Post-Transcription Actions
- **Command Mode** (Pro): Highlight text, speak instruction ("make this concise"), AI edits inline
- **Voice Shortcuts/Snippets**: Trigger phrases expand to pre-written text (up to 60 char triggers)
- **Auto-transform**: Longer dictations auto-transform in background, shows diff for review
- **Tone presets**: Professional, Casual, Gen Z, Partner, or custom

### AI Features
- Multi-layer pipeline: transcription + cleanup (filler removal, punctuation, backtracking)
- Automatic tone adaptation per app (no config needed)
- IDE integrations (Cursor, VS Code, Windsurf): reads code context, recognizes variable names
- "Hey Flow" wake word for hands-free

### Limitations
- No shell/custom actions
- No post-transcription automation beyond text rewriting
- $15/mo

---

## SuperWhisper (superwhisper.com)

### Post-Transcription Actions
- **Auto-paste** (default): Text inserted on release
- **Hold Shift to auto-send**: Simulates Enter after paste
- **Restore Clipboard**: Restores previous clipboard after transcription paste
- **Simulate Keypresses**: Types character-by-character (experimental, US QWERTY only)

### Modes System
Each mode bundles: voice model + LLM post-processor + system prompt + auto-activation rules
- Built-in: Voice to Text, Message, Email, Note, Super Mode, Meeting, Custom
- **Super Mode**: Captures app context, selected text, clipboard -- feeds to LLM
- **Custom Mode**: User-written system prompts, choice of AI model, per-mode context toggles
- **Shell command trigger**: Modes can trigger shell commands after transcription
- Per-mode keyboard shortcuts (v2.12.0+)

### AI Model Support
- Cloud: OpenAI, Anthropic Claude, Groq, custom endpoints, Amazon Bedrock
- Local: Ollama, Llama, Mistral, Phi, DeepSeek

### Third-Party Automation (Macrowhisper)
Community CLI tool that watches SuperWhisper output folder:
- **Triggers**: voice commands, active app, active mode, browser URL
- **Actions**: text insertion, URL opening, keyboard shortcuts, shell scripts, AppleScript, Apple Shortcuts, action chaining
- **Placeholders**: `{{swResult}}`, `{{selectedText}}`, `{{clipboardContext}}`, `{{frontApp}}`, `{{date:format}}`
- Configured via JSON (no GUI)

### Agent Integrations (v2.13.0+)
- Claude Code and Open Code agent integration (macOS, April 2026)
- Codex hook support (v2.14.0)

---

## VoiceInk (tryvoiceink.com)

### Post-Transcription Actions
- **Power Mode**: Named modes that auto-activate per frontmost app or browser URL
- Each mode has: language, AI prompt, auto-send keystroke (Return, Shift+Return, Cmd+Return, None)
- Context awareness via screen capture
- Per-mode keyboard shortcuts

### AI Enhancement
- BYOK: OpenAI, Anthropic, or Gemini API keys
- Per-mode custom prompts for grammar, tone, formatting

### Limitations
- No IDE integration (no VS Code/Cursor)
- Apple Silicon only, macOS 14.4+
- Local Whisper models only
- Open source (GPL v3)

---

## Talon Voice (talonvoice.com)

### Philosophy
Not a dictation tool -- full computer control via voice. Commands ARE actions.

### Automation
- `.talon` files: declarative command definitions
- Python 3 scripts: arbitrary logic for complex actions
- Can execute: shell commands, keystroke chains, OS APIs, window management, any Python code

### Per-App Behavior
Strongest in category:
- Context rules: `app: Chrome`, `app: vscode`, file extension matching, OS filtering
- Tag-based activation
- Community command set: 15+ programming languages, major IDEs

### AI (community)
- **talon-ai-tools** plugin: voice commands to query LLMs (OpenAI, Copilot, local models)

### Tradeoffs
- Steep learning curve (weeks to become comfortable)
- Very high ceiling
- Free (Patreon-supported beta)

---

## Key Takeaways for Aqua Voice Hook

### Clean division of responsibility
- **Aqua Voice owns**: text quality (rewriting, tone, formatting, context awareness)
- **Aqua Voice Hook owns**: post-paste actions (auto-submit, triggers, integrations)

### The gap nobody fills well
- **No-code action building**: Everyone either requires shell scripts or offers fixed behaviors
- **LLM-powered action creation**: Nobody uses an LLM to interpret "when I dictate in Messages, auto-send it" into a configured action
- **Hands-free activation**: Most tools require a keyboard hotkey to start dictation

### Features worth considering
1. Auto-submit (Return) per app -- already built
2. macOS Notification on dictation
3. Append to file / daily log
4. Run macOS Shortcut
5. Open URL
6. Natural language action creation via Claude SDK
7. Gaze-triggered dictation via OAK-D Lite (see oak-d-lite-gaze-detection.md)
