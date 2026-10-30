# FlyCo with Docker on Linux

For x86_64 Linux hosts. Containers provide Ubuntu 20.04, ROS Noetic, and CUDA 11.8; UE 4.25, scenes, and models stay on the host.

## Before You Start

- Docker Engine and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html), usable without `sudo`.
- NVIDIA GPU/driver, X11 display (XWayland on Wayland), `git`, `curl`, `python3`, `nvidia-smi`, and 150 GiB free for a new UE build.
- GitHub SSH access to UE4.25. [Link Epic and GitHub](https://www.unrealengine.com/en-US/ue-on-github), authorize EpicGames, and accept its invitation once. Account authorization requires your browser; `setup.sh` checks access and then continues automatically.

## Install

From the directory containing `docker/` (the folder works on its own):

```bash
bash docker/setup.sh
```

The script checks the host, clones FlyCo into `FlyCo/` if needed, downloads UE4.25, the [FlyCo UE project](https://drive.google.com/drive/folders/1BXd7_2unaK4iHz50_pSFBnJU25b3mYVl?usp=sharing), all 16 scene maps, and the SAM2, mesh, NKSR, DINOv2, SigLIP, and EVF-SAM model resources. It then builds the Docker images and shared UE editor/project. Downloads are cached under `FlyCo/.docker-data/` (or `.docker-data/` beside existing source); rerun the same command after interruptions. Setup prepares the scenes but does not run flight tests.

Check an existing installation without downloads or builds:

```bash
bash docker/setup.sh --check
```

`setup.sh` detects the GPU compute capability for the ML image. Set `TORCH_CUDA_ARCH_LIST` only if you need to override it. Public download throttling is handled by rerunning the same command; verified files are reused.

Google Drive project downloads use a cached downloader and file listing under
`.docker-data/`. Each file reports its position in the listing. Network reads
time out after 60 seconds without data and retry up to 3 times; completed files
and partial transfers are reused on the next run. Each successfully listed
folder is cached, so a late directory error does not restart the entire crawl;
the full file listing is published only after successful discovery. Set
`DOWNLOAD_TIMEOUT` (seconds) and `DOWNLOAD_RETRIES` to override these defaults.
Files download from the Drive attachment endpoint with 4 workers by default
(`DOWNLOAD_JOBS` overrides this), avoiding preview-page link discovery. Interrupted
transfers use `.drive.part` files and validated HTTP range responses. Error pages
are rejected before writing; files are published only after transfer completion.
Transient TLS connection closures and Drive download-link failures are retried
with certificate checks enabled. Persistent permission or quota errors still
stop setup and preserve the downloaded files.
The curl-based scene/checkpoint downloads also retry TLS failures and abort
transfers that receive no data for 60 seconds. Failed scene transfers keep their
temporary files and are never published as completed assets.
Host HTTP/HTTPS proxy environment variables are passed to the download container.
The project download includes `FlyCo.uproject`, `Config`, `Content`, `Plugins`,
and `Source`; root build outputs, IDE files, saved logs/crash dumps, and derived
data caches are omitted because setup builds the project locally.

If the UE image fails to fetch Ubuntu packages with proxy errors such as
`502 Bad Gateway`, and direct access to the Ubuntu repositories works, resume
with `FLYCO_APT_PROXY=DIRECT bash docker/setup.sh`. This overrides the proxy only
for APT in the UE build image; existing images and downloaded resources are reused.
`FLYCO_APT_PROXY` can also specify an APT proxy URL. Leave it unset to retain the
Docker client's proxy settings.

## Run a Scene

From the FlyCo directory, run one scene at a time. If you began with only `docker/`, first `cd FlyCo`.

```bash
./docker/run.sh bahai
```

The scan completion threshold is `coverage_objective=99.5` in
`planner_simulator/src/flyco_planner_manager/launch/demo/param.xml`. The planner
marks the task finished when Flight Coverage is strictly greater than this
percentage. The launcher mounts this configuration read-only, so changes take
effect when starting a new scene container without rebuilding the image.

Follow the [Quick Start](../README.md) sequence: LB, Y, visual/text prompt, X, RB. The launcher passes through `/dev/input/js0` when present. Detach with `Ctrl-P`, `Ctrl-Q`; reattach with `docker attach flyco-bahai`. To stop and switch scenes:

```bash
docker stop flyco-bahai
./docker/run.sh church
```

Without a joystick, open a second host terminal while the scene is running:

```bash
bash docker/keyboard.sh bahai
```

This works with the running container without rebuilding the image. Keep the
keyboard terminal focused when pressing these keys:

1. Press `1` (LB) to initialize the modules; wait for them to be ready.
2. Press `2` (Y) for the initial flight; wait for the drone to settle.
3. In **FlyCo-UI**, drag with the middle mouse button to box the target, or
   left-click points on the target, then click **send points**. Right-click
   negative/background points if needed; **clear points** clears the selection.
   Optionally describe the target in the text field and click **send text**.
4. Return to the keyboard terminal and press `3` (X) to enable planning services.
   Wait for the target segmentation/point cloud and planning data to appear.
5. Press `4` (RB) to trigger autonomous scanning of the selected structure.

FlyCo plans a scanning route around the prompted structure. The UI selects the
target; the keyboard triggers the mission stages. `h` shows help and `q` exits
the keyboard program without stopping an active flight. To end the simulation,
run `docker stop flyco-bahai` from another terminal.

For a connection-only check, run `bash docker/keyboard.sh bahai --check`; this
sends no control messages. The controller publishes `sensor_msgs/Joy` on `/joy`
with button indices 4/3/2/5 corresponding to LB/Y/X/RB, followed by release
messages. Logs are under `.docker-data/logs/`.

## Edits and Rebuilds

Launch files, scripts, and ROS code run from `flyco:full`. `setup.sh` keeps existing images; after changing code, rebuild both images and restart the scene:

```bash
docker build --network=host -f docker/Dockerfile -t flyco:noetic .
docker build --network=host -f docker/Dockerfile.ml -t flyco:full .
```

Re-run `./docker/build-ue.sh` after changing UE C++ source.

The Docker build context excludes `ros2_migration/`, Git metadata, local build
directories, logs, cached simulation assets, and downloaded model weights. The
standalone `docker/` installer includes the same map-origin raycasting fix and
regression test as the ROS1 source tree.
