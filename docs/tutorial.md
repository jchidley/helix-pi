# Tutorial: Your First Pi Session in Helix

This tutorial walks you through installing and using helix-pi for the first time.

## Before You Start

You need:
- Helix editor built with Steel support (`cargo xtask steel`)
- The `pi` CLI installed and configured with an API key
- This repository cloned locally

Verify pi works:
```bash
pi --version
```

You should see version output. If not, install pi first.

## Step 1: Install the Plugin

Copy the plugin files to your Helix config:

```bash
mkdir -p ~/.config/helix/cogs/pi
cp src/*.scm ~/.config/helix/cogs/pi/
```

You should see no errors.

## Step 2: Configure helix.scm

Open your Helix configuration:

```bash
~/git/helix/target/release/hx ~/.config/helix/helix.scm
```

Add these lines near the top (after other `require` statements):

```scheme
(require (only-in "cogs/pi/pi.scm" 
                  pi-start pi-continue pi-resume pi-send pi-abort pi-quit pi-recover
                  pi-model pi-thinking pi-status pi-compact pi-new pi-steer pi-follow))
```

Find your existing `provide` statement and add the pi commands:

```scheme
(provide ...your-existing-exports...
         pi-start pi-continue pi-resume pi-send pi-abort pi-quit pi-recover
         pi-model pi-thinking pi-status pi-compact pi-new pi-steer pi-follow)
```

Save the file (`:w`).

## Step 3: Restart Helix

Close and reopen Helix:

```bash
~/git/helix/target/release/hx .
```

If Helix starts normally, the plugin loaded successfully.

If you see errors, check [How to Debug](debugging.md).

## Step 4: Start a Pi Session

Type `:pi-start` (or press `Alt-p n`) and press Enter.

You should see:
- Two new buffers appear in a horizontal split
- Top buffer: `[pi/output]` - where responses appear
- Bottom buffer: `[pi/input]` - where you type prompts
- Status bar shows: `pi: ready`

## Step 5: Send Your First Prompt

You're now in the input buffer. Type a message:

```
Say hello in exactly 3 words
```

Now send it:
- Type `:pi-send` (or press `Alt-p s`) and press Enter

Watch the output buffer. You should see:
- `## You` followed by your prompt
- `## Assistant` followed by the streaming response
- Status changes to `pi: streaming...` then `pi: idle`

## Step 6: Send a Follow-up

The input buffer was cleared. Type another message:

```
Now say goodbye in 2 words
```

Send with `:pi-send` (or `Alt-p s`).

Notice the conversation continues - the assistant remembers your first request.

## Step 7: End the Session

Type `:pi-quit` (or `Alt-p q`).

You should see: `pi: stopped (session saved)`

The buffers close and your session is saved.

## Step 8: Resume the Session

Start Helix again and type `:pi-continue` (or `Alt-p p`).

This loads your most recent session. Type:

```
What was my first request?
```

Send with `:pi-send` (or `Alt-p s`). The assistant should remember your earlier conversation because the session was restored with prompt caching.

## Step 9: Browse Other Sessions

Type `:pi-quit` to close, then `:pi-resume` (or `Alt-p r`) with an empty input buffer.

You should see a list of available sessions in the output buffer with their paths and timestamps.

To resume a specific session, put its path in the input buffer and run `:pi-resume` again.

## Next Steps

- Learn about [debugging](debugging.md) if things go wrong
- Read [About the Architecture](architecture.md) to understand how it works
- Check [Steel Plugin Patterns](patterns.md) if you want to modify the plugin
