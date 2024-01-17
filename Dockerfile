#docker build --no-cache -t docker-st:latest .; docker run -it -p 8000:8000 -p 5100:5100 --name "docker-st" --rm docker-st:latest
FROM node:20-bookworm
ENV DEBIAN_FRONTEND noninteractive

# image captioning module
# Salesforce/blip-image-captioning-large - good base model
# Salesforce/blip-image-captioning-base - slightly faster but less accurate
#
# sentiment classification model
# nateraw/bert-base-uncased-emotion = 6 supported emotions<br>
# joeddav/distilbert-base-uncased-go-emotions-student = 28 supported emotions
# 
# story summarization module
# slauw87/bart_summarisation - general purpose summarization model
# Qiliang/bart-large-cnn-samsum-ChatGPT_v3 - summarization model optimized for chats
# Qiliang/bart-large-cnn-samsum-ElectrifAi_v10 - nice results so far, but still being evaluated
# distilbart-xsum-12-3 - faster, but pretty basic alternative
# 
# SD picture generation
# ckpt/anything-v4.5-vae-swapped - anime style model
# hakurei/waifu-diffusion - anime style model
# philz1337/clarity - realistic style model
# prompthero/openjourney - midjourney style model
# ckpt/sd15 - base SD 1.5
# stabilityai/stable-diffusion-2-1-base - base SD 2.1

# Arguments
ARG APP_HOME=/home/node/app

ARG PYTHON_VER=3.11.0

ARG MODULES="caption,summarize,classify,sd,silero-tts,rvc,chromadb,whisper-stt,talkinghead"
ENV MODULES=${MODULES:-$MODULES}

ARG CLASSIFICATION_MODEL="joeddav/distilbert-base-uncased-go-emotions-student"
ENV CLASSIFICATION_MODEL=${CLASSIFICATION_MODEL:-$CLASSIFICATION_MODEL}

ARG SUMMARIZATION_MODEL="Qiliang/bart-large-cnn-samsum-ElectrifAi_v10"
ENV SUMMARIZATION_MODEL=${SUMMARIZATION_MODEL:-$SUMMARIZATION_MODEL}

ARG CAPTIONING_MODEL="Salesforce/blip-image-captioning-large"
ENV CAPTIONING_MODEL=${CAPTIONING_MODEL:-$CAPTIONING_MODEL}

ARG SD_REMOTE_HOST="192.168.0.171"
ENV SD_REMOTE_HOST=${SD_REMOTE_HOST:-$SD_REMOTE_HOST}

ARG SD_REMOTE_PORT="7860"
ENV SD_REMOTE_PORT=${SD_REMOTE_PORT:-$SD_REMOTE_PORT}

# voice models https://voice-models.com/top
# gotta be rvmpe
ARG RVC_MODEL="https://huggingface.co/MUSTAR/Hoshino_Ai_U/resolve/main/Hoshino_Ai_U.zip"
ENV RVC_MODEL=${RVC_MODEL:-$RVC_MODEL}

#https://oobabooga.github.io/silero-samples/index.html
#ARG WHISPER_MODEL="v3_en.pt"
#ENV WHISPER_MODEL=${WHISPER_MODEL:-$WHISPER_MODEL}


ARG API_KEY

# Build and install python3.11 for chromadb
RUN apt update -y \
    && apt upgrade -y \
    && apt -y install build-essential \
        zlib1g-dev \
        libncurses5-dev \
        libgdbm-dev \ 
        libnss3-dev \
        libssl-dev \
        libreadline-dev \
        libffi-dev \
        libsqlite3-dev \
        libbz2-dev \
        wget \
    && apt purge -y imagemagick imagemagick-6-common 

RUN cd /usr/src \
    && wget https://www.python.org/ftp/python/$PYTHON_VER/Python-$PYTHON_VER.tgz \
    && tar -xzf Python-$PYTHON_VER.tgz \
    && cd Python-$PYTHON_VER \
    && ./configure --enable-loadable-sqlite-extensions --enable-optimizations \
    && make profile-gen-stamp; ./python -m test.regrtest --pgo -j8; make build_all_merge_profile; touch profile-run-stamp; make \
    && make altinstall

RUN update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.11 1

# Clean up build packages
RUN apt autoremove -y --purge build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev libbz2-dev \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* /usr/src/Python-$PYTHON_VER.tgz

# Install sillytavern packages
RUN apt update && \
    apt install -y tini git dos2unix sqlite3 ffmpeg unzip && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR ${APP_HOME}

RUN git clone https://github.com/SillyTavern/SillyTavern /tmp/source

# Install app dependencies
RUN cp /tmp/source/package*.json /tmp/source/post-install.js ./
RUN \
  echo "*** Install npm packages ***" && \
  npm install && npm cache clean --force

