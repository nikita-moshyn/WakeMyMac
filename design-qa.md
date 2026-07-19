# Design QA

## Evidence

- Source problem screenshot: `/var/folders/q8/8_w54z5d12g439kqv_6pz1sw0000gn/T/TemporaryItems/NSIRD_screencaptureui_2Uttwz/Screenshot 2026-07-19 at 18.20.40.png`
- Implementation screenshot: `/Users/mn/.codex/visualizations/2026/07/19/019f7b14-8010-78e1-9ed9-33fe39d48c94/wakemymac-ui/fullscreen-implementation.png`
- Combined comparison: `/Users/mn/.codex/visualizations/2026/07/19/019f7b14-8010-78e1-9ed9-33fe39d48c94/wakemymac-ui/fullscreen-comparison.png`
- Tested viewport: 80 × 24 terminal.
- State: wake session inactive; Always Active running in mouse mode; home action selected.

## Findings and iteration history

1. The source screen mixed shell history, prior alerts, completed prompts, status output, and the current menu in one scrolling surface. The active frame was not visually isolated.
2. The implementation now enters the terminal alternate buffer (`1049h`), draws one full frame, and restores the primary buffer (`1049l`) on exit. No UI output remains in shell history.
3. Wake and Always Active state occupy two fixed, aligned live rows. Remaining and elapsed time redraw every second without adding lines.
4. Navigation, details, durations, custom input, confirmations, Accessibility guidance, and Always Active management replace content inside the same frame.
5. The focused action uses a full-width inverse/tinted row plus a leading marker. The selected action's explanation has a stable location below the menu.
6. The final capture shows no prior shell content, no repeated WakeMyMac headings, no prompt-completion logs, no clipping, and no layout overlap at 80 × 24.
7. Exiting through `q`, Ctrl-C, or termination restores cursor visibility, terminal input mode, and the previous terminal screen.

Final result: passed
