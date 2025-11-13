````markdown
A Toolbox for Dasymetric Population Mapping (Elbe Use Case)

This repository provides an R-based **Dasymetric Mapping Toolbox** for the **Elbe** use case, implementing a full workflow using **NUTS**, **CORINE**, and **Census** data.
It follows the **Data-to-Knowledge (D2K)** framework of the **AquaINFRA** project.
````
## 🚀 Launch in MyBinder (optional)

You can open this toolbox in an online RStudio environment (no installation needed) using **MyBinder**:

[![Launch RStudio on MyBinder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/<your-username>/elbe-d2k-toolbox/main?urlpath=rstudio)

Replace `<your-username>` with your GitHub username after pushing this repository.

---

## 🗺️ Data Sources

| Dataset | Description | URL |
|----------|--------------|-----|
| **LAU Data** | Local Administrative Units population data (Germany) | https://aquainfra-aau.a3s.fi/elbe/LAUpop2018DE.gpkg |
| **Census Grid** | Census grid polygons | https://aquainfra-aau.a3s.fi/elbe/censusDE_catchSE.gpkg |
| **CORINE Raster** | CORINE Land Cover raster | https://aquainfra-aau.a3s.fi/elbe/cor2018DE_catchSE.tif |
| **CORINE Legend (DBF)** | CORINE raster attribute table | https://aquainfra-aau.a3s.fi/elbe/cor2018DE_catchSE.tif.vat.dbf |
| **CORINE Vector** | CORINE polygon data clipped to Elbe | https://aquainfra-aau.a3s.fi/elbe/corDE_nutsSE.gpkg |
| **Subbasins** | ECRINS subbasin geometries for Elbe | https://aquainfra-aau.a3s.fi/elbe/catchsub_ecrins_northsea_elbeSE.gpkg |

---

## 🐳 Run the Workflow with Docker

All scripts read from and write to the local `./out` folder.  
Make sure the folder exists before running.

### Build the Docker Image
```bash
docker build -t d2k-toolbox .
````

---

### Step 1: Fetch NUTS and Eurostat Data

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=combine_eurostat_data.R d2k-toolbox "DE" "/out/nuts3_pop_data.gpkg"
```

---

### Step 2: Calculate Population Weights

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=weighting_functions.R d2k-toolbox "https://aquainfra-aau.a3s.fi/elbe/cor2018DE_catchSE.tif" "https://aquainfra-aau.a3s.fi/elbe/censusDE_catchSE.gpkg" "https://aquainfra-aau.a3s.fi/elbe/cor2018DE_catchSE.tif.vat.dbf" "/out/weight_table.csv" "/out/weight_table.rds"
```

---

### Step 3: Clean Catchment Geometries

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=clean_catchment_geometry.R d2k-toolbox "https://aquainfra-aau.a3s.fi/elbe/catchsub_ecrins_northsea_elbeSE.gpkg" "/out/catchment_cleaned.gpkg"
```

---

### Step 4: Filter and Clip All Data to Analysis Extent

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=filter_clip_clean_extent.R d2k-toolbox "/out/nuts3_pop_data.gpkg" "https://aquainfra-aau.a3s.fi/elbe/LAUpop2018DE.gpkg" "https://aquainfra-aau.a3s.fi/elbe/catchsub_ecrins_northsea_elbeSE.gpkg" "/out/nuts3_filtered.gpkg" "/out/lau_processed.gpkg" "/out/analysis_extent.gpkg"
```

---

### Step 5: Perform Dasymetric Refinement (Core Step)

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=process_dasymetric_refinement.R d2k-toolbox "/out/nuts3_filtered.gpkg" "/out/weight_table.rds" "/out/analysis_extent.gpkg" "https://aquainfra-aau.a3s.fi/elbe/corDE_nutsSE.gpkg" "/out/ancillary_data.gpkg"
```

---

### Step 6: Interpolate Population to LAU

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=process_interpolate_lau.R d2k-toolbox "/out/ancillary_data.gpkg" "/out/lau_processed.gpkg" "/out/lau_population_errors.gpkg"
```

---

### Step 7: Interpolate Population to Subbasins

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=process_interpolate_subbasins.R d2k-toolbox "/out/ancillary_data.gpkg" "/out/catchment_cleaned.gpkg" "/out/subbasin_population_density.gpkg"
```

---

### Step 8: Create Final Visualizations

```bash
docker run -it --rm -v ./out:/out -e R_SCRIPT=process_create_visualizations.R d2k-toolbox "/out/weight_table.rds" "/out/lau_population_errors.gpkg" "/out/subbasin_population_density.gpkg" "/out/visual_weight_table.csv" "/out/visual_lau_error_map.html" "/out/visual_subbasin_density_map.html"
```

---

## Run the Workflow with MyBinder (or locally)

Visit [https://mybinder.org/v2/gh/MarkusKonk/aquainfra-usecase-elbe/HEAD](https://mybinder.org/v2/gh/MarkusKonk/aquainfra-usecase-elbe/HEAD).

Note: https://mybinder.org/ is just a test instance with limited resources. While step 1 and 3 succeed, step 2 is taking too much memory resulting in a connection error. Consequently, a more powerful MyBinder instance is needed. As an intermediate solution, just copy the files "example_output/weight_table.csv" "example_output//weight_table.rds" to the folder "out" created below.

### Create directory
Open Terminal

```bash
cd src/
mkdir out
````

---

### Step 1: Fetch NUTS and Eurostat Data

```bash
Rscript combine_eurostat_data.R "DE" "out/nuts3_pop_data.gpkg"
```

---

### Step 2: Calculate Population Weights

```bash
Rscript weighting_functions.R "https://aquainfra-aau.a3s.fi/elbe/cor2018DE_catchSE.tif" "https://aquainfra-aau.a3s.fi/elbe/censusDE_catchSE.gpkg" "https://aquainfra-aau.a3s.fi/elbe/cor2018DE_catchSE.tif.vat.dbf" "out/weight_table.csv" "out/weight_table.rds"
```

---

### Step 3: Clean Catchment Geometries

```bash
Rscript clean_catchment_geometry.R "https://aquainfra-aau.a3s.fi/elbe/catchsub_ecrins_northsea_elbeSE.gpkg" "out/catchment_cleaned.gpkg"
```

---

### Step 4: Filter and Clip All Data to Analysis Extent

```bash
Rscript filter_clip_clean_extent.R "out/nuts3_pop_data.gpkg" "https://aquainfra-aau.a3s.fi/elbe/LAUpop2018DE.gpkg" "https://aquainfra-aau.a3s.fi/elbe/catchsub_ecrins_northsea_elbeSE.gpkg" "out/nuts3_filtered.gpkg" "out/lau_processed.gpkg" "out/analysis_extent.gpkg"
```

---

### Step 5: Perform Dasymetric Refinement (Core Step)

```bash
Rscript process_dasymetric_refinement.R "out/nuts3_filtered.gpkg" "out/weight_table.rds" "out/analysis_extent.gpkg" "https://aquainfra-aau.a3s.fi/elbe/corDE_nutsSE.gpkg" "out/ancillary_data.gpkg"
```

---

### Step 6: Interpolate Population to LAU

```bash
Rscript process_interpolate_lau.R "out/ancillary_data.gpkg" "out/lau_processed.gpkg" "out/lau_population_errors.gpkg"
```

---

### Step 7: Interpolate Population to Subbasins

```bash
Rscript process_interpolate_subbasins.R "out/ancillary_data.gpkg" "out/catchment_cleaned.gpkg" "out/subbasin_population_density.gpkg"
```

---

### Step 8: Create Final Visualizations

```bash
Rscript process_create_visualizations.R "out/weight_table.rds" "out/lau_population_errors.gpkg" "out/subbasin_population_density.gpkg" "out/visual_weight_table.csv" "out/visual_lau_error_map.html" "out/visual_subbasin_density_map.html"
```

---

## 💻 Platform Notes

### 🪟 Windows CMD / PowerShell

* Use the commands **exactly as shown** (each on a single line).
* Volume paths like `./out:/out` work inside the same directory where you run Docker.
* Example:

  ```bash
  cd "D:\05.HSBO\AquaInfra\01. Gulf of Riga\Code\Elbe_Codes\New_Elbe_Docker"
  docker build -t d2k-toolbox .
  ```

### 🐧 Linux / macOS

Use the same commands, or replace paths with full directories if needed:

```bash
docker run -it --rm -v $(pwd)/out:/out -e R_SCRIPT=combine_eurostat_data.R d2k-toolbox "DE" "/out/nuts3_pop_data.gpkg"
```

---

## 🧪 Quick Test Run (Optional Sanity Check)

Before running the full workflow, verify that your **Docker image**, **R environment**, and **GDAL bindings** work correctly.

```bash
docker run -it --rm d2k-toolbox R -e "library(sf); p <- st_point(c(10, 50)); s <- st_sfc(p, crs=4326); print(st_transform(s, 3035))"
```

Expected output (example):

```
Geometry set for 1 feature 
Geometry type: POINT 
Dimension:     XY 
Bounding box:  xmin: 3962764 ymin: 2999718 xmax: 3962764 ymax: 2999718 
Projected CRS: ETRS89-extended / LAEA Europe
```

✅ If this runs without errors, your environment is correctly set up for the Elbe workflow.

---

## 🧾 How to Cite

> *Your Name(s). (Year). A Toolbox for Dasymetric Population Mapping (Elbe Use Case). Zenodo. DOI: XXXXXXXX*

---

## ⚖️ License

This repository is released under the **Apache License 2.0**.

---

## 🧠 Troubleshooting

| Issue | Cause | Solution |
|-------|--------|-----------|
| **exec /app/entrypoint.sh: no such file or directory** | 1. You created `entrypoint.sh` after building the image. <br> 2. (On Windows) Your editor used Windows (`\r\n`) line endings. | Rebuild the image (`docker build -t d2k-toolbox .`). The Dockerfile automatically copies the new file and fixes line endings. |
| **“URL using bad/illegal format” or “cannot open URL”** | The command is missing the `https://` prefix or has extra quotes. | Use plain URLs only with `https://`, e.g., `https://aquainfra-aau.a3s.fi/elbe/...`. |
| **File not found (e.g., `/out/...` missing)** | The `out` directory is not mounted or doesn’t exist locally. | Run `mkdir out` in your project folder before starting Docker. |
| **Eurostat download fails (Error 410 Gone)** | The Eurostat R package is outdated and using a dead API link. | Ensure you have the latest Dockerfile and `.binder/environment.yml`, then rebuild the image (`docker build ...`). |
| **“object not found” in R logs** | The previous step failed, so the input file for the current step was never created. | Check the log of the previous command. Fix the error and re-run that step. |
| **A step fails with a “corrupt file” or “empty geometry” error** | A previous failed run left a partial or empty file in `./out`. | Delete all files in `./out` (e.g., `rm -rf ./out/*`) and run the workflow again from Step 1. |
| **Final maps are empty or show wrong data on hover (e.g., 44733.33%)** | A bug in the R visualization or calculation scripts. | 1. Ensure your `src` scripts are up to date. <br> 2. Rebuild the image (`docker build ...`). <br> 3. Re-run the workflow from Step 6. |
| **Changes to Dockerfile or R scripts don’t seem to work** | Docker is using old cached layers. | Force a clean rebuild:<br>`docker builder prune -af`<br>`docker rmi d2k-toolbox`<br>`docker build -t d2k-toolbox .` |
| **Permission denied on Windows** | Docker can’t access your drive. | Enable drive sharing in *Docker Desktop → Settings → Resources → File Sharing*. |
| **Performance slow or process killed** | Insufficient memory for GDAL or raster ops. | Increase Docker Desktop memory to ≥ 8 GB (*Settings → Resources → Memory*). |

---

## 💾 Saving and Automating Your Commands

You can capture Docker logs, run all workflow steps at once, or export your command history.

---

### 1. Save the *Output* of a Single Command

To save both normal output and error messages to a file, use `*>&1` redirection:

```powershell
docker run -it --rm -v ./out:/out -e R_SCRIPT=combine_eurostat_data.R d2k-toolbox "DE" "/out/nuts3_pop_data.gpkg" *>&1 > step1_log.txt
````

This stores all console messages from Step 1 in `step1_log.txt`.

---

### 2. Run All Steps Automatically

There is a PowerShell script named `run_workflow.ps1/sh` in your project folder :


Run the full pipeline in one go:

```powershell
.\run_workflow.ps1
```

If PowerShell blocks the script:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
macOS Terminal

```powershell
# Execute directly using bash
bash run_workflow.sh
```
---

### 3. Save Your Command History

To save all commands you typed in the current session:

Windows
```powershell
Get-History | Out-File -FilePath my_command_history.txt
```

macOS Terminal

```powershell
history > my_command_history.txt
```
---

This lets users capture logs, automate workflows, and archive terminal history in Windows environments.

```

---


## 🧩 Notes

* The `out/` directory stores all intermediate and final outputs.
* MyBinder sessions are **temporary**; for reproducible work, use **Docker locally**.
* Ensure stable internet when fetching large datasets (CORINE, Eurostat).
* You can chain Docker steps in a shell script for full automation.

---