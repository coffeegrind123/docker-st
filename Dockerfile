#docker build --no-cache -t docker-st:latest .; docker run -it -p 8000:8000 -p 5100:5100 --name "docker-st" --rm docker-st:latest
FROM python:3.11.7-bookworm
ENV DEBIAN_FRONTEND noninteractive

# Arguments
ARG APP_HOME=/content/sillytavern

#ARG PYTHON_VER=3.11.0

ARG LISTEN_PORT="8000"
ENV LISTEN_PORT=${LISTEN_PORT:-$LISTEN_PORT}

ARG LISTEN_PORT_API="5100"
ENV LISTEN_PORT_API=${LISTEN_PORT_API:-$LISTEN_PORT_API}

ARG MODULES="caption,summarize,classify,sd,silero-tts,rvc,chromadb,whisper-stt,talkinghead"
ENV MODULES=${MODULES:-$MODULES}

# sentiment classification model
# nateraw/bert-base-uncased-emotion = 6 supported emotions<br>
# joeddav/distilbert-base-uncased-go-emotions-student = 28 supported emotions
ARG CLASSIFICATION_MODEL="joeddav/distilbert-base-uncased-go-emotions-student"
ENV CLASSIFICATION_MODEL=${CLASSIFICATION_MODEL:-$CLASSIFICATION_MODEL}

# story summarization module
# slauw87/bart_summarisation - general purpose summarization model
# Qiliang/bart-large-cnn-samsum-ChatGPT_v3 - summarization model optimized for chats
# Qiliang/bart-large-cnn-samsum-ElectrifAi_v10 - nice results so far, but still being evaluated
# distilbart-xsum-12-3 - faster, but pretty basic alternative
ARG SUMMARIZATION_MODEL="Qiliang/bart-large-cnn-samsum-ElectrifAi_v10"
ENV SUMMARIZATION_MODEL=${SUMMARIZATION_MODEL:-$SUMMARIZATION_MODEL}

# image captioning module
# Salesforce/blip-image-captioning-large - good base model
# Salesforce/blip-image-captioning-base - slightly faster but less accurate
ARG CAPTIONING_MODEL="Salesforce/blip-image-captioning-large"
ENV CAPTIONING_MODEL=${CAPTIONING_MODEL:-$CAPTIONING_MODEL}

# SD picture generation
# ckpt/anything-v4.5-vae-swapped - anime style model
# hakurei/waifu-diffusion - anime style model
# philz1337/clarity - realistic style model
# prompthero/openjourney - midjourney style model
# ckpt/sd15 - base SD 1.5
# stabilityai/stable-diffusion-2-1-base - base SD 2.1
ARG SD_REMOTE_HOST="192.168.0.171"
ENV SD_REMOTE_HOST=${SD_REMOTE_HOST:-$SD_REMOTE_HOST}

ARG SD_REMOTE_PORT="7860"
ENV SD_REMOTE_PORT=${SD_REMOTE_PORT:-$SD_REMOTE_PORT}

ARG TG_REMOTE_HOST="192.168.0.171"
ENV TG_REMOTE_HOST=${TG_REMOTE_HOST:-$TG_REMOTE_HOST}

ARG TG_REMOTE_PORT="5000"
ENV TG_REMOTE_PORT=${TG_REMOTE_PORT:-$TG_REMOTE_PORT}

# voice models https://voice-models.com/top
# gotta be rvmpe
ARG RVC_MODEL="https://huggingface.co/MUSTAR/Hoshino_Ai_U/resolve/main/Hoshino_Ai_U.zip"
ENV RVC_MODEL=${RVC_MODEL:-$RVC_MODEL}

#https://oobabooga.github.io/silero-samples/index.html
#ARG WHISPER_MODEL="v3_en.pt"
#ENV WHISPER_MODEL=${WHISPER_MODEL:-$WHISPER_MODEL}

ARG API_KEY
ENV API_KEY=${API_KEY:-$API_KEY}

# Install sillytavern packages
RUN apt update && apt upgrade -y && \
    apt install -y tini git dos2unix sqlite3 ffmpeg unzip curl wget

# Install node
RUN curl -fsSL https://deb.nodesource.com/setup_current.x | bash - && \
    apt install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR ${APP_HOME}

RUN git clone https://github.com/SillyTavern/SillyTavern /tmp/source

# Install app dependencies
RUN cp /tmp/source/package*.json /tmp/source/post-install.js ./ && \
    npm install && npm cache clean --force

