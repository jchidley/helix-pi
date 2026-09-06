# Tutorial: Your First Pi Session in Helix

This is a historical installation walkthrough for an explicitly approved live setup, not a tested current-version tutorial. Read [operating limits](commands.md#operating-limits) first. Copying/configuring/restarting changes the live editor; prompts and compaction may use paid providers and tools. Preserve plugin/config files and unsaved work, use synthetic inputs, and do not disable confirmation safeguards to work around unsupported RPC dialogs. Alt-p shortcuts apply only after installing the example keybindings in the command reference.

## Before You Start

You need:
- Helix editor built with Steel support (`cargo xtask steel`)
- The `pi` CLI installed and configured with an API key
- This repository cloned locally

Verify pi works:
```bash
pi --version
```

Version output verifies only that binary's presence, not Steel/Helix compatibility or authentication. If prerequisites are missing, arrange setup separately; do not install as part of a guidance review.

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

That legacy status message is not proof of persistence or child exit. The implementation closes stdin and clears local process state without waiting for the child; buffers remain.

## Step 8: Resume the Session

Start Helix again and type `:pi-continue` (or `Alt-p p`).

This loads your most recent session. Type:

```
What was my first request?
```

Send with `:pi-send` (or `Alt-p s`). Session history restoration and provider prompt caching are different mechanisms. Neither a rendered history nor this example proves the active branch was restored or a cache hit occurred.

## Step 9: Browse Other Sessions

Type `:pi-quit` to close, then `:pi-resume` (or `Alt-p r`) with an empty input buffer.

With empty input, the implementation opens a picker, not an output-buffer listing with timestamps. Session discovery has POSIX/path/whitespace limits; verify the selected session and child response before relying on the displayed history.

To resume a specific session, put its path in the input buffer and run `:pi-resume` again.

## Next Steps

- Learn about [debugging](debugging.md) if things go wrong
- Read [About the Architecture](architecture.md) to understand how it works
- Check [Steel Plugin Patterns](patterns.md) if you want to modify the plugin