# Bundle app source
RUN cp -r /tmp/source/* ./

# Create missing dir
RUN mkdir public/user

# Copy default chats, characters and user avatars to <folder>.default folder
RUN \
  IFS="," RESOURCES="assets,backgrounds,user,context,instruct,QuickReplies,movingUI,themes,characters,chats,groups,group chats,User Avatars,worlds,OpenAI Settings,NovelAI Settings,KoboldAI Settings,TextGen Settings" && \
  \
  echo "*** Store default $RESOURCES in <folder>.default ***" && \
  for R in $RESOURCES; do mv "public/$R" "public/$R.default"; done || true && \
  \
  echo "*** Create symbolic links to config directory ***" && \
  for R in $RESOURCES; do ln -s "../config/$R" "public/$R"; done || true && \
  \
  rm -f "config.yaml" "public/settings.json" || true && \
  ln -s "./config/config.yaml" "config.yaml" || true && \
  ln -s "../config/settings.json" "public/settings.json" || true && \
  mkdir "config" || true

# Necessary config modifications
RUN sed -i "s/securityOverride: false/securityOverride: true/" /home/node/app/default/config.yaml
RUN sed -i "s/whitelistMode: true/whitelistMode: false/" /home/node/app/default/config.yaml
RUN sed -i "s/listen: false/listen: true/" /home/node/app/default/config.yaml
RUN sed -i "s/allowKeysExposure: false/allowKeysExposure: true/" /home/node/app/default/config.yaml

# Install wxpython for talkingheads
#RUN apt update && \
#   apt install -y python3-wxgtk4.0 python3-wxgtk-webview4.0 python3-wxgtk-media4.0 && \
#   rm -rf /var/lib/apt/lists/*

#RUN apt update && \
#   apt install make gcc libgtk-3-dev libwebkit2gtk-4.0-dev  libgstreamer-gl1.0-0 freeglut3 freeglut3-dev  python3-gst-1.0 libglib2.0-dev ubuntu-restricted-extras libgstreamer-plugins-base1.0-dev

# Install extras
RUN git clone https://github.com/SillyTavern/SillyTavern-extras /tmp/extras && \
    cp -r /tmp/extras /home/node/app/extras && \
    #git clone https://github.com/Cohee1207/tts_samples /tmp/samples && \
    #cp -r /tmp/samples/* /home/node/app/extras && \
    wget "$RVC_MODEL" -P /tmp/model && \
    for f in /tmp/model/*.zip; do unzip "$f" -d "/home/node/app/extras/data/models/rvc/$(basename "$f" .zip)"; done && \
    cd /home/node/app/extras && \
    npm install -g localtunnel && npm cache clean --force && \
    sed -i -E "/--extra-index-url https:\/\/download.pytorch.org\/whl\/cu118/d" requirements.txt && \
    sed -i -E "/torch/d" requirements.txt  && \
    python3 -m pip install pip -U && \
# enable the following line with the index url to get gpu inference support instead of just cpu
    python3 -m pip install torch==2.0.1+cu118 torchvision==0.15.2+cu118 torchaudio==2.0.2+cu118 --extra-index-url https://download.pytorch.org/whl/cu118 -U && \
#   python3 -m pip install torch torchvision torchaudio -U && \
    python3 -m pip install triton==2.0.0 fastapi==0.90.0 -U && \
    python3 -m pip install -U -f https://extras.wxpython.org/wxPython4/extras/linux/gtk3/ubuntu-20.04 wxPython && \
    python3 -m pip install -U tha3 && \
    python3 -m pip install -r requirements.txt && \
    python3 -m pip install -r requirements-rvc.txt && \
    python3 -m pip install pysqlite3-binary tensorboardX git+https://github.com/One-sixth/fairseq.git -U && \
    wget https://github.com/cloudflare/cloudflared/releases/download/2023.5.0/cloudflared-linux-amd64 -O /tmp/cloudflared-linux-amd64 && \
    git clone https://github.com/city-unit/SillyTavern-Chub-Search /tmp/chubsearch && \
    cp -r /tmp/chubsearch /home/node/app/public/scripts/extensions/chubsearch && \
    git clone https://github.com/city-unit/st-auto-tagger /tmp/st-auto-tagger && \
    cp -r /tmp/st-auto-tagger /home/node/app/public/scripts/extensions/st-auto-tagger && \
    chmod +x /tmp/cloudflared-linux-amd64

RUN if [ -z "${API_KEY}" ]; then \
      API_KEY=$(openssl rand -hex 5); \
      echo "${API_KEY}" > /home/node/app/extras/api_key.txt; \
      export API_KEY=${API_KEY}; \
    else \
      echo "${API_KEY}" > /home/node/app/extras/api_key.txt; \
      export API_KEY=${API_KEY}; \
    fi

ENV API_KEY=${API_KEY:-$API_KEY}


# Cleanup unnecessary files
RUN \
  echo "*** Cleanup ***" && \
  mv "./docker/docker-entrypoint.sh" "./" && \
  rm -rf "./docker" && \
  rm -rf "/tmp/source" && \
  rm -rf "/tmp/extras" && \
  rm -rf "/tmp/samples" && \
  echo "*** Make docker-entrypoint.sh executable ***" && \
  chmod +x "./docker-entrypoint.sh" && \
  echo "*** Convert line endings to Unix format ***" && \
  dos2unix "./docker-entrypoint.sh"

# Modify startup command to include extras server
# --stt-whisper-model-path=\"\${WHISPER_MODEL}\"
# --chroma-folder=/chromadb/
RUN sed -i -E "s/exec node server.js/echo \"\\n***********************\\n\\nApi key is \$(cat extras\/api_key.txt)\\n\\n***********************\\n\"\n\ncd extras \&\& exec python3 server.py --listen --chroma-persist --cpu --secure --classification-model=\"\${CLASSIFICATION_MODEL}\" --summarization-model=\"\${SUMMARIZATION_MODEL}\" --captioning-model=\"\${CAPTIONING_MODEL}\" --enable-modules=\"\${MODULES}\" --max-content-length=2000 --rvc-save-file --sd-remote --sd-remote-host=\"\${SD_REMOTE_HOST}\" --sd-remote-port=\"\${SD_REMOTE_PORT}\" --talkinghead-gpu \&\n\nexec node server.js/g" /home/node/app/docker-entrypoint.sh


EXPOSE 8000 5100

# Ensure proper handling of kernel signals
ENTRYPOINT [ "tini", "--" ]

CMD [ "./docker-entrypoint.sh" ]
