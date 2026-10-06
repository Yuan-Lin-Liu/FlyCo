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

## Run a Scene

From the FlyCo directory, run one scene at a time. If you began with only `docker/`, first `cd FlyCo`.

```bash
./docker/run.sh bahai
```

Follow the [Quick Start](../README.md) sequence: LB, Y, visual/text prompt, X, RB. The launcher passes through `/dev/input/js0` when present. Detach with `Ctrl-P`, `Ctrl-Q`; reattach with `docker attach flyco-bahai`. To stop and switch scenes:

```bash
docker stop flyco-bahai
./docker/run.sh church
```

Without a joystick, publish `sensor_msgs/Joy` to `/joy` inside the container; button indices 4/3/2/5 correspond to LB/Y/X/RB. Logs are under `.docker-data/logs/`.

## Edits and Rebuilds

Launch files, scripts, and ROS code run from `flyco:full`. `setup.sh` keeps existing images; after changing code, rebuild both images and restart the scene:

```bash
docker build --network=host -f docker/Dockerfile -t flyco:noetic .
docker build --network=host -f docker/Dockerfile.ml -t flyco:full .
```

Re-run `./docker/build-ue.sh` after changing UE C++ source.
