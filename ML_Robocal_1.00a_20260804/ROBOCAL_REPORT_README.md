# RoboCal CSV Report Tool

`robocal_report.py` extracts only these report fields:

- Test Name
- Reading
- Minimum Spec
- Maximum Spec

It uses Python's standard library and does not require package installation.

## Supported sources

The tool discovers RoboCal runs from timestamped DGC/DCC directories and root log files. For each run it reads:

1. `DCC/<run>/dcc_limits_summary.csv`, when available. This is the preferred source because it can contain test names, readings, and production limits.
2. The `limits_file` selected by each run's `DCC/<run>/dcc_config.json`. If its installed path is unavailable, the tool resolves the same relative path under `--robocal-root` or `%USERPROFILE%\Robocal-v4`.
3. `DCC/<run>/white_point_calibration/correction/right/color_correction.textproto` for official pre-calibration total and white residual readings.
4. `DGC/<run>/nominal_workflow_calibration/calibration_specs.yaml` for DGC feature count, depth, FOV, and display-center readings.
5. `log_file_<run>.log` for measured auto-exposure intensity and its acceptance range, pre-calibration XYZ values, white-point solver diagnostics, and spectrometer hardware averaging.
6. DCC `device_metadata/*.yaml` files for pre-calibration, OK2CAL, and post-calibration integration time, wavelength shift, display brightness, panel temperature, and unsaturated state.

Missing limits are left empty. The tool never invents a spec.

## Readings and production specs

The report includes two kinds of rows:

- Production tests: a reading plus minimum and/or maximum limits explicitly present in the source data.
- Diagnostics: reliable measured or recorded values whose production limits are not present in the workspace. Their minimum and maximum spec columns remain empty.

Configuration targets, exposure settings, golden spectra, and panel attributes are not treated as acceptance limits.

## Commands

Generate a report for the latest run:

```powershell
python .\robocal_report.py . --output .\ML_Robocal.csv
```

Generate a report for one run:

```powershell
python .\robocal_report.py . --run 20260729_085628 --output .\ML_Robocal_20260729_085628.csv
```

Generate one report per run:

```powershell
python .\robocal_report.py . --all-runs --output .\generated_reports
```

Generate a production-test report without diagnostic rows that have no limits:

```powershell
python .\robocal_report.py . --all-runs --official-only --output .\official_reports
```

Official limits are one-sided in the source YAML. A maximum test leaves Minimum Spec empty, and a minimum test leaves Maximum Spec empty. The tool does not replace an unbounded side with an invented number.

Specify an external RoboCal source tree for configured DCC specs:

```powershell
python .\robocal_report.py . --all-runs --robocal-root C:\Users\User\Robocal-v4 --output .\generated_reports
```

Fill an existing ML template while preserving its other columns and rows:

```powershell
python .\robocal_report.py . --template .\ML_Robocal_template.csv --output .\ML_Robocal.csv
```

The template must have recognizable columns for test name, reading, minimum spec, and maximum spec. Common names such as `Test Name`, `Reading`, `Min Spec`, `Max Spec`, `LSL`, and `USL` are accepted.

## Current data availability

The supplied runs use `calibration_limits/glasses/betty_evt2_dcc_specs.yaml`. The file defines 13 production limits and is available in both the installed RoboCal files and `C:\Users\User\Robocal-v4`.

The run directories do not preserve `dcc_limits_summary.csv`, the generated color-error report, or the uniformity metric outputs. Consequently:

- All 13 official test names and limits are included.
- `total_residual` and `white_residual` include readings recovered from the color-correction artifact.
- The other 11 official tests have blank readings because their measurement artifacts are unavailable.

Copying an original `dcc_limits_summary.csv` into its matching `DCC/<run>/` directory will fill those readings automatically using RoboCal's exported `limit_name`, `value`, `limit_value`, `measurement_stage`, `eye`, and `limit_type` fields.

## Convert to the production ML format

`robocal_ml_adapter.py` appends a generated four-column report to an existing 20-column ML CSV. It keeps the existing rows, copies all fields from the template's last data row, and overwrites these fields for each generated test:

| Generated report | ML CSV |
| --- | --- |
| Test Name | TestName |
| Reading | Value |
| Minimum Spec | LowerLimit |
| Maximum Spec | UpperLimit |

```powershell
py -3.11 .\robocal_ml_adapter.py .\ML_Robocal_regenerated_20260729_085628.csv `
	--template .\ML_Robocal.csv `
	--output .\ML_Robocal_merged_20260729_085628.csv
```

The input template must contain at least one data row to use as the inherited values. Use a separate output path when the original template must remain unchanged.

## Generate by serial number

`generate_ml_robocal.ps1` runs both Python tools and resolves the input directory as `C:\Users\User\Desktop\logs\<SN>`. Change only the `-SN` argument for each machine:

```powershell
.\generate_ml_robocal.ps1 -SN S6A67340005M
```

If Windows reports that script execution is disabled, enable it for the current PowerShell process only and rerun the command:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\generate_ml_robocal.ps1 -SN S6A67340005M
```

The final report is written to `C:\Users\User\Desktop\logs\S6A67340005M\ML_Robocal.csv`. Optional arguments include:

```powershell
.\generate_ml_robocal.ps1 -SN S6A67340005M `
	-Run 20260729_085628 `
	-OfficialOnly `
	-LogsRoot C:\Users\User\Desktop\logs `
	-RobocalRoot C:\Users\User\Robocal-v4
```

Keep `generate_ml_robocal.ps1`, `robocal_report.py`, `robocal_ml_adapter.py`, and `ML_Robocal.csv` in the same directory. Use `-Template` to select a different ML template. Use `-LogSubdirectory` only if a future layout adds another directory below the SN folder.

To update the selected ML CSV in place instead of creating a new final CSV, add `-OverwriteTemplate`:

```powershell
.\generate_ml_robocal.ps1 -SN S6A67340005M `
	-OverwriteTemplate
```

The generated four-column report uses a system temporary file and is deleted automatically. The adapter atomically replaces the selected CSV only after the complete output has been written.
Existing rows with the same generated test names are replaced, so rerunning the command does not duplicate tests. Other rows such as `Boot Status Check` are preserved.

For a deployed tool directory at `D:\logparser` and logs at `C:\Users\User\Desktop\logs\<SN>`, run:

```powershell
Set-Location D:\logparser
.\generate_ml_robocal.ps1 -SN S6A67340005X -OverwriteTemplate
```

This updates `D:\logparser\ML_Robocal.csv` in place.