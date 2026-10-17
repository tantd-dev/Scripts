# Docker VHDX Auto-Compact (Windows + Docker Desktop)

A small PowerShell setup for scheduling Docker Desktop's WSL2 virtual disk maintenance and recording each run to CSV and TXT logs.

> **Important:** This repository is intended for Windows machines using Docker Desktop with the WSL2 backend. Review the scripts before running them, especially if you use a non-default Docker data location.

## What it does

- Registers a Windows Scheduled Task named `DockerCompact`.
- Runs every **Sunday at 03:00 AM**.
- Runs the existing compaction script (`docker-compact.ps1`) through a logging wrapper.
- Automatically creates `C:\Scripts\logs\` when the wrapper runs.
- Records the VHDX size and free space on `C:` before and after each run, duration, exit status, and captured output.

Default log files:

- `C:\Scripts\logs\docker-compact-history.csv` — one summary row per run.
- `C:\Scripts\logs\docker-compact.log` — timestamped run details and output.

## Repository layout

Keep these files together in `C:\Scripts\`:

```text
C:\Scripts\
├── docker-compact.ps1
├── docker-compact-logged.ps1
└── Update-DockerCompactTask-Logging.ps1
```

- `docker-compact.ps1` — the actual compaction script.
- `docker-compact-logged.ps1` — runs the compaction script and writes logs.
- `Update-DockerCompactTask-Logging.ps1` — updates the existing scheduled task to use the logging wrapper.

**Make sure `docker-compact.ps1` is included in the repository** if you want a fresh clone to work without manually copying another file. Do not commit machine-specific secrets or credentials.

## Requirements

- Windows 10/11.
- Docker Desktop configured to use the WSL2 backend.
- PowerShell.
- Permission to create/update a Scheduled Task (run setup from an elevated PowerShell window).
- The Docker VHDX file is at the default location:
  `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`

If a machine uses a different VHDX path, review and update the scripts before running them.

## Install on another computer

### 1. Clone the repository

Open PowerShell:

```powershell
git clone <YOUR_REPOSITORY_URL> C:\Scripts
Set-Location C:\Scripts
```

Replace `<YOUR_REPOSITORY_URL>` with the HTTPS or SSH URL of your GitHub repository.

If `C:\Scripts` already exists and contains files, clone into a different directory or back up the existing files first.

### 2. Review the scripts

Read `docker-compact.ps1`, `docker-compact-logged.ps1`, and `Update-DockerCompactTask-Logging.ps1` before running them. Confirm that the VHDX path and scheduled-task settings match the target computer.

### 3. Register the scheduled task

If your repository includes a registration script named `Register-DockerCompactTask.ps1`, open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; & "C:\Scripts\DockerCompact-AutoSetup.ps1"
```

This creates or registers the `DockerCompact` task for Sundays at 03:00 AM.

If the repository does **not** include `Register-DockerCompactTask.ps1`, add it to the repository or register the task using your existing setup script before continuing.

### 4. Enable logging for the scheduled task

In the same elevated PowerShell window, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "C:\Scripts\Update-DockerCompactTask-Logging.ps1"
```

This updates the existing `DockerCompact` task's action to run `docker-compact-logged.ps1`. It is intended to preserve the task's existing trigger and principal.

> Run the registration step first on a new machine, then run the logging update step.

### 5. Test the task

Start the task immediately:

```powershell
Start-ScheduledTask -TaskName "DockerCompact"
```

Wait for it to finish, then inspect its status:

```powershell
Get-ScheduledTaskInfo -TaskName "DockerCompact" |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
```

Check the logs:

```powershell
Get-Content "C:\Scripts\logs\docker-compact.log" -Tail 80
Import-Csv "C:\Scripts\logs\docker-compact-history.csv" |
    Format-Table -AutoSize
```

The `logs` directory and log files are created automatically when the logging wrapper runs; you do not need to create them manually.

## Run the compaction manually

To run the original compaction script directly:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "C:\Scripts\docker-compact.ps1"
```

To run it with logging, use:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "C:\Scripts\docker-compact-logged.ps1"
```

## Check or manage the scheduled task

Check the task:

```powershell
Get-ScheduledTask -TaskName "DockerCompact"
Get-ScheduledTaskInfo -TaskName "DockerCompact"
```

Run it now:

```powershell
Start-ScheduledTask -TaskName "DockerCompact"
```

Disable it:

```powershell
Disable-ScheduledTask -TaskName "DockerCompact"
```

Enable it again:

```powershell
Enable-ScheduledTask -TaskName "DockerCompact"
```

Remove it:

```powershell
Unregister-ScheduledTask -TaskName "DockerCompact" -Confirm
```

## Important notes

- The task is configured to run as the Windows account used during registration. On another computer, register it under the account that should own and run the task.
- If the task uses an **Interactive** logon type, the user generally needs to be signed in for it to run. A task scheduled for 03:00 AM may not run while the account is signed out. The task's `StartWhenAvailable` setting can allow a missed run to start later, subject to Windows Task Scheduler behavior.
- Compaction may require Docker Desktop/WSL to be stopped. Review the original script to understand what it stops and whether it could interrupt running containers or development work.
- Do not assume that a successful PowerShell process exit guarantees the VHDX shrank. Compare the before/after values in the CSV log.
- The wrapper treats exit code `0` from the original script as success. If the original script catches an error but exits with code `0`, the recorded status may be misleading; the original script should return a non-zero exit code on failure.
- The VHDX **logical size** (`Length`) is not necessarily the same as the physical space it occupies on the host drive. The log may also include `Get-VHD` values when that command is available.
- Test the setup manually on each machine before relying on the weekly schedule.

## Troubleshooting

### The task does not exist

Run the task registration script from an elevated PowerShell window first.

### The logs are not appearing

Check that the scheduled task points to:

```text
C:\Scripts\docker-compact-logged.ps1
```

Then start the task manually and inspect the Task Scheduler result and any PowerShell error output. Confirm the wrapper and original script are present.

### The task runs but no space is reclaimed

Check the CSV's before/after sizes and free-space values. Sparse VHD behavior, Docker/WSL state, deleted data, and Windows storage behavior can all affect whether host free space changes. A successful run does not guarantee a particular amount of reclaimed space.

---

## License

Add a license file if you intend others to reuse or redistribute this repository.
