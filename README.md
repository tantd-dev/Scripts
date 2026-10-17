# Docker VHDX Auto-Compact (Windows + Docker Desktop)

A PowerShell setup for scheduling Docker Desktop's WSL2 virtual-disk compaction and recording each run to CSV and TXT logs.

> **Important:** This setup is intended for Windows 10/11 with Docker Desktop using the WSL2 backend. Review `docker-compact.ps1` before running it. Compaction may stop Docker Desktop/WSL and interrupt running containers.

## What it does

- Creates or updates a Windows Scheduled Task named `DockerCompact`.
- Schedules it for every **Sunday at 03:00 AM**.
- Uses one setup script, `DockerCompact-AutoSetup.ps1`, for both task registration and logged execution.
- Runs the existing `docker-compact.ps1` script when the task starts.
- Logs each run's start/end time, duration, status, exit code, VHDX size, and free space on drive `C:`.
- Creates the log directory automatically.

Log files:

- `C:\Scripts\logs\docker-compact-history.csv` — one summary row per run; can be opened in Excel.
- `C:\Scripts\logs\docker-compact.log` — detailed timestamped output and errors.

## Repository layout

Place these files in `C:\Scripts\`:

```text
C:\Scripts\
├── DockerCompact-AutoSetup.ps1
├── docker-compact.ps1
└── logs\
    ├── docker-compact-history.csv   # created automatically
    └── docker-compact.log           # created automatically
```

- `DockerCompact-AutoSetup.ps1` — creates/updates the scheduled task and runs the logging workflow when invoked by Task Scheduler.
- `docker-compact.ps1` — the existing script that performs the actual compaction.
- `logs\` — created automatically; no need to create it manually.

The unified setup script expects the compaction script at `C:\Scripts\docker-compact.ps1`. It must itself be saved at `C:\Scripts\DockerCompact-AutoSetup.ps1` because the scheduled task uses that fixed path.

## Requirements

- Windows 10/11.
- Docker Desktop configured to use the WSL2 backend.
- PowerShell.
- Administrator permission to register/update the scheduled task.
- Docker VHDX at the default location: `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`.

If your Docker VHDX is stored elsewhere, review and update the setup script before running it.

## Install / set up

### 1. Put the files in place

Copy `DockerCompact-AutoSetup.ps1` and your existing `docker-compact.ps1` into `C:\Scripts\`.

If `C:\Scripts\` already contains files, do not overwrite them blindly. Back up anything you need first.

### 2. Register the scheduled task (one-time setup)

Open **PowerShell as Administrator** and run this one-line command:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; & "C:\Scripts\DockerCompact-AutoSetup.ps1"
```

The script creates or updates `DockerCompact` to run every Sunday at 03:00 AM. You do not need to run a separate registration script or logging updater.

Verify the task exists:

```powershell
Get-ScheduledTask -TaskName "DockerCompact"
```

Check the next/last run information:

```powershell
Get-ScheduledTaskInfo -TaskName "DockerCompact" | Format-List LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
```

## View logs without opening the CSV

### Show the latest detailed log lines

```powershell
Get-Content "C:\Scripts\logs\docker-compact.log" -Tail 30
```

### Follow the log live

```powershell
Get-Content "C:\Scripts\logs\docker-compact.log" -Tail 20 -Wait
```

Press `Ctrl+C` to stop following the log.

### Show only the most recent CSV summary row

```powershell
Import-Csv "C:\Scripts\logs\docker-compact-history.csv" | Select-Object -Last 1 | Format-List StartTime, EndTime, DurationSeconds, Status, ExitCode, VhdxLogicalBeforeGiB, VhdxLogicalAfterGiB, VhdxAllocatedBeforeGiB, VhdxAllocatedAfterGiB, CFreeBeforeGiB, CFreeAfterGiB, Error
```

### Show all CSV runs as a table

```powershell
Import-Csv "C:\Scripts\logs\docker-compact-history.csv" | Format-Table StartTime, DurationSeconds, Status, VhdxLogicalBeforeGiB, VhdxLogicalAfterGiB, CFreeBeforeGiB, CFreeAfterGiB -AutoSize
```

### Open the logs in Notepad

```powershell
notepad "C:\Scripts\logs\docker-compact.log"
```

```powershell
notepad "C:\Scripts\logs\docker-compact-history.csv"
```

The CSV can also be opened in Excel.

## Test the task manually

> **Warning:** Starting this task performs real compaction and may stop Docker Desktop/WSL and interrupt running containers. Save your work and run it only when it is safe to stop Docker.

Start the task:

```powershell
Start-ScheduledTask -TaskName "DockerCompact"
```

Check its status:

```powershell
Get-ScheduledTaskInfo -TaskName "DockerCompact" | Format-List LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
```

Review the detailed log:

```powershell
Get-Content "C:\Scripts\logs\docker-compact.log" -Tail 80
```

## Check or manage the scheduled task

Check the task definition:

```powershell
Get-ScheduledTask -TaskName "DockerCompact" | Format-List TaskName, TaskPath, State
```

Check run information:

```powershell
Get-ScheduledTaskInfo -TaskName "DockerCompact" | Format-List LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
```

Disable it:

```powershell
Disable-ScheduledTask -TaskName "DockerCompact"
```

Enable it again:

```powershell
Enable-ScheduledTask -TaskName "DockerCompact"
```

Remove it (Windows asks for confirmation):

```powershell
Unregister-ScheduledTask -TaskName "DockerCompact" -Confirm
```

## Task Scheduler GUI

1. Press `Win+R`, enter `taskschd.msc`, and press Enter.
2. Select **Task Scheduler Library**.
3. Select `DockerCompact`.
4. Review **Last Run Time**, **Last Run Result**, **Next Run Time**, and the **History** tab.
5. If History is empty, select **Enable All Tasks History** in the Actions pane.

Task Scheduler history shows whether Windows started the task and how it ended. The CSV/TXT logs contain the compaction measurements and script output.

## Important notes

- The task runs under the Windows account used when registering it, with the highest run level. Its Interactive logon type generally requires that account to be signed in; `StartWhenAvailable` may allow a missed run to start later, subject to Task Scheduler behavior.
- `LastTaskResult = 0` means Windows recorded a zero exit code; it does not prove that the VHDX shrank.
- The setup script records success based on the exit code of `docker-compact.ps1`. If that script catches an error but still exits with code `0`, the logged status may be misleading.
- VHDX logical file size (`Length`) is not the same as physical space occupied on the host drive. Allocated/virtual-size values are recorded only if `Get-VHD` is available.
- Compare before/after values in the CSV to see whether free space on `C:` increased. A successful run does not guarantee a particular amount of reclaimed space.
- Test the setup manually before relying on the weekly schedule.

## Troubleshooting

### The task does not exist

Confirm the setup script is at `C:\Scripts\DockerCompact-AutoSetup.ps1`, then run PowerShell as Administrator and execute:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; & "C:\Scripts\DockerCompact-AutoSetup.ps1"
```

If registration fails, read the error printed in PowerShell.

### The log files do not exist

The log files are created when the scheduled task runs. First check that the task exists, then start it manually when it is safe to stop Docker:

```powershell
Start-ScheduledTask -TaskName "DockerCompact"
```

Then inspect the log:

```powershell
Get-Content "C:\Scripts\logs\docker-compact.log" -Tail 80
```

### The task runs but no space is reclaimed

Compare the CSV's before/after values. Sparse VHD behavior, Docker/WSL state, deleted data, and Windows storage behavior can all affect whether host free space changes.

---

## License

Add a license file if you intend others to reuse or redistribute this repository.