# Bundle app source
RUN cp -r /tmp/source/* ./

# Create missing dir
RUN mkdir public/user

# Copy default chats, characters and user avatars to <folder>.default folder
RUN IFS="," RESOURCES="assets,backgrounds,user,context,instruct,QuickReplies,movingUI,themes,characters,chats,groups,group chats,User Avatars,worlds,OpenAI Settings,NovelAI Settings,KoboldAI Settings,TextGen Settings" && \
    for R in $RESOURCES; do mv "public/$R" "public/$R.default"; done || true && \
    for R in $RESOURCES; do ln -s "../config/$R" "public/$R"; done || true && \
    rm -f "config.yaml" "public/settings.json" || true && \
    ln -s "./config/config.yaml" "config.yaml" || true && \
    ln -s "../config/settings.json" "public/settings.json" || true && \
    mkdir "config" || true

# Necessary config modifications
RUN sed -i "s/securityOverride: false/securityOverride: true/" /content/sillytavern/default/config.yaml && \
    sed -i "s/whitelistMode: true/whitelistMode: false/" /content/sillytavern/default/config.yaml && \
    sed -i "s/listen: false/listen: true/" /content/sillytavern/default/config.yaml && \
    sed -i "s/port: 8000/port: ${LISTEN_PORT}/" /content/sillytavern/default/config.yaml && \
    sed -i "s/allowKeysExposure: false/allowKeysExposure: true/" /content/sillytavern/default/config.yaml

# Install extras
RUN git clone https://github.com/SillyTavern/SillyTavern-extras /tmp/extras && \
    cp -r /tmp/extras /content/sillytavern/extras && \
    #git clone https://github.com/Cohee1207/tts_samples /tmp/samples && \
    #cp -r /tmp/samples/* /content/sillytavern/extras && \
    wget "$RVC_MODEL" -P /tmp/model && \
    for f in /tmp/model/*.zip; do unzip "$f" -d "/content/sillytavern/extras/data/models/rvc/$(basename "$f" .zip)"; done && \
    cd /content/sillytavern/extras && \
    npm install -g localtunnel && npm cache clean --force && \
    python3 -m venv myenv && \
    . myenv/bin/activate && \
    python3 -m pip install pip --upgrade && \
    python3 -m pip install wheel && \
    python3 -m pip install -r requirements.txt && \
    python3 -m pip install -r requirements-rvc.txt && \
    deactivate && \
    wget https://github.com/cloudflare/cloudflared/releases/download/2023.5.0/cloudflared-linux-amd64 -O /tmp/cloudflared-linux-amd64 && \
    chmod +x /tmp/cloudflared-linux-amd64 && \
    git clone https://github.com/city-unit/SillyTavern-Chub-Search /tmp/chubsearch && \
    cp -r /tmp/chubsearch /content/sillytavern/public/scripts/extensions/chubsearch && \
    git clone https://github.com/city-unit/st-auto-tagger /tmp/st-auto-tagger && \
    cp -r /tmp/st-auto-tagger /content/sillytavern/public/scripts/extensions/st-auto-tagger && \
    git clone https://github.com/SillyTavern/Extension-RVC /tmp/rvc && \
    cp -r /tmp/rvc /content/sillytavern/public/scripts/extensions/rvc && \
    git clone https://github.com/SillyTavern/Extension-Randomizer /tmp/randomizer && \
    cp -r /tmp/randomizer /content/sillytavern/public/scripts/extensions/randomizer && \
    git clone https://github.com/SillyTavern/Extension-ChromaDB /tmp/chromadb && \
    cp -r /tmp/chromadb /content/sillytavern/public/scripts/extensions/chromadb

RUN if [ -z "${API_KEY}" ]; then \
      API_KEY=$(openssl rand -hex 5); \
      echo "${API_KEY}" > /content/sillytavern/extras/api_key.txt; \
      export API_KEY=${API_KEY}; \
      sed -i "s/\"apiKey\": \"\"/\"apiKey\": \"${API_KEY}\"/g" /content/sillytavern/default/settings.json; \
    else \
      echo "${API_KEY}" > /content/sillytavern/extras/api_key.txt; \
      export API_KEY=${API_KEY}; \
      sed -i "s/\"apiKey\": \"\"/\"apiKey\": \"${API_KEY}\"/g" /content/sillytavern/default/settings.json; \
    fi

RUN sed -i 's/"autoConnect": false/"autoConnect": true/g' /content/sillytavern/default/settings.json
RUN sed -i 's/"main_api": "koboldhorde"/"main_api": "textgenerationwebui"/g' /content/sillytavern/default/settings.json
RUN sed -i "0,/\"negative_prompt\": \"\"/{s//\"negative_prompt\": \"\",\\n        \"type\": \"ooba\",\\n        \"server_urls\": {\\n            \"ooba\": \"http:\/\/${TG_REMOTE_HOST}:${TG_REMOTE_PORT}\/\"\\n        }/}" /content/sillytavern/default/settings.json

# Cleanup unnecessary files
RUN echo "*** Cleanup ***" && \
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

RUN sed -i -E "s/exec node server.js/cd extras \&\& . myenv\/bin\/activate \&\& exec python3 server.py --listen --port \${LISTEN_PORT_API} --chroma-persist --chroma-folder=/content/sillytavern/chromadb/ --cpu --secure --classification-model=\"\${CLASSIFICATION_MODEL}\" --summarization-model=\"\${SUMMARIZATION_MODEL}\" --captioning-model=\"\${CAPTIONING_MODEL}\" --enable-modules=\"\${MODULES}\" --max-content-length=2000 --rvc-save-file --sd-remote --sd-remote-host=\"\${SD_REMOTE_HOST}\" --sd-remote-port=\"\${SD_REMOTE_PORT}\" --talkinghead-gpu \&\n\nexec node server.js/g" /content/sillytavern/docker-entrypoint.sh

EXPOSE 8000 5100

# Ensure proper handling of kernel signals
ENTRYPOINT [ "tini", "--" ]

CMD [ "./docker-entrypoint.sh" ]
