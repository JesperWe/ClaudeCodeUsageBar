# usageBar

A macOS menu bar app that displays your Claude Code usage statistics at a glance.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)

## Features

- **Menu bar icon** with two progress bars showing session and weekly usage
- **Auto-refresh** every 10 minutes
- **Visual alerts** — bars turn orange and pulse when usage exceeds 90%
- **Error reporting** — shows CLI output when something goes wrong
- Persistent folder configuration stored across launches

## Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed

## Setup

1. Build and run the app in Xcode
2. On first launch, select a folder where Claude Code has been trusted
3. The app will begin polling usage data automatically

## How it works

The app runs `claude /usage` in a pseudo-terminal (PTY) against the configured working directory, parses the ANSI output for session and weekly usage percentages, and renders them as two stacked bars in the menu bar.

- **Top bar** — current session usage
- **Bottom bar** — weekly usage (all models)

## Menu bar controls

- **Refresh** — manually trigger a usage check
- **Change Folder…** — select a different trusted directory
- **Quit** — exit the app
