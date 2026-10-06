FROM osrf/ros:noetic-desktop-full

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV CONDA_ENV=system

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake curl ca-certificates zsh tmux expect cpulimit \
    python3-catkin-tools python3-pip python3-rosdep \
    libeigen3-dev libompl-dev libyaml-cpp-dev libgsl-dev \
    libopencv-dev libpcl-dev libboost-all-dev \
    ros-noetic-cv-bridge ros-noetic-geographic-msgs \
    ros-noetic-image-geometry ros-noetic-image-transport \
    ros-noetic-joy ros-noetic-mavros ros-noetic-pcl-ros \
    ros-noetic-tf2-geometry-msgs ros-noetic-tf2-sensor-msgs \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://gitlab.com/libeigen/eigen/-/archive/3.4.1/eigen-3.4.1.tar.gz \
      -o /tmp/eigen-3.4.1.tar.gz \
    && tar -xzf /tmp/eigen-3.4.1.tar.gz -C /tmp \
    && cmake -S /tmp/eigen-3.4.1 -B /tmp/eigen-3.4.1-build -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --install /tmp/eigen-3.4.1-build \
    && rm -rf /tmp/eigen-3.4.1*

WORKDIR /opt/flyco
COPY planner_simulator planner_simulator
RUN cmake -S planner_simulator/src/skeleton_decomp/fps/sampling_cpu \
      -B planner_simulator/src/skeleton_decomp/fps/sampling_cpu/build \
    && cmake --build planner_simulator/src/skeleton_decomp/fps/sampling_cpu/build \
      --target kdline -j 2

# The vendored AirSim source expects Eigen at this path, but omits the headers.
RUN mkdir -p planner_simulator/src/airsim_simulator/ThirdParty/AirLib/deps \
    && ln -s /usr/local/include/eigen3 planner_simulator/src/airsim_simulator/ThirdParty/AirLib/deps/eigen3 \
    && source /opt/ros/noetic/setup.bash \
    && source planner_simulator/src/3rdparty/embree-3/embree.bash \
    && cd planner_simulator \
    && catkin config --extend /opt/ros/noetic -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE=/usr/bin/python3 -DEigen3_DIR=/usr/local/share/eigen3/cmake \
    && catkin build -j 2 -p 2 --no-status --cmake-args -Wno-dev

COPY perception_predictor perception_predictor
RUN source planner_simulator/devel/setup.bash \
    && cd perception_predictor \
    && catkin config --extend /opt/flyco/planner_simulator/devel -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE=/usr/bin/python3 -DEigen3_DIR=/usr/local/share/eigen3/cmake \
    && catkin build -j 2 -p 2 --no-status --cmake-args -Wno-dev

COPY scripts scripts
RUN printf '%s\n' \
    'source /opt/ros/noetic/setup.bash' \
    'source /opt/flyco/planner_simulator/src/3rdparty/embree-3/embree.bash' \
    'source /opt/flyco/perception_predictor/devel/setup.bash' \
    >> /etc/bash.bashrc

CMD ["bash"]
