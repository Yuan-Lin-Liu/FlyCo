FROM nvidia/cuda:11.8.0-devel-ubuntu20.04 AS cuda

FROM flyco:noetic
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TORCH_CUDA_ARCH_LIST=8.9
ENV DEBIAN_FRONTEND=noninteractive \
    CONDA_ENV=system \
    CUDA_HOME=/usr/local/cuda-11.8 \
    PATH=/usr/local/cuda-11.8/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64 \
    TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} \
    MAX_JOBS=2

COPY --from=cuda /usr/local/cuda-11.8 /usr/local/cuda-11.8

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ninja-build python3-dev ffmpeg python3-opencv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir --upgrade 'pip<25' 'setuptools<70' wheel 'numpy<2' \
    && python3 -m pip install --no-cache-dir \
      torch==2.3.1 torchvision==0.18.1 \
      --index-url https://download.pytorch.org/whl/cu118

RUN python3 -m pip install --no-cache-dir --ignore-installed 'PyYAML>=6,<7' \
    && sed -e '/^rospy$/d' -e '/^catkin_tools$/d' -e '/^ffmpeg$/d' \
      -e '/^jupyter$/d' -e '/^wget$/d' \
      -e '/^opencv-python$/d' perception_predictor/src/sam_tracking/requirements.txt \
      > /tmp/sam-requirements.txt \
    && sed -e '/^nksr$/d' -e '/^opencv-python$/d' \
      perception_predictor/src/mesh_predict/requirements.txt \
      > /tmp/mesh-requirements.txt \
    && python3 -m pip install --no-cache-dir \
      -r /tmp/sam-requirements.txt -r /tmp/mesh-requirements.txt \
    && python3 -m pip install --no-cache-dir --no-index --no-deps \
      -f https://data.pyg.org/whl/torch-2.3.0+cu118.html torch-scatter \
    && python3 -m pip install --no-cache-dir python-pycg==1.0.3 GitPython ninja

RUN git clone --depth 1 https://github.com/nv-tlabs/NKSR.git /tmp/NKSR \
    && python3 -m pip install --no-cache-dir --no-build-isolation /tmp/NKSR/package \
    && python3 -m pip install --no-cache-dir --no-build-isolation -e \
      /opt/flyco/perception_predictor/src/sam_tracking/thirdparty/sam2-realtime \
    && rm -rf /tmp/NKSR

RUN python3 -m pip install --no-cache-dir --no-deps --ignore-installed matplotlib==3.7.5

ENV PYTHONPATH=/opt/flyco/perception_predictor/src/sam_tracking/thirdparty/sam2-realtime
RUN source /opt/flyco/perception_predictor/devel/setup.bash \
    && python3 -c 'import torch, sam2, nksr, pointnet2_ops; print(torch.__version__, torch.version.cuda, nksr.__version__)'

RUN python3 -m pip install --no-cache-dir sentencepiece 'protobuf>=3.20,<5'

RUN cp /root/.cache/torch_extensions/py38_cu118/_ext/_ext.so \
      /opt/flyco/perception_predictor/src/mesh_predict/src/pointnet2_ops/_ext.so \
    && groupadd -g 1000 flyco \
    && useradd -u 1000 -g flyco -m -s /usr/bin/zsh flyco \
    && chown -R flyco:flyco /opt/flyco

USER flyco
ENV HOME=/home/flyco SHELL=/usr/bin/zsh LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64
